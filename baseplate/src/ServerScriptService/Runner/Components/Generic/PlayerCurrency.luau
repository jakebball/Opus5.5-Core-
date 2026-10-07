local PlayerCurrency = {}
PlayerCurrency.__index = PlayerCurrency
PlayerCurrency.Tag = "PlayerCurrency"

function PlayerCurrency.Start()
	setmetatable(PlayerCurrency, { __index = PlayerCurrency.BaseClass })
	PlayerCurrency.Observers.observePlayer(function(player)
		player:AddTag("PlayerCurrency")
	end)
end

function PlayerCurrency.new(instance)
	local self = setmetatable(PlayerCurrency.BaseClass.new(instance), PlayerCurrency)

	self:registerRemote("CurrencySync")

	self.onChanged = PlayerCurrency.GoodSignal.new()
	self.onEarned = PlayerCurrency.GoodSignal.new()

	PlayerCurrency.EntityStore.promiseGetComponent(instance, "PlayerProfile"):andThen(function(profileComp)
		profileComp:modifyProfileData(function(data)
			data.Currencies = data.Currencies or {}
			if data.Coins ~= nil then
				data.Currencies.Coins = data.Currencies.Coins or data.Coins
				data.Coins = nil
			end
			return data
		end)
		self:_sync()
	end)

	return self
end

function PlayerCurrency:_data()
	local profile = PlayerCurrency.EntityStore.getComponent(self.instance, "PlayerProfile")
	if not profile or not profile.profile then return nil end
	local data = profile.profile.Data
	data.Currencies = data.Currencies or {}
	return data
end

function PlayerCurrency:_sync()
	local data = self:_data()
	if not data then return end
	self:sendNetworkEvent(self.instance, "CurrencySync", data.Currencies)
	if self.onChanged then
		self.onChanged:Fire(data.Currencies)
	end
end

function PlayerCurrency:get(name)
	local data = self:_data()
	if not data then return 0 end
	return data.Currencies[name] or 0
end

function PlayerCurrency:getAll()
	local data = self:_data()
	if not data then return {} end
	return table.clone(data.Currencies)
end

function PlayerCurrency:canAfford(name, amount)
	return self:get(name) >= amount
end

function PlayerCurrency:add(name, amount)
	if amount < 0 then
		warn("[PlayerCurrency] add called with negative amount; use remove instead")
		return
	end
	local profile = PlayerCurrency.EntityStore.getComponent(self.instance, "PlayerProfile")
	if not profile then
		warn("[PlayerCurrency] No PlayerProfile for add")
		return
	end

	profile:modifyProfileData(function(data)
		data.Currencies = data.Currencies or {}
		data.Currencies[name] = (data.Currencies[name] or 0) + amount
		return data
	end)
	self:_sync()
	if self.onEarned then
		self.onEarned:Fire(name, amount)
	end
end

function PlayerCurrency:remove(name, amount)
	if amount < 0 then
		warn("[PlayerCurrency] remove called with negative amount; use add instead")
		return false
	end
	local profile = PlayerCurrency.EntityStore.getComponent(self.instance, "PlayerProfile")
	if not profile then
		warn("[PlayerCurrency] No PlayerProfile for remove")
		return false
	end

	local current = self:get(name)
	if current < amount then
		return false
	end

	profile:modifyProfileData(function(data)
		data.Currencies = data.Currencies or {}
		data.Currencies[name] = (data.Currencies[name] or 0) - amount
		return data
	end)
	self:_sync()
	return true
end

function PlayerCurrency:set(name, amount)
	local profile = PlayerCurrency.EntityStore.getComponent(self.instance, "PlayerProfile")
	if not profile then
		warn("[PlayerCurrency] No PlayerProfile for set")
		return
	end

	profile:modifyProfileData(function(data)
		data.Currencies = data.Currencies or {}
		data.Currencies[name] = amount
		return data
	end)
	self:_sync()
end

function PlayerCurrency:transact(deltas)
	local profile = PlayerCurrency.EntityStore.getComponent(self.instance, "PlayerProfile")
	if not profile then
		warn("[PlayerCurrency] No PlayerProfile for transact")
		return false
	end

	local data = self:_data()
	if not data then return false end

	for name, delta in deltas do
		if delta < 0 and (data.Currencies[name] or 0) + delta < 0 then
			return false
		end
	end

	profile:modifyProfileData(function(d)
		d.Currencies = d.Currencies or {}
		for name, delta in deltas do
			d.Currencies[name] = (d.Currencies[name] or 0) + delta
		end
		return d
	end)
	self:_sync()
	return true
end

function PlayerCurrency:destroy()
	self.trove:Clean()
end

return PlayerCurrency