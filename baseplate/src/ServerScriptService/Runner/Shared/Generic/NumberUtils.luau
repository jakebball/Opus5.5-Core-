local NumberUtils = {}

local SUFFIXES = {"", "K", "M", "B", "T"}

function NumberUtils.Abbreviate(n)
	if n < 1000 then
		return "$" .. tostring(math.floor(n))
	end
	local tier = math.floor(math.log10(n) / 3)
	if tier > #SUFFIXES - 1 then tier = #SUFFIXES - 1 end
	local scaled = n / (10 ^ (tier * 3))
	local formatted = string.format("%.1f", scaled)
	formatted = formatted:gsub("%.0$", "")
	return "$" .. formatted .. SUFFIXES[tier + 1]
end

function NumberUtils.Grouped(amount)
	local digits = tostring(math.floor(tonumber(amount) or 0))
	local replacements = 1

	while replacements > 0 do
		digits, replacements = string.gsub(digits, "^(-?%d+)(%d%d%d)", "%1,%2")
	end

	return digits
end

function NumberUtils.SecondsToHMS(s)
	s = math.floor(s)

	local hours = math.floor(s / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local seconds = s % 60

	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

return NumberUtils
