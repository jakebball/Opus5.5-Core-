
local RagdollUtils = require(script.RagdollUtils)

local Ragdoll = {}
Ragdoll.__index = Ragdoll
Ragdoll.Tag = "Ragdoll"

const STATE_REMOTE = "RagdollState"

function Ragdoll.Start()
	setmetatable(Ragdoll, { __index = Ragdoll.BaseClass })
	Ragdoll.Observers.observePlayer(function(player)
		player:AddTag(Ragdoll.Tag)
	end)
end

function Ragdoll.new(instance)
	local self = setmetatable(Ragdoll.BaseClass.new(instance), Ragdoll)

	self._ragdolled = false
	self._timedToken = 0

	self:registerRemote(STATE_REMOTE)

	self.trove:Add(self.instance.CharacterAdded:Connect(function(character)
		self._ragdolled = false
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2)
			RagdollUtils.build(character)
		end)
	end))
	self.trove:Add(self.instance.CharacterRemoving:Connect(function(character)
		self._timedToken += 1
		self._ragdolled = false
		RagdollUtils.teardown(character)
	end))

	local current = self.instance.Character
	if current then
		RagdollUtils.build(current)
	end

	return self
end

function Ragdoll:_character()
	return self.instance.Character
end

function Ragdoll:ragdoll(opts)
	local character = self:_character()
	if not character then
		warn("[Ragdoll/server] ragdoll: no character for " .. self.instance.Name)
		return
	end

	self._ragdolled = true
	character:SetAttribute("IsRagdoll", true)
	RagdollUtils.engage(character)

	self:sendNetworkEvent(self.instance, STATE_REMOTE, {
		active = true,
		impulse = opts and opts.impulse,
	})
end

function Ragdoll:unragdoll()
	if not self._ragdolled then return end
	self._ragdolled = false

	local character = self:_character()
	if character then
		RagdollUtils.disengage(character)
		character:SetAttribute("IsRagdoll", nil)
	end

	self:sendNetworkEvent(self.instance, STATE_REMOTE, { active = false })
end

function Ragdoll:timedRagdoll(seconds, opts)
	self:ragdoll(opts)

	self._timedToken += 1
	local token = self._timedToken
	task.delay(seconds, function()
		if self._timedToken == token then
			self:unragdoll()
		end
	end)
end

function Ragdoll:applyImpulse(impulseVector)
	self:sendNetworkEvent(self.instance, STATE_REMOTE, { impulse = impulseVector })
end

function Ragdoll:isRagdolled()
	return self._ragdolled
end

function Ragdoll:destroy()
	self._timedToken += 1
	self._ragdolled = false
	local character = self:_character()
	if character then
		RagdollUtils.teardown(character)
	end
	self.trove:Clean()
end

return Ragdoll
