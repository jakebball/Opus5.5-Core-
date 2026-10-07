
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Subscription = {}
Subscription.__index = Subscription
Subscription.Tag = "Subscription"

const REFRESH_INTERVAL = 300

function Subscription.Start()
	setmetatable(Subscription, { __index = Subscription.BaseClass })
	Subscription.Observers.observePlayer(function(player)
		player:AddTag("Subscription")
	end)
	MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(player)
		local comp = Subscription.EntityStore.getComponent(player, "Subscription")
		if comp then
			task.spawn(function()
				comp:refresh()
			end)
		end
	end)
end

function Subscription.new(instance)
	local self = setmetatable(Subscription.BaseClass.new(instance), Subscription)

	self.onChanged = Subscription.GoodSignal.new()
	self._status = {}
	self.config = Subscription.getConfig().Subscriptions or {}

	self:registerRemote("SubscriptionSync")
	self:onRemoteEvent("SubscriptionSync", function()
		self:_sync()
	end)

	self._pollThread = task.spawn(function()
		self:refresh()
		while self.instance and self.instance:IsDescendantOf(Players) do
			task.wait(REFRESH_INTERVAL)
			self:refresh()
		end
	end)

	return self
end

function Subscription:_pollOne(id)
	if not id or id == "" then return false end
	local ok, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(self.instance, id)
	end)
	if not ok then
		warn("[Subscription] GetUserSubscriptionStatusAsync failed for " .. tostring(id) .. ": " .. tostring(status))
		return nil
	end
	return status ~= nil and status.IsSubscribed == true
end

function Subscription:refresh()
	local changed = false
	for key, info in self.config do
		local result = self:_pollOne(info and info.id)
		if result ~= nil and result ~= self._status[key] then
			self._status[key] = result
			self.onChanged:Fire(key, result)
			changed = true
		end
	end
	if changed then self:_sync() end
end

function Subscription:_sync()
	self:sendNetworkEvent(self.instance, "SubscriptionSync", { status = table.clone(self._status) })
end

function Subscription:isSubscribed(key)
	return self._status[key] == true
end

function Subscription:destroy()
	if self._pollThread then
		pcall(task.cancel, self._pollThread)
	end
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	self.trove:Clean()
end

return Subscription
