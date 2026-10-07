local RunService = game:GetService("RunService")

return {
	ProfileVersion = 1,
	UseMockstore = RunService:IsStudio(),
	DataTemplate = {
		Currencies = {
			Coins = 0,
		},
		Inventory = {},
		HotbarGuids = {},
		EquippedItems = {},
		TotalXp = 0,
		LastSeen = 0,
		OnboardingComplete = false,
		SeasonPass = {
			Season = 1,
			Xp = 0,
			Claimed = { Free = {}, Premium = {}, Group = {} },
		},
		Quests = {},
	},
}
