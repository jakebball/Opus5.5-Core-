local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

const TREE_TAG = "_BTree"
const AUTO_RUN_ATTRIBUTE = "AutoRun"

const WORLD_BOARD = "World"

local BehaviourTreeRunner = {}
BehaviourTreeRunner.__index = BehaviourTreeRunner
BehaviourTreeRunner.Tag = "BehaviourTreeRunner"

function BehaviourTreeRunner.Start()
	setmetatable(BehaviourTreeRunner, { __index = BehaviourTreeRunner.BaseClass })
	workspace:AddTag(BehaviourTreeRunner.Tag)
end

function BehaviourTreeRunner.new(instance)
	local self = setmetatable(BehaviourTreeRunner.BaseClass.new(instance), BehaviourTreeRunner)

	self.config = BehaviourTreeRunner.getConfig().BehaviourTree
	self.treesByAgent = {}
	self.autoAgentsByFolder = {}
	self.warnedAgents = {}
	self.tickBuffer = {}
	self.timeSinceTick = 0

	self.worldBoard = {}
	BehaviourTreeRunner.BehaviorTreeCreator:RegisterSharedBlackboard(WORLD_BOARD, self.worldBoard)

	self.trove:Add(CollectionService:GetInstanceAddedSignal(TREE_TAG):Connect(function(treeFolder)
		self:_startAutoRun(treeFolder)
	end), "Disconnect")

	self.trove:Add(CollectionService:GetInstanceRemovedSignal(TREE_TAG):Connect(function(treeFolder)
		self:_stopAutoRun(treeFolder)
	end), "Disconnect")

	for _, treeFolder in CollectionService:GetTagged(TREE_TAG) do
		self:_startAutoRun(treeFolder)
	end

	self.trove:Add(RunService.Heartbeat:Connect(function(deltaTime)
		self:_tick(deltaTime)
	end), "Disconnect")

	return self
end

function BehaviourTreeRunner:getWorldBoard()
	return self.worldBoard
end

function BehaviourTreeRunner:register(agent, treeFolder)
	assert(type(agent) == "table", "[BehaviourTreeRunner] agent must be a table")

	local tree = BehaviourTreeRunner.BehaviorTreeCreator:Create(treeFolder)
	if not tree then
		warn("[BehaviourTreeRunner] could not build a tree from " .. treeFolder:GetFullName())
		return nil
	end

	self.treesByAgent[agent] = tree
	return tree
end

function BehaviourTreeRunner:unregister(agent)
	local tree = self.treesByAgent[agent]
	if not tree then return end

	tree:Abort(agent)
	tree.DataLookup[agent] = nil
	self.treesByAgent[agent] = nil
	self.warnedAgents[agent] = nil
end

function BehaviourTreeRunner:isRegistered(agent)
	return self.treesByAgent[agent] ~= nil
end

function BehaviourTreeRunner:_startAutoRun(treeFolder)
	if not treeFolder:GetAttribute(AUTO_RUN_ATTRIBUTE) then return end
	if self.autoAgentsByFolder[treeFolder] then return end

	local agent = { Blackboard = {}, instance = treeFolder }
	if self:register(agent, treeFolder) then
		self.autoAgentsByFolder[treeFolder] = agent
	end
end

function BehaviourTreeRunner:_stopAutoRun(treeFolder)
	local agent = self.autoAgentsByFolder[treeFolder]
	if not agent then return end

	self.autoAgentsByFolder[treeFolder] = nil
	self:unregister(agent)
end

function BehaviourTreeRunner:_tick(deltaTime)
	self.timeSinceTick += deltaTime
	if self.timeSinceTick < 1 / self.config.TickRate then return end
	self.timeSinceTick = 0

	local pending = self.tickBuffer
	table.clear(pending)
	for agent in self.treesByAgent do
		table.insert(pending, agent)
	end

	for _, agent in pending do
		local tree = self.treesByAgent[agent]
		if tree then
			local succeeded, failure = pcall(tree.Run, tree, agent)
			if not succeeded and not self.warnedAgents[agent] then
				self.warnedAgents[agent] = true
				local label = if typeof(agent.instance) == "Instance" then agent.instance:GetFullName() else "<unnamed agent>"
				warn(string.format("[BehaviourTreeRunner] %s stopped: its tree errors every tick, so no branch past the fault runs. Further warnings for it suppressed. %s",
					label, tostring(failure)))
			end
		end
	end
end

return BehaviourTreeRunner
