
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.AdminSystem.Config)

local GroupMembership = {}
GroupMembership.__index = GroupMembership
GroupMembership.Tag = "GroupMembership"

function GroupMembership.Start()
	setmetatable(GroupMembership, { __index = GroupMembership.BaseClass })
	GroupMembership.Observers.observePlayer(function(player)
		player:AddTag("GroupMembership")
	end)
end

function GroupMembership.new(instance)
	local self = setmetatable(GroupMembership.BaseClass.new(instance), GroupMembership)

	self.onChanged = GroupMembership.GoodSignal.new()
	self._inGroup = false

	self:registerRemote("GroupMembershipSync")
	self:onRemoteEvent("GroupMembershipSync", function()
		self:_sync()
	end)

	task.spawn(function()
		self:refresh()
	end)

	return self
end

function GroupMembership:_poll()
	local groupId = AdminConfig.GroupId
	if not groupId or groupId <= 0 then return false end
	local ok, result = pcall(function()
		return self.instance:IsInGroup(groupId)
	end)
	return ok and result == true
end

function GroupMembership:refresh()
	local inGroup = self:_poll()
	if inGroup ~= self._inGroup then
		self._inGroup = inGroup
		self:_sync()
		self.onChanged:Fire(inGroup)
	end
	return inGroup
end

function GroupMembership:_sync()
	self:sendNetworkEvent(self.instance, "GroupMembershipSync", { inGroup = self._inGroup })
end

function GroupMembership:isInGroup()
	return self._inGroup
end

function GroupMembership:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	self.trove:Clean()
end

return GroupMembership
