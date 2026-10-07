local Players = game:GetService("Players")

const DEFAULT_DISTANCE = 200
const DEFAULT_UPDATE_RATE = 0.5

const MOVE_EPSILON = 0.05
const MOVING_STREAK = 2
const STILL_STREAK = 3

local octree
local components = {}
local minTickRate = DEFAULT_UPDATE_RATE
local maxQueryRadius = DEFAULT_DISTANCE

local ProximityTrigger = {}
ProximityTrigger.__index = ProximityTrigger
ProximityTrigger.Tag = "ProximityTrigger"

local function ensureOctree()
	if not octree then
		octree = ProximityTrigger.Octree.new()
	end
end

local function recomputeBounds()
	local minRate, maxDist = math.huge, 0
	local any = false
	for component in components do
		any = true
		if component.updateRate < minRate then minRate = component.updateRate end
		if component.distance > maxDist then maxDist = component.distance end
	end
	if any then
		minTickRate = minRate
		maxQueryRadius = maxDist
	else
		minTickRate = DEFAULT_UPDATE_RATE
		maxQueryRadius = DEFAULT_DISTANCE
	end
end

function ProximityTrigger.Start()
	setmetatable(ProximityTrigger, { __index = ProximityTrigger.BaseClass })
	ensureOctree()

	task.spawn(function()
		while true do
			ProximityTrigger._tick()
			task.wait(minTickRate)
		end
	end)
end

function ProximityTrigger._tick()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	if not hrp then
		for component in components do
			if component.inRange then
				component.inRange = false
				component.exited:Fire()
			end
		end
		return
	end

	local now = os.clock()
	local pos = hrp.Position

	for component in components do
		component:_trackMovement()
	end

	local nearby = octree:RadiusSearch(pos, maxQueryRadius)
	local nearbySet = {}
	for _, component in nearby do
		nearbySet[component] = true
	end

	for _, component in nearby do
		if now - component._lastCheck >= component.updateRate then
			component._lastCheck = now
			component:_evaluate(pos)
		end
	end

	for component in components do
		if not nearbySet[component] and component.inRange then
			component.inRange = false
			component.exited:Fire()
		end
	end
end

function ProximityTrigger.new(instance, options)
	local self = ProximityTrigger.BaseClass.new(instance)
	setmetatable(self, ProximityTrigger)

	options = options or {}
	self.distance = options.distance or instance:GetAttribute("ProximityDistance") or DEFAULT_DISTANCE
	self.updateRate = options.updateRate or instance:GetAttribute("ProximityUpdateRate") or DEFAULT_UPDATE_RATE
	self.inRange = false
	self._lastCheck = 0
	self.entered = ProximityTrigger.GoodSignal.new()
	self.exited = ProximityTrigger.GoodSignal.new()

	ensureOctree()

	local position = self:_getPosition()
	if position then
		self._octreeNode = octree:CreateNode(position, self)
	end
	self._lastSampledPos = position
	self._movingStreak = 0
	self._stillStreak = 0
	self._isMoving = false

	components[self] = true
	recomputeBounds()

	self.trove:Add(function()
		components[self] = nil
		recomputeBounds()
		if self._octreeNode then
			self._octreeNode:Destroy()
			self._octreeNode = nil
		end
		self.entered:DisconnectAll()
		self.exited:DisconnectAll()
	end)

	return self
end

function ProximityTrigger:_getPosition()
	local instance = self.instance
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart.Position
		end
		local cf = instance:GetBoundingBox()
		return cf.Position
	end
	return nil
end

function ProximityTrigger:_trackMovement()
	local node = self._octreeNode
	if not node then return end

	local position = self:_getPosition()
	if not position then return end

	local last = self._lastSampledPos
	self._lastSampledPos = position
	local moved = last == nil or (position - last).Magnitude > MOVE_EPSILON

	if moved then
		self._stillStreak = 0
		self._movingStreak += 1
		if self._movingStreak >= MOVING_STREAK then
			self._isMoving = true
		end
	else
		self._movingStreak = 0
		self._stillStreak += 1
		if self._stillStreak >= STILL_STREAK then
			self._isMoving = false
		end
	end

	if self._isMoving or moved then
		node:SetPosition(position)
	end
end

function ProximityTrigger:_evaluate(playerPosition)
	local position = self:_getPosition()
	if not position then return end

	local nowInRange = (playerPosition - position).Magnitude <= self.distance

	if nowInRange and not self.inRange then
		self.inRange = true
		self.entered:Fire()
	elseif not nowInRange and self.inRange then
		self.inRange = false
		self.exited:Fire()
	end
end

function ProximityTrigger.QueryRadius(position, radius)
	if not octree then return {} end
	local objects = octree:RadiusSearch(position, radius)
	return objects
end

return ProximityTrigger