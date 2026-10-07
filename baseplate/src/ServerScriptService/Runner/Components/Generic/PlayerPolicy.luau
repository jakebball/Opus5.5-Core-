local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

const INITIAL_BACKOFF_SECONDS = 1
const MAX_BACKOFF_SECONDS = 30
const MAX_FETCH_ATTEMPTS = math.huge

local PlayerPolicy = {}
PlayerPolicy.__index = PlayerPolicy
PlayerPolicy.Tag = "PlayerPolicy"

function PlayerPolicy.Start()
	setmetatable(PlayerPolicy, { __index = PlayerPolicy.BaseClass })

	PlayerPolicy.Observers.observePlayer(function(player)
		player:AddTag(PlayerPolicy.Tag)
	end)
end

function PlayerPolicy.new(instance)
	local self = setmetatable(PlayerPolicy.BaseClass.new(instance), PlayerPolicy)

	self.player = instance
	self.loaded = false
	self.policy = nil
	self.lastError = nil

	self._restricted = true
	self:registerRemote("PaidRandomSync")
	self:onRemoteEvent("PaidRandomSync", function()
		self:_syncPaidRandom()
	end)

	self.onLoaded = PlayerPolicy.GoodSignal.new()
	self.trove:Add(function()
		self.onLoaded:DisconnectAll()
	end)

	task.spawn(function()
		self:_fetchWithRetry()
	end)

	return self
end

function PlayerPolicy:promiseLoaded()
	return PlayerPolicy.Promise.new(function(resolve, reject, onCancel)
		if self.loaded then
			resolve(self.policy)
			return
		end
		local conn
		conn = self.onLoaded:Connect(function()
			if conn then conn:Disconnect(); conn = nil end
			resolve(self.policy)
		end)
		onCancel(function()
			if conn then conn:Disconnect(); conn = nil end
		end)
	end)
end

function PlayerPolicy:isLoaded()
	return self.loaded
end

function PlayerPolicy:get(key)
	if not self.loaded or not self.policy then return nil end
	return self.policy[key]
end

function PlayerPolicy:snapshot()
	if not self.loaded or not self.policy then return nil end
	local out = {}
	for k, v in self.policy do out[k] = v end
	return out
end

function PlayerPolicy:areAdsAllowed()
	if not self.loaded then return false end
	return self.policy.AreAdsAllowed == true
end

function PlayerPolicy:arePaidRandomItemsRestricted()
	if not self.loaded then return true end
	return self.policy.ArePaidRandomItemsRestricted ~= false
end

function PlayerPolicy:isContentSharingAllowed()
	if not self.loaded then return false end
	return self.policy.IsContentSharingAllowed == true
end

function PlayerPolicy:isPhotoToAvatarAllowed()
	return self:isContentSharingAllowed()
end

function PlayerPolicy:isEligibleToPurchaseSubscription()
	if not self.loaded then return false end
	return self.policy.IsEligibleToPurchaseSubscription == true
end

function PlayerPolicy:isPaidItemTradingAllowed()
	if not self.loaded then return false end
	return self.policy.IsPaidItemTradingAllowed == true
end

function PlayerPolicy:isSubjectToChinaPolicies()
	if not self.loaded then return false end
	return self.policy.IsSubjectToChinaPolicies == true
end

function PlayerPolicy:getAllowedExternalLinkReferences()
	if not self.loaded then return {} end
	return self.policy.AllowedExternalLinkReferences or {}
end

function PlayerPolicy:isExternalLinkAllowed(name)
	for _, n in self:getAllowedExternalLinkReferences() do
		if n == name then return true end
	end
	return false
end

function PlayerPolicy:refresh()
	self.loaded = false
	self.policy = nil
	if self.player.Parent then
		self._restricted = true
		self:_syncPaidRandom()
	end
	task.spawn(function()
		self:_fetchWithRetry()
	end)
end

function PlayerPolicy:_publishPaidRandomAttribute()
	if not self.player.Parent then return end
	self._restricted = self:arePaidRandomItemsRestricted()
	self:_syncPaidRandom()
end

function PlayerPolicy:_syncPaidRandom()
	self:sendNetworkEvent(self.player, "PaidRandomSync", { restricted = self._restricted })
end

function PlayerPolicy:_fetchWithRetry()
	local attempts = 0
	local delay = INITIAL_BACKOFF_SECONDS

	while not self.loaded and attempts < MAX_FETCH_ATTEMPTS do
		if not self.player.Parent then return end

		attempts += 1
		local ok, result = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(self.player)
		end)

		if ok and typeof(result) == "table" then
			self.policy = result
			self.loaded = true
			self.lastError = nil
			self:_publishPaidRandomAttribute()
			self.onLoaded:Fire(result)
			return
		end

		self.lastError = (not ok) and tostring(result) or "policy returned non-table"
		warn(string.format(
			"[PlayerPolicy] fetch failed for %s (attempt %d): %s",
			self.player.Name, attempts, self.lastError
		))
		task.wait(delay)
		delay = math.min(delay * 2, MAX_BACKOFF_SECONDS)
	end
end

return PlayerPolicy