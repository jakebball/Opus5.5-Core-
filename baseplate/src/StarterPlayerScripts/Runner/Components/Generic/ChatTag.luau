local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

local ChatTag = {}
ChatTag.__index = ChatTag
ChatTag.Tag = "ChatTag"

const ATTRIBUTE_NAME = "ChatTagData"
const DEFAULT_COLOR_HEX = "FFFFFF"

const FONT_FMT = [[<font color="#%s">%s</font>]]

local function hexToRGB(hex)
	if type(hex) ~= "string" or #hex < 6 then
		return 255, 255, 255
	end
	return tonumber(string.sub(hex, 1, 2), 16) or 255,
		tonumber(string.sub(hex, 3, 4), 16) or 255,
		tonumber(string.sub(hex, 5, 6), 16) or 255
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function lerpHex(a, b, t)
	local ar, ag, ab = hexToRGB(a)
	local br, bg, bb = hexToRGB(b)
	return string.format("%02X%02X%02X",
		math.floor(lerp(ar, br, t) + 0.5),
		math.floor(lerp(ag, bg, t) + 0.5),
		math.floor(lerp(ab, bb, t) + 0.5))
end

local function sampleGradient(stops, t)
	local n = #stops
	if n == 0 then return DEFAULT_COLOR_HEX end
	if n == 1 then return stops[1] end
	t = t - math.floor(t)
	local scaled = t * (n - 1)
	local i = math.floor(scaled)
	local frac = scaled - i
	local a = stops[i + 1]
	local b = stops[(i + 1) % n + 1]
	return lerpHex(a, b, frac)
end

local function iterCodepoints(text)
	local out = {}
	for _, c in utf8.codes(text) do
		table.insert(out, utf8.char(c))
	end
	return out
end

local function renderTag(info)
	if type(info) ~= "table" or type(info.text) ~= "string" then return "" end
	local bracketed = "[" .. info.text .. "]"
	local gradient = info.gradient
	if type(gradient) == "table" and type(gradient.stopsHex) == "table" and #gradient.stopsHex > 0 then
		local chars = iterCodepoints(bracketed)
		local n = #chars
		if n == 0 then return "" end
		local phase = 0
		if gradient.animated then
			local cycle = tonumber(gradient.cycleSeconds) or 2
			if cycle > 0 then
				phase = (os.clock() % cycle) / cycle
			end
		end
		local parts = {}
		for i, ch in chars do
			local t = (i - 1) / math.max(1, n - 1)
			local hex = sampleGradient(gradient.stopsHex, t + phase)
			table.insert(parts, string.format(FONT_FMT, hex, ch))
		end
		return table.concat(parts)
	end
	local hex = info.colorHex or DEFAULT_COLOR_HEX
	return string.format(FONT_FMT, hex, bracketed)
end

local function buildPrefix(player)
	if not player then return "" end
	local raw = player:GetAttribute(ATTRIBUTE_NAME)
	if type(raw) ~= "string" or raw == "" then return "" end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then return "" end
	local ordered = {}
	for _, info in decoded do
		table.insert(ordered, info)
	end
	if #ordered == 0 then return "" end
	table.sort(ordered, function(a, b)
		return (tonumber(a.priority) or 0) > (tonumber(b.priority) or 0)
	end)
	local parts = {}
	for _, info in ordered do
		table.insert(parts, renderTag(info))
	end
	return table.concat(parts)
end

function ChatTag.Start()
	setmetatable(ChatTag, { __index = ChatTag.BaseClass })

	TextChatService.OnIncomingMessage = function(message)
		if message.TextSource == nil then return end
		local player = Players:GetPlayerByUserId(message.TextSource.UserId)
		if not player then return end
		local prefix = buildPrefix(player)
		if prefix == "" then return end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = prefix .. " " .. message.PrefixText
		return properties
	end
end

function ChatTag.new(instance)
	local self = setmetatable(ChatTag.BaseClass.new(instance), ChatTag)
	return self
end

function ChatTag:destroy()
	self.trove:Clean()
end

return ChatTag