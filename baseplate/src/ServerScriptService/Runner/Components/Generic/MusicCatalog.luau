local MarketplaceService = game:GetService("MarketplaceService")

local MusicCatalog = {}
MusicCatalog.__index = MusicCatalog
MusicCatalog.Tag = "MusicCatalog"

local function assetIdFrom(soundId)
	return tonumber(string.match(soundId or "", "%d+"))
end

function MusicCatalog.Start()
	setmetatable(MusicCatalog, { __index = MusicCatalog.BaseClass })
	workspace:AddTag(MusicCatalog.Tag)
end

function MusicCatalog.new(instance)
	local self = setmetatable(MusicCatalog.BaseClass.new(instance), MusicCatalog)

	self.config = MusicCatalog.getConfig().Music
	self.entries = {}

	self:registerRemote("Catalog")
	self:onRemoteEvent("CatalogSync", function(player)
		self:sendNetworkEvent(player, "Catalog", self.entries)
	end)

	task.spawn(function()
		self:_buildCatalog()
	end)

	return self
end

function MusicCatalog:getEntries()
	return self.entries
end

function MusicCatalog:_buildCatalog()
	local sounds = self:_collectSounds()
	local pending = {}

	for _, sound in sounds do
		local assetId = assetIdFrom(sound.SoundId)
		if not assetId then
			warn("[MusicCatalog] " .. sound:GetFullName() .. " has an unreadable SoundId: " .. tostring(sound.SoundId))
		else
			local key = tostring(assetId)
			self.entries[key] = self:_authoredEntry(sound)
			if not pending[key] then
				pending[key] = sound
			end
		end
	end

	for key, sound in pending do
		local entry = self.entries[key]

		if not entry.title or not entry.artist then
			local fetched = self:_fetchInfo(tonumber(key))
			if fetched then
				entry.title = entry.title or fetched.title
				entry.artist = entry.artist or fetched.artist
			end
			task.wait(self.config.LookupDelay)
		end

		entry.title = entry.title or sound.Name
	end

	self:sendNetworkEvent("All", "Catalog", self.entries)
end

function MusicCatalog:_collectSounds()
	local sounds = {}
	local root = MusicCatalog.Assets.Get(self.config.Folder)
	if not root then
		warn("[MusicCatalog] no folder at " .. self.config.Folder .. " — no track names will be available")
		return sounds
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Sound") and descendant.SoundId ~= "" then
			table.insert(sounds, descendant)
		end
	end
	return sounds
end

function MusicCatalog:_authoredEntry(sound)
	local title = sound:GetAttribute(self.config.TitleAttribute)
	local artist = sound:GetAttribute(self.config.ArtistAttribute)
	return {
		title = type(title) == "string" and title ~= "" and title or nil,
		artist = type(artist) == "string" and artist ~= "" and artist or nil,
	}
end

function MusicCatalog:_fetchInfo(assetId)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)

	if not ok or type(info) ~= "table" then
		warn("[MusicCatalog] lookup failed for asset " .. tostring(assetId) .. ": " .. tostring(info))
		return nil
	end

	return {
		title = info.Name,
		artist = info.Creator and info.Creator.Name or nil,
	}
end

return MusicCatalog
