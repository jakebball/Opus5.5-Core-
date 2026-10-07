local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

const NPC = {}
NPC.__index = NPC
NPC.Tag = "NPC"

local player = Players.LocalPlayer

const MAX_DIALOGUE_DISTANCE = 30
const PROMPT_FIND_ATTEMPTS = 10
const PROMPT_FIND_INTERVAL = 0.5
const NO_RESPONSE_CLOSE_DELAY = 2
const RESPONSE_HOVER_COLOR = Color3.fromRGB(255, 235, 160)

const KEY_TO_INDEX = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local activeDialogue = nil

local function findAttachPart(npcInstance)
	return npcInstance:FindFirstChild("Head")
		or npcInstance:FindFirstChild("HumanoidRootPart")
		or npcInstance.PrimaryPart
end

local function getDistanceToNPC(npcInstance)
	local character = player.Character
	if not character then return math.huge end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return math.huge end

	return (humanoidRootPart.Position - npcInstance:GetPivot().Position).Magnitude
end

local function findDialoguePrompt(npcInstance)
	for _, descendant in npcInstance:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "DialoguePrompt" then
			return descendant
		end
	end
	return nil
end

function NPC.Start()
	setmetatable(NPC, { __index = NPC.BaseClass })
end

function NPC.new(instance)
	local self = NPC.BaseClass.new(instance)
	setmetatable(self, NPC)

	self.dialogueBillboard = nil
	self.inputConnection = nil
	self.distanceCheckConnection = nil
	self.responsesScreenGui = nil
	self.responsesContainer = nil

	self:onRemoteEvent("CollectVFX", function(sourcePosition)
		local position = sourcePosition or instance:GetPivot().Position
		if NPC.CollectVFX and NPC.CollectVFX.play then
			NPC.CollectVFX.play(NPC, position)
		end
	end)

	self:onRemoteEvent("DialogueData", function(dialogueData)
		self:_onDialogueData(dialogueData)
	end)

	self:onRemoteEvent("DialogueEnd", function()
		self:closeDialogue(true)
	end)

	task.spawn(function()
		local prompt
		for _ = 1, PROMPT_FIND_ATTEMPTS do
			prompt = findDialoguePrompt(instance)
			if prompt then break end
			task.wait(PROMPT_FIND_INTERVAL)
		end
		if not prompt then return end
		self.trove:Add(prompt.Triggered:Connect(function()
			self:startDialogue()
		end))
	end)

	return self
end

function NPC:_isOpen()
	return activeDialogue == self
end

function NPC:_ensureUi()
	if self.responsesContainer and self.responsesContainer.Parent then return true end

	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not playerGui then return false end

	local screenGui = playerGui:WaitForChild("DialogueResponses", 10)
	if not screenGui then return false end

	local container = screenGui:WaitForChild("Container", 10)
	if not container then return false end

	self.responsesScreenGui = screenGui
	self.responsesContainer = container
	return true
end

function NPC:setNPCPromptEnabled(enabled)
	local prompt = findDialoguePrompt(self.instance)
	if prompt then
		prompt.Enabled = enabled
	end
end

function NPC:createDialogueBillboard()
	local attachPart = findAttachPart(self.instance)
	if not attachPart then return nil end

	local existing = attachPart:FindFirstChild("DialogueBillboard")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DialogueBillboard"
	billboard.Size = UDim2.new(13, 0, 1, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 1
	billboard.MaxDistance = 150
	billboard.Parent = attachPart

	local dialogueLabel = NPC.Assets.Clone("Gui/Dialogue")
	if dialogueLabel then
		dialogueLabel.Name = "DialogueText"
		dialogueLabel.Text = ""
		dialogueLabel.Parent = billboard
	end

	return billboard
end

function NPC:clearResponses()
	if not self.responsesContainer then return end
	for _, child in self.responsesContainer:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

function NPC:createResponseButton(index, responseData)
	local button = NPC.Assets.Clone("Gui/DialogueButton")
	if not button then return nil end

	button.Name = "Response_" .. index
	button.LayoutOrder = index
	button.Active = true

	local numberLabel = button:FindFirstChild("Number")
	if numberLabel then
		numberLabel.Text = "#" .. index
	end

	local textLabel = button:FindFirstChild("Text")
	if textLabel then
		textLabel.Text = responseData.text
	end

	button.Parent = self.responsesContainer

	local baseColor = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = RESPONSE_HOVER_COLOR
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = baseColor
	end)
	button.Activated:Connect(function()
		self:selectResponse(index)
	end)

	return button
end

function NPC:setupInputListener()
	if self.inputConnection then return end

	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not self:_isOpen() then return end

		local keyNumber = KEY_TO_INDEX[input.KeyCode]
		if keyNumber then
			self:selectResponse(keyNumber)
		end
	end)
end

function NPC:cleanupInputListener()
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
end

function NPC:startDistanceCheck()
	if self.distanceCheckConnection then return end

	self.distanceCheckConnection = RunService.Heartbeat:Connect(function()
		if not self:_isOpen() then return end
		if getDistanceToNPC(self.instance) > MAX_DIALOGUE_DISTANCE then
			self:closeDialogue(false)
		end
	end)
end

function NPC:stopDistanceCheck()
	if self.distanceCheckConnection then
		self.distanceCheckConnection:Disconnect()
		self.distanceCheckConnection = nil
	end
end

function NPC:startDialogue()
	if self:_isOpen() then return end
	if not self:_ensureUi() then
		warn("[NPC] dialogue UI unavailable for", self.instance.Name)
		return
	end

	if activeDialogue then
		activeDialogue:closeDialogue(false)
	end
	activeDialogue = self

	self:setNPCPromptEnabled(false)

	self.dialogueBillboard = self:createDialogueBillboard()
	if not self.dialogueBillboard then
		activeDialogue = nil
		self:setNPCPromptEnabled(true)
		return
	end

	self.responsesScreenGui.Enabled = true
	self:setupInputListener()
	self:startDistanceCheck()
	self:sendNetworkEvent("StartDialogue")
end

function NPC:_onDialogueData(dialogueData)
	if not self:_isOpen() then return end
	if not dialogueData then
		self:closeDialogue(true)
		return
	end
	self:_displayDialogue(dialogueData)
end

function NPC:_displayDialogue(dialogueData)
	local billboardOk = (self.dialogueBillboard and self.dialogueBillboard.Parent) ~= nil
	if not billboardOk then return end

	local dialogueText = self.dialogueBillboard:FindFirstChild("DialogueText")
	if not dialogueText then return end

	self:clearResponses()

	local displayText = (dialogueData.text or ""):gsub("%s*|%s*", " ")
	dialogueText.Text = displayText

	self:sendNetworkEvent("FinishedTalking")

	if dialogueData.responses and #dialogueData.responses > 0 then
		for index, response in dialogueData.responses do
			self:createResponseButton(index, response)
		end
	else
		task.delay(NO_RESPONSE_CLOSE_DELAY, function()
			if self:_isOpen() then
				self:closeDialogue(false)
			end
		end)
	end
end

function NPC:selectResponse(responseIndex)
	if not self:_isOpen() then return end

	local responseButton = self.responsesContainer:FindFirstChild("Response_" .. responseIndex)
	if not responseButton then return end

	if self.dialogueBillboard then
		local dialogueText = self.dialogueBillboard:FindFirstChild("DialogueText")
		if dialogueText then
			dialogueText.Text = ""
		end
	end
	self:clearResponses()

	self:sendNetworkEvent("SelectResponse", responseIndex)
end

function NPC:closeDialogue(fromServer)
	if not self:_isOpen() then return end

	self:cleanupInputListener()
	self:stopDistanceCheck()
	self:setNPCPromptEnabled(true)

	if not fromServer then
		self:sendNetworkEvent("EndDialogue")
	end

	activeDialogue = nil

	if self.dialogueBillboard then
		self.dialogueBillboard:Destroy()
		self.dialogueBillboard = nil
	end

	self:clearResponses()
	if self.responsesScreenGui then
		self.responsesScreenGui.Enabled = false
	end
end

function NPC:destroy()
	self:closeDialogue(true)
end

return NPC
