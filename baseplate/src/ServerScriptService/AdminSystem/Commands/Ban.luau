return {
	Name = "Ban",
	Description = "Ban a player by UserId. Duration in minutes (-1 = permanent).",
	MinPermissionLevel = 2,
	LayoutOrder = 100,

	Parameters = {
		{ Name = "UserId",   Type = "Number", Required = true },
		{ Name = "Duration", Type = "Number", Required = true, Default = -1 },
		{ Name = "Reason",   Type = "String", Required = false, Default = "No reason provided" },
	},

	Execute = function(context, params)
		local userId = params.UserId
		if not userId or userId <= 0 then
			return false, "Invalid UserId."
		end

		local duration = params.Duration or -1
		local reason = params.Reason or "No reason provided"

		local banStore = context.GetBanDataStore()
		local banData = {
			BannedBy = context.Player.UserId,
			BannedByName = context.Player.Name,
			BannedAt = os.time(),
			Duration = duration,
			Reason = reason,
		}

		local ok, err = pcall(function()
			banStore:SetAsync("ban_" .. tostring(userId), banData)
		end)

		if not ok then
			return false, "DataStore error: " .. tostring(err)
		end

		local Players = game:GetService("Players")
		local targetPlayer = Players:GetPlayerByUserId(userId)
		if targetPlayer then
			local durationText = duration == -1 and "Permanent" or (tostring(duration) .. " minutes")
				targetPlayer:Kick("You have been banned. Reason: " .. reason .. " | Duration: " .. durationText)
		end

		local durationText = duration == -1 and "permanently" or ("for " .. tostring(duration) .. " minutes")
		return true, "Banned UserId " .. tostring(userId) .. " " .. durationText .. ". Reason: " .. reason
	end,
}