
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local Ragdoll = {}
Ragdoll.__index = Ragdoll
Ragdoll.Tag = "Ragdoll"

const STATE_REMOTE = "RagdollState"
const CONSTRAINT_NAME = "RagdollConstraint"
const STIFF_FRICTION_TORQUE = 1000
const LIMP_FRICTION_TORQUE = 0
const FRICTION_EASE_TIME = 0.3

function Ragdoll.Start()
	setmetatable(Ragdoll, { __index = Ragdoll.BaseClass })
	Ragdoll.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(Ragdoll.Tag)
		end
	end)
end

function Ragdoll.new(instance)
	local self = setmetatable(Ragdoll.BaseClass.new(instance), Ragdoll)
	if instance ~= localPlayer then return self end

	self._prevCollide = nil
	self._easeConn = nil

	self:onRemoteEvent(STATE_REMOTE, function(payload)
		self:_onState(payload)
	end)

	self.trove:Add(localPlayer.CharacterAdded:Connect(function()
		self._prevCollide = nil
		self:_stopEase()
	end))

	return self
end

local function gatherRagdollMotors(character, rootPart)
	local motors = {}
	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
			if rootPart and (joint.Part0 == rootPart or joint.Part1 == rootPart) then
				continue
			end
			table.insert(motors, joint)
		end
	end
	return motors
end

local function gatherBallSockets(character)
	local sockets = {}
	for _, inst in character:GetDescendants() do
		if inst.Name == CONSTRAINT_NAME and inst:IsA("BallSocketConstraint") then
			table.insert(sockets, inst)
		end
	end
	return sockets
end

function Ragdoll:_onState(payload)
	if type(payload) ~= "table" then return end

	local character = localPlayer.Character
	if not character then
		warn("[Ragdoll/client] _onState: no character")
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")


	if payload.active == true then
		self:_enter(character, humanoid, hrp)
	elseif payload.active == false then
		self:_exit(character, humanoid, hrp)
	end

	if payload.impulse and hrp then
		hrp:ApplyImpulse(payload.impulse)
	end
end

function Ragdoll:_enter(character, humanoid, hrp)
	if not humanoid then
		warn("[Ragdoll/client] _enter: humanoid is nil — cannot ragdoll")
		return
	end

	local rootPart = humanoid.RootPart or hrp
	local motors = gatherRagdollMotors(character, rootPart)
	for _, motor in motors do
		motor.Enabled = false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and #motors > 0 then
		animator:ApplyJointVelocities(motors)
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	self:_easeFriction(character)

	if hrp and self._prevCollide == nil then
		self._prevCollide = hrp.CanCollide
		hrp.CanCollide = false
	end
	local camera = workspace.CurrentCamera
	local head = character:FindFirstChild("Head")
	if camera and head then
		camera.CameraSubject = head
	end
end

-- Lerp every ball-socket's MaxFrictionTorque from stiff to limp over FRICTION_EASE_TIME so
-- the body settles. We own the sim, so writing the value locally is what the physics reads;
-- the hinge neck has no MaxFrictionTorque so it is skipped.
function Ragdoll:_easeFriction(character)
	self:_stopEase()
	local sockets = gatherBallSockets(character)
	if #sockets == 0 then return end
	for _, socket in sockets do
		socket.MaxFrictionTorque = STIFF_FRICTION_TORQUE
	end
	local elapsed = 0
	self._easeConn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local alpha = math.clamp(elapsed / FRICTION_EASE_TIME, 0, 1)
		local value = STIFF_FRICTION_TORQUE + (LIMP_FRICTION_TORQUE - STIFF_FRICTION_TORQUE) * alpha
		for _, socket in sockets do
			if socket.Parent then
				socket.MaxFrictionTorque = value
			end
		end
		if alpha >= 1 then
			self:_stopEase()
		end
	end)
end

function Ragdoll:_stopEase()
	if self._easeConn then
		self._easeConn:Disconnect()
		self._easeConn = nil
	end
end

function Ragdoll:_exit(character, humanoid, hrp)
	self:_stopEase()
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		if self._prevCollide ~= nil then
			hrp.CanCollide = self._prevCollide
			self._prevCollide = nil
		end
	end
	local rootPart = (humanoid and humanoid.RootPart) or hrp
	for _, motor in gatherRagdollMotors(character, rootPart) do
		motor.Enabled = true
	end
	for _, socket in gatherBallSockets(character) do
		socket.MaxFrictionTorque = STIFF_FRICTION_TORQUE
	end
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraSubject = humanoid
		end
	end
end

function Ragdoll:destroy()
	self:_stopEase()
	self.trove:Clean()
end

return Ragdoll
