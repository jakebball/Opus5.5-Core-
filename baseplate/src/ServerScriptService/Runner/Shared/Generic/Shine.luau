local TweenService = game:GetService("TweenService")

local Shine = {}

const SHINE_NAME = "Shine"
const GRADIENT_NAME = "ShineGradient"
const DEFAULTS = {
	Rotation = 18,
	Travel = 1.3,
	SweepTime = 1.6,
	HoldTime = 0.5,
	PeakTransparency = 0.5,
}

local function pick(opts, key)
	local value = opts[key]
	if value == nil then return DEFAULTS[key] end
	return value
end

function Shine.apply(parent, opts, parentTrove)
	if not (parent and parent:IsA("GuiObject")) then return nil end
	opts = opts or {}

	local rotation = pick(opts, "Rotation")
	local travel = pick(opts, "Travel")
	local sweepTime = pick(opts, "SweepTime")
	local holdTime = pick(opts, "HoldTime")
	local peakTransparency = pick(opts, "PeakTransparency")
	local startPlaying = opts.StartPlaying
	if startPlaying == nil then startPlaying = true end

	local existing = parent:FindFirstChild(SHINE_NAME)
	if existing then existing:Destroy() end

	local shine = Instance.new("Frame")
	shine.Name = SHINE_NAME
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.5, 0.5)
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BorderSizePixel = 0
	shine.Active = false
	shine.ZIndex = parent.ZIndex + 1

	local existingCorner = parent:FindFirstChildOfClass("UICorner")
	if existingCorner then
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = existingCorner.CornerRadius
		shineCorner.Parent = shine
	end

	local gradient = Instance.new("UIGradient")
	gradient.Name = GRADIENT_NAME
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, peakTransparency),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-travel, 0)
	gradient.Parent = shine

	shine.Parent = parent

	local info = TweenInfo.new(sweepTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, holdTime)
	local tween = TweenService:Create(gradient, info, { Offset = Vector2.new(travel, 0) })
	if parentTrove then parentTrove:Add(tween) end
	if startPlaying then tween:Play() end

	local handle = { instance = shine, tween = tween }
	function handle.setPlaying(on)
		if on then tween:Play() else tween:Pause() end
	end
	return handle
end

return Shine
