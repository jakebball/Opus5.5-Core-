local RunService = game:GetService("RunService")

local PathFollower = {}

const ARRIVE_SPEED_DIVISOR = 30

function PathFollower.awaitWaypoint(instance, rootPart, target, timeout, arriveRadius, shouldAbort)
	local deadline = os.clock() + timeout

	while os.clock() < deadline do
		if shouldAbort and shouldAbort() then return false end
		if not instance.Parent then return false end

		local offset = rootPart.Position - target
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= arriveRadius then
			return true
		end
		RunService.Heartbeat:Wait()
	end

	return false
end

function PathFollower.follow(instance, humanoid, rootPart, path, destination, settings)
	local computed = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)
	if not computed or path.Status ~= Enum.PathStatus.Success then return false end

	-- A waypoint is "reached" within one frame of travel at the current speed, so the radius
	-- floor scales with WalkSpeed: at 30 fps a bot moves WalkSpeed/30 studs between checks.
	local arriveRadius = math.max(settings.ArriveRadius, humanoid.WalkSpeed / ARRIVE_SPEED_DIVISOR)
	local waypoints = path:GetWaypoints()

	for index = 2, #waypoints do
		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		humanoid:MoveTo(waypoint.Position)
		if not PathFollower.awaitWaypoint(instance, rootPart, waypoint.Position, settings.WaypointTimeout, arriveRadius, settings.shouldAbort) then
			if instance.Parent then
				humanoid:MoveTo(rootPart.Position)
			end
			return false
		end
	end

	return true
end

return PathFollower
