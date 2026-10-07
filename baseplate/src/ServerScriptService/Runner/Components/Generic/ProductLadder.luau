local ProductLadder = {}
ProductLadder.__index = ProductLadder
ProductLadder.Tag = "ProductLadder"

const REWARD_GRANTS = {
	Dice = function(r) return { kind = "rollpack", diceCount = r.Amount } end,
	LuckyBlock = function(r) return { kind = "bundle", luckyBlockRarity = r.Rarity } end,
	Needoh = function(r) return { kind = "needoh", needohId = r.Id } end,
	Cash = function(r) return { kind = "cash", coins = r.Amount } end,
}

function ProductLadder.Start()
	setmetatable(ProductLadder, { __index = ProductLadder.BaseClass })
	ProductLadder.Observers.observePlayer(function(player)
		player:AddTag(ProductLadder.Tag)
	end)
end

function ProductLadder.new(instance)
	local self = ProductLadder.BaseClass.new(instance)
	setmetatable(self, ProductLadder)

	self:registerRemote("ProductLadderSync")

	self.player = instance

	ProductLadder.EntityStore.promiseGetComponent(instance, "PlayerProfile"):andThen(function(profile)
		self.profile = profile
		profile:waitForDataLoaded()
		if not profile.profile or not profile.profile.Data then return end

		profile:modifyProfileData(function(d)
			d.ProductLadders = d.ProductLadders or {}
			d.ProductLadderWindows = d.ProductLadderWindows or {}
			return d
		end)

		self:_initWindows()
		self:_syncToClient()
	end)

	ProductLadder.EntityStore.promiseGetComponent(instance, "Commerce"):andThen(function(commerce)
		self.commerce = commerce
		commerce:registerGrantHandler("ladderStep", function(_, grant)
			return self:_fulfillStep(grant.ladder, grant.step)
		end)
	end):catch(function() end)

	return self
end

local function getLadderConfig(ladderName)
	local config = ProductLadder.getConfig().ProductLadders
	if not config then return nil end
	return config[ladderName]
end

function ProductLadder:_getOwnedTable(ladderName)
	if not self.profile or not self.profile.profile then return {} end
	local data = self.profile.profile.Data.ProductLadders or {}
	return data[ladderName] or {}
end

function ProductLadder:getNextStep(ladderName)
	local config = getLadderConfig(ladderName)
	if not config then return nil end
	local owned = self:_getOwnedTable(ladderName)
	for _, step in config.Steps do
		if not owned[step] then
			return step
		end
	end
	return nil
end

function ProductLadder:isOwned(ladderName, stepKey)
	return self:_getOwnedTable(ladderName)[stepKey] == true
end

function ProductLadder:getOwnedSteps(ladderName)
	local copy = {}
	for k, v in self:_getOwnedTable(ladderName) do copy[k] = v end
	return copy
end

function ProductLadder:consumeStep(ladderName, stepKey)
	local config = getLadderConfig(ladderName)
	if not config then
		warn("[ProductLadder] unknown ladder: " .. tostring(ladderName))
		return false, false
	end

	if not self.profile or not self.profile.profile then return false, false end

	local owned = self:_getOwnedTable(ladderName)

	if owned[stepKey] then
		return true, false
	end

	local expected = self:getNextStep(ladderName)
	if expected ~= stepKey then
		warn(string.format(
			"[ProductLadder] out-of-order purchase on ladder %s: expected %s, got %s — consuming anyway",
			tostring(ladderName), tostring(expected), tostring(stepKey)
		))
		return true, false
	end

	self.profile:modifyProfileData(function(d)
		d.ProductLadders = d.ProductLadders or {}
		d.ProductLadders[ladderName] = d.ProductLadders[ladderName] or {}
		d.ProductLadders[ladderName][stepKey] = true
		return d
	end)

	self:_syncToClient()
	return true, true
end

function ProductLadder:_getWindows()
	if not self.profile or not self.profile.profile then return {} end
	return self.profile.profile.Data.ProductLadderWindows or {}
end

function ProductLadder:_windowStart(ladderName)
	return self:_getWindows()[ladderName]
end

function ProductLadder:_setWindowStart(ladderName, epoch)
	if not self.profile or not self.profile.profile then return end
	self.profile:modifyProfileData(function(d)
		d.ProductLadderWindows = d.ProductLadderWindows or {}
		d.ProductLadderWindows[ladderName] = epoch
		return d
	end)
end

function ProductLadder:_initWindows()
	local config = ProductLadder.getConfig().ProductLadders
	if not config then return end
	for ladderName, ladderConfig in config do
		if ladderConfig.DurationMinutes and self:getNextStep(ladderName) ~= nil then
			if not self:_windowStart(ladderName) then
				self:_setWindowStart(ladderName, os.time())
			end
		end
	end
end

function ProductLadder:getRemainingSeconds(ladderName)
	local config = getLadderConfig(ladderName)
	local minutes = config and config.DurationMinutes
	if not minutes then return math.huge end
	if self:getNextStep(ladderName) == nil then return 0 end
	local start = self:_windowStart(ladderName)
	if not start then return math.huge end
	return math.max(0, (minutes * 60) - (os.time() - start))
end

function ProductLadder:isActive(ladderName)
	if self:getNextStep(ladderName) == nil then return false end
	return self:getRemainingSeconds(ladderName) > 0
end

function ProductLadder:_fulfillStep(ladderName, stepKey)
	local config = getLadderConfig(ladderName)
	if not config then
		warn("[ProductLadder] ladderStep grant for unknown ladder " .. tostring(ladderName))
		return false
	end
	if not self.profile or not self.profile.profile then
		return false
	end

	if self:isOwned(ladderName, stepKey) then
		return true
	end

	if config.DurationMinutes and self:getRemainingSeconds(ladderName) <= 0 then
		warn(string.format(
			"[ProductLadder] %s/%s purchased past window; consuming receipt without grant",
			ladderName, tostring(stepKey)))
		return true
	end

	local consumed, newPurchase = self:consumeStep(ladderName, stepKey)
	if not consumed then
		return false
	end
	if not newPurchase then
		return true
	end

	local stepData = config.StepData and config.StepData[stepKey]
	if stepData and stepData.Rewards and self.commerce then
		for _, reward in stepData.Rewards do
			local builder = REWARD_GRANTS[reward.Kind]
			if builder then
				self.commerce:_fulfillGrant(builder(reward))
			else
				warn("[ProductLadder] unknown reward kind: " .. tostring(reward.Kind))
			end
		end
	end

	if config.DurationMinutes then
		self:_setWindowStart(ladderName, os.time())
	end
	self:_syncToClient()

	return true
end

function ProductLadder:_syncToClient()
	if not self.profile or not self.profile.profile then return end
	local owned = self.profile.profile.Data.ProductLadders or {}

	local endsAt = {}
	local config = ProductLadder.getConfig().ProductLadders
	if config then
		for ladderName, ladderConfig in config do
			if ladderConfig.DurationMinutes and self:getNextStep(ladderName) ~= nil then
				local start = self:_windowStart(ladderName)
				if start then
					endsAt[ladderName] = start + ladderConfig.DurationMinutes * 60
				end
			end
		end
	end

	self:sendNetworkEvent(self.instance, "ProductLadderSync", { owned = owned, endsAt = endsAt })
end

function ProductLadder:destroy()
	self.trove:Clean()
end

return ProductLadder
