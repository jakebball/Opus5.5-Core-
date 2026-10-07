local RunService = game:GetService("RunService")

local RainbowGradient = {}
RainbowGradient.__index = RainbowGradient
RainbowGradient.Tag = "RainbowGradient"

const DEFAULT_TIME_PERIOD = 4
const DEFAULT_SPREAD = 0.5
const SURFACE_TINT_SATURATION = 0.6

const ACTIVATION_DISTANCE = 250
const PROXIMITY_UPDATE_RATE = 0.25
const GUI_KEYPOINTS = 6

local activeInstances = {}
local elapsed = 0

local function referenceCFrame(instance)
	if instance:IsA("Model") then
		local ok, cf = pcall(instance.GetPivot, instance)
		if ok and cf then return cf end
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	local handle = instance:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then return handle.CFrame end
	local first = instance:FindFirstChildWhichIsA("BasePart", true)
	return first and first.CFrame or CFrame.new()
end

function RainbowGradient:_setActive(flag)
	if flag then
		activeInstances[self] = true
	else
		activeInstances[self] = nil
	end
end

-- Each keypoint's hue is the time hue plus its position across the gradient times the spread, so the band scrolls.
local function guiRainbow(timeHue, spread, saturation, value)
	local keypoints = table.create(GUI_KEYPOINTS + 1)
	for index = 0, GUI_KEYPOINTS do
		local fraction = index / GUI_KEYPOINTS
		keypoints[index + 1] = ColorSequenceKeypoint.new(fraction, Color3.fromHSV((timeHue + fraction * spread) % 1, saturation, value))
	end
	return ColorSequence.new(keypoints)
end

function RainbowGradient.Start()
	setmetatable(RainbowGradient, { __index = RainbowGradient.BaseClass })

	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime

		for self in activeInstances do
			local timeHue = elapsed / self.timePeriod
			local spread = self.spread
			if self.guiGradient then
				self.guiGradient.Color = guiRainbow(timeHue, spread, self.saturation, self.value)
				continue
			end
			for part, data in self.paintTargets do
				if part.Parent then
					local hue = (timeHue + data.frac * spread) % 1
					part.Color = Color3.fromHSV(hue, 1, 1)
					if data.surfaceAppearance then
						data.surfaceAppearance.Color = Color3.fromHSV(hue, SURFACE_TINT_SATURATION, 1)
					end
				end
			end
		end
	end)
end

local function buildPaintTargets(instance)
	local parts = {}
	if instance:IsA("BasePart") and instance.Transparency < 1 then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			table.insert(parts, descendant)
		end
	end

	if #parts == 0 then return {} end

	local pivotCFrame = referenceCFrame(instance)

	local localPositions = table.create(#parts)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for index, part in parts do
		local localPos = pivotCFrame:PointToObjectSpace(part.Position)
		localPositions[index] = localPos
		if localPos.X < minX then minX = localPos.X end
		if localPos.Y < minY then minY = localPos.Y end
		if localPos.Z < minZ then minZ = localPos.Z end
		if localPos.X > maxX then maxX = localPos.X end
		if localPos.Y > maxY then maxY = localPos.Y end
		if localPos.Z > maxZ then maxZ = localPos.Z end
	end

	local sizeX, sizeY, sizeZ = maxX - minX, maxY - minY, maxZ - minZ
	local axis, origin, span
	if sizeX >= sizeY and sizeX >= sizeZ then
		axis, origin, span = "X", minX, math.max(sizeX, 0.01)
	elseif sizeY >= sizeZ then
		axis, origin, span = "Y", minY, math.max(sizeY, 0.01)
	else
		axis, origin, span = "Z", minZ, math.max(sizeZ, 0.01)
	end

	local targets = {}
	for index, part in parts do
		local localPos = localPositions[index]
		local coord = localPos[axis]
		local frac = (coord - origin) / span
		local surfaceAppearance = part:FindFirstChildOfClass("SurfaceAppearance")
		targets[part] = {
			original = part.Color,
			frac = frac,
			surfaceAppearance = surfaceAppearance,
			originalSurfaceColor = surfaceAppearance and surfaceAppearance.Color,
		}
	end
	return targets
end

function RainbowGradient.new(instance)
	local self = setmetatable({}, RainbowGradient)
	self.trove = RainbowGradient.Trove.new()
	self.instance = instance
	self.timePeriod = instance:GetAttribute("RainbowSpeed") or DEFAULT_TIME_PERIOD
	self.spread = instance:GetAttribute("RainbowSpread") or DEFAULT_SPREAD
	self.activationDistance = instance:GetAttribute("RainbowDistance") or ACTIVATION_DISTANCE
	self.paintTargets = buildPaintTargets(instance)

	self.trove:Add(instance:GetAttributeChangedSignal("RainbowSpeed"):Connect(function()
		self.timePeriod = instance:GetAttribute("RainbowSpeed") or DEFAULT_TIME_PERIOD
	end), "Disconnect")

	self.trove:Add(instance:GetAttributeChangedSignal("RainbowSpread"):Connect(function()
		self.spread = instance:GetAttribute("RainbowSpread") or DEFAULT_SPREAD
	end), "Disconnect")

	if instance:IsA("UIGradient") then
		if instance:FindFirstAncestorOfClass("PlayerGui") then
			self.guiGradient = instance
			self.saturation = instance:GetAttribute("RainbowSaturation") or 1
			self.value = instance:GetAttribute("RainbowValue") or 1
			self:_setActive(true)
			self.trove:Add(function()
				self:_setActive(false)
			end)
		end
		return self
	end

	local proximity = RainbowGradient.ProximityTrigger.new(instance, {
		distance = self.activationDistance,
		updateRate = PROXIMITY_UPDATE_RATE,
	})
	self.proximity = proximity

	self.trove:Add(proximity.entered:Connect(function()
		self:_setActive(true)
	end), "Disconnect")

	self.trove:Add(proximity.exited:Connect(function()
		self:_setActive(false)
	end), "Disconnect")

	self.trove:Add(function()
		proximity.trove:Destroy()
	end)

	self.trove:Add(function()
		self:_setActive(false)
	end)

	return self
end

function RainbowGradient:restoreColors()
	if not self.paintTargets then return end
	for part, data in self.paintTargets do
		if part.Parent then
			part.Color = data.original
			if data.surfaceAppearance and data.originalSurfaceColor then
				data.surfaceAppearance.Color = data.originalSurfaceColor
			end
		end
	end
end

function RainbowGradient:destroy()
	self:restoreColors()
	self.trove:Clean()
end

return RainbowGradient
