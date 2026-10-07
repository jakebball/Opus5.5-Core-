
local Players = game:GetService("Players")

local Quests = {}
Quests.__index = Quests
Quests.Tag = "Quests"

local localPlayer = Players.LocalPlayer

function Quests.Start()
	setmetatable(Quests, { __index = Quests.BaseClass })
	Quests.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("Quests")
		end
	end)
end

function Quests.new(instance)
	local self = setmetatable(Quests.BaseClass.new(instance, { remoteInstance = localPlayer }), Quests)
	if instance ~= localPlayer then
		return self
	end

	self.state = {}
	self.onChanged = Quests.GoodSignal.new()

	task.spawn(function()
		self:_init()
	end)

	return self
end

function Quests:_init()
	self:onRemoteEvent("QuestsSync", function(payload)
		self:_onSync(payload)
	end)
	self:requestSync()
end

function Quests:_onSync(payload)
	if type(payload) ~= "table" then return end
	self.state = payload
	self.onChanged:Fire(self.state)
end

function Quests:getState()
	return self.state
end

function Quests:getCategory(category)
	return self.state[category]
end

function Quests:getProgress(category, questId)
	local cat = self.state[category]
	return (cat and cat.progress and cat.progress[questId]) or 0
end

function Quests:isCompleted(category, questId)
	local cat = self.state[category]
	return cat ~= nil and cat.completed ~= nil and cat.completed[questId] == true
end

function Quests:getResetAt(category)
	local cat = self.state[category]
	return cat and cat.resetAt or nil
end

function Quests:requestSync()
	self:sendNetworkEvent("QuestsRequestSync")
end

function Quests:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	if self.trove then
		self.trove:Clean()
	end
end

return Quests