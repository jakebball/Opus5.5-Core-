local ZoneComponent = {}
ZoneComponent.__index = ZoneComponent
ZoneComponent.Tag = "Zone"

function ZoneComponent.new(instance)
	local self = setmetatable({}, ZoneComponent)
	self.instance = instance
	self.trove = ZoneComponent.Trove.new()

	self.onPlayerEntered = ZoneComponent.GoodSignal.new()
	self.onPlayerExited = ZoneComponent.GoodSignal.new()

	local zone = ZoneComponent.Zone.new(instance)

	zone.localPlayerEntered:Connect(function()
		self.onPlayerEntered:Fire()
	end)

	zone.localPlayerExited:Connect(function()
		self.onPlayerExited:Fire()
	end)

	self.trove:Add(function()
		zone.janitor:destroy()
	end)

	return self
end

function ZoneComponent:destroy()
	self.trove:Destroy()
	self.onPlayerEntered:DisconnectAll()
	self.onPlayerExited:DisconnectAll()
end

return ZoneComponent