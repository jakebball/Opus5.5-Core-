
local Players = game:GetService("Players")

local GroupMembership = {}
GroupMembership.__index = GroupMembership
GroupMembership.Tag = "GroupMembership"

local localPlayer = Players.LocalPlayer

function GroupMembership.Start()
	setmetatable(GroupMembership, { __index = GroupMembership.BaseClass })
	GroupMembership.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("GroupMembership")
		end
	end)
end

function GroupMembership.new(instance)
	local self = setmetatable(GroupMembership.BaseClass.new(instance), GroupMembership)
	if instance ~= localPlayer then return self end

	self._inGroup = false
	self.onChanged = GroupMembership.GoodSignal.new()

	self:onRemoteEvent("GroupMembershipSync", function(state)
		if type(state) ~= "table" or type(state.inGroup) ~= "boolean" then return end
		if state.inGroup == self._inGroup then return end
		self._inGroup = state.inGroup
		self.onChanged:Fire(self._inGroup)
	end)

	self:sendNetworkEvent("GroupMembershipSync")

	return self
end

function GroupMembership:isInGroup()
	return self._inGroup
end

function GroupMembership:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	if self.trove then
		self.trove:Clean()
	end
end

return GroupMembership
