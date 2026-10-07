local RunService = game:GetService("RunService")

local Slot = {}
Slot.__index = Slot
Slot.Tag = "Slot"

Slot.DoNotAnimateTag = "DoNotAnimate"

const ATTR_ITEM_KEY = "SlotItemKey"
const ATTR_SLOT_NUMBER = "SlotNumber"
const RAINBOW_PERIOD = 3

local activeRainbowSlots = {}

function Slot.Start()
	setmetatable(Slot, { __index = Slot.BaseClass })
	RunService.Heartbeat:Connect(function()
		if not next(activeRainbowSlots) then return end
		local hue = (os.clock() / RAINBOW_PERIOD) % 1
		local color = Color3.fromHSV(hue, 1, 1)
		for _, overlay in activeRainbowSlots do
			if overlay.Parent then
				overlay.BackgroundColor3 = color
			end
		end
	end)
end

function Slot.new(instance)
	local self = setmetatable({}, Slot)

	self.trove = Slot.Trove.new()
	self.instance = instance

	local getInstance = Slot.getInstance
	local uiDragDetector = getInstance(instance, "UIDragDetector")

	self.activated = instance.Activated
	self.dragStart = uiDragDetector.DragStart
	self.dragContinue = uiDragDetector.DragContinue
	self.dragEnd = uiDragDetector.DragEnd

	self._originalSize = instance.Size
	self._destroyed = false
	self._itemKey = nil
	self._shakeTween = nil
	self._rainbowOverlay = nil
	self._hidden = false
	self._mutationName = nil

	self:_initialize()

	return self
end

function Slot:_initialize()
	self:setText("")
	self:setIcon("")
	self:setHeaderText("")
	self:setEquipped(false)
	self:setDraggingEnabled(false)
	self:setMutation(nil)

	self._modelViewport = nil
	self._pendingModel = nil
	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")
	self._viewportFrame = contentFrame:FindFirstChild("ViewportFrame")
	if self._viewportFrame then
		Slot.EntityStore.promiseGetComponent(self._viewportFrame, "ModelViewport"):andThen(function(mv)
			if self._destroyed then return end
			self._modelViewport = mv
			if self._pendingModel ~= nil then
				mv:setModel(self._pendingModel)
				self._viewportFrame.Visible = true
				self._pendingModel = nil
			end
		end):catch(function() end)
	end

	self:_updateTextSize()
	self.trove:Add(self.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateTextSize()
	end), "Disconnect")
end

function Slot:setItem(payload)
	if payload == nil then
		self.instance:SetAttribute(ATTR_ITEM_KEY, nil)
		self._itemKey = nil
		self:setText("")
		self:setIcon("")
		self:setHeaderText("")
		self:setMutation(nil)
		self:setRarityGradient(nil)
		self:setModel(nil)
		return
	end

	self._itemKey = payload.key
	self.instance:SetAttribute(ATTR_ITEM_KEY, payload.key)
	self:setText(payload.text or "")
	self:setIcon(payload.icon or "")
	if payload.headerText ~= nil then
		self:setHeaderText(payload.headerText)
	end
	self:setRarityGradient(payload.gradient)
	self:setModel(payload.model, payload.modelKey)
end

function Slot:setModel(model, modelKey)
	if not self._viewportFrame then
		if model then model:Destroy() end
		return
	end

	if modelKey ~= nil and modelKey == self._currentModelKey and model ~= nil then
		model:Destroy()
		return
	end

	self._currentModelKey = modelKey

	local iconImageLabel = Slot.getInstance(self.instance, "ContentFrame", "Icon")

	if self._modelViewport then
		self._modelViewport:setModel(model)
		self._viewportFrame.Visible = model ~= nil
	else
		if self._pendingModel and self._pendingModel ~= model then
			self._pendingModel:Destroy()
		end
		self._pendingModel = model
	end

	iconImageLabel.Visible = model == nil
end

function Slot:getItemKey()
	return self._itemKey
end

function Slot:isEmpty()
	return self._itemKey == nil
end

function Slot:setSlotNumber(slotNumber)
	self.instance:SetAttribute(ATTR_SLOT_NUMBER, slotNumber)
end

function Slot:getSlotNumber()
	return self.instance:GetAttribute(ATTR_SLOT_NUMBER)
end

function Slot:setText(text)
	local textLabel = Slot.getInstance(self.instance, "ContentFrame", "Text")
	textLabel.Text = text or ""
end

function Slot:setIcon(icon)
	local iconImageLabel = Slot.getInstance(self.instance, "ContentFrame", "Icon")
	iconImageLabel.Image = icon or ""
end

function Slot:setHeaderText(text)
	local headerTextLabel = Slot.getInstance(self.instance, "ContentFrame", "HeaderText")
	headerTextLabel.Text = text or ""
end

function Slot:getText()
	local textLabel = Slot.getInstance(self.instance, "ContentFrame", "Text")
	return textLabel.Text
end

function Slot:getIcon()
	local iconImageLabel = Slot.getInstance(self.instance, "ContentFrame", "Icon")
	return iconImageLabel.Image
end

function Slot:getInstance_()
	return self.instance
end

function Slot:_updateTextSize()
	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")
	local textLabel = Slot.getInstance(contentFrame, "Text")
	local headerTextLabel = Slot.getInstance(contentFrame, "HeaderText")
	textLabel.TextSize = self.instance.AbsoluteSize.Y / 3.5
	headerTextLabel.TextSize = self.instance.AbsoluteSize.Y / 3.5
end

function Slot:setDraggingEnabled(isEnabled)
	local uiDragDetector = Slot.getInstance(self.instance, "UIDragDetector")
	uiDragDetector.Enabled = isEnabled and true or false
end

function Slot:setContentVisible(isVisible)
	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")
	contentFrame.Visible = isVisible and true or false
end

function Slot:setEquipped(isEquipped)
	local equippedUiStroke = Slot.getInstance(self.instance, "ContentFrame", "EquippedUIStroke")
	equippedUiStroke.Enabled = isEquipped and true or false
end

function Slot:isDestroyed()
	return self._destroyed
end

function Slot:setMutation(name)
	if name == "Normal" then name = nil end
	self._mutationName = name

	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")
	local overlay = contentFrame:FindFirstChild("MutationOverlay")
	if not overlay then
		self:_stopMutationAnimation()
		return
	end

	self:_stopMutationAnimation()

	if name == nil then
		overlay.Visible = false
		Slot.MutationGradient.Apply(overlay, nil)
		return
	end

	overlay.Visible = true

	if name == "Rainbow" then
		Slot.MutationGradient.Apply(overlay, nil)
		self:_startRainbow(overlay)
	else
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Slot.MutationGradient.Apply(overlay, name)
	end
end

function Slot:_startRainbow(overlay)
	self._rainbowOverlay = overlay
	self:_refreshRainbowRegistration()
end

function Slot:_refreshRainbowRegistration()
	if self._rainbowOverlay and not self._hidden then
		activeRainbowSlots[self] = self._rainbowOverlay
	else
		activeRainbowSlots[self] = nil
	end
end

function Slot:_stopMutationAnimation()
	self._rainbowOverlay = nil
	activeRainbowSlots[self] = nil
end

function Slot:setRarityGradient(colorSequence)
	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")
	local overlay = contentFrame:FindFirstChild("RarityOverlay")
	if not overlay then return end
	local gradient = overlay:FindFirstChild("RarityGradient")
	if colorSequence == nil then
		overlay.Visible = false
		if gradient then
			gradient.Color = ColorSequence.new(Color3.new(1, 1, 1))
		end
		return
	end
	if gradient then
		gradient.Color = colorSequence
	end
	overlay.Visible = true
end

function Slot:shake()
	local contentFrame = Slot.getInstance(self.instance, "ContentFrame")

	if self._shakeTween then
		self._shakeTween:Cancel()
		self._shakeTween = nil
	end

	contentFrame.Rotation = 10

	local shakeTween = Slot.UITween.rotation(contentFrame, 0, 0.25, Enum.EasingStyle.Back)
	self._shakeTween = shakeTween
	shakeTween.Completed:Once(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			self._shakeTween = nil
		end
	end)
end

function Slot:setSize(size)
	self._originalSize = size
	self.instance.Size = size
end

function Slot:getSizeInOffset()
	local absoluteSize = self.instance.AbsoluteSize
	return UDim2.fromOffset(absoluteSize.X, absoluteSize.Y)
end

function Slot:setVisible(isVisible)
	self._hidden = not isVisible
	self:_refreshRainbowRegistration()
	if isVisible then
		self.instance:RemoveTag(Slot.DoNotAnimateTag)
		self.instance.Visible = true
		Slot.UITween.size(self.instance, self._originalSize, 0.15, Enum.EasingStyle.Quart)
	else
		self.instance:AddTag(Slot.DoNotAnimateTag)
		Slot.UITween.size(self.instance, UDim2.new(), 0.15, Enum.EasingStyle.Quart).Completed
			:Once(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed then
					self.instance.Visible = false
				end
			end)
	end
end

function Slot:setParent(parent)
	self.instance.Parent = parent
end

function Slot:destroy()
	if self._destroyed then return end
	self._destroyed = true
	self:_stopMutationAnimation()
	if self._pendingModel then
		self._pendingModel:Destroy()
		self._pendingModel = nil
	end
	self.trove:Clean()
	self.instance:Destroy()
end

return Slot