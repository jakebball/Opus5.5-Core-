local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local ProximityPrompt = {}
ProximityPrompt.__index = ProximityPrompt
ProximityPrompt.Tag = "ProximityPrompt"

const SCREEN_GUI_NAME = "ProximityPrompts"
const TEMPLATE_NAME = "Default"

const FADE_TIME = 0.15
const HOLD_SQUEEZE = UDim2.fromScale(0.5, 1)
const FULL_WIDTH = UDim2.fromScale(1, 1)

const PROMPT_HEIGHT = 72
const BUTTON_WIDTH = 72
const TEXT_PADDING_LEFT = 72
const TEXT_PADDING_RIGHT = 24
const OBJECT_TEXT_OFFSET = -10
const ACTION_TEXT_OFFSET = 9

const TOUCH_ICON = "rbxasset://textures/ui/Controls/TouchTapIcon.png"

const GAMEPAD_BUTTON_IMAGE = {
	[Enum.KeyCode.ButtonX] = "rbxasset://textures/ui/Controls/xboxX.png",
	[Enum.KeyCode.ButtonY] = "rbxasset://textures/ui/Controls/xboxY.png",
	[Enum.KeyCode.ButtonA] = "rbxasset://textures/ui/Controls/xboxA.png",
	[Enum.KeyCode.ButtonB] = "rbxasset://textures/ui/Controls/xboxB.png",
	[Enum.KeyCode.DPadLeft] = "rbxasset://textures/ui/Controls/dpadLeft.png",
	[Enum.KeyCode.DPadRight] = "rbxasset://textures/ui/Controls/dpadRight.png",
	[Enum.KeyCode.DPadUp] = "rbxasset://textures/ui/Controls/dpadUp.png",
	[Enum.KeyCode.DPadDown] = "rbxasset://textures/ui/Controls/dpadDown.png",
	[Enum.KeyCode.ButtonSelect] = "rbxasset://textures/ui/Controls/xboxmenu.png",
	[Enum.KeyCode.ButtonL1] = "rbxasset://textures/ui/Controls/xboxLS.png",
	[Enum.KeyCode.ButtonR1] = "rbxasset://textures/ui/Controls/xboxRS.png",
}

const KEYBOARD_BUTTON_IMAGE = {
	[Enum.KeyCode.Backspace] = "rbxasset://textures/ui/Controls/backspace.png",
	[Enum.KeyCode.Return] = "rbxasset://textures/ui/Controls/return.png",
	[Enum.KeyCode.LeftShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.RightShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.Tab] = "rbxasset://textures/ui/Controls/tab.png",
}

const KEYBOARD_ICON_MAPPING = {
	["'"] = "rbxasset://textures/ui/Controls/apostrophe.png",
	[","] = "rbxasset://textures/ui/Controls/comma.png",
	["`"] = "rbxasset://textures/ui/Controls/graveaccent.png",
	["."] = "rbxasset://textures/ui/Controls/period.png",
	[" "] = "rbxasset://textures/ui/Controls/spacebar.png",
}

const KEY_CODE_TEXT = {
	[Enum.KeyCode.LeftControl] = "Ctrl", [Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftAlt] = "Alt", [Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.F1] = "F1", [Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3", [Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5", [Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7", [Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9", [Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11", [Enum.KeyCode.F12] = "F12",
}

local playerGui
local template

local function cursorIsFree()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return false
	end

	local localPlayer = Players.LocalPlayer
	return localPlayer == nil or localPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson
end

local function getScreenGui()
	local screenGui = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = SCREEN_GUI_NAME
		screenGui.ResetOnSpawn = false
		screenGui.Parent = playerGui
	end
	return screenGui
end

local function fadeProperties(instance)
	if instance:IsA("UIStroke") then
		return { "Transparency" }
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
		return { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" }
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		return { "BackgroundTransparency", "ImageTransparency" }
	elseif instance:IsA("GuiObject") then
		return { "BackgroundTransparency" }
	end
	return nil
end

local function collectFadeTargets(promptUI, holdExclusion)
	local targets = {}

	for _, descendant in promptUI:GetDescendants() do
		local properties = fadeProperties(descendant)
		if properties then
			local shownValues = {}
			for _, propertyName in properties do
				shownValues[propertyName] = descendant[propertyName]
			end

			table.insert(targets, {
				instance = descendant,
				shownValues = shownValues,
				fadesOnHold = not descendant:IsDescendantOf(holdExclusion),
			})
		end
	end

	return targets
end

local function snapHidden(targets)
	for _, target in targets do
		for propertyName in target.shownValues do
			target.instance[propertyName] = 1
		end
	end
end

local function playFade(targets, visible, holdOnly)
	local tweenInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, target in targets do
		if not holdOnly or target.fadesOnHold then
			local goal = {}
			for propertyName, shownValue in target.shownValues do
				goal[propertyName] = if visible then shownValue else 1
			end
			TweenService:Create(target.instance, tweenInfo, goal):Play()
		end
	end
end

local function applyInputGlyph(inputFrame, prompt, inputType)
	local buttonImage = inputFrame.ButtonImage
	local buttonText = inputFrame.ButtonText
	local buttonIcon = inputFrame.ButtonTextImage

	buttonImage.Visible = false
	buttonText.Visible = false
	buttonIcon.Visible = false

	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local image = GAMEPAD_BUTTON_IMAGE[prompt.GamepadKeyCode]
		if image then
			buttonIcon.Image = image
			buttonIcon.Visible = true
		end
		return
	end

	if inputType == Enum.ProximityPromptInputType.Touch then
		buttonImage.Image = TOUCH_ICON
		buttonImage.Visible = true
		return
	end

	buttonImage.Visible = true

	local keyText = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	local keyImage = KEYBOARD_BUTTON_IMAGE[prompt.KeyboardKeyCode] or KEYBOARD_ICON_MAPPING[keyText]

	if keyImage then
		buttonIcon.Image = keyImage
		buttonIcon.Visible = true
		return
	end

	keyText = KEY_CODE_TEXT[prompt.KeyboardKeyCode] or keyText

	if keyText == nil or keyText == "" then
		warn("[ProximityPrompt] " .. prompt.Name .. " has a KeyboardKeyCode with nothing to draw: " .. tostring(prompt.KeyboardKeyCode))
		return
	end

	if #keyText > 2 then
		buttonText.TextSize = math.round(buttonText.TextSize * 6 / 7)
	end

	buttonText.Text = keyText
	buttonText.Visible = true
end

local function measureText(label)
	if label.Text == "" then return 0 end

	local params = Instance.new("GetTextBoundsParams")
	params.Text = label.Text
	params.Font = label.FontFace
	params.Size = label.TextSize
	params.Width = 1000

	return TextService:GetTextBoundsAsync(params).X
end

local function resizePrompt(promptUI, prompt)
	local frame = promptUI.PromptFrame
	local actionText = frame.ActionText
	local objectText = frame.ObjectText

	actionText.Text = prompt.ActionText
	objectText.Text = prompt.ObjectText

	local width = BUTTON_WIDTH
	if prompt.ActionText ~= "" or prompt.ObjectText ~= "" then
		width = math.max(measureText(actionText), measureText(objectText)) + TEXT_PADDING_LEFT + TEXT_PADDING_RIGHT
	end

	local actionOffsetY = if prompt.ObjectText ~= "" then ACTION_TEXT_OFFSET else 0
	actionText.Position = UDim2.new(0.5, TEXT_PADDING_LEFT - width / 2, 0, actionOffsetY)
	objectText.Position = UDim2.new(0.5, TEXT_PADDING_LEFT - width / 2, 0, OBJECT_TEXT_OFFSET)

	promptUI.Size = UDim2.fromOffset(width, PROMPT_HEIGHT)
	promptUI.SizeOffset = Vector2.new(prompt.UIOffset.X / width, prompt.UIOffset.Y / PROMPT_HEIGHT)
end

local function bindProgressRing(inputFrame, progress)
	local bar = inputFrame:FindFirstChild("ProgressBar")
	local leftImage = bar and bar.LeftGradient:FindFirstChild("ProgressBarImage")
	local rightImage = bar and bar.RightGradient:FindFirstChild("ProgressBarImage")
	local leftGradient = leftImage and leftImage:FindFirstChildOfClass("UIGradient")
	local rightGradient = rightImage and rightImage:FindFirstChildOfClass("UIGradient")

	if not leftGradient or not rightGradient then return nil end

	return progress:GetPropertyChangedSignal("Value"):Connect(function()
		-- the ring is two half-discs: the left sweeps 180deg->360deg, the right 0deg->180deg
		local angle = math.clamp(progress.Value * 360, 0, 360)
		leftGradient.Rotation = math.clamp(angle, 180, 360)
		rightGradient.Rotation = math.clamp(angle, 0, 180)
	end)
end

function ProximityPrompt.Start()
	setmetatable(ProximityPrompt, { __index = ProximityPrompt.BaseClass })

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	playerGui = localPlayer:WaitForChild("PlayerGui")
	template = script:FindFirstChild(TEMPLATE_NAME)

	if not template then
		warn("[ProximityPrompt] the " .. TEMPLATE_NAME .. " template is missing — custom prompts cannot render")
	end
end

function ProximityPrompt.new(instance)
	local self = setmetatable(ProximityPrompt.BaseClass.new(instance), ProximityPrompt)

	if not instance:IsA("ProximityPrompt") then
		warn("[ProximityPrompt] " .. instance:GetFullName() .. " is a " .. instance.ClassName .. ", not a ProximityPrompt")
		return self
	end

	self.promptUI = nil
	self.targets = nil
	self.showGeneration = 0

	self.uiTrove = ProximityPrompt.Trove.new()
	self.trove:Add(self.uiTrove)

	self.trove:Add(instance.PromptShown:Connect(function(inputType)
		self:_show(inputType)
	end))

	self.trove:Add(instance.PromptHidden:Connect(function()
		self:_hide()
	end))

	return self
end

function ProximityPrompt:isShowing()
	return self.promptUI ~= nil
end

function ProximityPrompt:_show(inputType)
	if not template then return end
	if self.instance.Style == Enum.ProximityPromptStyle.Default then return end

	self:_hide()

	self.showGeneration += 1
	local generation = self.showGeneration

	local promptUI, targets, connections = self:_build(inputType)
	if not promptUI then return end

	-- _build yields on GetTextBoundsAsync. If the prompt hid, re-showed, or this component was
	-- freed while it ran, the UI belongs to a show that is already over and must not be parented.
	if generation ~= self.showGeneration then
		for _, connection in connections do
			connection:Disconnect()
		end
		promptUI:Destroy()
		return
	end

	for _, connection in connections do
		self.uiTrove:Add(connection, "Disconnect")
	end

	self.uiTrove:Add(function()
		playFade(targets, false, false)
		task.delay(FADE_TIME, function()
			promptUI:Destroy()
		end)
	end)

	self.promptUI = promptUI
	self.targets = targets

	promptUI.Parent = getScreenGui()
	playFade(targets, true, false)
end

function ProximityPrompt:_hide()
	self.showGeneration += 1
	self.promptUI = nil
	self.targets = nil
	self.uiTrove:Clean()
end

function ProximityPrompt:_build(inputType)
	local prompt = self.instance

	local promptUI = template:Clone()
	promptUI.Enabled = true
	promptUI.Adornee = prompt.Parent

	local frame = promptUI.PromptFrame
	local inputFrame = frame.InputFrame.Frame

	local connections = {}
	local targets = collectFadeTargets(promptUI, frame.InputFrame)
	snapHidden(targets)

	applyInputGlyph(inputFrame, prompt, inputType)

	local progress = Instance.new("NumberValue")
	progress.Name = "ThemeProgress"
	progress.Value = 0
	progress.Parent = promptUI

	local ringConnection = bindProgressRing(inputFrame, progress)
	if ringConnection then
		table.insert(connections, ringConnection)
	end

	if prompt.HoldDuration > 0 then
		local fillInfo = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		local squeezeInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fillTween = TweenService:Create(progress, fillInfo, { Value = 1 })

		table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
			fillTween:Play()
			playFade(targets, false, true)
			TweenService:Create(frame, squeezeInfo, { Size = HOLD_SQUEEZE }):Play()
		end))

		table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
			fillTween:Cancel()
			progress.Value = 0
			playFade(targets, true, true)
			TweenService:Create(frame, squeezeInfo, { Size = FULL_WIDTH }):Play()
		end))
	end

	table.insert(connections, prompt.Triggered:Connect(function()
		playFade(targets, false, false)
	end))

	table.insert(connections, prompt.TriggerEnded:Connect(function()
		playFade(targets, true, false)
	end))

	local isTouch = inputType == Enum.ProximityPromptInputType.Touch

	if isTouch or (prompt.ClickablePrompt and cursorIsFree()) then
		local button = promptUI.TextButton
		local holding = false

		table.insert(connections, button.InputBegan:Connect(function(input)
			if input.UserInputState == Enum.UserInputState.Change then return end
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

			holding = true
			prompt:InputHoldBegin()
		end))

		table.insert(connections, button.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if not holding then return end

			holding = false
			prompt:InputHoldEnd()
		end))

		promptUI.Active = true
		button.Interactable = true
	end

	for _, propertyName in { "ActionText", "ObjectText" } do
		table.insert(connections, prompt:GetPropertyChangedSignal(propertyName):Connect(function()
			resizePrompt(promptUI, prompt)
		end))
	end

	resizePrompt(promptUI, prompt)

	return promptUI, targets, connections
end

function ProximityPrompt:destroy()
	self.showGeneration += 1
	self.trove:Clean()
end

return ProximityPrompt
