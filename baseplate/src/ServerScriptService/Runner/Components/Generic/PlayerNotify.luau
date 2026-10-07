local PlayerNotify = {}
PlayerNotify.__index = PlayerNotify
PlayerNotify.Tag = "PlayerNotify"

const NOTICE_REMOTE = "ServerNotice"
const DEFAULT_KIND = "Info"
const KINDS = { Success = true, Error = true, Warning = true, Info = true }

function PlayerNotify.Start()
	setmetatable(PlayerNotify, { __index = PlayerNotify.BaseClass })
	PlayerNotify.Observers.observePlayer(function(player)
		player:AddTag(PlayerNotify.Tag)
	end)
end

function PlayerNotify.new(player)
	local self = setmetatable(PlayerNotify.BaseClass.new(player), PlayerNotify)
	self:registerRemote(NOTICE_REMOTE)
	return self
end

function PlayerNotify:notify(text, kind)
	if type(text) ~= "string" then return end
	self:sendNetworkEvent(self.instance, NOTICE_REMOTE, text, if KINDS[kind] then kind else DEFAULT_KIND)
end

function PlayerNotify.send(player, text, kind)
	local component = PlayerNotify.EntityStore.findComponent(player, PlayerNotify.Tag)
	if component then
		component:notify(text, kind)
	end
end

function PlayerNotify:destroy()
	self.trove:Clean()
end

return PlayerNotify
