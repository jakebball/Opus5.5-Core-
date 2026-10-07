return {
	Name = "Kick",
	Description = "Kick a player currently in the server.",
	MinPermissionLevel = 1,
	LayoutOrder = 50,

	Parameters = {
		{ Name = "Player", Type = "PlayerList", Required = true },
		{ Name = "Reason", Type = "String",     Required = false, Default = "Kicked by admin" },
	},

	Execute = function(context, params)
		local targetUserId = params.Player
		if not targetUserId then
			return false, "No player selected."
		end

		local reason = params.Reason or "Kicked by admin"

		local Players = game:GetService("Players")
		local targetPlayer = Players:GetPlayerByUserId(targetUserId)
		if not targetPlayer then
			return false, "Player not found in server."
		end

		local targetName = targetPlayer.Name
		targetPlayer:Kick("Kicked by " .. context.Player.Name .. ": " .. reason)

		return true, "Kicked " .. targetName .. ". Reason: " .. reason
	end,
}