local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local AdminSystem = script.Parent
local Config = require(AdminSystem.Config)
local ServerHandler = require(AdminSystem.ServerHandler)
local CommandsFolder = AdminSystem.Commands
local Assets = AdminSystem.Assets

local remoteFunction = Instance.new("RemoteFunction")
remoteFunction.Name = "AdminPanel_Invoke"
remoteFunction.Parent = ReplicatedStorage

local adminRemote = Instance.new("RemoteEvent")
adminRemote.Name = "ADMIN_REMOTE"
adminRemote.Parent = ReplicatedStorage

local adminPanel = Assets:WaitForChild("AdminPanel")
local adminListItem = Assets:WaitForChild("AdminListItem")
local adminClient = Assets:WaitForChild("AdminClient")
local globalMessageItem = Assets:WaitForChild("GlobalMessageItem")
local globalMessage = Assets:WaitForChild("GlobalMessage")

adminPanel.Parent = StarterGui
globalMessage.Parent = StarterGui
adminListItem.Parent = ReplicatedStorage
adminClient.Parent = StarterPlayer.StarterPlayerScripts
globalMessageItem.Parent = ReplicatedStorage

ServerHandler.Init(Config, CommandsFolder)