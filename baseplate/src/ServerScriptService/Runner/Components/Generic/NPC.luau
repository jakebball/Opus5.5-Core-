local Players = game:GetService("Players")

const NPC = {}
NPC.__index = NPC
NPC.Tag = "NPC"
NPC.ActionHandlers = {}

local activeNPCs = {}
const MAX_INTERACTION_DISTANCE = 30

local function getDistanceToNPC(player, npcInstance)
	local character = player.Character
	if not character then return math.huge end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return math.huge end

	local npcPosition = npcInstance:GetPivot().Position
	return (humanoidRootPart.Position - npcPosition).Magnitude
end

function NPC.Start()
	setmetatable(NPC, { __index = NPC.BaseClass })

	local actionsFolder = script.Parent:FindFirstChild("Actions")
	if actionsFolder then
		for _, child in actionsFolder:GetChildren() do
			if child:IsA("ModuleScript") then
				NPC.ActionHandlers[child.Name] = require(child)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, npcComponent in activeNPCs do
			if npcComponent:isInDialogue(player) then
				npcComponent:endDialogue(player)
			end
		end
	end)
end

function NPC.new(instance)
	local self = NPC.BaseClass.new(instance)
	setmetatable(self, NPC)

	self.npcId = instance:GetAttribute("NPCId") or instance.Name

	local NPCConfig = NPC.getConfig().NPCs
	self.config = NPCConfig[self.npcId]

	self.activeSessions = {}

	self:registerRemote("DialogueData")
	self:registerRemote("DialogueEnd")
	self:registerRemote("CollectVFX")
	self.idleTrack = nil
	self.talkTrack = nil

	activeNPCs[instance] = self

	self:onRemoteEvent("StartDialogue", function(player)
		if getDistanceToNPC(player, instance) > MAX_INTERACTION_DISTANCE then
			return
		end

		local dialogueData = self:startDialogue(player)
		if not dialogueData then return end

		self:sendNetworkEvent(player, "DialogueData", dialogueData)
	end)

	self:onRemoteEvent("SelectResponse", function(player, responseIndex)
		if type(responseIndex) ~= "number" then return end

		if getDistanceToNPC(player, instance) > MAX_INTERACTION_DISTANCE then
			self:endDialogue(player)
			return
		end

		local nextDialogue = self:selectResponse(player, responseIndex)
		if nextDialogue then
			self:sendNetworkEvent(player, "DialogueData", nextDialogue)
		else
			self:sendNetworkEvent(player, "DialogueEnd")
		end
	end)

	self:onRemoteEvent("EndDialogue", function(player)
		if self:isInDialogue(player) then
			self:endDialogue(player)
		end
	end)

	self:onRemoteEvent("FinishedTalking", function(player)
		if self:isInDialogue(player) then
			self:playIdleAnimation()
		end
	end)

	self:setup()

	return self
end

function NPC:setup()
	if not self.config then return end

	self.instance:SetAttribute("DisplayName", self.config.displayName)
	self.instance:SetAttribute("NPCId", self.npcId)

	local humanoid = self.instance:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local humanoidRootPart = self.instance:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		humanoidRootPart.Anchored = true
	end

	self:setupProximityPrompt()
	self:setupAnimations()
end

function NPC:setupProximityPrompt()
	local head = self.instance:FindFirstChild("Head")
	local torso = self.instance:FindFirstChild("Torso") or self.instance:FindFirstChild("UpperTorso")
	local attachPart = head or torso or self.instance:FindFirstChild("HumanoidRootPart") or self.instance.PrimaryPart
	if not attachPart then return end
	if not self.config or not self.config.startNode then return end
	if attachPart:FindFirstChild("DialoguePrompt") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DialoguePrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = self.config and self.config.displayName or self.npcId
	prompt.MaxActivationDistance = 20
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = attachPart
	self.trove:Add(prompt)
end

function NPC:setupAnimations()
	local NPCAnimationsFolder = NPC.Assets.Get("Animations/NPC")
	if not NPCAnimationsFolder then return end

	local NPCConfig = NPC.getConfig().NPCs
	local animId = NPCConfig.AnimationIds and NPCConfig.AnimationIds[self.npcId] or self.npcId
	local animFolder = NPCAnimationsFolder:FindFirstChild(animId)
	if not animFolder then return end

	local humanoid = self.instance:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local idleAnim = animFolder:FindFirstChild("Idle")
	local talkAnim = animFolder:FindFirstChild("Talk")

	if idleAnim then
		self.idleTrack = animator:LoadAnimation(idleAnim)
		self.idleTrack.Looped = true
		self.idleTrack.Priority = Enum.AnimationPriority.Action
		self.idleTrack:Play()
	end

	if talkAnim then
		self.talkTrack = animator:LoadAnimation(talkAnim)
		self.talkTrack.Looped = true
	end
end

function NPC:playTalkAnimation()
	if self.idleTrack and self.idleTrack.IsPlaying then
		self.idleTrack:Stop()
	end
	if self.talkTrack and not self.talkTrack.IsPlaying then
		self.talkTrack:Play()
	end
end

function NPC:playIdleAnimation()
	if self.talkTrack and self.talkTrack.IsPlaying then
		self.talkTrack:Stop()
	end
	if self.idleTrack and not self.idleTrack.IsPlaying then
		self.idleTrack:Play()
	end
end

function NPC:startDialogue(player)
	if not self.config then return nil end

	self.activeSessions[player] = {
		currentNode = self.config.startNode
	}

	self:playTalkAnimation()

	return self:getCurrentDialogue(player)
end

function NPC:getCurrentDialogue(player)
	local session = self.activeSessions[player]
	if not session then return nil end

	local node = self.config.nodes[session.currentNode]
	if not node then
		return nil
	end

	local text = node.text
	if session.actionResult then
		text = text:gsub("{result}", session.actionResult)
		session.actionResult = nil
	end

	local responses = {}
	if node.responses then
		for index, response in node.responses do
			responses[index] = { text = response.text }
		end
	end

	return {
		text = text,
		responses = responses,
	}
end

function NPC:selectResponse(player, responseIndex)
	local session = self.activeSessions[player]
	if not session then
		return nil
	end

	local currentNode = self.config.nodes[session.currentNode]
	if not currentNode then return nil end

	local response = currentNode.responses and currentNode.responses[responseIndex]
	if not response then return nil end

	if response.action then
		self:handleAction(player, response.action)
	end

	if response.nextNode == nil then
		self:endDialogue(player)
		return nil
	end

	session.currentNode = response.nextNode
	self:playTalkAnimation()
	return self:getCurrentDialogue(player)
end

function NPC:handleAction(player, action)
	local handler = NPC.ActionHandlers[action.type]
	if handler then
		handler(player, self, self.activeSessions[player], action)
	else
		warn("[NPC] Unknown action type:", action.type)
	end
end

function NPC:endDialogue(player)
	self.activeSessions[player] = nil

	local hasActiveSessions = false
	for _ in self.activeSessions do
		hasActiveSessions = true
		break
	end

	if not hasActiveSessions then
		self:playIdleAnimation()
	end
end

function NPC:isInDialogue(player)
	return self.activeSessions[player] ~= nil
end

function NPC:destroy()
	if self.idleTrack then
		self.idleTrack:Stop()
	end
	if self.talkTrack then
		self.talkTrack:Stop()
	end

	activeNPCs[self.instance] = nil
end

return NPC