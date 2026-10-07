
local Players = game:GetService("Players")

local WorldEffects = {}
WorldEffects.__index = WorldEffects
WorldEffects.Tag = "WorldEffects"

const REMOTE = "Effect"
const DEFAULT_RANGE = 400

function WorldEffects.Start()
	setmetatable(WorldEffects, { __index = WorldEffects.BaseClass })
	workspace:AddTag(WorldEffects.Tag)
end

function WorldEffects.new(instance)
	local self = setmetatable(WorldEffects.BaseClass.new(instance), WorldEffects)
	self:registerRemote(REMOTE)
	return self
end

function WorldEffects.get()
	return WorldEffects.EntityStore.findComponent(workspace, WorldEffects.Tag)
end

function WorldEffects.play(effectName, options)
	local effects = WorldEffects.get()
	if not effects then return end
	effects:_broadcast(effectName, options)
end

local function viewpointOf(player)
	local focus = player.ReplicationFocus
	if focus and focus:IsA("BasePart") then
		return focus.Position
	end
	local character = player.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	if root then
		return root.Position
	end
	return nil
end

local function payloadOf(options)
	local payload = {}
	for key, value in options do
		if key ~= "Parent" and typeof(value) ~= "Instance" and type(value) ~= "function" then
			payload[key] = value
		end
	end
	return payload
end

function WorldEffects:_broadcast(effectName, options)
	if type(effectName) ~= "string" or type(options) ~= "table" then return end

	local payload = payloadOf(options)
	local origin = payload.Origin
	local range = payload.MaxDistance or DEFAULT_RANGE
	payload.MaxDistance = nil

	if typeof(origin) ~= "Vector3" or range <= 0 then
		self:sendNetworkEvent("All", REMOTE, effectName, payload)
		return
	end

	for _, player in Players:GetPlayers() do
		local viewpoint = viewpointOf(player)
		if viewpoint == nil or (viewpoint - origin).Magnitude <= range then
			self:sendNetworkEvent(player, REMOTE, effectName, payload)
		end
	end
end

function WorldEffects:destroy()
	self.trove:Clean()
end

return WorldEffects
