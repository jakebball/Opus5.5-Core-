local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProjectilePhysics = {}
ProjectilePhysics.__index = ProjectilePhysics
ProjectilePhysics.Tag = "ProjectilePhysics"

const CLIENT_TAG = "ProjectilePhysicsClient"
const CLONE_HOST_NAME = "ProjectileClones"
const REMOTE_FOLDER_NAME = "ProjectilePhysics"
const REMOTE_ID_ATTRIBUTE = "ComponentRemoteId"
const SLOT_ATTRIBUTE = "ProjectileSlot"
const ORIGIN_ATTRIBUTE = "ProjectileOrigin"
const MAX_SLOTS = 255
const MAX_LEAD = 0.2
const LEAD_SKIN = 0.75

local liveRounds = {}
local slotCursor = 0
local remotes = nil
local started = false
local truncationWarned = false

local function allocateSlot()
	for _ = 1, MAX_SLOTS do
		slotCursor = slotCursor % MAX_SLOTS + 1
		if liveRounds[slotCursor] == nil then
			return slotCursor
		end
	end
	return nil
end

local function cloneHostFor(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local host = playerGui:FindFirstChild(CLONE_HOST_NAME)
	if not host then
		host = Instance.new("Folder")
		host.Name = CLONE_HOST_NAME
		host.Parent = playerGui
	end
	return host
end

function ProjectilePhysics.hiddenContainer(containerName)
	local existing = workspace:FindFirstChild(containerName)
	if existing then
		return existing
	end

	local camera = Instance.new("Camera")
	camera.Name = containerName
	camera.Parent = workspace
	return camera
end

local function stream()
	if not remotes or not remotes.Stream then
		return
	end

	local Codec = ProjectilePhysics.ProjectileCodec
	local samples = {}
	local overflow = false

	for slot, round in liveRounds do
		local pivot = round:pivot()
		if pivot then
			if #samples >= Codec.MaxEntries then
				overflow = true
				break
			end
			table.insert(samples, {
				slot = slot,
				delta = pivot.Position - round.spawnOrigin,
				rotation = pivot.Rotation,
			})
		end
	end

	if overflow and not truncationWarned then
		truncationWarned = true
		warn(string.format("[ProjectilePhysics] more than %d live rounds; the surplus is not streamed", Codec.MaxEntries))
	end

	local count = #samples
	if count == 0 then
		return
	end

	local packet = Codec.create(count)
	Codec.writeCount(packet, count)
	for index, sample in samples do
		Codec.writeEntry(packet, index - 1, sample.slot, sample.delta, sample.rotation)
	end

	remotes.Stream:FireAllClients(packet)
end

function ProjectilePhysics.Start()
	setmetatable(ProjectilePhysics, { __index = ProjectilePhysics.BaseClass })
	if started then
		return
	end
	started = true

	local sharedRemote = ProjectilePhysics.BaseClass.sharedRemote
	remotes = {
		Stream = sharedRemote(REMOTE_FOLDER_NAME, "Stream", "UnreliableRemoteEvent"),
		Adopt = sharedRemote(REMOTE_FOLDER_NAME, "Adopt"),
		Despawn = sharedRemote(REMOTE_FOLDER_NAME, "Despawn"),
	}

	ProjectilePhysics.Observers.observePlayer(function(player)
		player:WaitForChild("PlayerGui", 10)
		cloneHostFor(player)

		for _, round in liveRounds do
			round:_openFor(player)
		end

		return function()
			for _, round in liveRounds do
				round:_closeFor(player)
			end
		end
	end)

	RunService.Heartbeat:Connect(stream)

end

function ProjectilePhysics.spawn(origin, direction, options)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return false
	end
	if not (direction.Magnitude > 0.001) then
		return false
	end
	local unit = direction.Unit
	if unit.X ~= unit.X then
		return false
	end
	if not options.Template then
		return false
	end

	local Body = ProjectilePhysics.ProjectileBody
	local muzzle = origin + unit * (options.Offset or 0)
	local launchVelocity = Body.launchVelocity(unit, options.Speed, options.Lift)

	local lead = math.clamp(options.Lead or 0, 0, MAX_LEAD)
	local spawnPosition, spawnVelocity = muzzle, launchVelocity
	if lead > 0 then
		spawnPosition, spawnVelocity = Body.advance(muzzle, launchVelocity, lead, workspace.Gravity)

		local sweep = spawnPosition - muzzle
		if sweep.Magnitude > LEAD_SKIN then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = options.LeadFilter or {}
			local blocked = workspace:Raycast(muzzle, sweep, params)
			if blocked then
				spawnPosition = blocked.Position + blocked.Normal * LEAD_SKIN
			end
		end
	end

	local spawnOptions = table.clone(options)
	spawnOptions.SpawnPosition = spawnPosition
	spawnOptions.Velocity = spawnVelocity
	spawnOptions.OnSpawned = function(instance, root)
		if options.OnSpawned then
			options.OnSpawned(instance, root)
		end
		ProjectilePhysics.EntityStore.addComponent(instance, ProjectilePhysics.Tag, {
			Thrower = options.Thrower,
			PredictionId = options.PredictionId,
			SpawnOrigin = spawnPosition,
			KeepTags = options.KeepTags,
		})
	end

	return ProjectilePhysics.Projectile.spawn(origin, direction, spawnOptions)
end

function ProjectilePhysics.new(instance, options)
	local self = setmetatable(ProjectilePhysics.BaseClass.new(instance), ProjectilePhysics)
	options = options or {}

	self.root = ProjectilePhysics.ProjectileBody.rootOf(instance)
	self.thrower = options.Thrower
	self.predictionId = options.PredictionId
	self.spawnOrigin = options.SpawnOrigin or (self.root and self.root.Position) or Vector3.zero
	self.keepTags = options.KeepTags
	self.clientInstances = {}
	self.slot = allocateSlot()

	if not self.slot then
		warn("[ProjectilePhysics] every slot is taken; this round will not replicate")
		return self
	end
	liveRounds[self.slot] = self

	self.trove:Add(function()
		liveRounds[self.slot] = nil
		for _, clone in self.clientInstances do
			if clone.Parent then
				clone:Destroy()
			end
		end
		self.clientInstances = {}
		if self.thrower and self.predictionId and remotes and remotes.Despawn then
			remotes.Despawn:FireClient(self.thrower, self.slot)
		end
	end)

	for _, player in Players:GetPlayers() do
		self:_openFor(player)
	end

	if self.thrower and self.predictionId and remotes and remotes.Adopt then
		remotes.Adopt:FireClient(self.thrower, self.slot, self.predictionId, self.spawnOrigin)
	end

	return self
end

function ProjectilePhysics:pivot()
	local instance = self.instance
	if not instance or not instance.Parent then
		return nil
	end
	return instance:GetPivot()
end

function ProjectilePhysics:_keeps(tagName)
	if not self.keepTags then
		return false
	end
	return table.find(self.keepTags, tagName) ~= nil
end

function ProjectilePhysics:_openFor(player)
	if not self.slot then
		return
	end
	if self.clientInstances[player] then
		return
	end
	if self.predictionId and player == self.thrower then
		return
	end

	local host = cloneHostFor(player)
	if not host then
		return
	end

	local clone = self.instance:Clone()
	for _, tagName in clone:GetTags() do
		if not self:_keeps(tagName) then
			clone:RemoveTag(tagName)
		end
	end
	clone:SetAttribute(REMOTE_ID_ATTRIBUTE, nil)
	clone:SetAttribute(SLOT_ATTRIBUTE, self.slot)
	clone:SetAttribute(ORIGIN_ATTRIBUTE, self.spawnOrigin)
	clone:PivotTo(self.instance:GetPivot())
	clone:AddTag(CLIENT_TAG)
	clone.Parent = host

	self.clientInstances[player] = clone
end

function ProjectilePhysics:_closeFor(player)
	local clone = self.clientInstances[player]
	if not clone then
		return
	end
	self.clientInstances[player] = nil
	if clone.Parent then
		clone:Destroy()
	end
end

return ProjectilePhysics
