local RunService = game:GetService("RunService")

local LevelGradient = {}

local STATIC_GRADIENTS = {
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 160, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
	}),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 160, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 190, 110)),
	}),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 130, 190)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 160, 220)),
	}),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 150, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 180, 80)),
	}),
	ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 70, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 100, 220)),
	}),
}

local ANIMATED_GRADIENTS = {
	{
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 255, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 230, 230)),
		}),
		speed = 0.4,
	},
	{
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 120, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 50, 255)),
		}),
		speed = 0.5,
	},
	{
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 30)),
		}),
		speed = 0.6,
	},
	{
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 100, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(180, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		speed = 0.8,
		rainbow = true,
	},
	{
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.15, Color3.fromRGB(255, 100, 100)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 255, 100)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(100, 255, 100)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(100, 200, 255)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(200, 100, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		speed = 1.0,
		rainbow = true,
	},
}

local activeAnimations = {}

local MAX_LEVEL = 25
local TIER_DIVISOR = 0.4

function LevelGradient.GetColorSequence(level)
	level = math.clamp(level, 1, MAX_LEVEL)
	local tierIndex = math.ceil(level * TIER_DIVISOR)

	if tierIndex <= 5 then
		return STATIC_GRADIENTS[tierIndex]
	end

	local animIndex = tierIndex - 5
	return ANIMATED_GRADIENTS[animIndex].color
end

function LevelGradient.IsAnimated(level)
	return math.ceil(math.clamp(level, 1, MAX_LEVEL) * TIER_DIVISOR) > 5
end

function LevelGradient.Apply(textLabel, level)
	LevelGradient.Stop(textLabel)

	level = math.clamp(level, 1, MAX_LEVEL)
	local tierIndex = math.ceil(level * TIER_DIVISOR)

	local gradient = textLabel:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = textLabel
	end

	if tierIndex <= 5 then
		gradient.Color = STATIC_GRADIENTS[tierIndex]
		gradient.Offset = Vector2.new(0, 0)
		gradient.Rotation = 0
		return function() end
	end

	local animData = ANIMATED_GRADIENTS[tierIndex - 5]
	gradient.Color = animData.color
	gradient.Rotation = 0

	local elapsed = math.random() * 10
	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not textLabel.Parent then
			connection:Disconnect()
			activeAnimations[textLabel] = nil
			return
		end

		elapsed = elapsed + deltaTime * animData.speed
		local offsetX = math.sin(elapsed * math.pi * 2) * 0.5
		gradient.Offset = Vector2.new(offsetX, 0)

		if animData.rainbow then
			gradient.Rotation = (elapsed * 60) % 360
		end
	end)

	activeAnimations[textLabel] = connection

	return function()
		LevelGradient.Stop(textLabel)
	end
end

function LevelGradient.Stop(textLabel)
	local connection = activeAnimations[textLabel]
	if connection then
		connection:Disconnect()
		activeAnimations[textLabel] = nil
	end

	local gradient = textLabel:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Offset = Vector2.new(0, 0)
		gradient.Rotation = 0
	end
end

return LevelGradient