local BaseClass = {}
BaseClass.__index = BaseClass
BaseClass.Tag = "BaseClass"

local Shared = game.ReplicatedStorage:WaitForChild("Shared")

local Promise = require(Shared.Generic.Promise)
local Trove = require(Shared.Generic.Trove)

local REMOTE_ID_ATTR = "ComponentRemoteId"
local REMOTE_WAIT_TIMEOUT = 30

local sharedRemoteCache = {}

function BaseClass.new(instance, parameters)
	local self = setmetatable({}, BaseClass)

	self.trove = Trove.new()
	self.instance = instance

	if parameters then
		self.remoteIdOverride = parameters.remoteId
		self.remoteInstance = parameters.remoteInstance
	end

	return self
end

local function waitForRemoteId(instance, timeout)
	local existing = instance:GetAttribute(REMOTE_ID_ATTR)
	if typeof(existing) == "string" and existing ~= "" then
		return existing
	end

	local thread = coroutine.running()
	local resumed = false
	local connection
	local timeoutThread

	local function finish(value)
		if resumed then return end
		resumed = true
		if connection then
			connection:Disconnect()
		end
		if timeoutThread and coroutine.status(timeoutThread) == "suspended" then
			task.cancel(timeoutThread)
		end
		if coroutine.status(thread) ~= "suspended" then return end
		task.spawn(thread, value)
	end

	connection = instance:GetAttributeChangedSignal(REMOTE_ID_ATTR):Connect(function()
		local current = instance:GetAttribute(REMOTE_ID_ATTR)
		if typeof(current) == "string" and current ~= "" then
			finish(current)
		end
	end)
	timeoutThread = task.delay(timeout, function()
		finish(nil)
	end)

	return coroutine.yield()
end

function BaseClass.sharedRemote(channelName, remoteName)
	local cacheKey = channelName .. "/" .. remoteName
	local cached = sharedRemoteCache[cacheKey]
	if cached and cached.Parent then
		return cached
	end

	local remotesRoot = game.ReplicatedStorage:WaitForChild("ComponentRemotes", REMOTE_WAIT_TIMEOUT)
	local folder = remotesRoot and remotesRoot:WaitForChild(channelName, REMOTE_WAIT_TIMEOUT)
	local remote = folder and folder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT)
	if remote then
		sharedRemoteCache[cacheKey] = remote
	end
	return remote
end

function BaseClass:_resolveRemote(remoteName)
	return Promise.new(function(resolve, reject)
		local remotesRoot = game.ReplicatedStorage:WaitForChild("ComponentRemotes", REMOTE_WAIT_TIMEOUT)
		if not remotesRoot then
			return reject("ComponentRemotes folder never replicated")
		end
		local id = self.remoteIdOverride
		if not (typeof(id) == "string" and id ~= "") then
			local source = self.remoteInstance or self.instance
			id = waitForRemoteId(source, REMOTE_WAIT_TIMEOUT)
			if not (typeof(id) == "string" and id ~= "") then
				return reject(string.format("instance '%s' never published ComponentRemoteId", tostring(source and source.Name)))
			end
		end
		local folder = remotesRoot:WaitForChild(id, REMOTE_WAIT_TIMEOUT)
		if not folder then
			return reject(string.format("per-instance folder '%s' never replicated", id))
		end
		local remote = folder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT)
		if not remote then
			return reject(string.format("remote '%s' on '%s' never replicated", remoteName, id))
		end
		resolve(remote)
	end)
end

function BaseClass:onRemoteEvent(remoteName: string, callback: () -> ())
	self.trove:AddPromise(self:_resolveRemote(remoteName):andThen(function(remote)
		self.trove:Add(remote.OnClientEvent:Connect(function(...)
			callback(...)
		end))
	end):catch(function(err)
		warn(string.format("[BaseClass] onRemoteEvent failed for %s.%s: %s",
			tostring(self.instance and self.instance.Name), tostring(remoteName), tostring(err)))
	end))
end

function BaseClass:sendNetworkEvent(remoteName, ...)
	local args = table.pack(...)
	self.trove:AddPromise(self:_resolveRemote(remoteName):andThen(function(remote)
		remote:FireServer(table.unpack(args, 1, args.n))
	end):catch(function(err)
		warn(string.format("[BaseClass] sendNetworkEvent failed for %s.%s: %s",
			tostring(self.instance and self.instance.Name), tostring(remoteName), tostring(err)))
	end))
end

function BaseClass:onUnreliableRemoteEvent(remoteName: string, callback: () -> ())
	self.trove:AddPromise(self:_resolveRemote(remoteName):andThen(function(remote)
		self.trove:Add(remote.OnClientEvent:Connect(function(...)
			callback(...)
		end))
	end):catch(function(err)
		warn(string.format("[BaseClass] onUnreliableRemoteEvent failed for %s.%s: %s",
			tostring(self.instance and self.instance.Name), tostring(remoteName), tostring(err)))
	end))
end

function BaseClass:sendUnreliableNetworkEvent(remoteName, ...)
	local args = table.pack(...)
	self.trove:AddPromise(self:_resolveRemote(remoteName):andThen(function(remote)
		remote:FireServer(table.unpack(args, 1, args.n))
	end):catch(function(err)
		warn(string.format("[BaseClass] sendUnreliableNetworkEvent failed for %s.%s: %s",
			tostring(self.instance and self.instance.Name), tostring(remoteName), tostring(err)))
	end))
end

return BaseClass