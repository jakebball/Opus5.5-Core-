local MusicCatalog = {}
MusicCatalog.__index = MusicCatalog
MusicCatalog.Tag = "MusicCatalog"

local entries = {}

function MusicCatalog.Start()
	setmetatable(MusicCatalog, { __index = MusicCatalog.BaseClass })
	workspace:AddTag(MusicCatalog.Tag)
end

function MusicCatalog.new(instance)
	local self = setmetatable(MusicCatalog.BaseClass.new(instance), MusicCatalog)

	self:onRemoteEvent("Catalog", function(payload)
		entries = type(payload) == "table" and payload or {}
	end)
	self:sendNetworkEvent("CatalogSync")

	return self
end

function MusicCatalog.getInfo(soundId)
	local assetId = string.match(soundId or "", "%d+")
	if not assetId then return nil end
	return entries[assetId]
end

return MusicCatalog
