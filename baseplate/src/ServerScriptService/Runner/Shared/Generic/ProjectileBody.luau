local PhysicsService = game:GetService("PhysicsService")

local ProjectileBody = {}

ProjectileBody.profiles = {
	Grenade = {
		Offset = 2.5,
		Speed = 90,
		Lift = 18,
		Spin = 9,
		CanCollide = true,
		CollisionGroup = "Grenade",
		SelfCollide = false,
		PhysicalProperties = PhysicalProperties.new(1.2, 0.35, 0.6, 1, 1),
	},
}

local registeredGroups = {}

function ProjectileBody.ensureCollisionGroup(profile)
	local groupName = profile and profile.CollisionGroup
	if not groupName or registeredGroups[groupName] then return end
	registeredGroups[groupName] = true

	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	if profile.SelfCollide == false then
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(groupName, groupName, false)
		end)
	end
end

function ProjectileBody.rootOf(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	local root = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	if root and instance:IsA("Model") then
		instance.PrimaryPart = root
	end
	return root
end

function ProjectileBody.launchVelocity(unit, speed, lift)
	return unit * (speed or 0) + Vector3.yAxis * (lift or 0)
end

-- Free fall from a launch: p(t) = p0 + v0*t - 0.5*g*t^2*y, v(t) = v0 - g*t*y
function ProjectileBody.advance(position, velocity, elapsed, gravity)
	local fallen = 0.5 * gravity * elapsed * elapsed
	return position + velocity * elapsed - Vector3.yAxis * fallen,
		velocity - Vector3.yAxis * (gravity * elapsed)
end

function ProjectileBody.randomSpin(magnitude)
	if not magnitude or magnitude <= 0 then
		return nil
	end
	return Vector3.new(
		(math.random() - 0.5) * 2 * magnitude,
		(math.random() - 0.5) * 2 * magnitude,
		(math.random() - 0.5) * 2 * magnitude
	)
end

function ProjectileBody.build(options)
	local template = options.Template
	if not template then
		return nil
	end

	local instance = template:Clone()
	if options.Name then
		instance.Name = options.Name
	end

	local root = ProjectileBody.rootOf(instance)
	if not root then
		instance:Destroy()
		return nil
	end

	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	for _, part in parts do
		part.Anchored = options.Anchored == true
		part.Massless = false
		part.CanCollide = options.CanCollide == true
		part.CanQuery = options.CanQuery == true
		part.CanTouch = options.CanTouch == true
		part.CastShadow = options.CastShadow == true
		if options.CollisionGroup then
			part.CollisionGroup = options.CollisionGroup
		end
		if options.PhysicalProperties then
			part.CustomPhysicalProperties = options.PhysicalProperties
		end
	end

	local unit = options.Unit
	local spawnPosition = options.SpawnPosition
	if not spawnPosition then
		spawnPosition = options.Origin + unit * (options.Offset or 0)
	end

	if instance:IsA("Model") then
		instance:PivotTo(CFrame.new(spawnPosition))
	else
		instance.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + unit)
			* CFrame.Angles(0, math.pi * 0.5, 0)
	end

	return instance, root
end

return ProjectileBody
