
local PhysicsService = game:GetService("PhysicsService")

local RagdollUtils = {}

local ragdollData = setmetatable({}, { __mode = "k" })

const CONSTRAINT_NAME = "RagdollConstraint"

const COLLISION_GROUP = "Ragdoll"

const HINGE_JOINTS = { Neck = true }

const BALL_UPPER_ANGLE = 45
const TWIST_LOWER_ANGLE = -45
const TWIST_UPPER_ANGLE = 45
const HINGE_LOWER_ANGLE = -45
const HINGE_UPPER_ANGLE = 45
const STIFF_FRICTION_TORQUE = 1000

local collisionGroupReady = false
local function ensureCollisionGroup()
	if collisionGroupReady then
		return
	end
	collisionGroupReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	end)
end

local function applyCollisionGroup(character, data)
	ensureCollisionGroup()
	local previous = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			previous[part] = part.CollisionGroup
			part.CollisionGroup = COLLISION_GROUP
		end
	end
	data.collisionGroups = previous
end

local function restoreCollisionGroup(data)
	if not data.collisionGroups then
		return
	end
	for part, group in data.collisionGroups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	data.collisionGroups = nil
end

local function makeAttachment(name, cframe, parent)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = parent
	return attachment
end

function RagdollUtils.build(character)
	if ragdollData[character] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[RagdollUtils] build: no Humanoid on " .. character.Name)
		return
	end
	local rootPart = humanoid.RootPart
	if not rootPart then
		return
	end
	humanoid.BreakJointsOnDeath = false

	local instances = {}
	local motors = {}

	for _, joint in character:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
			if joint.Part0 == rootPart or joint.Part1 == rootPart then
				continue
			end

			local a0 = makeAttachment("RagdollAttachment0", joint.C0, joint.Part0)
			local a1 = makeAttachment("RagdollAttachment1", joint.C1, joint.Part1)

			local constraint
			if HINGE_JOINTS[joint.Name] then
				local hinge = Instance.new("HingeConstraint")
				hinge.LimitsEnabled = true
				hinge.LowerAngle = HINGE_LOWER_ANGLE
				hinge.UpperAngle = HINGE_UPPER_ANGLE
				constraint = hinge
			else
				local socket = Instance.new("BallSocketConstraint")
				socket.LimitsEnabled = true
				socket.UpperAngle = BALL_UPPER_ANGLE
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = TWIST_LOWER_ANGLE
				socket.TwistUpperAngle = TWIST_UPPER_ANGLE
				socket.MaxFrictionTorque = STIFF_FRICTION_TORQUE
				constraint = socket
			end
			constraint.Name = CONSTRAINT_NAME
			constraint.Attachment0 = a0
			constraint.Attachment1 = a1
			constraint.Parent = joint.Parent

			table.insert(instances, a0)
			table.insert(instances, a1)
			table.insert(instances, constraint)
			table.insert(motors, joint)
		end
	end

	if #motors == 0 then
		return
	end

	ragdollData[character] = { instances = instances, motors = motors, engaged = false }
end

function RagdollUtils.engage(character)
	local data = ragdollData[character]
	if not data then
		RagdollUtils.build(character)
		data = ragdollData[character]
		if not data then
			warn("[RagdollUtils] engage: could not build a ragdoll rig for " .. character.Name)
			return
		end
	end
	if data.engaged then
		return
	end
	data.engaged = true
	for _, motor in data.motors do
		if motor and motor.Parent then
			motor.Enabled = false
		end
	end
	applyCollisionGroup(character, data)
end

function RagdollUtils.disengage(character)
	local data = ragdollData[character]
	if not data or not data.engaged then
		return
	end
	data.engaged = false
	for _, motor in data.motors do
		if motor and motor.Parent then
			motor.Enabled = true
		end
	end
	restoreCollisionGroup(data)
end

function RagdollUtils.teardown(character)
	local data = ragdollData[character]
	if not data then
		return
	end

	restoreCollisionGroup(data)
	for _, inst in data.instances do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	for _, motor in data.motors do
		if motor and motor.Parent then
			motor.Enabled = true
		end
	end

	ragdollData[character] = nil
end

function RagdollUtils.isRagdolled(character)
	local data = ragdollData[character]
	return data ~= nil and data.engaged
end

return RagdollUtils
