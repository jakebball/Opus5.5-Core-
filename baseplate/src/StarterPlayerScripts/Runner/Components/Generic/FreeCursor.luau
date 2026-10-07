local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

local FreeCursor = {}
FreeCursor.__index = FreeCursor
FreeCursor.Tag = "FreeCursor"

const TOGGLE_ACTION = "FreeCursorToggle"
const TOGGLE_KEY = Enum.KeyCode.Q
const HOLD_BIND_NAME = "FreeCursorHold"
const RENDER_PRIORITY = Enum.RenderPriority.Camera.Value

function FreeCursor.Start()
	setmetatable(FreeCursor, { __index = FreeCursor.BaseClass })

	FreeCursor.InputManager.setup(FreeCursor.GoodSignal)
	FreeCursor.InputManager.bindAction(TOGGLE_ACTION, { TOGGLE_KEY })

	FreeCursor.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(FreeCursor.Tag)
		end
	end)
end

function FreeCursor.new(instance)
	local self = setmetatable(FreeCursor.BaseClass.new(instance), FreeCursor)

	if instance ~= localPlayer then
		return self
	end

	self.free = false
	self.cameraOffset = Vector3.zero
	self.frozenRotation = CFrame.identity

	self.freeChanged = FreeCursor.GoodSignal.new()
	self.trove:Add(self.freeChanged, "DisconnectAll")

	self.freeTrove = FreeCursor.Trove.new()
	self.trove:Add(self.freeTrove)

	local toggleAction = FreeCursor.InputManager.onActionBegan(TOGGLE_ACTION, function()
		self:toggle()
	end)
	if toggleAction then
		self.trove:Add(toggleAction, "Disconnect")
	end

	return self
end

function FreeCursor:isFree()
	return self.free
end

function FreeCursor:toggle()
	self:setFree(not self.free)
end

function FreeCursor:setFree(shouldBeFree)
	if shouldBeFree == self.free then return end

	self.free = shouldBeFree

	if shouldBeFree then
		self:_release()
	else
		self:_recapture()
	end

	self.freeChanged:Fire(shouldBeFree)
end

function FreeCursor:_release()
	local camera = workspace.CurrentCamera

	self.previousCameraType = camera and camera.CameraType or nil
	self.previousCameraMode = localPlayer.CameraMode
	self.previousMouseBehavior = UserInputService.MouseBehavior
	self.previousMouseIcon = UserInputService.MouseIconEnabled

	if camera then
		local anchor = self:_cameraAnchor()
		if anchor then
			self.cameraOffset = camera.CFrame.Position - anchor.Position
		else
			self.cameraOffset = Vector3.zero
		end

		self.frozenRotation = camera.CFrame - camera.CFrame.Position
		camera.CameraType = Enum.CameraType.Scriptable
	end

	localPlayer.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	self.freeTrove:BindToRenderStep(HOLD_BIND_NAME, RENDER_PRIORITY, function()
		self:_hold()
	end)
end

function FreeCursor:_recapture()
	self.freeTrove:Clean()

	localPlayer.CameraMode = self.previousCameraMode or Enum.CameraMode.LockFirstPerson

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = self.previousCameraType or Enum.CameraType.Custom
	end

	UserInputService.MouseBehavior = self.previousMouseBehavior or Enum.MouseBehavior.LockCenter
	if self.previousMouseIcon ~= nil then
		UserInputService.MouseIconEnabled = self.previousMouseIcon
	end
end

function FreeCursor:_cameraAnchor()
	local character = localPlayer.Character
	if not character then return nil end

	return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

function FreeCursor:_hold()
	local camera = workspace.CurrentCamera
	if not camera then return end

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	local anchor = self:_cameraAnchor()
	if not anchor then return end

	-- position-only CFrame times a rotation-only CFrame: the eye tracks the body while
	-- the look direction stays exactly as it was the frame the cursor was released
	camera.CFrame = CFrame.new(anchor.Position + self.cameraOffset) * self.frozenRotation
end

function FreeCursor:destroy()
	self:setFree(false)
end

return FreeCursor
