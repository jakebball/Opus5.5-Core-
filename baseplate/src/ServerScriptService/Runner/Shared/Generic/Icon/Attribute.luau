task.defer(function()
	local RunService = game:GetService("RunService")
	local VERSION = require(script.Parent.VERSION)
	local appVersion = VERSION.getAppVersion()
	local latestVersion = VERSION.getLatestVersion()
	local isOutdated = not VERSION.isUpToDate()
	if not RunService:IsStudio() then
		print(`🍍 Running TopbarPlus {appVersion} by @ForeverHD & HD Admin`)
	end
	if isOutdated then
		warn(`A new version of TopbarPlus ({latestVersion}) is available: https://devforum.roblox.com/t/topbarplus/1017485`)
	end
end)

return {}