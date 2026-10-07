--!native

local OctreeNode = require(script:WaitForChild("OctreeNode"))
local OctreeRegionUtils = require(script:WaitForChild("OctreeRegionUtils"))

local EPSILON = 1e-9

local Octree = {}
Octree.ClassName = "Octree"
Octree.__index = Octree

function Octree.new()
	local self = setmetatable({}, Octree)

	self._maxRegionSize = { 512, 512, 512 }
	self._maxDepth = 4
	self._regionHashMap = {}

	return self
end

function Octree:GetAllNodes()
	local options = {}

	for _, regionList in pairs(self._regionHashMap) do
		for _, region in pairs(regionList) do
			for node, _ in pairs(region.nodes) do
				options[node] = true
			end
		end
	end

	local nodes = {}
	for node, _ in pairs(options) do
		nodes[#nodes + 1] = node
	end
	return nodes
end

function Octree:CreateNode(position, object)
	assert(typeof(position) == "Vector3", "Bad position")
	assert(object, "Bad object")

	local node = OctreeNode.new(self, object)

	node:SetPosition(position)

	return node
end

function Octree:RadiusSearch(position, radius)
	assert(typeof(position) == "Vector3", "Bad position")
	assert(type(radius) == "number", "Bad radius")

	local px, py, pz = position.x, position.y, position.z
	return self:_radiusSearch(px, py, pz, radius)
end

function Octree:KNearestNeighborsSearch(position, k, radius)
	assert(typeof(position) == "Vector3", "Bad position")
	assert(type(radius) == "number", "Bad radius")

	local px, py, pz = position.x, position.y, position.z
	local objects, nodeDistances2 = self:_radiusSearch(px, py, pz, radius)

	local sortable = table.create(#objects)
	for index, dist2 in ipairs(nodeDistances2) do
		sortable[index] = {
			dist2 = dist2,
			obj = objects[index],
		}
	end

	table.sort(sortable, function(a, b)
		return a.dist2 < b.dist2
	end)

	local knearest = {}
	local knearestDist2 = {}
	for i = 1, math.min(k, #sortable) do
		local item = sortable[i]
		knearestDist2[#knearestDist2 + 1] = item.dist2
		knearest[#knearest + 1] = item.obj
	end

	return knearest, knearestDist2
end

function Octree:GetOrCreateLowestSubRegion(px, py, pz)
	local region = OctreeRegionUtils.getOrCreateRegion(self._regionHashMap, self._maxRegionSize, px, py, pz)
	return OctreeRegionUtils.getOrCreateSubRegionAtDepth(region, px, py, pz, self._maxDepth)
end

function Octree:_radiusSearch(px, py, pz, radius)
	local objectsFound = {}
	local nodeDistances2 = {}

	local diameter = self._maxRegionSize[1]
	local searchRadiusSquared = OctreeRegionUtils.getSearchRadiusSquared(radius, diameter, EPSILON)

	for _, regionList in pairs(self._regionHashMap) do
		for _, region in pairs(regionList) do
			local rpx, rpy, rpz = region.position[1], region.position[2], region.position[3]
			local ox, oy, oz = px - rpx, py - rpy, pz - rpz
			local dist2 = ox*ox + oy*oy + oz*oz

			if dist2 <= searchRadiusSquared then
				OctreeRegionUtils.getNeighborsWithinRadius(
					region, radius, px, py, pz, objectsFound, nodeDistances2, self._maxDepth)
			end
		end
	end

	return objectsFound, nodeDistances2
end

return Octree