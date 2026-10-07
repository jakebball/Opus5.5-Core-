local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

const KICK_MESSAGE = "Your data was reset by an admin. Rejoin to start fresh."

local function getConfig()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not shared then return nil end
	local mod = shared:WaitForChild("getConfig", 5)
	if not mod then return nil end
	return require(mod)()
end

local function deepCopy(source)
	local copy = {}
	for key, value in source do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

return {
	Name = "ResetPlayerData",
	Description = "Wipe a target player's profile back to the fresh DataTemplate (Coins, dice pool, inventory, rebirth, upgrades, onboarding, placed needohs — everything), then kick them so every system reloads clean on rejoin. Irreversible.",
	MinPermissionLevel = 3,
	LayoutOrder = 150,

	Parameters = {
		{ Name = "Target",  Type = "PlayerList", Required = true },
		{ Name = "Confirm", Type = "CustomList", Required = true },
	},

	CustomLists = {
		Confirm = function()
			return {
				{ Text = "No — cancel", Value = "No" },
				{ Text = "Yes — wipe ALL data", Value = "Yes" },
			}
		end,
	},

	Execute = function(context, params)
		if params.Confirm ~= "Yes" then
			return false, "Reset cancelled — set Confirm to 'Yes — wipe ALL data' to proceed."
		end

		local target = Players:GetPlayerByUserId(params.Target)
		if not target then
			return false, "Target player is not in this server."
		end

		local config = getConfig()
		local template = config and config.Profile and config.Profile.DataTemplate
		if not template then
			return false, "Could not resolve the profile DataTemplate."
		end

		local profile = require(ServerScriptService.Runner.EntityStore).getComponent(target, "PlayerProfile")
		if not profile or not profile.profile then
			return false, "PlayerProfile component not ready for target player."
		end

		profile:modifyProfileData(function()
			return deepCopy(template)
		end)

		local targetName = target.Name
		target:Kick(KICK_MESSAGE)

		return true, ("Wiped %s's profile to the default template and kicked them — they rejoin with a fresh save."):format(targetName)
	end,
}
