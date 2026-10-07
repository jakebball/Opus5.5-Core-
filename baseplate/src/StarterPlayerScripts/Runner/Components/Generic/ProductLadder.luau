local Players = game:GetService("Players")

local ProductLadder = {}
ProductLadder.__index = ProductLadder
ProductLadder.Tag = "ProductLadder"

local localPlayer = Players.LocalPlayer

function ProductLadder.Start()
	setmetatable(ProductLadder, { __index = ProductLadder.BaseClass })
end

function ProductLadder.new(instance)
	local self = ProductLadder.BaseClass.new(instance)
	setmetatable(self, ProductLadder)

	if instance ~= localPlayer then
		return self
	end

	self.ladders = {}
	self.endsAt = {}
	self.onChanged = ProductLadder.GoodSignal.new()

	self:onRemoteEvent("ProductLadderSync", function(payload)
		payload = payload or {}
		self.ladders = payload.owned or {}
		self.endsAt = payload.endsAt or {}
		self.onChanged:Fire(self.ladders)
	end)

	return self
end

local function getLadderConfig(ladderName)
	local config = ProductLadder.getConfig().ProductLadders
	if not config then return nil end
	return config[ladderName]
end

function ProductLadder:_getOwnedTable(ladderName)
	return self.ladders and self.ladders[ladderName] or {}
end

function ProductLadder:getNextStep(ladderName)
	local config = getLadderConfig(ladderName)
	if not config then return nil end
	local owned = self:_getOwnedTable(ladderName)
	for _, step in config.Steps do
		if not owned[step] then return step end
	end
	return nil
end

function ProductLadder:isOwned(ladderName, stepKey)
	return self:_getOwnedTable(ladderName)[stepKey] == true
end

function ProductLadder:getOwnedSteps(ladderName)
	local copy = {}
	for k, v in self:_getOwnedTable(ladderName) do copy[k] = v end
	return copy
end

function ProductLadder:canBuy(ladderName, stepKey)
	return self:getNextStep(ladderName) == stepKey
end

function ProductLadder:isComplete(ladderName)
	return self:getNextStep(ladderName) == nil
end

function ProductLadder:getStepName(ladderName)
	local stepKey = self:getNextStep(ladderName)
	if not stepKey then return nil end
	local config = getLadderConfig(ladderName)
	local stepData = config and config.StepData and config.StepData[stepKey]
	return (stepData and stepData.DisplayName) or stepKey
end

function ProductLadder:getEndsAt(ladderName)
	return self.endsAt and self.endsAt[ladderName]
end

function ProductLadder:destroy()
	if self.onChanged then self.onChanged:DisconnectAll() end
end

return ProductLadder