local RunService = game:GetService("RunService")

const DEFAULT_DISTANCE = 500
const PROXIMITY_UPDATE_RATE = 0.3
const DEFAULT_FILL_COLOR = Color3.fromRGB(255, 255, 255)
const DEFAULT_OUTLINE_COLOR = Color3.fromRGB(0, 0, 0)
const DEFAULT_FILL_TRANSPARENCY = 0.5
const DEFAULT_OUTLINE_TRANSPARENCY = 0
const DEFAULT_PULSE_PERIOD = 1.2
const HIGHLIGHT_NAME = "ProximityHighlight"

local ProximityHighlight = {}
ProximityHighlight.__index = ProximityHighlight
ProximityHighlight.Tag = "ProximityHighlight"

local pulsing = {}
local heartbeatStarted = false

local function triangle(t)
	return 1 - math.abs(t * 2 - 1)
end

local function startHeartbeat()
	if heartbeatStarted then return end
	heartbeatStarted = true
	RunService.Heartbeat:Connect(function()
		if not next(pulsing) then return end
		local now = os.clock()
		for self in pulsing do
			local highlight = self.highlight
			if highlight and highlight.Parent then
				local phase = (now % self.pulsePeriod) / self.pulsePeriod
				highlight.FillColor = self.fillColor:Lerp(self.pulseColor, triangle(phase))
			end
		end
	end)
end

function ProximityHighlight.Start()
	setmetatable(ProximityHighlight, { __index = ProximityHighlight.BaseClass })
	startHeartbeat()
end

function ProximityHighlight.new(instance)
	local self = setmetatable({}, ProximityHighlight)
	self.trove = ProximityHighlight.Trove.new()
	self.instance = instance
	self.inRange = false

	local stray = instance:FindFirstChild(HIGHLIGHT_NAME)
	if stray then stray:Destroy() end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = instance
	highlight.Enabled = false
	highlight.Parent = instance
	self.highlight = highlight
	self.trove:Add(highlight)

	self:_readConfig()

	for _, name in {
		"HighlightFillColor", "HighlightOutlineColor",
		"HighlightFillTransparency", "HighlightOutlineTransparency",
		"HighlightPulseColor", "HighlightPulsePeriod",
		"HighlightDistance", "HighlightAlwaysOn",
	} do
		self.trove:Add(instance:GetAttributeChangedSignal(name):Connect(function()
			self:_readConfig()
			self:_apply()
		end), "Disconnect")
	end

	local proximity = ProximityHighlight.ProximityTrigger.new(instance, {
		distance = self.distance,
		updateRate = PROXIMITY_UPDATE_RATE,
	})
	self.proximity = proximity
	self.inRange = proximity.inRange

	self.trove:Add(proximity.entered:Connect(function()
		self.inRange = true
		self:_apply()
	end), "Disconnect")
	self.trove:Add(proximity.exited:Connect(function()
		self.inRange = false
		self:_apply()
	end), "Disconnect")
	self.trove:Add(function() proximity.trove:Destroy() end)
	self.trove:Add(function() pulsing[self] = nil end)

	self:_apply()
	return self
end

function ProximityHighlight:_readConfig()
	local instance = self.instance
	self.fillColor = instance:GetAttribute("HighlightFillColor") or DEFAULT_FILL_COLOR
	self.pulseColor = instance:GetAttribute("HighlightPulseColor")
	self.pulsePeriod = instance:GetAttribute("HighlightPulsePeriod") or DEFAULT_PULSE_PERIOD
	if self.pulsePeriod <= 0 then self.pulsePeriod = DEFAULT_PULSE_PERIOD end
	self.distance = instance:GetAttribute("HighlightDistance") or DEFAULT_DISTANCE
	self.alwaysOn = instance:GetAttribute("HighlightAlwaysOn") == true

	local highlight = self.highlight
	if highlight then
		highlight.FillColor = self.fillColor
		highlight.OutlineColor = instance:GetAttribute("HighlightOutlineColor") or DEFAULT_OUTLINE_COLOR
		highlight.FillTransparency = instance:GetAttribute("HighlightFillTransparency") or DEFAULT_FILL_TRANSPARENCY
		highlight.OutlineTransparency = instance:GetAttribute("HighlightOutlineTransparency") or DEFAULT_OUTLINE_TRANSPARENCY
	end

	if self.proximity then self.proximity.distance = self.distance end
end

function ProximityHighlight:_apply()
	local highlight = self.highlight
	if not highlight or not highlight.Parent then return end
	local active = self.alwaysOn or self.inRange
	highlight.Enabled = active
	if active and self.pulseColor then
		pulsing[self] = true
	else
		pulsing[self] = nil
		if active then highlight.FillColor = self.fillColor end
	end
end

function ProximityHighlight:destroy()
	pulsing[self] = nil
	self.trove:Clean()
end

return ProximityHighlight
