local Players = game:GetService("Players")

local ShopTransactions = {}
ShopTransactions.__index = ShopTransactions
ShopTransactions.Tag = "ShopTransactions"

local localPlayer = Players.LocalPlayer

local purchaseSound

const VFX_LIFETIME = 2

function ShopTransactions.Start()
	setmetatable(ShopTransactions, { __index = ShopTransactions.BaseClass })
	purchaseSound = ShopTransactions.Assets.Get("Sounds/Misc/PurchaseSuccessful")

	ShopTransactions.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag("ShopTransactions")
		end
	end)
end

function ShopTransactions.new(instance)
	local self = setmetatable(ShopTransactions.BaseClass.new(instance), ShopTransactions)
	if instance ~= localPlayer then return self end

	self.lastPurchaseSoundAt = 0
	self:onRemoteEvent("PurchaseSuccess", function(_kind)
		if not purchaseSound then return end
		local now = os.clock()
		if now - self.lastPurchaseSoundAt < 0.25 then return end
		self.lastPurchaseSoundAt = now
		purchaseSound:Play()
	end)

	return self
end

function ShopTransactions:upgrade(upgradeType, quantity)
	self:sendNetworkEvent("Upgrade", upgradeType, quantity or 1)
end

function ShopTransactions:rebirth()
	self:sendNetworkEvent("Rebirth")
end

function ShopTransactions:buyBoard(boardId)
	self:sendNetworkEvent("BuyBoard", boardId)
end

function ShopTransactions:equipBoard(boardId)
	self:sendNetworkEvent("EquipBoard", boardId)
end

function ShopTransactions:buyDice()
	self:sendNetworkEvent("BuyDice")
end

function ShopTransactions:destroy()
end

return ShopTransactions