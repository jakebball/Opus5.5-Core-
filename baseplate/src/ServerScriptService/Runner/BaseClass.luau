local BaseClass = {}
BaseClass.__index = BaseClass
BaseClass.Tag = "BaseClass"

local Trove = require(game.ReplicatedStorage:WaitForChild("Shared").Generic.Trove)
local HttpService = game:GetService("HttpService")

local ComponentRemotes = Instance.new("Folder")
ComponentRemotes.Name = "ComponentRemotes"
ComponentRemotes.Parent = game.ReplicatedStorage

local REMOTE_ID_ATTR = "ComponentRemoteId"

local sharedRemoteCache = {}

local function allocateRemoteId(instance)
	local existing = instance:GetAttribute(REMOTE_ID_ATTR)
	if typeof(existing) == "string" and existing ~= "" then
		return existing
	end
	local id = HttpService:GenerateGUID(false)
	instance:SetAttribute(REMOTE_ID_ATTR, id)
	return id
end

function BaseClass.new(instance, parameters)
	local self = setmetatable({}, BaseClass)

	self.instance = instance

	local overrideId = parameters and parameters.remoteId
	if typeof(overrideId) == "string" and overrideId ~= "" then
		instance:SetAttribute(REMOTE_ID_ATTR, overrideId)
		self.remoteId = overrideId
	else
		self.remoteId = allocateRemoteId(instance)
	end

	self.remotes = ComponentRemotes:FindFirstChild(self.remoteId)
	if not self.remotes then
		self.remotes = Instance.new("Folder")
		self.remotes.Name = self.remoteId
		self.remotes.Parent = ComponentRemotes
	end

	self.trove = Trove.new()

	return self
end

function BaseClass.sharedRemote(channelName, remoteName, className)
	local channel = sharedRemoteCache[channelName]
	if not channel then
		channel = {}
		sharedRemoteCache[channelName] = channel
	end

	local remote = channel[remoteName]
	if remote and remote.Parent then
		return remote
	end

	local folder = ComponentRemotes:FindFirstChild(channelName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = channelName
		folder.Parent = ComponentRemotes
	end

	remote = folder:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new(className or "RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
	end

	channel[remoteName] = remote
	return remote
end

function BaseClass:registerRemote(remoteName)
	local remote = self.remotes:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = self.remotes
	end
	return remote
end

function BaseClass:sendNetworkEvent(target : string | Player, remoteName : string, ...)
	local remote = self:registerRemote(remoteName)

	if target == "All" then
		remote:FireAllClients(...)
	else
		remote:FireClient(target, ...)
	end
end

function BaseClass:onRemoteEvent(remoteName, callback)
	local remote = self:registerRemote(remoteName)
	self.trove:Add(remote.OnServerEvent:Connect(callback))
end

function BaseClass:registerUnreliableRemote(remoteName)
	local remote = self.remotes:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = remoteName
		remote.Parent = self.remotes
	end
	return remote
end

function BaseClass:sendUnreliableNetworkEvent(target : string | Player, remoteName : string, ...)
	local remote = self:registerUnreliableRemote(remoteName)

	if target == "All" then
		remote:FireAllClients(...)
	else
		remote:FireClient(target, ...)
	end
end

function BaseClass:onUnreliableRemoteEvent(remoteName, callback)
	local remote = self:registerUnreliableRemote(remoteName)
	self.trove:Add(remote.OnServerEvent:Connect(callback))
end

return BaseClass