local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Commerce = {}
Commerce.__index = Commerce
Commerce.Tag = "Commerce"

local localPlayer = Players.LocalPlayer

const RESTRICTED_TOAST_TEXT = "This item is restricted in your region."
const RESTRICTED_TOAST_COLOR = Color3.fromRGB(230, 80, 80)
const SUBSCRIPTION_PRICE_REFRESH = 300

local function subscriptionPriceFromInfo(data)
	if not data then return nil end
	local robux = data.PriceInRobux
	if type(robux) ~= "number" or robux <= 0 then
		robux = nil
	end
	local display = data.DisplayPrice
	if type(display) ~= "string" or display == "" then
		display = nil
	end
	if not robux and not display then return nil end
	return { robux = robux, display = display }
end

function Commerce.Start()
	setmetatable(Commerce, { __index = Commerce.BaseClass })

	Commerce.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(Commerce.Tag)
		end
	end)
end

function Commerce.new(instance)
	local self = setmetatable(Commerce.BaseClass.new(instance), Commerce)
	if instance ~= localPlayer then return self end

	self.gamepasses = {}
	self.onGamepassChanged = Commerce.GoodSignal.new()

	self.prices = {}
	self.onPricesChanged = Commerce.GoodSignal.new()

	self.subscriptionPrices = {}
	self.onSubscriptionPricesChanged = Commerce.GoodSignal.new()

	self:onRemoteEvent("GamepassSync", function(gamepassData)
		self.gamepasses = gamepassData or {}
		self.onGamepassChanged:Fire(self.gamepasses)
	end)

	self:onRemoteEvent("PriceSync", function(priceData)
		self.prices = priceData or {}
		self.onPricesChanged:Fire(self.prices)
	end)

	local subsConfig = Commerce.getConfig().Subscriptions
	if subsConfig then
		self._subPriceThread = task.spawn(function()
			while true do
				self:_pollSubscriptionPricesOnce(subsConfig)
				task.wait(SUBSCRIPTION_PRICE_REFRESH)
			end
		end)
	end

	return self
end

function Commerce:_pollSubscriptionPricesOnce(subsConfig)
	local changed = false
	for key, info in subsConfig do
		local id = info and info.id
		if id and id ~= "" then
			local ok, data = pcall(function()
				return MarketplaceService:GetSubscriptionProductInfoAsync(id)
			end)
			local fresh = ok and subscriptionPriceFromInfo(data)
			if fresh then
				local cached = self.subscriptionPrices[key]
				if not cached or cached.robux ~= fresh.robux or cached.display ~= fresh.display then
					self.subscriptionPrices[key] = fresh
					changed = true
				end
			end
		end
	end
	if changed then
		self.onSubscriptionPricesChanged:Fire(self.subscriptionPrices)
	end
end

function Commerce:ownsGamepass(gamepassKey)
	return self.gamepasses[gamepassKey] == true
end

function Commerce:isPaidRandomRestricted()
	local policy = Commerce.EntityStore.getComponent(self.instance, "PlayerPolicy")
	return not policy or policy:isPaidRandomRestricted()
end

local function showRestrictedToast()
	local notifs = Commerce.Notifications
	if notifs and notifs.show then
		notifs.show(RESTRICTED_TOAST_TEXT, { color = RESTRICTED_TOAST_COLOR })
	end
end

function Commerce:promptProductPurchase(productName)
	do
		local _mon = Commerce.getConfig().Monetization
		local _pi = _mon and _mon.DeveloperProducts[productName]
	end
	local monetization = Commerce.getConfig().Monetization
	local productInfo = monetization.DeveloperProducts[productName]
	if not productInfo or productInfo.id == 0 then
		warn("[Commerce] Unknown product: " .. tostring(productName))
		return
	end
	if productInfo.paidRandom and self:isPaidRandomRestricted() then
		showRestrictedToast()
		return
	end
	MarketplaceService:PromptProductPurchase(self.instance, productInfo.id)
end

function Commerce:promptGamePassPurchase(gamepassKey)
	local monetization = Commerce.getConfig().Monetization
	local info = monetization.Gamepasses and monetization.Gamepasses[gamepassKey]
	if not info then
		local available = {}
		if monetization.Gamepasses then
			for k in monetization.Gamepasses do
				table.insert(available, k)
			end
		end
		warn(("[Commerce] No Monetization.Gamepasses entry for key '%s' — available keys: %s"):format(
			tostring(gamepassKey),
			#available > 0 and table.concat(available, ", ") or "(none)"))
		return
	end
	if info.id == 0 then
		warn(("[Commerce] Gamepass '%s' has placeholder id=0 — set Monetization.Gamepasses.%s.id to the real dashboard id"):format(
			tostring(gamepassKey), tostring(gamepassKey)))
		return
	end
	if info.paidRandom and self:isPaidRandomRestricted() then
		showRestrictedToast()
		return
	end
	MarketplaceService:PromptGamePassPurchase(self.instance, info.id)
end

function Commerce:getPrice(productName)
	return self.prices[productName]
end

function Commerce:getSubscriptionPrice(subscriptionKey)
	return self.subscriptionPrices[subscriptionKey]
end

function Commerce:destroy()
	if self._subPriceThread then
		pcall(task.cancel, self._subPriceThread)
	end
	if self.onGamepassChanged then
		self.onGamepassChanged:DisconnectAll()
	end
	if self.onPricesChanged then
		self.onPricesChanged:DisconnectAll()
	end
	if self.onSubscriptionPricesChanged then
		self.onSubscriptionPricesChanged:DisconnectAll()
	end
end

return Commerce