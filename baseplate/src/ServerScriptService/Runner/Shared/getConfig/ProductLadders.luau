return {
	Starterpack = {
		DurationMinutes = 24 * 60,
		Steps = { "Starter", "Pro", "Hacker" },
		StepData = {
			Starter = {
				ProductKey = "Starterpack",
				DisplayName = "Starter Pack",
				Rewards = {
					{ Kind = "Dice", Amount = 100 },
					{ Kind = "LuckyBlock", Rarity = "Legendary" },
					{ Kind = "Needoh", Id = "Popsicle" },
				},
			},
			Pro = {
				ProductKey = "ProPack",
				DisplayName = "Pro Pack",
				Rewards = {
					{ Kind = "Dice", Amount = 300 },
					{ Kind = "LuckyBlock", Rarity = "Mythic" },
					{ Kind = "Needoh", Id = "Fuzzball" },
				},
			},
			Hacker = {
				ProductKey = "HackerPack",
				DisplayName = "Hacker Pack",
				Rewards = {
					{ Kind = "Dice", Amount = 500 },
					{ Kind = "LuckyBlock", Rarity = "Secret" },
					{ Kind = "Needoh", Id = "Fatcat" },
				},
			},
		},
	},
}
