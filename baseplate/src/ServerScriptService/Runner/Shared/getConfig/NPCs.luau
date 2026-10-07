return {
	UpgradeShopNPC = { displayName = "Upgrades" },

	SellNPC = {
		displayName = "Needoh Buyer",
		startNode = "greeting",
		nodes = {
			greeting = {
				text = "What can I help you with?",
				responses = {
					{ text = "How much is this worth?", action = { type = "Sell", mode = "quote", vendorComponent = "SellNPC" }, nextNode = "result" },
					{ text = "I want to sell this", action = { type = "Sell", mode = "held", vendorComponent = "SellNPC" }, nextNode = "result" },
					{ text = "I want to sell my inventory", action = { type = "Sell", mode = "all", vendorComponent = "SellNPC" }, nextNode = "result" },
					{ text = "Never mind", nextNode = nil },
				},
			},
			result = {
				text = "{result}",
				responses = {
					{ text = "Anything else?", nextNode = "greeting" },
					{ text = "Goodbye", nextNode = nil },
				},
			},
		},
	},
}