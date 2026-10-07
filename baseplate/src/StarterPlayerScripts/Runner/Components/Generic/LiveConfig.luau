const REMOTE_ID = "LiveConfig"
const SYNC_REMOTE = "LiveConfigSync"

local LiveConfig = {}
LiveConfig.__index = LiveConfig
LiveConfig.Tag = "LiveConfig"

local values = {}
local onChangedSignal
local ready = false

function LiveConfig.Start()
	setmetatable(LiveConfig, { __index = LiveConfig.BaseClass })
	onChangedSignal = LiveConfig.GoodSignal.new()
end

function LiveConfig.new(instance)
	local self = setmetatable(LiveConfig.BaseClass.new(instance, { remoteId = REMOTE_ID }), LiveConfig)
	
	self:onRemoteEvent(SYNC_REMOTE, function(payload)
		if type(payload) ~= "table" then return end
		values = payload
		if onChangedSignal then onChangedSignal:Fire() end
	end)
	
	self:sendNetworkEvent(SYNC_REMOTE)
	
	ready = true
	
	return self
end

function LiveConfig.get(key)
	return values[key]
end

function LiveConfig.onChanged(callback)
	if not onChangedSignal then return nil end
	return onChangedSignal:Connect(callback)
end

function LiveConfig.isReady()
	return ready
end

function LiveConfig:destroy()
	self.trove:Clean()
end

return LiveConfig