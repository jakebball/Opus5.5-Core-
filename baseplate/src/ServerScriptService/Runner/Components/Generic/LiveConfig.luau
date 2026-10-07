local ConfigService = game:GetService("ConfigService")

const REMOTE_ID = "LiveConfig"
const SYNC_REMOTE = "LiveConfigSync"

local LiveConfig = {}
LiveConfig.__index = LiveConfig
LiveConfig.Tag = "LiveConfig"

local singletonSelf
local snapshot
local onChangedSignal
local mirrorKeys = {}

local function readRaw(key)
	if not snapshot then return nil end
	local ok, value = pcall(function()
		return snapshot:GetValue(key)
	end)
	if ok then return value end
	return nil
end

local function buildPayload()
	local payload = {}
	for key in mirrorKeys do
		payload[key] = readRaw(key)
	end
	return payload
end

local function broadcast()
	if not singletonSelf then return end
	singletonSelf:sendNetworkEvent("All", SYNC_REMOTE, buildPayload())
end

local function hookKeySignal(key)
	if not (snapshot and singletonSelf) then return end
	local ok, signal = pcall(function()
		return snapshot:GetValueChangedSignal(key)
	end)
	if ok and signal then
		singletonSelf.trove:Add(signal:Connect(function()
			broadcast()
			if onChangedSignal then onChangedSignal:Fire(key) end
		end))
	end
end

function LiveConfig.Start()
	setmetatable(LiveConfig, { __index = LiveConfig.BaseClass })

	local config = LiveConfig.getConfig().LiveConfig or {}
	onChangedSignal = LiveConfig.GoodSignal.new()

	for _, key in config.MirrorKeys or {} do
		mirrorKeys[key] = true
	end

	LiveConfig.EntityStore.addComponent(workspace, LiveConfig.Tag)

	task.spawn(function()
		local ok, result = pcall(function()
			return ConfigService:GetConfigAsync()
		end)
		if not ok then
			warn("[LiveConfig] GetConfigAsync failed: " .. tostring(result))
			return
		end
		snapshot = result
		broadcast()
		for key in mirrorKeys do
			hookKeySignal(key)
		end
		if singletonSelf then
			local hooked = pcall(function()
				singletonSelf.trove:Add(snapshot.UpdateAvailable:Connect(function()
					pcall(function() snapshot:Refresh() end)
					broadcast()
					if onChangedSignal then onChangedSignal:Fire() end
				end))
			end)
			if not hooked then
				warn("[LiveConfig] UpdateAvailable not connectable on this build")
			end
		end
		if onChangedSignal then onChangedSignal:Fire() end
	end)
end

function LiveConfig.new(instance)
	local self = setmetatable(LiveConfig.BaseClass.new(instance, { remoteId = REMOTE_ID }), LiveConfig)
	singletonSelf = self
	self:onRemoteEvent(SYNC_REMOTE, function(player)
		self:sendNetworkEvent(player, SYNC_REMOTE, buildPayload())
	end)
	return self
end

function LiveConfig.get(key)
	return readRaw(key)
end

function LiveConfig.register(key)
	mirrorKeys[key] = true
	broadcast()
	hookKeySignal(key)
end

function LiveConfig.onChanged(callback)
	if not onChangedSignal then return nil end
	return onChangedSignal:Connect(callback)
end

function LiveConfig:destroy()
	if self == singletonSelf then
		singletonSelf = nil
	end
	self.trove:Clean()
end

return LiveConfig