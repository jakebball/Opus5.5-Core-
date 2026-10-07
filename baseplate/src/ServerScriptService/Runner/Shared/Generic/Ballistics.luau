--[[ Ballistics (shared, generic) -- the trajectory of a round, as maths rather than as physics.

     CLOSED FORM, not incremental integration, and that is the load-bearing choice. Any peer can
     evaluate any instant without having stepped there, two peers cannot drift apart through float
     accumulation, and a round that has to be spawned already part-way along its flight is placed by
     asking for a larger elapsed rather than by fast-forwarding anything.

     `gravity` is a positive magnitude in studs/s^2, pulling -Y.
]]

local Ballistics = {}

const MIN_ROCKET_SPEED = 1e-6

function Ballistics.positionAt(origin, velocity, gravity, elapsed)
	return origin
		+ velocity * elapsed
		- Vector3.yAxis * (0.5 * gravity * elapsed * elapsed)
end

function Ballistics.velocityAt(velocity, gravity, elapsed)
	return velocity - Vector3.yAxis * (gravity * elapsed)
end


function Ballistics.rocketDistanceAt(speed, acceleration, maxSpeed, elapsed)
	if not acceleration or acceleration <= 0 then
		return speed * elapsed
	end
	local cruise = maxSpeed or math.huge
	if cruise <= speed then
		return speed * elapsed
	end
	local burn = (cruise - speed) / acceleration
	if elapsed <= burn then
		return speed * elapsed + 0.5 * acceleration * elapsed * elapsed
	end
	return speed * burn + 0.5 * acceleration * burn * burn + cruise * (elapsed - burn)
end

function Ballistics.rocketPositionAt(origin, velocity, acceleration, maxSpeed, elapsed)
	local speed = velocity.Magnitude
	if speed < MIN_ROCKET_SPEED then return origin end
	return origin
		+ (velocity / speed) * Ballistics.rocketDistanceAt(speed, acceleration, maxSpeed, elapsed)
end

-- Scatter a direction inside a cone of `degrees`. sqrt of a uniform sample spreads shots
-- evenly over the cone's disc rather than bunching them at the centre (disc area grows with
-- r^2); the roll about the look axis picks the radial direction, the pitch steps off it.
function Ballistics.applySpread(direction, degrees)
	if degrees <= 0 then return direction end

	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	local basis = CFrame.lookAt(Vector3.zero, direction)
	return (basis * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

return Ballistics
