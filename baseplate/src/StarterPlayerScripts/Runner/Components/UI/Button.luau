local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Button = {}
Button.__index = Button
Button.Tag = "Button"

const DEFAULT_HOVER_SCALE = 1.1
const SCALE_NAME = "ButtonScale"

local clickSound
local hoverSound

function Button.Start()
	setmetatable(Button, { __index = Button.BaseClass })
	clickSound = Button.Assets.Get("Sounds/UI/Click")
	hoverSound = Button.Assets.Get("Sounds/UI/ButtonHover")
end

function Button.new(instance)
	local self = setmetatable({}, Button)

	self.trove = Button.Trove.new()
	self.instance = instance

	self.hoverScale = instance:GetAttribute("HoverScale") or DEFAULT_HOVER_SCALE

	local scale = instance:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = SCALE_NAME
		scale.Parent = instance
	end
	self.scale = scale

	self.enabled = true
	self.hoverOverride = false
	self.triggeredEvent = Button.GoodSignal.new()
	self.pressedEvent = Button.GoodSignal.new()
	self.releasedEvent = Button.GoodSignal.new()
	self.quiet = false
	self.activeInput = nil
	self.releaseConnection = nil

	self.trove:Add(self.instance.Activated:Connect(function()
		if not self.enabled then return end
		self.triggeredEvent:Fire()

		if clickSound and not self.quiet then
			clickSound:Play()
		end

		if not self.instance.Parent then return end
		self:_springToRest()
	end))

	self.trove:Add(self.instance.InputBegan:Connect(function(input)
		if not self.enabled then return end
		if self.activeInput then return end
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		self.activeInput = input
		self.releaseConnection = UserInputService.InputEnded:Connect(function(endedInput)
			if endedInput ~= self.activeInput then return end
			self:_release()
		end)
		self.pressedEvent:Fire()
	end))

	self.trove:Add(self.instance.MouseEnter:Connect(function()
		if not self.enabled then return end
		if not self.instance.Parent then return end
		Button.Spr.target(self.scale, 0.8, 4, {
			Scale = self.hoverScale,
		})

		if hoverSound and not self.quiet then
			hoverSound:Play()
		end
	end))

	self.trove:Add(self.instance.MouseLeave:Connect(function()
		if not self.instance.Parent then return end
		self:_springToRest()
	end))

	if self.instance:GetAttribute("Animated") then
		self.hoverOverride = true
		self.trove:Add(RunService.Heartbeat:Connect(function()
			if not self.enabled then return end
			local alpha = (math.sin(tick() * 4) + 1) / 2
			self.scale.Scale = 1 + (self.hoverScale - 1) * alpha
		end))
	end

	return self
end

function Button:_springToRest()
	Button.Spr.target(self.scale, 0.8, 4, {
		Scale = (self.enabled and self.hoverOverride) and self.hoverScale or 1,
	})
end

function Button:setEnabled(enabled)
	enabled = enabled ~= false
	if enabled == self.enabled then return end

	self.enabled = enabled
	if not enabled then
		self:_release()
	end
	if self.instance:IsA("GuiButton") then
		self.instance.AutoButtonColor = enabled
	end
	self:_springToRest()
end

function Button:_release()
	if not self.activeInput then return end
	self.activeInput = nil
	if self.releaseConnection then
		self.releaseConnection:Disconnect()
		self.releaseConnection = nil
	end
	self.releasedEvent:Fire()
end

function Button:setQuiet(quiet)
	self.quiet = quiet ~= false
end

function Button:isEnabled()
	return self.enabled
end

function Button:setHoverOverride(enabled)
	self.hoverOverride = enabled
	self:_springToRest()
end

function Button:destroy()
	self:_release()
	self.trove:Clean()
end

return Button
