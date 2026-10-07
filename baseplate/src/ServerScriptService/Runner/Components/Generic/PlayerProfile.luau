local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile
PlayerProfile.Tag = "PlayerProfile"

local store
local profiles = {}

const PLAYTIME_FLUSH = 30

function PlayerProfile.Start()
	setmetatable(PlayerProfile, { __index = PlayerProfile.BaseClass })
	PlayerProfile.Observers.observePlayer(function(player)
		player:AddTag("PlayerProfile")
	end)

	local config = PlayerProfile.getConfig().Profile

	store = PlayerProfile.Profilestore.New("Store (" .. config.ProfileVersion .. ")", config.DataTemplate)
end

function PlayerProfile.new(instance)
	local self = setmetatable({}, PlayerProfile)
	self.trove = PlayerProfile.Trove.new()

	self.config = PlayerProfile.getConfig().Profile
	self.instance = instance
	self.dataLoaded = false
	self.DataLoaded = PlayerProfile.GoodSignal.new()

	local profile

	if self.config.UseMockstore then
		profile = store.Mock:StartSessionAsync("Player_" .. self.instance.UserId, {
			Cancel = function()
				return not self.instance:IsDescendantOf(game.Players)
			end,
		})
	else
		profile = store:StartSessionAsync("Player_" .. self.instance.UserId, {
			Cancel = function()
				return not self.instance:IsDescendantOf(game.Players)
			end,
		})
	end

	if not profile then
		warn("[PlayerProfile] Failed to load profile for: " .. instance.Name)
		return self
	end

	profile:Reconcile()
	profiles[instance] = profile
	self.profile = profile
	self.dataLoaded = true
	self.DataLoaded:Fire()

	self._sessionStart = os.time()
	self._flushTask = task.spawn(function()
		while self.profile do
			task.wait(PLAYTIME_FLUSH)
			if not self.profile then break end
			self:_flushPlayTime()
		end
	end)

	return self
end

function PlayerProfile:waitForDataLoaded()
	return self.dataLoaded
end

function PlayerProfile:modifyProfileData(callback)
	if not self.profile then
		return
	end
	local success, newdata = pcall(callback, self.profile.Data)

	if not success then
		warn("Error modifying profiledata")
		warn(debug.traceback())
		return
	end

	if newdata == nil then
		warn("error modifying profile data")
		warn(debug.traceback())
		return
	end

	self.profile.Data = newdata

	return newdata
end

function PlayerProfile:getProfileData()
	return self.profile.Data
end

function PlayerProfile:getProfile(player)
	return self.profile
end

function PlayerProfile:_flushPlayTime()
	if not self.profile or not self._sessionStart then return end
	local now = os.time()
	local delta = now - self._sessionStart
	if delta <= 0 then return end
	self._sessionStart = now
	self:modifyProfileData(function(d)
		d.TotalPlayTime = (d.TotalPlayTime or 0) + delta
		return d
	end)
end

function PlayerProfile:getTotalPlayTime()
	if not self.profile then return 0 end
	local persisted = self.profile.Data.TotalPlayTime or 0
	if not self._sessionStart then return persisted end
	return persisted + math.max(0, os.time() - self._sessionStart)
end

function PlayerProfile:destroy()
	if self._flushTask then
		pcall(task.cancel, self._flushTask)
		self._flushTask = nil
	end
	self:_flushPlayTime()
	if self.profile then
		self.profile:EndSession()
	end
	self.DataLoaded:DisconnectAll()
	profiles[self.instance] = nil
end

return PlayerProfile