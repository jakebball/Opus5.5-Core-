local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

const PRICE_POLL_INTERVAL = 30

local Commerce = {}
Commerce.__index = Commerce
Commerce.Tag = "Commerce"

local priceCache = {}

-- PriceInRobux is the developer's base figure and UserBasePriceInRobux is what the buyer is actually
-- charged; the two differ by the platform's uplift (49 buys against a base of 40 in this universe),
-- so a shop panel fed the first one under-quotes the prompt the player is about to see. The fallback
-- covers a product old enough not to carry the second field.
local function buyerPrice(data)
	if not data then return nil end
	return data.UserBasePriceInRobux or data.PriceInRobux
end

function Commerce.Start()
	setmetatable(Commerce, { __index = Commerce.BaseClass })

	Commerce.Observers.observePlayer(function(player)
		player:AddTag(Commerce.Tag)
	end)

	local monetConfig = Commerce.getConfig().Monetization

	if monetConfig and monetConfig.DeveloperProducts then
		for key, info in monetConfig.DeveloperProducts do
			if info.price then
				priceCache[key] = info.price
			end
			task.spawn(function()
				local ok, data = pcall(function()
					return MarketplaceService:GetProductInfo(info.id, Enum.InfoType.Product)
				end)
				local price = ok and buyerPrice(data)
				if price then
					priceCache[key] = price
					Commerce._broadcastPrices()
				end
			end)
		end

		task.spawn(function()
			while true do
				task.wait(PRICE_POLL_INTERVAL)
				if Commerce._pollPrices() then
					Commerce._broadcastPrices()
				end
			end
		end)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then return end
		local commerce = Commerce.EntityStore.getComponent(player, "Commerce")
		if commerce then
			commerce:onGamepassPurchased(gamepassId)
		end
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player or not player.Parent then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local commerce = Commerce.EntityStore.getComponent(player, "Commerce")
		if not commerce then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, granted = pcall(function()
			return commerce:onProductPurchased(receiptInfo.ProductId)
		end)
		if ok and granted then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not ok then
			warn("[Commerce] ProcessReceipt error for product " .. tostring(receiptInfo.ProductId) .. ": " .. tostring(granted))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function Commerce._pollPrices()
	local monetConfig = Commerce.getConfig().Monetization
	if not monetConfig or not monetConfig.DeveloperProducts then
		return false
	end
	local changed = false
	for key, info in monetConfig.DeveloperProducts do
		local ok, data = pcall(function()
			return MarketplaceService:GetProductInfo(info.id, Enum.InfoType.Product)
		end)
		local price = ok and buyerPrice(data)
		if price and priceCache[key] ~= price then
			priceCache[key] = price
			changed = true
		end
	end
	return changed
end

function Commerce._broadcastPrices()
	for _, player in Players:GetPlayers() do
		local c = Commerce.EntityStore.getComponent(player, "Commerce")
		if c then
			c:syncPrices()
		end
	end
end

function Commerce.new(instance)
	local self = Commerce.BaseClass.new(instance)
	setmetatable(self, Commerce)

	self.productHandlers = {}
	self.gamepasses = {}
	self._sessionPurchases = {}
	self.grantHandlers = {}
	self.monetizationConfig = Commerce.getConfig().Monetization

	self:registerRemote("GamepassSync")
	self:registerRemote("PriceSync")

	self:_setupProductHandlers()

	task.spawn(function()
		local changed = self:pollGamepassOwnership()
		if changed then self:syncToClient() end
	end)

	self:syncPrices()

	self.onPricesChanged = Commerce.GoodSignal.new()

	return self
end

function Commerce:registerGrantHandler(kind, handler)
	self.grantHandlers[kind] = handler
end

function Commerce:getPrice(productKey)
	return priceCache[productKey]
end

function Commerce:isPaidRandomRestricted()
	local policy = Commerce.EntityStore.getComponent(self.instance, "PlayerPolicy")
	if not policy then return true end
	return policy:arePaidRandomItemsRestricted()
end

function Commerce:_setupProductHandlers()
	local config = self.monetizationConfig
	if not config or not config.DeveloperProducts then return end

	for productKey, info in config.DeveloperProducts do
		if info.grant then
			local grant = info.grant
			local paidRandom = info.paidRandom == true
			local displayKey = productKey
			self:registerProductHandler(info.id, function()
				if paidRandom and self:isPaidRandomRestricted() then
					warn(string.format(
						"[Commerce] refusing paid-random grant '%s' for %s (PolicyService restricted)",
						tostring(displayKey), self.instance.Name))
					return false
				end
				return self:_fulfillGrant(grant)
			end)
		end
	end
end

function Commerce:onProductPurchased(productId)
	local handler = self.productHandlers[productId]
	if not handler then
		warn("[Commerce] No handler for product " .. tostring(productId))
		return false
	end
	return handler()
end

function Commerce:_fulfillGrant(grant)
	if type(grant) ~= "table" or not grant.kind then
		warn("[Commerce] malformed grant: " .. tostring(grant))
		return false
	end
	local handler = self.grantHandlers[grant.kind]
	if not handler then
		warn("[Commerce] no grant handler registered for kind: " .. tostring(grant.kind))
		return false
	end
	local result = handler(self, grant)
	if result then
		local shopTx = Commerce.EntityStore.getComponent(self.instance, "ShopTransactions")
		if shopTx and shopTx.firePurchaseSuccess then
			shopTx:firePurchaseSuccess("robux")
		end
	end
	return result
end

function Commerce:registerProductHandler(productId, callback)
	self.productHandlers[productId] = callback
end

function Commerce:pollGamepassOwnership()
	local changed = false
	for gamepassKey, gamepassInfo in self.monetizationConfig.Gamepasses do
		local success, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(self.instance.UserId, gamepassInfo.id)
		end)
		if success then
			if self._sessionPurchases[gamepassKey] then
				owns = true
			end
			if self.gamepasses[gamepassKey] ~= owns then
				self.gamepasses[gamepassKey] = owns
				changed = true
			end
		else
			warn("[Commerce] Error checking gamepass for " .. self.instance.Name .. ": " .. tostring(owns))
		end
	end
	return changed
end

function Commerce:onGamepassPurchased(gamepassId)
	for gamepassKey, gamepassInfo in self.monetizationConfig.Gamepasses do
		if gamepassInfo.id == gamepassId then
			self._sessionPurchases[gamepassKey] = true
			self.gamepasses[gamepassKey] = true
			self:syncToClient()
			return
		end
	end
end

function Commerce:syncToClient()
	self:sendNetworkEvent(self.instance, "GamepassSync", self.gamepasses)
end

function Commerce:syncPrices()
	self:sendNetworkEvent(self.instance, "PriceSync", priceCache)
end

function Commerce.getPriceCache()
	return priceCache
end

function Commerce:ownsGamepass(gamepassKey)
	return self.gamepasses[gamepassKey] == true
end

function Commerce:destroy()
	self.trove:Clean()
end

return Commerce