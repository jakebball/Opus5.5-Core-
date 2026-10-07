local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local localPlayer = Players.LocalPlayer

local Spectator = {}
Spectator.__index = Spectator
Spectator.Tag = "Spectator"

const FOCUS_DAMPING = 1
const FOCUS_FREQUENCY = 6
const LOOK_SENSITIVITY = 0.006
const DEFAULT_PITCH = math.rad(-15)
const MIN_PITCH = math.rad(-75)
const MAX_PITCH = math.rad(75)
const MIN_DISTANCE = 8
const MAX_DISTANCE = 65
const DEFAULT_DISTANCE = 24
const ZOOM_STEP = 4
const FOCUS_HEIGHT_OFFSET = 2

function Spectator.Start()
	setmetatable(Spectator, { __index = Spectator.BaseClass })
	Spectator.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(Spectator.Tag)
		end
	end)
end

function Spectator.new(instance)
	local self = setmetatable(Spectator.BaseClass.new(instance), Spectator)
	if instance ~= localPlayer then return self end

	self.active = false
	self.targets = {}
	self.targetIndex = 0
	self._yaw = 0
	self._pitch = DEFAULT_PITCH
	self._distance = DEFAULT_DISTANCE
	self._rotating = false
	self._sessionConnections = {}
	self._targetFilter = nil
	self._paused = false
	self._onNoTargets = nil
	self._noTargetsFired = false

	self._focusValue = Instance.new("Vector3Value")
	self.trove:Add(self._focusValue)

	self.shell = nil
	self.trove:AddPromise(Spectator.EntityStore.promiseGetComponent(localPlayer, "CinematicShell"):andThen(function(shell)
		self.shell = shell
	end):catch(function() end))

	self.trove:Add(localPlayer.CharacterAdded:Connect(function()
		self:deactivate()
	end))

	return self
end

function Spectator:isActive()
	return self.active == true
end

function Spectator:getTarget()
	return self.targets[self.targetIndex]
end

function Spectator:activate(opts)
	if self.instance ~= localPlayer then return end
	if self.active then return end

	self._targetFilter = opts and opts.filter or nil
	self._onNoTargets = opts and opts.onNoTargets or nil
	self._noTargetsFired = false
	self:_rebuildTargets()
	if #self.targets == 0 then return end

	self.active = true
	self.targetIndex = 1
	self._rotating = false
	self._pitch = DEFAULT_PITCH
	self:_faceBehindCurrentTarget()

	local shell = self.shell or Spectator.EntityStore.getComponent(localPlayer, "CinematicShell")
	self.shell = shell
	if shell then
		shell:hideHud()
		shell:lockCamera()
	else
		local camera = workspace.CurrentCamera
		if camera then camera.CameraType = Enum.CameraType.Scriptable end
	end

	self:_setControlsEnabled(false)

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	local startCharacter = self:_targetCharacter()
	if startCharacter then
		self._focusValue.Value = self:_focusPositionFor(startCharacter)
	end

	self:_buildBanner()
	self:_updateBanner()
	self:_bindInput()

	self._renderConnection = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
end

function Spectator:deactivate()
	if self.instance ~= localPlayer then return end
	local wasActive = self.active

	self.active = false
	self._rotating = false
	self._paused = false

	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end
	self:_unbindInput()
	self:_destroyBanner()
	self.Spr.stop(self._focusValue)

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	if wasActive then
		self:_setControlsEnabled(true)

		local camera = workspace.CurrentCamera
		if self.shell then
			self.shell:releaseCamera()
			self.shell:restoreHud()
		end
		if camera and camera.Parent and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end

	self.targets = {}
	self.targetIndex = 0
	self._targetFilter = nil
	self._onNoTargets = nil
	self._noTargetsFired = false
end

function Spectator:next()
	self:_cycle(1)
end

function Spectator:previous()
	self:_cycle(-1)
end

function Spectator:_cycle(direction)
	if not self.active then return end
	self:_rebuildTargets()
	local count = #self.targets
	if count == 0 then return end
	self.targetIndex = ((self.targetIndex - 1 + direction) % count) + 1
	self:_faceBehindCurrentTarget()
	self:_updateBanner()
end

function Spectator:setTarget(player)
	if not self.active then return false end
	self:_rebuildTargets()
	for index, candidate in self.targets do
		if candidate == player then
			self.targetIndex = index
			self:_faceBehindCurrentTarget()
			self:_updateBanner()
			return true
		end
	end
	return false
end

function Spectator:refreshTargets()
	if not self.active then return end
	local previousTarget = self.targets[self.targetIndex]
	self:_rebuildTargets()
	self:_updateBanner()
	if #self.targets == 0 then
		self:_notifyNoTargets()
		return
	end
	if self.targets[self.targetIndex] ~= previousTarget then
		self:_faceBehindCurrentTarget()
	end
end

function Spectator:_notifyNoTargets()
	if self._noTargetsFired then return end
	self._noTargetsFired = true
	if self._onNoTargets then
		task.spawn(self._onNoTargets)
	end
end

function Spectator:_isWatchable(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return character ~= nil and humanoid ~= nil and humanoid.Health > 0
end

function Spectator:_passesFilter(player)
	return self._targetFilter == nil or self._targetFilter(player) == true
end

function Spectator:_rebuildTargets()
	local previousTarget = self.targets[self.targetIndex]

	local watchable = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and self:_isWatchable(player) and self:_passesFilter(player) then
			table.insert(watchable, player)
		end
	end

	if #watchable == 0 and self:_isWatchable(localPlayer) and self:_passesFilter(localPlayer) then
		table.insert(watchable, localPlayer)
	end

	self.targets = watchable

	local resolvedIndex = 0
	if #watchable > 0 then
		resolvedIndex = 1
		for index, player in watchable do
			if player == previousTarget then
				resolvedIndex = index
				break
			end
		end
	end
	self.targetIndex = resolvedIndex
end

function Spectator:_targetCharacter()
	local player = self.targets[self.targetIndex]
	if not player or not player.Parent then return nil end
	if not self:_isWatchable(player) then return nil end
	if not self:_passesFilter(player) then return nil end
	return player.Character
end

function Spectator:_focusPositionFor(character)
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if root then
		return root.Position + Vector3.new(0, FOCUS_HEIGHT_OFFSET, 0)
	end
	return self._focusValue.Value
end

-- Default the orbit to sit directly behind the watched character: the yaw whose
-- horizontal offset points opposite the character's facing (atan2 of the negated
-- look vector) so the camera looks the same way the player does.
function Spectator:_faceBehindCurrentTarget()
	local character = self:_targetCharacter()
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then return end
	local lookVector = root.CFrame.LookVector
	local horizontalLength = math.sqrt(lookVector.X * lookVector.X + lookVector.Z * lookVector.Z)
	if horizontalLength < 1e-4 then return end
	self._yaw = math.atan2(-lookVector.X, -lookVector.Z)
end

function Spectator:_step()
	if self._paused then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = self:_targetCharacter()
	if not character then
		self:_rebuildTargets()
		self:_updateBanner()
		if #self.targets == 0 then
			self:_notifyNoTargets()
			return
		end
		character = self:_targetCharacter()
		if not character then return end
	end

	local goalFocus = self:_focusPositionFor(character)
	self.Spr.target(self._focusValue, FOCUS_DAMPING, FOCUS_FREQUENCY, { Value = goalFocus })
	local focus = self._focusValue.Value

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(focus)
		* CFrame.fromEulerAnglesYXZ(self._pitch, self._yaw, 0)
		* CFrame.new(0, 0, self._distance)
end

function Spectator:_bindInput()
	table.insert(self._sessionConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not self.active then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._rotating = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			return
		end
		if gameProcessed then return end
		local keyCode = input.KeyCode
		if keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
			self:next()
		elseif keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
			self:previous()
		end
	end))

	table.insert(self._sessionConnections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._rotating = false
			if self.active then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
	end))

	table.insert(self._sessionConnections, UserInputService.InputChanged:Connect(function(input)
		if not self.active then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if not self._rotating then return end
			self._yaw -= input.Delta.X * LOOK_SENSITIVITY
			self._pitch = math.clamp(self._pitch - input.Delta.Y * LOOK_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			self._distance = math.clamp(self._distance - input.Position.Z * ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
		end
	end))

	table.insert(self._sessionConnections, UserInputService.WindowFocusReleased:Connect(function()
		self:_releaseRotateDrag()
	end))

	table.insert(self._sessionConnections, GuiService.MenuOpened:Connect(function()
		self:_releaseRotateDrag()
	end))
end

function Spectator:_releaseRotateDrag()
	if not self.active then return end
	if not self._rotating then return end
	self._rotating = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function Spectator:_unbindInput()
	for _, connection in self._sessionConnections do
		connection:Disconnect()
	end
	self._sessionConnections = {}
end

function Spectator:_getControls()
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then return nil end
	local ok, controls = pcall(function()
		return require(playerModule):GetControls()
	end)
	if ok then return controls end
	return nil
end

function Spectator:_setControlsEnabled(enabled)
	local controls = self:_getControls()
	if not controls then return end
	if enabled then
		pcall(function() controls:Enable() end)
	else
		pcall(function() controls:Disable() end)
	end
end

function Spectator:_makeArrow(name, glyph, anchorX, positionX)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(anchorX, 0.5)
	button.Position = UDim2.fromScale(positionX, 0.5)
	button.Size = UDim2.fromOffset(78, 78)
	button.BackgroundColor3 = Color3.new(0, 0, 0)
	button.BackgroundTransparency = 0.35
	button.AutoButtonColor = true
	button.Text = glyph
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.18, 0)
	padding.PaddingRight = UDim.new(0.18, 0)
	padding.Parent = button

	return button
end

function Spectator:_buildBanner()
	if self._banner then return end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpectatorBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:AddTag("CinematicKeep")

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.fromScale(0.5, 0.06)
	container.Size = UDim2.fromScale(0.36, 0.11)
	container.BackgroundColor3 = Color3.new(0, 0, 0)
	container.BackgroundTransparency = 0.4
	container.BorderSizePixel = 0
	container.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.12)
	title.Size = UDim2.fromScale(0.92, 0.46)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.RichText = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Spectating"
	title.Parent = container

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromScale(0.5, 0.92)
	hint.Size = UDim2.fromScale(0.92, 0.32)
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(205, 205, 205)
	hint.Text = "Hold right-click to look   •   Scroll to zoom"
	hint.Parent = container

	local leftArrow = self:_makeArrow("LeftArrow", "◀", 0.5, 0.30)
	leftArrow.Parent = gui
	local rightArrow = self:_makeArrow("RightArrow", "▶", 0.5, 0.70)
	rightArrow.Parent = gui

	table.insert(self._sessionConnections, leftArrow.Activated:Connect(function()
		self:previous()
	end))
	table.insert(self._sessionConnections, rightArrow.Activated:Connect(function()
		self:next()
	end))

	gui.Parent = playerGui
	self._banner = gui
	self._bannerTitle = title
	self._leftArrow = leftArrow
	self._rightArrow = rightArrow
end

function Spectator:_updateBanner()
	local hasChoices = #self.targets > 1
	if self._leftArrow then self._leftArrow.Visible = hasChoices end
	if self._rightArrow then self._rightArrow.Visible = hasChoices end

	if not self._bannerTitle then return end
	local player = self.targets[self.targetIndex]
	local displayName = player and player.DisplayName or "..."
	self._bannerTitle.Text = string.format("Spectating  <b>%s</b>", displayName)
end

function Spectator:_destroyBanner()
	if self._banner then
		self._banner:Destroy()
		self._banner = nil
		self._bannerTitle = nil
		self._leftArrow = nil
		self._rightArrow = nil
	end
end

function Spectator:setBannerHidden(hidden)
	if self._banner then
		self._banner.Enabled = not hidden
	end
end

function Spectator:setPaused(paused)
	self._paused = paused == true
end

function Spectator:destroy()
	self:deactivate()
	self.trove:Clean()
end

return Spectator
