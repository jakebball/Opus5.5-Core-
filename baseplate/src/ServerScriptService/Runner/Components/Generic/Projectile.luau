local RunService = game:GetService("RunService")

local Projectile = {}
Projectile.__index = Projectile
Projectile.Tag = "Projectile"

const CONTAINER_NAME = "Projectiles"
const MIN_SEGMENT = 0.0001
const MAX_LIFETIME = 8
const SUB_STEP = 1 / 60
const MAX_SUB_STEPS = 24
const DEFAULT_SPEED = 300
const DEFAULT_RANGE = 1000

local pendingSpawns = {}
local ballisticRounds = {}
local stepsBound = false

local function container()
	local folder = workspace:FindFirstChild(CONTAINER_NAME)
	if folder then return folder end

	folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace
	return folder
end

local function createRound(origin, unit, options)
	local Body = Projectile.ProjectileBody
	local instance, root = Body.build({
		Template = options.Template,
		Name = options.Name,
		Origin = origin,
		Unit = unit,
		Offset = options.Offset,
		SpawnPosition = options.SpawnPosition,
		CanCollide = options.CanCollide,
		CanQuery = options.CanQuery,
		CanTouch = options.CanTouch,
		CastShadow = options.CastShadow,
		CollisionGroup = options.CollisionGroup,
		PhysicalProperties = options.PhysicalProperties,
	})
	if not instance then
		return nil
	end

	instance.Parent = options.Container or container()

	local velocity = options.Velocity
		or Body.launchVelocity(unit, options.Speed or DEFAULT_SPEED, options.Lift)
	root:ApplyImpulse(velocity * root.AssemblyMass)

	local spin = Body.randomSpin(options.Spin)
	if spin then
		root.AssemblyAngularVelocity = spin
	end
	pcall(root.SetNetworkOwner, root, nil)

	return instance, root
end

function Projectile._positionAt(round, elapsed)
	if round.acceleration then
		return Projectile.Ballistics.rocketPositionAt(
			round.origin, round.velocity, round.acceleration, round.maxSpeed, elapsed
		)
	end
	return Projectile.Ballistics.positionAt(round.origin, round.velocity, round.gravity, elapsed)
end

function Projectile._advanceRound(round, index)
	local elapsed = workspace:GetServerTimeNow() - round.spawnTime
	if elapsed > MAX_LIFETIME then
		table.remove(ballisticRounds, index)
		return
	end

	local from = round.lastElapsed
	local steps = 0
	while from < elapsed and steps < MAX_SUB_STEPS do
		local to = math.min(from + SUB_STEP, elapsed)
		local head = Projectile._positionAt(round, from)
		local tail = Projectile._positionAt(round, to)
		local segment = tail - head
		local travelled = segment.Magnitude
		if travelled > MIN_SEGMENT then
			round.remaining -= travelled
			local _, spent = round.resolve(head, segment.Unit, travelled, round.spawnTime + from)
			if spent or round.remaining <= 0 then
				table.remove(ballisticRounds, index)
				return
			end
		end
		from = to
		steps += 1
	end
	round.lastElapsed = from
end

local function ensureSteps()
	if stepsBound then return end
	stepsBound = true

	RunService:BindToSimulation(function()
		if #pendingSpawns > 0 then
			local batch = pendingSpawns
			pendingSpawns = {}
			for _, request in batch do
				local instance, root = createRound(request.origin, request.unit, request.options)
				if instance and request.options.OnSpawned then
					task.defer(request.options.OnSpawned, instance, root)
				end
			end
		end
	end, Enum.StepFrequency.Hz60)

	RunService.Heartbeat:Connect(function()
		for index = #ballisticRounds, 1, -1 do
			Projectile._advanceRound(ballisticRounds[index], index)
		end
	end)
end

function Projectile.Start()
	setmetatable(Projectile, { __index = Projectile.BaseClass })
	ensureSteps()
end

function Projectile.container()
	return container()
end

function Projectile.clearAll()
	for _, child in container():GetChildren() do
		child:Destroy()
	end
	ballisticRounds = {}
	pendingSpawns = {}
end

function Projectile.new(instance)
	local self = setmetatable(Projectile.BaseClass.new(instance), Projectile)

	self.trove:Add(function()
		for index = #ballisticRounds, 1, -1 do
			if ballisticRounds[index].owner == self then
				table.remove(ballisticRounds, index)
			end
		end
	end)

	return self
end

function Projectile.spawn(origin, direction, options)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return false end
	if not (direction.Magnitude > 0.001) then return false end
	local unit = direction.Unit
	if unit.X ~= unit.X then return false end
	if not options.Template then return false end

	ensureSteps()
	table.insert(pendingSpawns, { origin = origin, unit = unit, options = options })
	return true
end

function Projectile:launch(origin, direction, options)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return false end
	if not (direction.Magnitude > 0.001) then return false end
	local unit = direction.Unit
	if unit.X ~= unit.X then return false end
	if not options.Resolve then return false end

	ensureSteps()

	table.insert(ballisticRounds, {
		owner = self,
		origin = origin,
		velocity = unit * (options.Speed or DEFAULT_SPEED),
		gravity = options.Gravity or 0,
		acceleration = options.Acceleration,
		maxSpeed = options.MaxSpeed,
		spawnTime = options.SpawnTime or workspace:GetServerTimeNow(),
		remaining = options.Range or DEFAULT_RANGE,
		lastElapsed = 0,
		resolve = options.Resolve,
	})
	return true
end

return Projectile
