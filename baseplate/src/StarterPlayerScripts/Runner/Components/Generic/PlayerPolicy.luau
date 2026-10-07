
local Players = game:GetService("Players")

local PlayerPolicy = {}
PlayerPolicy.__index = PlayerPolicy
PlayerPolicy.Tag = "PlayerPolicy"

local localPlayer = Players.LocalPlayer

function PlayerPolicy.Start()
	setmetatable(PlayerPolicy, { __index = PlayerPolicy.BaseClass })
	PlayerPolicy.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("PlayerPolicy")
		end
	end)
end

function PlayerPolicy.new(instance)
	local self = setmetatable(PlayerPolicy.BaseClass.new(instance), PlayerPolicy)
	if instance ~= localPlayer then return self end

	self._restricted = true
	self.onChanged = PlayerPolicy.GoodSignal.new()

	self:onRemoteEvent("PaidRandomSync", function(state)
		if type(state) ~= "table" or type(state.restricted) ~= "boolean" then return end
		if state.restricted == self._restricted then return end
		self._restricted = state.restricted
		self.onChanged:Fire(self._restricted)
	end)

	self:sendNetworkEvent("PaidRandomSync")

	return self
end

function PlayerPolicy:isPaidRandomRestricted()
	return self._restricted
end

function PlayerPolicy:destroy()
	if self.onChanged then self.onChanged:DisconnectAll() end
end

return PlayerPolicy
