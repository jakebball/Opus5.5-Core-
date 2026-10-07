const DEFAULT_WALK_SPEED = 16
const OUT_OF_BOARD_WALK_MULT = 2
const DEFAULT_JUMP_HEIGHT = 7.2

local CharacterMovement = {}
CharacterMovement.__index = CharacterMovement
CharacterMovement.Tag = "CharacterMovement"

function CharacterMovement.Start()
	setmetatable(CharacterMovement, { __index = CharacterMovement.BaseClass })
	CharacterMovement.Observers.observePlayer(function(player)
		player:AddTag("CharacterMovement")
	end)
end

function CharacterMovement.new(instance)
	local self = setmetatable(CharacterMovement.BaseClass.new(instance), CharacterMovement)
	self.disabled = {}
	self.movementSnapshot = nil
	self:registerRemote("SetInputDisabled")

	return self
end

function CharacterMovement:disableInput(actionName)
	if self.disabled[actionName] then return end
	self.disabled[actionName] = true
	self:sendNetworkEvent(self.instance, "SetInputDisabled", actionName, true)
end

function CharacterMovement:enableInput(actionName)
	if not self.disabled[actionName] then return end
	self.disabled[actionName] = nil
	self:sendNetworkEvent(self.instance, "SetInputDisabled", actionName, false)
end

function CharacterMovement:isDisabled(actionName)
	return self.disabled[actionName] == true
end

function CharacterMovement:lockMovement()
	self:disableInput("Walk")
	if self.movementSnapshot then return end
	local character = self.instance.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	self.movementSnapshot = {
		walkSpeed = humanoid.WalkSpeed,
		jumpHeight = humanoid.JumpHeight,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
end

function CharacterMovement:unlockMovement()
	local snapshot = self.movementSnapshot
	self.movementSnapshot = nil
	local character = self.instance.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local walk = snapshot and snapshot.walkSpeed
		local jump = snapshot and snapshot.jumpHeight
		humanoid.WalkSpeed = (walk and walk > 0) and walk or DEFAULT_WALK_SPEED * OUT_OF_BOARD_WALK_MULT
		humanoid.JumpHeight = (jump and jump > 0) and jump or DEFAULT_JUMP_HEIGHT
	end
	self:enableInput("Walk")
end

function CharacterMovement:isMovementLocked()
	return self.movementSnapshot ~= nil
end

function CharacterMovement:destroy()
	self.disabled = {}
	self.movementSnapshot = nil
end

return CharacterMovement
