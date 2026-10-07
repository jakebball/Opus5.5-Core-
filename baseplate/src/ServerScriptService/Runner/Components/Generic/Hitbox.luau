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
	self:registerRemote("Hit")
	return self
end

function Hitbox:reportHit(hitInstance, hitPosition, shooter, direction, damage, headshot, carveRadius, damageKind)
	self.onHit:Fire(hitInstance, hitPosition, shooter, direction, damage, headshot, carveRadius, damageKind)
	self:sendNetworkEvent("All", "Hit", hitInstance, hitPosition, shooter, direction, damage, headshot, damageKind)
end

return Hitbox