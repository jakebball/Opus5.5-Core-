return {
	Name = "Unban",
	Description = "Remove a ban for a player by UserId.",
	MinPermissionLevel = 2,
	LayoutOrder = 200,

	Parameters = {
		{ Name = "UserId", Type = "Number", Required = true },
	},

	Execute = function(context, params)
		local userId = params.UserId
		if not userId or userId <= 0 then
			return false, "Invalid UserId."
		end

		local banStore = context.GetBanDataStore()
		local key = "ban_" .. tostring(userId)

		local banData
		local ok, err = pcall(function()
			banData = banStore:GetAsync(key)
		end)

		if not ok then
			return false, "DataStore error: " .. tostring(err)
		end

		if not banData then
			return false, "UserId " .. tostring(userId) .. " is not banned."
		end

		local removeOk, removeErr = pcall(function()
			banStore:RemoveAsync(key)
		end)

		if not removeOk then
			return false, "DataStore error: " .. tostring(removeErr)
		end

		return true, "Unbanned UserId " .. tostring(userId) .. "."
	end,
}