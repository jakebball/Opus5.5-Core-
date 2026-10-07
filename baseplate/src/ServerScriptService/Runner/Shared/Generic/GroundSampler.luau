local GroundSampler = {}

local params = nil

function GroundSampler.positionAt(basePosition, settings, excluded)
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
	end
	params.FilterDescendantsInstances = excluded or {}

	local origin = basePosition + Vector3.yAxis * settings.RayHeight
	local result = workspace:Raycast(origin, Vector3.yAxis * -settings.RayLength, params)
	if not result or result.Normal.Y < settings.MinGroundNormalY then return nil end
	return result.Position
end

return GroundSampler
