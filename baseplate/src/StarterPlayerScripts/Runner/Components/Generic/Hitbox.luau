local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

const ECHO_WINDOW = 0.35

local Hitbox = {}
Hitbox.__index = Hitbox
Hitbox.Tag = "Hitbox"

function Hitbox.Start()
	setmetatable(Hitbox, { __index = Hitbox.BaseClass })
end

function Hitbox.new(instance)
	local self = setmetatable(Hitbox.BaseClass.new(instance), Hitbox)
	self.onHit = Hitbox.GoodSignal.new()
	self.trove:Add(self.onHit, "DisconnectAll")
	self.localHitAt = 0
	self:onRemoteEvent("Hit", function(hitInstance, hitPosition, shooter, direction, damage, headshot, damageKind)
		if shooter == localPlayer and os.clock() - self.localHitAt < ECHO_WINDOW then return end
		self.onHit:Fire(hitInstance, hitPosition, shooter, direction, damage, headshot, nil, damageKind)
	end)
	return self
end

function Hitbox:noteLocalHit()
	self.localHitAt = os.clock()
end

return Hitbox