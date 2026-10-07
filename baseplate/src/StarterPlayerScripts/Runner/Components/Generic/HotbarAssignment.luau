local Players = game:GetService("Players")

local HotbarAssignment = {}
HotbarAssignment.__index = HotbarAssignment
HotbarAssignment.Tag = "HotbarAssignment"

local localPlayer = Players.LocalPlayer

function HotbarAssignment.Start()
	setmetatable(HotbarAssignment, { __index = HotbarAssignment.BaseClass })
	HotbarAssignment.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("HotbarAssignment")
		end
	end)
end

function HotbarAssignment.new(instance)
	local self = HotbarAssignment.BaseClass.new(instance)
	setmetatable(self, HotbarAssignment)

	if instance ~= localPlayer then return self end

	self.hotbarGuids = {}
	self.hotbarSet = {}
	self.onSlotAdded = HotbarAssignment.GoodSignal.new()
	self.onSlotRemoved = HotbarAssignment.GoodSignal.new()
	self.onSynced = HotbarAssignment.GoodSignal.new()

	HotbarAssignment.EntityStore.promiseGetComponent(localPlayer, "Inventory"):andThen(function(inventory)
		self.inventory = inventory
	end)

	self:onRemoteEvent("HotbarSync", function(guids)
		self.hotbarGuids = guids
		self.hotbarSet = {}
		for _, guid in guids do
			self.hotbarSet[guid] = true
		end
		self.onSynced:Fire()
	end)

	self:onRemoteEvent("HotbarSlotAdded", function(guid, itemData)
		if self.hotbarSet[guid] then return end
		table.insert(self.hotbarGuids, guid)
		self.hotbarSet[guid] = true
		self.onSlotAdded:Fire(guid, itemData)
	end)

	self:onRemoteEvent("HotbarSlotRemoved", function(guid)
		if not self.hotbarSet[guid] then return end
		for i, g in self.hotbarGuids do
			if g == guid then
				table.remove(self.hotbarGuids, i)
				break
			end
		end
		self.hotbarSet[guid] = nil
		local itemData = self.inventory and self.inventory:getItem(guid)
		self.onSlotRemoved:Fire(guid, itemData)
	end)

	return self
end

function HotbarAssignment:isOnHotbar(guid)
	return self.hotbarSet[guid] == true
end

function HotbarAssignment:getHotbarGuids()
	return self.hotbarGuids
end

function HotbarAssignment:requestMoveToHotbar(guid)
	self:sendNetworkEvent("RequestMoveToHotbar", guid)
end

function HotbarAssignment:requestMoveToBackpack(guid)
	self:sendNetworkEvent("RequestMoveToBackpack", guid)
end

function HotbarAssignment:requestSwapHotbarSlot(newGuid, oldGuid)
	self:sendNetworkEvent("RequestSwapHotbarSlot", newGuid, oldGuid)
end

function HotbarAssignment:destroy()
	if self.onSlotAdded then self.onSlotAdded:DisconnectAll() end
	if self.onSlotRemoved then self.onSlotRemoved:DisconnectAll() end
	if self.onSynced then self.onSynced:DisconnectAll() end
end

return HotbarAssignment