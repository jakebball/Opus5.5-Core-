const MAX_SLOTS = 8

local HotbarAssignment = {}
HotbarAssignment.__index = HotbarAssignment
HotbarAssignment.Tag = "HotbarAssignment"

function HotbarAssignment.Start()
	setmetatable(HotbarAssignment, { __index = HotbarAssignment.BaseClass })
	HotbarAssignment.Observers.observePlayer(function(player)
		player:AddTag("HotbarAssignment")
	end)
end

function HotbarAssignment.new(instance)
	local self = HotbarAssignment.BaseClass.new(instance)
	setmetatable(self, HotbarAssignment)

	self.player = instance
	self.hotbarGuids = {}
	self.hotbarSet = {}
	self.profileLoaded = false
	self.onSlotAdded = HotbarAssignment.GoodSignal.new()
	self.onSlotRemoved = HotbarAssignment.GoodSignal.new()
	self.pinnedGuids = {}
	self._pins = {}

	self:registerRemote("HotbarSync")
	self:registerRemote("HotbarSlotAdded")
	self:registerRemote("HotbarSlotRemoved")
	self:registerRemote("RequestMoveToHotbar")
	self:registerRemote("RequestMoveToBackpack")
	self:registerRemote("RequestSwapHotbarSlot")

	self:onRemoteEvent("RequestMoveToHotbar", function(player, guid)
		if player ~= self.player then return end
		self:moveToHotbar(guid)
	end)

	self:onRemoteEvent("RequestMoveToBackpack", function(player, guid)
		if player ~= self.player then return end
		self:moveToBackpack(guid)
	end)

	self:onRemoteEvent("RequestSwapHotbarSlot", function(player, newGuid, oldGuid)
		if player ~= self.player then return end
		self:swapHotbarSlot(newGuid, oldGuid)
	end)

	HotbarAssignment.EntityStore.promiseGetComponent(instance, "Inventory"):andThen(function(inventory)
		self.inventory = inventory

		self.trove:Add(inventory.onItemAdded:Connect(function(guid, itemData)
			if not self.profileLoaded then return end

			if #self.hotbarGuids < MAX_SLOTS and not self.hotbarSet[guid] then
				self:addToHotbar(guid, itemData)
			end
		end), "Disconnect")

		self.trove:Add(inventory.onItemRemoved:Connect(function(guid)
			if self.hotbarSet[guid] then
				self:removeFromHotbar(guid)
			end
		end), "Disconnect")

		if inventory.loaded then
			self:loadFromProfile()
		else
			self.trove:Add(inventory.onLoaded:Connect(function()
				self:loadFromProfile()
			end), "Disconnect")
		end
	end)

	return self
end

function HotbarAssignment:loadFromProfile()
	HotbarAssignment.EntityStore.promiseGetComponent(self.player, "PlayerProfile"):andThen(function(profile)
		self.profile = profile
		local data = profile:getProfileData()
		local savedIndices = data and data.HotbarGuids

		if savedIndices and #savedIndices > 0 then
			local items = self.inventory:getItems()
			for _, idx in savedIndices do
				local entry = items[idx]
				if entry and not self.hotbarSet[entry.guid] then
					self:addToHotbar(entry.guid, entry.data)
				end
			end
		else
			local items = self.inventory:getItems()
			for i, entry in items do
				if i > MAX_SLOTS then break end
				if not self.hotbarSet[entry.guid] then
					self:addToHotbar(entry.guid, entry.data)
				end
			end
		end

		self.profileLoaded = true
		self:_applyPins()

		self:sendNetworkEvent(self.player, "HotbarSync", self.hotbarGuids)
	end)
end

function HotbarAssignment:saveToProfile()
	if not self.profile then return end
	self.profile:modifyProfileData(function(data)
		local indices = {}
		local items = self.inventory:getItems()
		local guidToIndex = {}
		local persistentIdx = 0
		for _, entry in items do
			if entry.data and not entry.data.transient and not entry.data.hidden then
				persistentIdx += 1
				guidToIndex[entry.guid] = persistentIdx
			end
		end
		for _, guid in self.hotbarGuids do
			local idx = guidToIndex[guid]
			if idx then
				table.insert(indices, idx)
			end
		end
		data.HotbarGuids = indices
		return data
	end)
end

function HotbarAssignment:addToHotbar(guid, itemData)
	table.insert(self.hotbarGuids, guid)
	self.hotbarSet[guid] = true
	self.onSlotAdded:Fire(guid, itemData)
	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSlotAdded", guid, itemData)
	end
	self:saveToProfile()
end

function HotbarAssignment:removeFromHotbar(guid)
	local itemData = self.inventory and self.inventory:getItem(guid)
	for i, g in self.hotbarGuids do
		if g == guid then
			table.remove(self.hotbarGuids, i)
			break
		end
	end
	self.hotbarSet[guid] = nil
	self.onSlotRemoved:Fire(guid, itemData)
	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSlotRemoved", guid)
	end
	self:saveToProfile()
end

function HotbarAssignment:pinToSlot(guid, index)
	self._pins = self._pins or {}
	table.insert(self._pins, { guid = guid, index = index })
	if self.profileLoaded then
		self:_applyPins()
	end
end

function HotbarAssignment:_applyPins()
	if not self._pins or #self._pins == 0 then return end
	if not self.inventory then return end
	self.pinnedGuids = self.pinnedGuids or {}

	for _, pin in self._pins do
		local guid = pin.guid
		if self.inventory:getItem(guid) then
			for i, g in self.hotbarGuids do
				if g == guid then
					table.remove(self.hotbarGuids, i)
					break
				end
			end
			local index = math.clamp(pin.index, 1, #self.hotbarGuids + 1)
			table.insert(self.hotbarGuids, index, guid)
			self.hotbarSet[guid] = true
			self.pinnedGuids[guid] = true
			self.onSlotAdded:Fire(guid, self.inventory:getItem(guid))
		end
	end

	local i = #self.hotbarGuids
	while #self.hotbarGuids > MAX_SLOTS and i >= 1 do
		local g = self.hotbarGuids[i]
		if not self.pinnedGuids[g] then
			table.remove(self.hotbarGuids, i)
			self.hotbarSet[g] = nil
			self.onSlotRemoved:Fire(g, self.inventory:getItem(g))
			if self.player:IsA("Player") then
				self:sendNetworkEvent(self.player, "HotbarSlotRemoved", g)
			end
		end
		i -= 1
	end

	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSync", self.hotbarGuids)
	end
end

function HotbarAssignment:moveToHotbar(guid)
	if not self.inventory then return false end
	if not self.inventory:getItem(guid) then return false end
	if self.hotbarSet[guid] then return false end
	if #self.hotbarGuids >= MAX_SLOTS then return false end

	self:addToHotbar(guid, self.inventory:getItem(guid))
	return true
end

function HotbarAssignment:swapHotbarSlot(newGuid, oldGuid)
	if not self.inventory then return false end
	if not self.inventory:getItem(newGuid) then return false end
	if not self.hotbarSet[oldGuid] then return false end
	if self.hotbarSet[newGuid] then return false end
	if self.pinnedGuids and (self.pinnedGuids[oldGuid] or self.pinnedGuids[newGuid]) then return false end

	local character = self.player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("ItemGuid") == oldGuid then
				child.Parent = self.player.Backpack
				break
			end
		end
	end

	for i, g in self.hotbarGuids do
		if g == oldGuid then
			self.hotbarGuids[i] = newGuid
			break
		end
	end
	self.hotbarSet[oldGuid] = nil
	self.hotbarSet[newGuid] = true

	local oldData = self.inventory:getItem(oldGuid)
	self.onSlotRemoved:Fire(oldGuid, oldData)
	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSlotRemoved", oldGuid)
	end

	local newData = self.inventory:getItem(newGuid)
	self.onSlotAdded:Fire(newGuid, newData)
	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSlotAdded", newGuid, newData)
	end

	if self.player:IsA("Player") then
		self:sendNetworkEvent(self.player, "HotbarSync", self.hotbarGuids)
	end

	self:saveToProfile()
	return true
end

function HotbarAssignment:moveToBackpack(guid)
	if not self.hotbarSet[guid] then return false end
	if self.pinnedGuids and self.pinnedGuids[guid] then return false end

	local character = self.player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("ItemGuid") == guid then
				child.Parent = self.player.Backpack
				break
			end
		end
	end

	self:removeFromHotbar(guid)
	return true
end

function HotbarAssignment:isOnHotbar(guid)
	return self.hotbarSet[guid] == true
end

function HotbarAssignment:getHotbarGuids()
	return self.hotbarGuids
end

function HotbarAssignment:getBackpackGuids()
	if not self.inventory then return {} end
	local result = {}
	for _, entry in self.inventory:getItems() do
		if not self.hotbarSet[entry.guid] then
			table.insert(result, entry.guid)
		end
	end
	return result
end

function HotbarAssignment:destroy()
	self.onSlotAdded:DisconnectAll()
	self.onSlotRemoved:DisconnectAll()
end

return HotbarAssignment