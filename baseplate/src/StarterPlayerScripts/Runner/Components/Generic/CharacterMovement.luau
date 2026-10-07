local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer = Players.LocalPlayer

local CharacterMovement = {}
CharacterMovement.__index = CharacterMovement
CharacterMovement.Tag = "CharacterMovement"

const ACTION_KEYS = {
	Walk = {
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Thumbstick1,
	},
	Jump = {
		Enum.KeyCode.Space, Enum.KeyCode.ButtonA,
	},
}

local function actionTagFor(actionName)
	return "CharacterMovement_Disable_" .. actionName
end

function CharacterMovement.Start()
	setmetatable(CharacterMovement, { __index = CharacterMovement.BaseClass })
	CharacterMovement.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("CharacterMovement")
		end
	end)
end

function CharacterMovement.new(instance)
	local self = setmetatable(CharacterMovement.BaseClass.new(instance), CharacterMovement)
	self.disabled = {}
	task.spawn(function()
		self:onRemoteEvent("SetInputDisabled", function(actionName, isDisabled)
			self:_apply(actionName, isDisabled)
		end)
	end)
	return self
end

function CharacterMovement:_apply(actionName, isDisabled)
	local keys = ACTION_KEYS[actionName]
	if not keys then
		warn("[CharacterMovement] unknown action: " .. tostring(actionName))
		return
	end
	local actionTag = actionTagFor(actionName)
	if isDisabled then
		self.disabled[actionName] = true
		ContextActionService:BindActionAtPriority(
			actionTag,
			function() return Enum.ContextActionResult.Sink end,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(keys)
		)
	else
		self.disabled[actionName] = nil
		ContextActionService:UnbindAction(actionTag)
	end
end

function CharacterMovement:destroy()
	for actionName in self.disabled do
		ContextActionService:UnbindAction(actionTagFor(actionName))
	end
	self.disabled = {}
end

return CharacterMovement
