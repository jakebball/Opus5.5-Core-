local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

const SHOULDER_OFFSET = Vector3.new(2, 0.5, 0.1)
const LOCKED_ZOOM = 8
const MAX_PITCH = math.rad(45)
const SPR_DAMPING = 0.8
const SPR_FREQ = 4
const RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local nextRenderStepId = 0

local function normalizeAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local OverShoulderCamera = {}
OverShoulderCamera.__index = OverShoulderCamera
OverShoulderCamera.Tag = "OverShoulderCamera"

function OverShoulderCamera.Start()
	setmetatable(OverShoulderCamera, { __index = OverShoulderCamera.BaseClass })
end

local function resolvePitchTarget(character)
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local upperTorso = character:FindFirstChild("UpperTorso")
	if lowerTorso and upperTorso then
		local waistConstraint = upperTorso:FindFirstChild("Waist")
		if waistConstraint and waistConstraint:IsA("AnimationConstraint") then
			local att = waistConstraint.Attachment0
			if att then
				return {
					kind = "constraint",
					attachment = att,
					baseCFrame = att.CFrame,
				}
			end
		end

		if waistConstraint and waistConstraint:IsA("Motor6D") then
			return {
				kind = "motor6d_r15",
				motor = waistConstraint,
				baseC0 = waistConstraint.C0,
			}
		end
	end

	local torso = character:FindFirstChild("Torso")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if torso and hrp then
		local rootJoint = hrp:FindFirstChild("RootJoint")
		local leftHip = torso:FindFirstChild("Left Hip")
		local rightHip = torso:FindFirstChild("Right Hip")
		if rootJoint and leftHip and rightHip then
			return {
				kind = "motor6d_r6",
				motor = rootJoint,
				baseC0 = rootJoint.C0,
				leftHip = leftHip,
				baseLeftHip = leftHip.C0,
				rightHip = rightHip,
				baseRightHip = rightHip.C0,
			}
		end
	end

	return nil
end

local function applyPitch(target, clampPitch)
	if target.kind == "constraint" then
		target.attachment.CFrame = target.baseCFrame * CFrame.Angles(clampPitch, 0, 0)
	elseif target.kind == "motor6d_r15" then
		target.motor.C0 = target.baseC0 * CFrame.Angles(clampPitch, 0, 0)
	elseif target.kind == "motor6d_r6" then
		target.motor.C0 = target.baseC0 * CFrame.Angles(-clampPitch, 0, 0)
		target.leftHip.C0 = target.baseLeftHip * CFrame.Angles(0, 0, clampPitch)
		target.rightHip.C0 = target.baseRightHip * CFrame.Angles(0, 0, -clampPitch)
	end
end

local function restorePitch(target)
	if target.kind == "constraint" then
		if target.attachment.Parent then
			target.attachment.CFrame = target.baseCFrame
		end
	elseif target.kind == "motor6d_r15" then
		if target.motor.Parent then
			target.motor.C0 = target.baseC0
		end
	elseif target.kind == "motor6d_r6" then
		if target.motor.Parent then
			target.motor.C0 = target.baseC0
		end
		if target.leftHip.Parent then target.leftHip.C0 = target.baseLeftHip end
		if target.rightHip.Parent then target.rightHip.C0 = target.baseRightHip end
	end
end

function OverShoulderCamera.new(instance)
	local self = setmetatable(OverShoulderCamera.BaseClass.new(instance), OverShoulderCamera)

	self.character = instance
	self.humanoid = instance:WaitForChild("Humanoid")
	self.rootPart = instance:WaitForChild("HumanoidRootPart")

	self.pitchTarget = resolvePitchTarget(instance)
	self.pitchAttempts = 0

	self.lockTarget = nil
	self.lockedCameraPos = nil

	self.yawValue = Instance.new("NumberValue")
	self.yawValue.Name = "AimYaw"
	local _, ry = self.rootPart.CFrame:ToOrientation()
	self.yawValue.Value = ry
	self.yawValue.Parent = instance
	self.trove:Add(self.yawValue)

	self.offsetValue = Instance.new("Vector3Value")
	self.offsetValue.Name = "AimOffset"
	self.offsetValue.Value = Vector3.zero
	self.offsetValue.Parent = instance
	self.trove:Add(self.offsetValue)

	local player = Players:GetPlayerFromCharacter(instance)
	self.player = player
	self.prevMouseBehavior = UserInputService.MouseBehavior
	self.prevMouseIcon = UserInputService.MouseIconEnabled
	self.prevMinZoom = player and player.CameraMinZoomDistance or nil
	self.prevMaxZoom = player and player.CameraMaxZoomDistance or nil
	self.prevCameraType = workspace.CurrentCamera and workspace.CurrentCamera.CameraType

	self.humanoid.AutoRotate = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	if player then
		player.CameraMinZoomDistance = LOCKED_ZOOM
		player.CameraMaxZoomDistance = LOCKED_ZOOM
	end

	OverShoulderCamera.Spr.target(self.offsetValue, SPR_DAMPING, SPR_FREQ, { Value = SHOULDER_OFFSET })

	nextRenderStepId += 1
	local renderName = "OverShoulderCamera_" .. nextRenderStepId
	RunService:BindToRenderStep(renderName, RENDER_PRIORITY, function(deltaTime)
		self:_align(deltaTime)
	end)

	self.trove:Add(function()
		RunService:UnbindFromRenderStep(renderName)

		if OverShoulderCamera.Spr.stop then
			OverShoulderCamera.Spr.stop(self.offsetValue)
			OverShoulderCamera.Spr.stop(self.yawValue)
		end

		if self.humanoid.Parent then
			self.humanoid.AutoRotate = true
		end

		UserInputService.MouseBehavior = self.prevMouseBehavior
		UserInputService.MouseIconEnabled = self.prevMouseIcon

		if player and self.prevMinZoom and self.prevMaxZoom then
			player.CameraMinZoomDistance = self.prevMinZoom
			player.CameraMaxZoomDistance = self.prevMaxZoom
		end

		local cam = workspace.CurrentCamera
		if cam and self.prevCameraType then
			cam.CameraType = self.prevCameraType
		end

		if self.pitchTarget then
			restorePitch(self.pitchTarget)
		end
	end)

	return self
end

function OverShoulderCamera:lockTo(target)
	if not target or not target.Parent then return end
	self.lockTarget = target

	local cam = workspace.CurrentCamera
	if cam then
		self.lockedCameraPos = cam.CFrame.Position
		cam.CameraType = Enum.CameraType.Scriptable
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	if self.pitchTarget then
		applyPitch(self.pitchTarget, 0)
	end
end

function OverShoulderCamera:unlock()
	self.lockTarget = nil
	self.lockedCameraPos = nil

	local cam = workspace.CurrentCamera
	if cam and self.prevCameraType then
		cam.CameraType = self.prevCameraType
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

function OverShoulderCamera:_align(deltaTime)
	local camera = workspace.CurrentCamera
	if not camera or not self.rootPart.Parent then return end

	if self.lockTarget and self.lockTarget.Parent and self.lockedCameraPos then
		camera.CFrame = CFrame.lookAt(self.lockedCameraPos, self.lockTarget.Position)
		return
	end

	camera.CFrame = camera.CFrame * CFrame.new(self.offsetValue.Value)

	local lookVector = camera.CFrame.LookVector

	local targetYaw = math.atan2(-lookVector.X, -lookVector.Z)
	local currentYaw = self.yawValue.Value
	local smoothedYawTarget = currentYaw + normalizeAngle(targetYaw - currentYaw)
	OverShoulderCamera.Spr.target(self.yawValue, SPR_DAMPING, SPR_FREQ, { Value = smoothedYawTarget })

	local pos = self.rootPart.Position
	self.rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, self.yawValue.Value, 0)

	if not self.pitchTarget and self.pitchAttempts < 30 then
		self.pitchAttempts += 1
		self.pitchTarget = resolvePitchTarget(self.character)
	end

	if self.pitchTarget then
		local pitch = math.asin(math.clamp(lookVector.Y, -1, 1))
		local clampPitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
		applyPitch(self.pitchTarget, clampPitch)
	end
end

function OverShoulderCamera:destroy()
	self.trove:Clean()
end

return OverShoulderCamera