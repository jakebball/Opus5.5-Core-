local HttpService = game:GetService("HttpService")

local ChatTag = {}
ChatTag.__index = ChatTag
ChatTag.Tag = "ChatTag"

const ATTRIBUTE_NAME = "ChatTagData"

local function color3ToHex(color)
	return string.format("%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5))
end

local function serializeInfo(info)
	local out = {
		text = info.text,
		priority = info.priority,
	}
	if typeof(info.color) == "Color3" then
		out.colorHex = color3ToHex(info.color)
	end
	if type(info.gradient) == "table" and type(info.gradient.stops) == "table" then
		local stopsHex = {}
		for i, stop in info.gradient.stops do
			if typeof(stop) == "Color3" then
				stopsHex[i] = color3ToHex(stop)
			end
		end
		if #stopsHex > 0 then
			out.gradient = {
				stopsHex = stopsHex,
				animated = info.gradient.animated and true or false,
				cycleSeconds = tonumber(info.gradient.cycleSeconds) or 2,
			}
		end
	end
	return out
end

function ChatTag.Start()
	setmetatable(ChatTag, { __index = ChatTag.BaseClass })

	ChatTag.Observers.observePlayer(function(player)
		player:AddTag(ChatTag.Tag)
	end)
end

function ChatTag.new(instance)
	local self = setmetatable(ChatTag.BaseClass.new(instance), ChatTag)
	self.tags = {}
	return self
end

function ChatTag:_publish()
	if not self.instance or not self.instance:IsA("Player") then return end
	if next(self.tags) == nil then
		self.instance:SetAttribute(ATTRIBUTE_NAME, "")
		return
	end
	local serialized = {}
	for key, info in self.tags do
		serialized[key] = serializeInfo(info)
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, serialized)
	if not ok then
		warn("[ChatTag] JSONEncode failed: " .. tostring(encoded))
		return
	end
	self.instance:SetAttribute(ATTRIBUTE_NAME, encoded)
end

function ChatTag:addTag(key, info)
	if type(key) ~= "string" or type(info) ~= "table" or type(info.text) ~= "string" then
		warn("[ChatTag] addTag requires string key + table with .text — got: " ..
			tostring(key) .. " / " .. tostring(info))
		return
	end
	self.tags[key] = {
		text = info.text,
		color = info.color,
		gradient = info.gradient,
		priority = tonumber(info.priority) or 0,
	}
	self:_publish()
end

function ChatTag:removeTag(key)
	if self.tags[key] == nil then return end
	self.tags[key] = nil
	self:_publish()
end

function ChatTag:hasTag(key)
	return self.tags[key] ~= nil
end

function ChatTag:destroy()
	self.tags = {}
	self.trove:Clean()
end

return ChatTag