local Players = game:GetService("Players")

local PlayerCurrency = {}
PlayerCurrency.__index = PlayerCurrency
PlayerCurrency.Tag = "PlayerCurrency"

local localPlayer = Players.LocalPlayer

function PlayerCurrency.Start()
	setmetatable(PlayerCurrency, { __index = PlayerCurrency.BaseClass })
	PlayerCurrency.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("PlayerCurrency")
		end
	end)
end

function PlayerCurrency.new(instance)
	local self = setmetatable(PlayerCurrency.BaseClass.new(instance), PlayerCurrency)
	if instance ~= localPlayer then return self end

	self.currencies = {}
	self.onCurrencyChanged = PlayerCurrency.GoodSignal.new()

	self:onRemoteEvent("CurrencySync", function(currencies)
		self.currencies = currencies or {}
		self.onCurrencyChanged:Fire(self.currencies)
	end)

	return self
end

function PlayerCurrency:get(name)
	return self.currencies[name] or 0
end

function PlayerCurrency:getAll()
	return table.clone(self.currencies)
end

function PlayerCurrency:destroy()
	if self.onCurrencyChanged then
		self.onCurrencyChanged:DisconnectAll()
	end
end

return PlayerCurrency