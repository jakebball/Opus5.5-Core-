local HitscanMath = {}

const HITBOX_TAG = "Hitbox"
const HEADSHOT_TOP_FRACTION = 0.25
const RIG_FALLBACK_EXTENTS = Vector3.new(4, 6, 4)
const PARALLEL_EPSILON = 1e-6

function HitscanMath.findHitbox(instance)
	local current = instance
	while current and current ~= workspace do
		if current:HasTag(HITBOX_TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function rootOf(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

function HitscanMath.facingOf(instance)
	local root = rootOf(instance)
	return root and root.CFrame.LookVector or nil
end

function HitscanMath.positionOf(instance)
	local root = rootOf(instance)
	return root and root.Position or nil
end

function HitscanMath.rewindStamp(stamp, now, maxRewind)
	if not maxRewind or maxRewind <= 0 then return nil end
	if type(stamp) ~= "number" or stamp ~= stamp then return nil end
	local transit = math.max(now - stamp, 0)
	local target = stamp - transit
	if target >= now then return nil end
	return math.max(target, now - maxRewind)
end

function HitscanMath.volumeOf(instance)
	local boxCFrame, boxSize
	if instance:IsA("BasePart") then
		boxCFrame, boxSize = instance.CFrame, instance.Size
	elseif instance:IsA("Model") then
		local gotBox, modelCFrame, modelSize = pcall(instance.GetBoundingBox, instance)
		if gotBox and modelSize then
			boxCFrame, boxSize = modelCFrame, modelSize
		else
			local gotPivot, pivot = pcall(instance.GetPivot, instance)
			if gotPivot then
				boxCFrame, boxSize = pivot, RIG_FALLBACK_EXTENTS
			end
		end
	end

	if not boxCFrame then return nil, nil end
	return boxCFrame, boxSize
end

local function clipAxis(originAxis, directionAxis, halfExtent, entryDistance, exitDistance)
	if math.abs(directionAxis) < PARALLEL_EPSILON then
		if originAxis < -halfExtent or originAxis > halfExtent then return nil end
		return entryDistance, exitDistance
	end

	local first = (-halfExtent - originAxis) / directionAxis
	local second = (halfExtent - originAxis) / directionAxis
	if first > second then
		first, second = second, first
	end
	if first > entryDistance then entryDistance = first end
	if second < exitDistance then exitDistance = second end
	if entryDistance > exitDistance then return nil end
	return entryDistance, exitDistance
end

function HitscanMath.rayBox(origin, direction, range, boxCFrame, halfExtents)
	local localOrigin = boxCFrame:PointToObjectSpace(origin)
	local localDirection = boxCFrame:VectorToObjectSpace(direction)

	local entryDistance, exitDistance = 0, range
	entryDistance, exitDistance = clipAxis(localOrigin.X, localDirection.X, halfExtents.X, entryDistance, exitDistance)
	if not entryDistance then return nil end
	entryDistance, exitDistance = clipAxis(localOrigin.Y, localDirection.Y, halfExtents.Y, entryDistance, exitDistance)
	if not entryDistance then return nil end
	entryDistance, exitDistance = clipAxis(localOrigin.Z, localDirection.Z, halfExtents.Z, entryDistance, exitDistance)
	if not entryDistance then return nil end

	return entryDistance
end

function HitscanMath.surfacePoint(boxCFrame, size, point)
	local halfExtents = size * 0.5
	local localPoint = boxCFrame:PointToObjectSpace(point)
	return boxCFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPoint.X, -halfExtents.X, halfExtents.X),
		math.clamp(localPoint.Y, -halfExtents.Y, halfExtents.Y),
		math.clamp(localPoint.Z, -halfExtents.Z, halfExtents.Z)
	))
end

function HitscanMath.avatarOf(instance)
	if instance:IsA("Model") then return instance end
	local avatarName = (instance.Name:gsub("_Body$", "_Avatar"))
	return instance.Parent and instance.Parent:FindFirstChild(avatarName) or nil
end

function HitscanMath.isHeadshot(hitboxInstance, hitPosition)
	local avatar = HitscanMath.avatarOf(hitboxInstance)
	local head = avatar and avatar:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return hitPosition.Y >= head.Position.Y - head.Size.Y / 2
	end

	if hitboxInstance:IsA("BasePart") then
		local localPosition = hitboxInstance.CFrame:PointToObjectSpace(hitPosition)
		return localPosition.Y >= hitboxInstance.Size.Y * (0.5 - HEADSHOT_TOP_FRACTION)
	end
	return false
end

function HitscanMath.bearingDot(target, fromPosition)
	local facing = HitscanMath.facingOf(target)
	local targetPosition = HitscanMath.positionOf(target)
	if not facing or not targetPosition then return nil end

	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local flatBearing = Vector3.new(
		targetPosition.X - fromPosition.X,
		0,
		targetPosition.Z - fromPosition.Z
	)
	if flatFacing.Magnitude < PARALLEL_EPSILON then return nil end
	if flatBearing.Magnitude < PARALLEL_EPSILON then return nil end
	return flatFacing.Unit:Dot(flatBearing.Unit)
end

function HitscanMath.isBackstab(victim, attackerPosition, cosThreshold)
	local bearing = HitscanMath.bearingDot(victim, attackerPosition)
	return bearing ~= nil and bearing >= cosThreshold
end

-- True when a shot travelling along `direction` is heading INTO the target's front. Flattened to
-- the ground plane and measured against the target's own facing, dot(facing, direction) runs -1
-- for a dead head-on shot and +1 for one arriving from directly behind, so a frontal cone of
-- half-angle t is dot <= -cos(t).
--
-- Deliberately the shot's DIRECTION rather than the shooter's position: it is the bullet's own
-- line of travel that decides which face it strikes, it stays exact for a target that strafed
-- across the shot, and it has no degenerate case for an attacker standing on top of the target.
function HitscanMath.isIncomingFrontal(target, direction, cosThreshold)
	local facing = HitscanMath.facingOf(target)
	if not facing then return false end

	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatFacing.Magnitude < PARALLEL_EPSILON then return false end
	if flatDirection.Magnitude < PARALLEL_EPSILON then return false end
	return flatFacing.Unit:Dot(flatDirection.Unit) <= -cosThreshold
end

function HitscanMath.cast(origin, direction, range, options)
	local scale = options.Scale or 1
	local volumeAt = options.VolumeAt or HitscanMath.volumeOf
	local blockedAt = options.BlockedAt or range
	local reject = options.Reject

	local bestInstance, bestDistance, bestCFrame, bestSize

	for _, candidate in options.Candidates do
		if candidate.Parent and not (reject and reject(candidate)) then
			local boxCFrame, boxSize = volumeAt(candidate)
			if boxCFrame then
				local halfExtents = boxSize * (scale * 0.5)
				local distance = HitscanMath.rayBox(origin, direction, range, boxCFrame, halfExtents)
				if distance and distance <= blockedAt and (bestDistance == nil or distance < bestDistance) then
					bestInstance, bestDistance, bestCFrame, bestSize = candidate, distance, boxCFrame, boxSize
				end
			end
		end
	end

	if not bestInstance then return nil end

	local entryPoint = origin + direction * bestDistance
	return bestInstance, HitscanMath.surfacePoint(bestCFrame, bestSize, entryPoint), bestDistance
end

function HitscanMath.sweep(origin, direction, options)
	local range = options.Range or 0
	local scale = options.Scale or 1
	local cosArc = options.CosArc or -1
	local volumeAt = options.VolumeAt or HitscanMath.volumeOf
	local reject = options.Reject
	local blocked = options.Blocked

	local inReach = {}
	for _, candidate in options.Candidates do
		if candidate.Parent and not (reject and reject(candidate)) then
			local boxCFrame, boxSize = volumeAt(candidate)
			if boxCFrame then
				local reachPoint = HitscanMath.surfacePoint(boxCFrame, boxSize * scale, origin)
				local offset = reachPoint - origin
				local distance = offset.Magnitude
				local inArc = distance < PARALLEL_EPSILON or offset.Unit:Dot(direction) >= cosArc
				if distance <= range and inArc then
					table.insert(inReach, {
						instance = candidate,
						point = HitscanMath.surfacePoint(boxCFrame, boxSize, origin),
						distance = distance,
					})
				end
			end
		end
	end

	table.sort(inReach, function(left, right)
		return left.distance < right.distance
	end)

	for _, reached in inReach do
		if not (blocked and blocked(origin, reached.point, reached.instance)) then
			return reached.instance, reached.point, reached.distance
		end
	end
	return nil
end

return HitscanMath
