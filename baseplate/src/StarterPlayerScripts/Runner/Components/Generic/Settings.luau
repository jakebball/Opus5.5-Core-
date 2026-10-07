local Players = game:GetService("Players")

local Settings = {}
Settings.__index = Settings
Settings.Tag = "Settings"

local SETTINGS_IMAGE = "rbxassetid://87683061696358"
local ICON_NAME = "Settings"
local ICON_ALIGN = "Left"
local ICON_IMAGE_SCALE = 0.7

local PANEL_GUI_NAME = "Settings"
local PANEL_FRAME_NAME = "Settings"

local localPlayer = Players.LocalPlayer
local iconBuilt = false

local function resolvePanel()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild(PANEL_GUI_NAME)
	return screenGui:WaitForChild(PANEL_FRAME_NAME)
end

local function buildIcon()
	if iconBuilt then return end
	iconBuilt = true

	local Icon = Settings.Icon
	local EntityStore = Settings.EntityStore

	local icon = Icon.new()
	icon:setName(ICON_NAME)
	icon:setImage(SETTINGS_IMAGE)
	icon:setImageScale(ICON_IMAGE_SCALE)
	icon:align(ICON_ALIGN)
	icon:oneClick(true)

	local settingsGui

	icon.selected:Connect(function()
		if settingsGui then
			settingsGui:toggle()
			return
		end
		EntityStore.promiseGetComponent(resolvePanel(), "SettingsGui"):andThen(function(gui)
			settingsGui = gui
			gui:toggle()
		end):catch(function() end)
	end)
end

function Settings.Start()
	setmetatable(Settings, { __index = Settings.BaseClass })
	task.spawn(buildIcon)
end

function Settings.new(instance)
	local self = setmetatable(Settings.BaseClass.new(instance), Settings)
	return self
end

function Settings:destroy()
	self.trove:Clean()
end

return Settings
