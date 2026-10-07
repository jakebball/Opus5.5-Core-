local RunService = game:GetService("RunService")

local ProjectilePhysicsClient = {}
ProjectilePhysicsClient.__index = ProjectilePhysicsClient
ProjectilePhysicsClient.Tag = "ProjectilePhysicsClient"

const REMOTE_FOLDER_NAME = "ProjectilePhysics"
const SLOT_ATTRIBUTE = "ProjectileSlot"
const ORIGIN_ATTRIBUTE = "ProjectileOrigin"
const CONTAINER_NAME = "ClientProjectiles"
const TELEPORT_DISTANCE = 40
-- Exponential catch-up: a fraction 1 - base^dt of the remaining gap closes each frame, which is
-- frame-rate independent where a flat fraction is not.
const LERP_BASE = 0.000001
const BLEND_TIME = 0.25
const PREDICTION_TIMEOUT = 1.5

local componentsBySlot = {}
local predictedComponents = {}
local activeComponents = {}
local started = false


local function leavePrediction(instance)
	if instance:IsA("BasePart") then
		RunService:SetPredictionMode(instance, Enum.PredictionMode.Off)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			RunService:SetPredictionMode(descendant, Enum.PredictionMode.Off)
		end
	end
end

local function container()
	local folder = workspace:FindFirstChild(CONTAINER_NAME)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace
	return folder
end

function ProjectilePhysicsClient.Start()
	setmetatable(ProjectilePhysicsClient, { __index = ProjectilePhysicsClient.BaseClass })
	if started then
		return
	end
	started = true

	local sharedRemote = ProjectilePhysicsClient.BaseClass.sharedRemote
	local Codec = ProjectilePhysicsClient.ProjectileCodec

	task.spawn(function()
		local streamRemote = sharedRemote(REMOTE_FOLDER_NAME, "Stream")
		if not streamRemote then
			warn("[ProjectilePhysics] the Stream remote never replicated; rounds will not move")
			return
		end
		streamRemote.OnClientEvent:Connect(function(packet)
			local count = Codec.readCount(packet)
			for index = 0, count - 1 do
				local slot, delta, rotation = Codec.readEntry(packet, index)
				local component = componentsBySlot[slot]
				if component then
					component:_receive(delta, rotation)
				end
			end
		end)
	end)

	task.spawn(function()
		local adoptRemote = sharedRemote(REMOTE_FOLDER_NAME, "Adopt")
		if not adoptRemote then
			return
		end
		adoptRemote.OnClientEvent:Connect(function(slot, predictionId, spawnOrigin)
			local component = predictedComponents[predictionId]
			if component then
				component:_adopt(slot, spawnOrigin)
			end
		end)
	end)

	task.spawn(function()
		local despawnRemote = sharedRemote(REMOTE_FOLDER_NAME, "Despawn")
		if not despawnRemote then
			return
		end
		despawnRemote.OnClientEvent:Connect(function(slot)
			local component = componentsBySlot[slot]
			if component and component.instance then
				component.instance:Destroy()
			end
		end)
	end)

	RunService.RenderStepped:Connect(function(deltaTime)
		for component in activeComponents do
			component:_interpolate(deltaTime)
		end
	end)
end

function ProjectilePhysicsClient.predict(options)
	local Body = ProjectilePhysicsClient.ProjectileBody
	local profile = options.Profile or {}

	local direction = options.Direction
	if typeof(direction) ~= "Vector3" or not (direction.Magnitude > 0.001) then
		return nil
	end
	local unit = direction.Unit

	Body.ensureCollisionGroup(profile)

	local instance, root = Body.build({
		Template = options.Template,
		Name = options.Name,
		Origin = options.Origin,
		Unit = unit,
		Offset = profile.Offset,
		CanCollide = profile.CanCollide,
		CollisionGroup = profile.CollisionGroup,
		PhysicalProperties = profile.PhysicalProperties,
	})
	if not instance then
		return nil
	end

	if options.Attributes then
		for attributeName, value in options.Attributes do
			instance:SetAttribute(attributeName, value)
		end
	end

	leavePrediction(instance)
	instance.Parent = container()

	local velocity = Body.launchVelocity(unit, options.Speed or profile.Speed, options.Lift or profile.Lift)
	root:ApplyImpulse(velocity * root.AssemblyMass)
	local spin = Body.randomSpin(profile.Spin)
	if spin then
		root.AssemblyAngularVelocity = spin
	end

	if options.Tags then
		for _, tagName in options.Tags do
			instance:AddTag(tagName)
		end
	end

	ProjectilePhysicsClient.EntityStore.addComponent(instance, ProjectilePhysicsClient.Tag, {
		PredictionId = options.PredictionId,
	})

	return instance
end

function ProjectilePhysicsClient.new(instance, options)
	local self = setmetatable(ProjectilePhysicsClient.BaseClass.new(instance), ProjectilePhysicsClient)
	options = options or {}

	self.root = ProjectilePhysicsClient.ProjectileBody.rootOf(instance)
	self.predictionId = options.PredictionId
	self.streaming = false
	self.targetPosition = nil
	self.targetRotation = nil
	self.blendError = nil
	self.blendUntil = nil

	if self.predictionId then
		self.spawnOrigin = nil
		predictedComponents[self.predictionId] = self
		self:_armPredictionTimeout()
	else
		self.slot = instance:GetAttribute(SLOT_ATTRIBUTE)
		self.spawnOrigin = instance:GetAttribute(ORIGIN_ATTRIBUTE) or instance:GetPivot().Position
		self:_anchor()
		instance.Parent = container()
		if self.slot then
			componentsBySlot[self.slot] = self
		end
	end

	activeComponents[self] = true

	self.trove:Add(function()
		activeComponents[self] = nil
		if self.slot and componentsBySlot[self.slot] == self then
			componentsBySlot[self.slot] = nil
		end
		if self.predictionId and predictedComponents[self.predictionId] == self then
			predictedComponents[self.predictionId] = nil
		end
	end)

	return self
end

function ProjectilePhysicsClient:_armPredictionTimeout()
	task.delay(PREDICTION_TIMEOUT, function()
		if predictedComponents[self.predictionId] ~= self then
			return
		end
		if self.slot then
			return
		end
		if self.instance and self.instance.Parent then
			self.instance:Destroy()
		end
	end)
end

function ProjectilePhysicsClient:_anchor()
	local instance = self.instance
	if instance:IsA("BasePart") then
		instance.Anchored = true
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

function ProjectilePhysicsClient:_adopt(slot, spawnOrigin)
	if self.slot then
		return
	end
	self.slot = slot
	self.spawnOrigin = spawnOrigin
	componentsBySlot[slot] = self
end

function ProjectilePhysicsClient:_receive(delta, rotation)
	if not self.spawnOrigin then
		return
	end

	local position = self.spawnOrigin + delta

	if not self.streaming then
		self.streaming = true
		self:_anchor()
		local drift = self.instance:GetPivot().Position - position
		if drift.Magnitude <= TELEPORT_DISTANCE then
			self.blendError = drift
			self.blendUntil = os.clock() + BLEND_TIME
		end
	end

	self.targetPosition = position
	self.targetRotation = rotation
end

function ProjectilePhysicsClient:_interpolate(deltaTime)
	local instance = self.instance
	if not instance or not instance.Parent then
		return
	end
	if not self.targetPosition then
		return
	end

	local goal = CFrame.new(self.targetPosition) * self.targetRotation

	if self.blendUntil then
		local remaining = self.blendUntil - os.clock()
		if remaining <= 0 then
			self.blendUntil = nil
			self.blendError = nil
		else
			goal = CFrame.new(self.blendError * (remaining / BLEND_TIME)) * goal
		end
	end

	local current = instance:GetPivot()
	if (goal.Position - current.Position).Magnitude > TELEPORT_DISTANCE then
		instance:PivotTo(goal)
		return
	end

	instance:PivotTo(current:Lerp(goal, 1 - math.pow(LERP_BASE, deltaTime)))
end

return ProjectilePhysicsClient
