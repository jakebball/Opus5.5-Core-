local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local CinematicShell = {}
CinematicShell.__index = CinematicShell
CinematicShell.Tag = "CinematicShell"

function CinematicShell.Start()
	setmetatable(CinematicShell, { __index = CinematicShell.BaseClass })
	CinematicShell.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(CinematicShell.Tag)
		end
	end)
end

function CinematicShell.new(instance)
	local self = setmetatable(CinematicShell.BaseClass.new(instance), CinematicShell)
	if instance ~= localPlayer then return self end

	self._cameraLocked = false
	self._prevCameraType = nil
	self._prevCameraSubject = nil
	self._hudSnapshot = nil
	self._shakeConn = nil
	self._lookConn = nil
	self._barGui = nil

	return self
end

function CinematicShell:lockCamera()
	local camera = workspace.CurrentCamera
	if not camera or self._cameraLocked then return end
	self._prevCameraType = camera.CameraType
	self._prevCameraSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable
	self._cameraLocked = true
end

function CinematicShell:releaseCamera()
	self:_stopLook()
	if not self._cameraLocked then return end
	local camera = workspace.CurrentCamera
	if camera and camera.Parent then
		camera.CameraType = self._prevCameraType or Enum.CameraType.Custom
		local character = localPlayer and localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		elseif self._prevCameraSubject and self._prevCameraSubject.Parent then
			camera.CameraSubject = self._prevCameraSubject
		end
	end
	self._prevCameraType = nil
	self._prevCameraSubject = nil
	self._cameraLocked = false
end

function CinematicShell:lookAt(targetPosition, duration)
	local camera = workspace.CurrentCamera
	if not camera then return end
	self:_stopLook()
	duration = duration or 0.5
	local startCF = camera.CFrame
	local goalCF = CFrame.lookAt(startCF.Position, targetPosition)
	local startedAt = os.clock()
	self._lookConn = RunService.RenderStepped:Connect(function()
		local fraction = math.min((os.clock() - startedAt) / duration, 1)
		local eased = 1 - (1 - fraction) * (1 - fraction)
		camera.CFrame = startCF:Lerp(goalCF, eased)
		if fraction >= 1 then self:_stopLook() end
	end)
end

function CinematicShell:_stopLook()
	if self._lookConn then
		self._lookConn:Disconnect()
		self._lookConn = nil
	end
end

function CinematicShell:shake(baseCF, duration, intensity)
	self:stopShake()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local startedAt = os.clock()
	self._shakeConn = RunService.Heartbeat:Connect(function()
		local fraction = (os.clock() - startedAt) / duration
		if fraction >= 1 then
			self:stopShake()
			camera.CFrame = baseCF
			return
		end
		local amplitude = intensity * (1 - fraction)
		camera.CFrame = baseCF * CFrame.new(
			(math.random() - 0.5) * 2 * amplitude,
			(math.random() - 0.5) * 2 * amplitude,
			(math.random() - 0.5) * 2 * amplitude
		)
	end)
end

function CinematicShell:stopShake()
	if self._shakeConn then
		self._shakeConn:Disconnect()
		self._shakeConn = nil
	end
end

function CinematicShell:showBars(fraction, slideTime)
	fraction = fraction or 0.12
	slideTime = slideTime or 0.35
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	if not self._barGui then
		local gui = Instance.new("ScreenGui")
		gui.Name = "CinematicBars"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10000
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

		local top = Instance.new("Frame")
		top.Name = "TopBar"
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.AnchorPoint = Vector2.new(0.5, 0)
		top.Position = UDim2.fromScale(0.5, 0)
		top.Size = UDim2.fromScale(1, 0)
		top.Parent = gui

		local bottom = top:Clone()
		bottom.Name = "BottomBar"
		bottom.AnchorPoint = Vector2.new(0.5, 1)
		bottom.Position = UDim2.fromScale(0.5, 1)
		bottom.Parent = gui

		gui.Parent = playerGui
		self._barGui = gui
		self._barTop = top
		self._barBottom = bottom
	end

	local tweenInfo = TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goalSize = UDim2.fromScale(1, fraction)
	TweenService:Create(self._barTop, tweenInfo, { Size = goalSize }):Play()
	TweenService:Create(self._barBottom, tweenInfo, { Size = goalSize }):Play()
end

function CinematicShell:hideBars(slideTime)
	if not self._barGui then return end
	slideTime = slideTime or 0.3
	local gui = self._barGui
	local top = self._barTop
	local bottom = self._barBottom
	self._barGui = nil
	self._barTop = nil
	self._barBottom = nil

	local tweenInfo = TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local goalSize = UDim2.fromScale(1, 0)
	TweenService:Create(top, tweenInfo, { Size = goalSize }):Play()
	local closing = TweenService:Create(bottom, tweenInfo, { Size = goalSize })
	closing.Completed:Connect(function()
		if gui and gui.Parent then gui:Destroy() end
	end)
	closing:Play()
end

function CinematicShell:hideHud(keep)
	if self._hudSnapshot then return end
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local keepSet = {}
	for _, gui in keep or {} do
		keepSet[gui] = true
	end

	local snapshot = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled and not keepSet[gui] and not gui:HasTag("CinematicKeep") then
			snapshot[gui] = true
			gui.Enabled = false
		end
	end
	self._hudSnapshot = snapshot
end

function CinematicShell:restoreHud()
	if not self._hudSnapshot then return end
	for gui in self._hudSnapshot do
		if gui and gui.Parent then
			gui.Enabled = true
		end
	end
	self._hudSnapshot = nil
end

function CinematicShell:reset()
	self:stopShake()
	self:releaseCamera()
	self:hideBars()
	self:restoreHud()
end

function CinematicShell:destroy()
	self:reset()
end

return CinematicShell
