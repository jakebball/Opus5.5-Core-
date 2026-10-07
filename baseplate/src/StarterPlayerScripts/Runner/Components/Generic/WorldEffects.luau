
local WorldEffects = {}
WorldEffects.__index = WorldEffects
WorldEffects.Tag = "WorldEffects"

WorldEffects.effects = {}

const REMOTE = "Effect"
const ROOT_NAME = "ClientEffects"

function WorldEffects.Start()
	setmetatable(WorldEffects, { __index = WorldEffects.BaseClass })
	workspace:AddTag(WorldEffects.Tag)
end

function WorldEffects.registerEffect(effectName, handler)
	WorldEffects.effects[effectName] = handler
end

function WorldEffects.container(name)
	local root = workspace:FindFirstChild(ROOT_NAME)
	if not root then
		root = Instance.new("Folder")
		root.Name = ROOT_NAME
		root.Parent = workspace
	end
	if type(name) ~= "string" or name == "" then
		return root
	end

	local folder = root:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
	end
	return folder
end

WorldEffects.effects.DebrisBurst = function(options)
	options.Parent = WorldEffects.container(options.Container)
	WorldEffects.DebrisBurst.Fire(options)
end

function WorldEffects.new(instance)
	local self = setmetatable(WorldEffects.BaseClass.new(instance), WorldEffects)

	self:onRemoteEvent(REMOTE, function(effectName, options)
		if type(options) ~= "table" then return end
		local handler = WorldEffects.effects[effectName]
		if handler then
			handler(options)
		end
	end)

	return self
end

function WorldEffects:destroy()
	self.trove:Clean()
end

return WorldEffects
