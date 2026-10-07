local Players = game:GetService("Players")

local Inventory = {}
Inventory.__index = Inventory
Inventory.Tag = "Inventory"

local localPlayer = Players.LocalPlayer

function Inventory.Start()
	setmetatable(Inventory, { __index = Inventory.BaseClass })
	Inventory.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("Inventory")
		end
	end)
end

function Inventory.new(instance)
	local self = setmetatable(Inventory.BaseClass.new(instance), Inventory)
	if instance ~= localPlayer then return self end

	self.items = {}
	self.orderedGuids = {}
	self.onItemAdded = Inventory.GoodSignal.new()
	self.onItemRemoved = Inventory.GoodSignal.new()
	self.onItemUpdated = Inventory.GoodSignal.new()
	self.onCleared = Inventory.GoodSignal.new()

	self:onRemoteEvent("InventoryItemAdded", function(guid, itemData)
		self.items[guid] = itemData
		table.insert(self.orderedGuids, 1, guid)
		self.onItemAdded:Fire(guid, itemData)
	end)

	self:onRemoteEvent("InventoryItemRemoved", function(guid)
		local itemData = self.items[guid]
		self.items[guid] = nil
		for i, g in self.orderedGuids do
			if g == guid then
				table.remove(self.orderedGuids, i)
				break
			end
		end
		self.onItemRemoved:Fire(guid, itemData)
	end)

	self:onRemoteEvent("InventoryItemUpdated", function(guid, itemData)
		self.items[guid] = itemData
		self.onItemUpdated:Fire(guid, itemData)
	end)

	self:onRemoteEvent("InventoryCleared", function()
		self.items = {}
		self.orderedGuids = {}
		self.onCleared:Fire()
	end)

	return self
end

function Inventory:getItems()
	local result = {}
	for _, guid in self.orderedGuids do
		table.insert(result, { guid = guid, data = self.items[guid] })
	end
	return result
end

function Inventory:getItem(guid)
	return self.items[guid]
end

function Inventory:getCount()
	return #self.orderedGuids
end

function Inventory:destroy()
	if self.onItemAdded then self.onItemAdded:DisconnectAll() end
	if self.onItemRemoved then self.onItemRemoved:DisconnectAll() end
	if self.onItemUpdated then self.onItemUpdated:DisconnectAll() end
	if self.onCleared then self.onCleared:DisconnectAll() end
end

return Inventory