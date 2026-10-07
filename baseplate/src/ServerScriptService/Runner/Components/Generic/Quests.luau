
local Players = game:GetService("Players")

local Quests = {}
Quests.__index = Quests
Quests.Tag = "Quests"

const RESET_CHECK_INTERVAL = 30
const SYNC_DEBOUNCE = 1

local function cycleEnd(period, now)
	return (math.floor(now / period) + 1) * period
end

function Quests.Start()
	setmetatable(Quests, { __index = Quests.BaseClass })
	Quests.Observers.observePlayer(function(player)
		player:AddTag("Quests")
	end)
end

function Quests.new(instance)
	local self = setmetatable(Quests.BaseClass.new(instance), Quests)
	self._ready = false
	self._adapter = nil

	self:registerRemote("QuestsSync")
	self:registerRemote("QuestsRequestSync")
	self:onRemoteEvent("QuestsRequestSync", function(player)
		if player == instance then
			self:_maybeReset()
			self:_sync()
		end
	end)

	return self
end

function Quests:setAdapter(adapter)
	self._adapter = adapter
	Quests.EntityStore.promiseGetComponent(self.instance, "PlayerProfile"):andThen(function(profileComp)
		profileComp:waitForDataLoaded()
		self._ready = true
		self:_maybeReset()
		self:_sync()
		self._loop = task.spawn(function()
			while self.instance and self.instance:IsDescendantOf(Players) do
				task.wait(RESET_CHECK_INTERVAL)
				if self:_maybeReset() then
					self:_sync()
				end
			end
		end)
	end):catch(function() end)
end

function Quests:_profile()
	return Quests.EntityStore.getComponent(self.instance, "PlayerProfile")
end

function Quests:_categories()
	return self._adapter.config.Categories
end

function Quests:_defs(category)
	return self._adapter.config.Quests[category] or {}
end

function Quests:_data()
	if not self._adapter then return nil end
	local p = self:_profile()
	local d = p and p:getProfileData()
	return d and d[self._adapter.profileKey] or nil
end

function Quests:_maybeReset()
	if not self._adapter then return false end
	local profile = self:_profile()
	if not profile then return false end
	local now = os.time()
	local profileKey = self._adapter.profileKey
	local categories = self:_categories()
	local changed = false

	profile:modifyProfileData(function(d)
		local block = d[profileKey] or {}
		d[profileKey] = block
		for category, cat in categories do
			local cd = block[category] or {}
			block[category] = cd
			cd.progress = cd.progress or {}
			cd.completed = cd.completed or {}
			if not cd.resetAt or now >= cd.resetAt then
				cd.progress = {}
				cd.completed = {}
				cd.resetAt = cycleEnd(cat.period, now)
				changed = true
			end
		end
		return d
	end)
	return changed
end

function Quests:report(metric, amount, key)
	if not self._ready or not amount or amount <= 0 then return end
	self:_maybeReset()
	local profile = self:_profile()
	if not profile then return end
	local profileKey = self._adapter.profileKey
	local categories = self:_categories()
	local toGrant = {}

	profile:modifyProfileData(function(d)
		local block = d[profileKey]
		if not block then return d end
		for category in categories do
			local cd = block[category]
			if cd then
				for _, def in self:_defs(category) do
					if def.metric == metric and (def.target == nil or def.target == key) and not cd.completed[def.id] then
						local p = math.min(def.goal, (cd.progress[def.id] or 0) + amount)
						cd.progress[def.id] = p
						if p >= def.goal then
							cd.completed[def.id] = true
							table.insert(toGrant, def.reward)
						end
					end
				end
			end
		end
		return d
	end)

	if self._adapter.grant then
		for _, reward in toGrant do
			self._adapter.grant(self.instance, reward)
		end
	end

	if #toGrant > 0 then
		self:_sync()
	else
		self:_scheduleSync()
	end
end

function Quests:_scheduleSync()
	if self._syncScheduled then return end
	self._syncScheduled = true
	task.delay(SYNC_DEBOUNCE, function()
		self._syncScheduled = false
		self:_sync()
	end)
end

function Quests:_sync()
	local data = self:_data()
	if not data then return end
	local payload = {}
	for category in self:_categories() do
		local cd = data[category]
		if cd then
			payload[category] = {
				resetAt = cd.resetAt,
				progress = cd.progress,
				completed = cd.completed,
			}
		end
	end
	self:sendNetworkEvent(self.instance, "QuestsSync", payload)
end

function Quests:destroy()
	if self._loop then
		pcall(task.cancel, self._loop)
	end
	self.trove:Clean()
end

return Quests
