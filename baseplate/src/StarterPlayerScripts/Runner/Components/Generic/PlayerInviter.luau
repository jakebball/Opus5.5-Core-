local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local PlayerInviter = {}
PlayerInviter.__index = PlayerInviter
PlayerInviter.Tag = "PlayerInviter"

local localPlayer = Players.LocalPlayer

const REFRESH_INTERVAL = 5 * 60

function PlayerInviter.Start()
	setmetatable(PlayerInviter, { __index = PlayerInviter.BaseClass })

	PlayerInviter.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(PlayerInviter.Tag)
		end
	end)
end

function PlayerInviter.new(instance)
	local self = setmetatable(PlayerInviter.BaseClass.new(instance), PlayerInviter)
	if instance ~= localPlayer then return self end

	self.canInviteCached = false
	self.onCanInviteChanged = PlayerInviter.GoodSignal.new()

	self.trove:Add(task.spawn(function()
		while true do
			self:_refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end))

	return self
end

function PlayerInviter:_refresh()
	local ok, result = pcall(function()
		return SocialService:CanSendGameInviteAsync(localPlayer)
	end)
	if not ok then
		warn(("[PlayerInviter] CanSendGameInviteAsync failed for %s: %s"):format(
			localPlayer.Name, tostring(result)
		))
		return
	end
	local newValue = result == true
	if newValue ~= self.canInviteCached then
		self.canInviteCached = newValue
		self.onCanInviteChanged:Fire(newValue)
	end
end

function PlayerInviter:canInvite()
	return self.canInviteCached
end

function PlayerInviter:openInviteMenu()
	self:_refresh()
	if not self.canInviteCached then return end
	SocialService:PromptGameInvite(localPlayer)
end

function PlayerInviter:destroy()
	if self.onCanInviteChanged then
		self.onCanInviteChanged:DisconnectAll()
	end
	if self.trove then
		self.trove:Clean()
	end
end

return PlayerInviter