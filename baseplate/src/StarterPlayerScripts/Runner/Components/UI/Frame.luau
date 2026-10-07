local Frame = {}
Frame.__index = Frame
Frame.Tag = "Frame"

const CLOSED_SCALE = 0.01
const SCALE_NAME = "FrameScale"

local openSound
local closeSound

local groupRegistry = {}

local function registerGroup(frame, groupName)
	local set = groupRegistry[groupName]
	if not set then
		set = {}
		groupRegistry[groupName] = set
	end
	set[frame] = true
end

local function unregisterGroup(frame, groupName)
	local set = groupRegistry[groupName]
	if not set then return end
	set[frame] = nil
	if next(set) == nil then
		groupRegistry[groupName] = nil
	end
end

function Frame.Start()
	setmetatable(Frame, { __index = Frame.BaseClass })
	openSound = Frame.Assets.Get("Sounds/UI/FrameOpen")
	closeSound = Frame.Assets.Get("Sounds/UI/FrameClose")
end

function Frame.new(instance)
	local self = setmetatable({}, Frame)

	self.trove = Frame.Trove.new()
	self.instance = instance

	local scale = instance:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = SCALE_NAME
		scale.Parent = instance
	end
	self.scale = scale

	local shouldOpen = self.instance.Visible

	self.scale.Scale = CLOSED_SCALE
	self.instance.Visible = false

	self.group = instance:GetAttribute("FrameGroup")
	if self.group then
		registerGroup(self, self.group)
	end

	if shouldOpen then
		self:open()
	end

	return self
end

function Frame:open()
	if self.group and not self.instance.Visible then
		local set = groupRegistry[self.group]
		if set then
			for sibling in set do
				if sibling ~= self and sibling.instance.Visible then
					sibling:close()
				end
			end
		end
	end

	local wasVisible = self.instance.Visible
	self._visibilityGeneration = (self._visibilityGeneration or 0) + 1
	self.instance.Visible = true
	if not wasVisible and openSound then
		openSound:Play()
	end
	Frame.Spr.target(self.scale, 0.8, 4, {
		Scale = 1,
	})
end

function Frame:close()
	local wasVisible = self.instance.Visible
	self._visibilityGeneration = (self._visibilityGeneration or 0) + 1
	local gen = self._visibilityGeneration
	if wasVisible and closeSound then
		closeSound:Play()
	end
	Frame.Spr.target(self.scale, 0.8, 4, {
		Scale = CLOSED_SCALE,
	})
	Frame.Spr.completed(self.scale, function()
		if self._visibilityGeneration == gen then
			self.instance.Visible = false
		end
	end)
end

function Frame:destroy()
	if self.group then
		unregisterGroup(self, self.group)
	end
	self.trove:Clean()
end

return Frame