local HttpService = game:GetService("HttpService")

local Inventory = {}
Inventory.__index = Inventory
Inventory.Tag = "Inventory"

local function isStackable(itemData)
	return itemData and itemData.kind == "Resource"
end

function Inventory.Start()
	setmetatable(Inventory, { __index = Inventory.BaseClass })
	Inventory.Observers.observePlayer(function(player)
		player:AddTag("Inventory")
	end)
end

function Inventory.new(instance)
	local self = Inventory.BaseClass.new(instance)
	setmetatable(self, Inventory)

	self.items = {}
	self.orderedGuids = {}
	self.onItemAdded = Inventory.GoodSignal.new()
	self.onItemRemoved = Inventory.GoodSignal.new()
	self.onItemUpdated = Inventory.GoodSignal.new()
	self.onLoaded = Inventory.GoodSignal.new()
	self.loaded = false

	self:registerRemote("InventoryItemAdded")
	self:registerRemote("InventoryItemRemoved")
	self:registerRemote("InventoryItemUpdated")
	self:registerRemote("InventoryCleared")

	if instance:IsA("Player") then
		Inventory.EntityStore.promiseGetComponent(instance, "PlayerProfile"):andThen(function(profile)
			self.profile = profile
			self:loadFromProfile()
		end)
	end

	return self
end

function Inventory:loadFromProfile()
	if not self.profile then return end
	local data = self.profile:getProfileData()
	if not data or not data.Inventory then
		self.loaded = true
		self.onLoaded:Fire()
		return
	end

	for _, itemData in data.Inventory do
		if itemData.kind == "Slime" then itemData.kind = "Needoh" end
		local guid = HttpService:GenerateGUID(false)
		self.items[guid] = itemData
		table.insert(self.orderedGuids, guid)
	end

	self.loaded = true
	self.onLoaded:Fire()

	for _, guid in self.orderedGuids do
		self.onItemAdded:Fire(guid, self.items[guid], true)
		if self.instance:IsA("Player") then
			self:sendNetworkEvent(self.instance, "InventoryItemAdded", guid, self.items[guid])
		end
	end
end

function Inventory:saveToProfile()
	if not self.profile then return end
	self.profile:modifyProfileData(function(data)
		local saved = {}
		for _, guid in self.orderedGuids do
			local item = self.items[guid]
			if item and not item.transient then
				table.insert(saved, item)
			end
		end
		data.Inventory = saved
		return data
	end)
end

function Inventory:_findStackTarget(itemData)
	if not isStackable(itemData) then return nil end
	for _, guid in self.orderedGuids do
		local existing = self.items[guid]
		if existing and existing.kind == itemData.kind and existing.name == itemData.name then
			return guid, existing
		end
	end
	return nil, nil
end

function Inventory:add(itemData)
	if isStackable(itemData) then
		local guid, existing = self:_findStackTarget(itemData)
		if guid then
			local addQty = itemData.qty or 1
			existing.qty = (existing.qty or 1) + addQty
			self.onItemUpdated:Fire(guid, existing)
			if self.instance:IsA("Player") then
				self:sendNetworkEvent(self.instance, "InventoryItemUpdated", guid, existing)
			end
			self:saveToProfile()
			return guid
		end
		itemData.qty = itemData.qty or 1
	end

	local guid = HttpService:GenerateGUID(false)
	self.items[guid] = itemData
	table.insert(self.orderedGuids, 1, guid)
	if not itemData.hidden then
		self.onItemAdded:Fire(guid, itemData)
		if self.instance:IsA("Player") then
			self:sendNetworkEvent(self.instance, "InventoryItemAdded", guid, itemData)
		end
	end
	self:saveToProfile()
	return guid
end

function Inventory:removeStack(kind, name, qty)
	if not kind or not name then return 0 end
	qty = qty or math.huge
	for _, guid in self.orderedGuids do
		local existing = self.items[guid]
		if existing and existing.kind == kind and existing.name == name then
			local current = existing.qty or 1
			local removed = math.min(current, qty)
			if removed >= current then
				self:remove(guid)
			else
				existing.qty = current - removed
				self.onItemUpdated:Fire(guid, existing)
				if self.instance:IsA("Player") then
					self:sendNetworkEvent(self.instance, "InventoryItemUpdated", guid, existing)
				end
				self:saveToProfile()
			end
			return removed
		end
	end
	return 0
end

function Inventory:reveal(guid)
	local itemData = self.items[guid]
	if not itemData or not itemData.hidden then return end
	itemData.hidden = nil
	self.onItemAdded:Fire(guid, itemData)
	if self.instance:IsA("Player") then
		self:sendNetworkEvent(self.instance, "InventoryItemAdded", guid, itemData)
	end
	self:saveToProfile()
end

function Inventory:remove(guid)
	local itemData = self.items[guid]
	if not itemData then return nil end
	self.items[guid] = nil
	for i, g in self.orderedGuids do
		if g == guid then
			table.remove(self.orderedGuids, i)
			break
		end
	end

	self.onItemRemoved:Fire(guid, itemData)
	if self.instance:IsA("Player") then
		self:sendNetworkEvent(self.instance, "InventoryItemRemoved", guid)
	end
	self:saveToProfile()
	return itemData
end

function Inventory:getItem(guid)
	return self.items[guid]
end

function Inventory:getItems()
	local result = {}
	for _, guid in self.orderedGuids do
		table.insert(result, { guid = guid, data = self.items[guid] })
	end
	return result
end

function Inventory:getCount()
	return #self.orderedGuids
end

function Inventory:has(predicate)
	for _, guid in self.orderedGuids do
		if predicate(guid, self.items[guid]) then
			return true
		end
	end
	return false
end

function Inventory:findFirst(predicate)
	for _, guid in self.orderedGuids do
		local itemData = self.items[guid]
		if predicate(guid, itemData) then
			return guid, itemData
		end
	end
	return nil, nil
end

function Inventory:clear()
	self.items = {}
	self.orderedGuids = {}
	if self.instance:IsA("Player") then
		self:sendNetworkEvent(self.instance, "InventoryCleared")
	end
	self:saveToProfile()
end

function Inventory:removeFirst()
	if #self.orderedGuids == 0 then return nil, nil end
	local guid = self.orderedGuids[1]
	return guid, self:remove(guid)
end

function Inventory:destroy()
	self.onItemAdded:DisconnectAll()
	self.onItemRemoved:DisconnectAll()
	self.onItemUpdated:DisconnectAll()
	self.onLoaded:DisconnectAll()
end

return Inventory