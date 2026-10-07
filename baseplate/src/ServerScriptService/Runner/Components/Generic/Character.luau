local Character = {}
Character.__index = Character
Character.Tag = "Character"

function Character.Start()
	setmetatable(Character, { __index = Character.BaseClass })
	Character.Observers.observeCharacter(function(_, character)
		character:AddTag(Character.Tag)
	end)
end

function Character.new(instance)
	local self = setmetatable({}, Character)

	self.trove = Character.Trove.new()

	self.instance = instance

	return self
end

function Character:getHumanoidRootPartCFrame()
	if self.instance == nil then return end
	if self.instance:FindFirstChild("HumanoidRootPart") == nil then return end

	return self.instance.HumanoidRootPart.CFrame
end

function Character:destroy()
	self.trove:Clean()
end

return Character