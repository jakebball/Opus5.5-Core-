
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Subscription = {}
Subscription.__index = Subscription
Subscription.Tag = "Subscription"

local localPlayer = Players.LocalPlayer

function Subscription.Start()
	setmetatable(Subscription, { __index = Subscription.BaseClass })
	Subscription.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("Subscription")
		end
	end)
end

function Subscription.new(instance)
	local self = setmetatable(Subscription.BaseClass.new(instance), Subscription)
	if instance ~= localPlayer then
		return self
	end

	self.onChanged = Subscription.GoodSignal.new()
	self.config = Subscription.getConfig().Subscriptions or {}
	self._status = {}

	self:onRemoteEvent("SubscriptionSync", function(payload)
		if type(payload) ~= "table" or type(payload.status) ~= "table" then return end
		for key, val in payload.status do
			if type(val) == "boolean" and self._status[key] ~= val then
				self._status[key] = val
				self.onChanged:Fire(key, val)
			end
		end
	end)

	self:sendNetworkEvent("SubscriptionSync")

	return self
end

function Subscription:isSubscribed(key)
	return self._status[key] == true
end

function Subscription:prompt(key)
	local info = self.config[key]
	if not info or not info.id or info.id == "" then
		warn("[Subscription] no subscription id configured for key: " .. tostring(key))
		return false
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptSubscriptionPurchase(localPlayer, info.id)
	end)
	if not ok then
		warn("[Subscription] PromptSubscriptionPurchase failed: " .. tostring(err))
	end
	return ok
end

function Subscription:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	if self.trove then
		self.trove:Clean()
	end
end

return Subscription
