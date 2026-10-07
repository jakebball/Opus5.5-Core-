local Players = game:GetService("Players")

local PlayerHeadshot = {}
PlayerHeadshot.__index = PlayerHeadshot
PlayerHeadshot.Tag = "PlayerHeadshot"

const THUMB_TYPE = Enum.ThumbnailType.HeadShot
const THUMB_SIZE = Enum.ThumbnailSize.Size150x150
const MAX_RETRIES = 3
const RETRY_DELAY = 2

function PlayerHeadshot.Start()
	setmetatable(PlayerHeadshot, { __index = PlayerHeadshot.BaseClass })
	PlayerHeadshot.Observers.observePlayer(function(player)
		player:AddTag(PlayerHeadshot.Tag)
	end)
end

function PlayerHeadshot.new(instance)
	local self = setmetatable(PlayerHeadshot.BaseClass.new(instance), PlayerHeadshot)

	self.userId = instance.UserId
	self._content = nil
	self._destroyed = false
	self._fallback = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", self.userId)

	task.spawn(function()
		self:_fetch()
	end)

	return self
end

function PlayerHeadshot:_fetch()
	for _ = 1, MAX_RETRIES do
		if self._destroyed then return end
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(self.userId, THUMB_TYPE, THUMB_SIZE)
		end)
		if self._destroyed then return end
		if ok and content and content ~= "" then
			self._content = content
			return
		end
		task.wait(RETRY_DELAY)
	end
end

function PlayerHeadshot:get()
	return self._content or self._fallback
end

function PlayerHeadshot:destroy()
	self._destroyed = true
	self.trove:Clean()
end

return PlayerHeadshot
