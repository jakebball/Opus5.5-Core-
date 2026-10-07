
local SeasonPass = {}
SeasonPass.__index = SeasonPass
SeasonPass.Tag = "SeasonPass"


local function ensureData(d, profileKey, tracks, currentSeason)
	d[profileKey] = d[profileKey] or {}
	local sp = d[profileKey]
	sp.Season = sp.Season or currentSeason
	sp.Xp = sp.Xp or 0
	sp.Claimed = sp.Claimed or {}
	for _, track in tracks do
		sp.Claimed[track] = sp.Claimed[track] or {}
	end
	if sp.Season ~= currentSeason then
		sp.Season = currentSeason
		sp.Xp = 0
		sp.Claimed = {}
		for _, track in tracks do
			sp.Claimed[track] = {}
		end
	end
	return d
end

function SeasonPass.Start()
	setmetatable(SeasonPass, { __index = SeasonPass.BaseClass })
	SeasonPass.Observers.observePlayer(function(player)
		player:AddTag("SeasonPass")
	end)
end

function SeasonPass.new(instance)
	local self = setmetatable(SeasonPass.BaseClass.new(instance), SeasonPass)
	self._ready = false
	self._adapter = nil
	self._trackUnlocked = {}

	self:registerRemote("SeasonPassClaimTier")
	self:registerRemote("SeasonPassClaimResult")
	self:registerRemote("SeasonPassSync")
	self:registerRemote("SeasonPassRequestSync")

	self:onRemoteEvent("SeasonPassClaimTier", function(player, tier, track, slot)
		self:_handleClaim(player, tier, track, slot)
	end)
	self:onRemoteEvent("SeasonPassRequestSync", function(player)
		if player == instance then
			self:_sync()
		end
	end)

	return self
end

function SeasonPass:setAdapter(adapter)
	self._adapter = adapter

	SeasonPass.EntityStore.promiseGetComponent(self.instance, "PlayerProfile"):andThen(function(profileComp)
		profileComp:waitForDataLoaded()
		profileComp:modifyProfileData(function(d)
			return ensureData(d, adapter.profileKey, adapter.config.Tracks, adapter.config.CurrentSeason)
		end)
		self._ready = true
		self:_recomputeGates()
		self:_publish()
		self:_sync()
	end):catch(function() end)
end

function SeasonPass:_config()
	return self._adapter and self._adapter.config
end

function SeasonPass:_profile()
	return SeasonPass.EntityStore.getComponent(self.instance, "PlayerProfile")
end

function SeasonPass:_data()
	if not self._adapter then return nil end
	local p = self:_profile()
	local d = p and p:getProfileData()
	return d and d[self._adapter.profileKey] or nil
end

function SeasonPass:_levelFor(xp)
	return math.floor((xp or 0) / self:_config().XpPerLevel)
end

function SeasonPass:_recomputeGates()
	if not self._adapter then return false end
	local changed = false
	for _, track in self:_config().Tracks do
		local unlocked
		if self._adapter.isTrackUnlocked then
			unlocked = self._adapter.isTrackUnlocked(self.instance, track) == true
		else
			unlocked = (track == "Free")
		end
		if unlocked ~= self._trackUnlocked[track] then
			self._trackUnlocked[track] = unlocked
			changed = true
		end
	end
	return changed
end

function SeasonPass:refreshGates()
	if not self._ready then return end
	if self:_recomputeGates() then
		self:_sync()
	end
end

function SeasonPass:_reward(tier, track, slot)
	local tiers = self:_config().Tiers
	local entry = tiers and tiers[tier]
	local trackRewards = entry and entry[track]
	return trackRewards and trackRewards[slot]
end

function SeasonPass:_publish()
	self:_sync()
end

function SeasonPass:_sync()
	local sp = self:_data()
	if not sp then return end
	local config = self:_config()
	self:sendNetworkEvent(self.instance, "SeasonPassSync", {
		season = config.CurrentSeason,
		level = self:_levelFor(sp.Xp or 0),
		xpIntoLevel = (sp.Xp or 0) % config.XpPerLevel,
		xpPerLevel = config.XpPerLevel,
		maxTier = #config.Tiers,
		tracks = table.clone(self._trackUnlocked),
		claimed = sp.Claimed,
	})
end

function SeasonPass:getXp()
	local sp = self:_data()
	return (sp and sp.Xp) or 0
end

function SeasonPass:getLevel()
	return self:_levelFor(self:getXp())
end

function SeasonPass:addXp(amount)
	if not amount or amount <= 0 or not self._ready then return end
	local profile = self:_profile()
	if not profile then return end
	local key = self._adapter.profileKey
	profile:modifyProfileData(function(d)
		d[key].Xp = (d[key].Xp or 0) + amount
		return d
	end)
	self:_publish()
end

function SeasonPass:_claimResult(ok, reason, tier, track, slot)
	self:sendNetworkEvent(self.instance, "SeasonPassClaimResult", {
		ok = ok, reason = reason, tier = tier, track = track, slot = slot,
	})
end

function SeasonPass:_handleClaim(player, tier, track, slot)
	if player ~= self.instance then return end
	if not self._ready or not self._adapter then
		return self:_claimResult(false, "not-ready", tier, track, slot)
	end
	tier = tonumber(tier)
	slot = tonumber(slot) or 1
	if not tier then
		return self:_claimResult(false, "invalid", tier, track, slot)
	end

	local reward = self:_reward(tier, track, slot)
	if not reward then
		return self:_claimResult(false, "invalid", tier, track, slot)
	end

	local sp = self:_data()
	if not sp then
		return self:_claimResult(false, "profile-missing", tier, track, slot)
	end

	if self:_levelFor(sp.Xp or 0) < tier then
		return self:_claimResult(false, "not-reached", tier, track, slot)
	end
	if not self._trackUnlocked[track] then
		return self:_claimResult(false, "locked", tier, track, slot)
	end

	local key = tier .. "_" .. slot
	if sp.Claimed[track] and sp.Claimed[track][key] then
		return self:_claimResult(false, "already-claimed", tier, track, slot)
	end

	local profileKey = self._adapter.profileKey
	self:_profile():modifyProfileData(function(d)
		local claimed = d[profileKey].Claimed
		claimed[track] = claimed[track] or {}
		claimed[track][key] = true
		return d
	end)

	if not self._adapter.grant(self.instance, reward) then
		self:_profile():modifyProfileData(function(d)
			local claimed = d[profileKey].Claimed
			if claimed[track] then
				claimed[track][key] = nil
			end
			return d
		end)
		return self:_claimResult(false, "grant-failed", tier, track, slot)
	end

	self:_sync()
	self:_claimResult(true, nil, tier, track, slot)
end

function SeasonPass:destroy()
	self.trove:Clean()
end

return SeasonPass
