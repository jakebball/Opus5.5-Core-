
local Players = game:GetService("Players")

local SeasonPass = {}
SeasonPass.__index = SeasonPass
SeasonPass.Tag = "SeasonPass"


local localPlayer = Players.LocalPlayer

function SeasonPass.Start()
	setmetatable(SeasonPass, { __index = SeasonPass.BaseClass })
	SeasonPass.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("SeasonPass")
		end
	end)
end

function SeasonPass.new(instance)
	local self = setmetatable(SeasonPass.BaseClass.new(instance, { remoteInstance = localPlayer }), SeasonPass)
	if instance ~= localPlayer then
		return self
	end

	self.state = {
		level = 0,
		xpIntoLevel = 0,
		xpPerLevel = 1,
		maxTier = 0,
		tracks = {},
		claimed = {},
	}
	self.onChanged = SeasonPass.GoodSignal.new()
	self.onClaimResult = SeasonPass.GoodSignal.new()

	task.spawn(function()
		self:_init()
	end)

	return self
end

function SeasonPass:_init()
	self:_bindRemotes()
	self:requestSync()
	self.onChanged:Fire(self.state)
end

function SeasonPass:_bindRemotes()
	self:onRemoteEvent("SeasonPassSync", function(payload)
		self:_onSync(payload)
	end)
	self:onRemoteEvent("SeasonPassClaimResult", function(payload)
		self.onClaimResult:Fire(payload)
	end)
end

function SeasonPass:_onSync(payload)
	if not payload then return end
	local s = self.state
	s.level = payload.level or s.level
	s.xpIntoLevel = payload.xpIntoLevel or s.xpIntoLevel
	s.xpPerLevel = payload.xpPerLevel or s.xpPerLevel
	s.maxTier = payload.maxTier or s.maxTier
	s.tracks = payload.tracks or {}
	s.claimed = payload.claimed or {}
	self.onChanged:Fire(s)
end

function SeasonPass:getState()
	return self.state
end

function SeasonPass:isTrackUnlocked(track)
	return self.state.tracks[track] == true
end

function SeasonPass:isClaimed(track, tier, slot)
	local bucket = self.state.claimed[track]
	return bucket ~= nil and bucket[tier .. "_" .. slot] == true
end

function SeasonPass:claim(tier, track, slot)
	self:sendNetworkEvent("SeasonPassClaimTier", tier, track, slot)
end

function SeasonPass:requestSync()
	self:sendNetworkEvent("SeasonPassRequestSync")
end

function SeasonPass:destroy()
	if self.onChanged then
		self.onChanged:DisconnectAll()
	end
	if self.onClaimResult then
		self.onClaimResult:DisconnectAll()
	end
	if self.trove then
		self.trove:Clean()
	end
end

return SeasonPass
