return {
	TestWeaponMode = false,

	-- TESTING VALUE, 2026-08-11. Grants enough XP to own the whole unlock ladder, so every weapon
	-- and gadget is equippable without grinding for it.
	--
	-- STUDIO ONLY. Unlike every other flag in this file, leaving this one true cannot reach a
	-- player: it is additionally gated on RunService:IsStudio(). For a grant-everything fixture
	-- that is the right way round -- the failure mode of a Studio-only gate is a published test
	-- that lacks the grant, and the failure mode of no gate is a published game that hands the
	-- whole catalog to everybody.
	--
	-- A FLOOR, NOT A GRANT: it tops up to the figure rather than adding to it, so a player who has
	-- genuinely earned more is never reduced. The figure is derived by
	-- ProgressionMath.xpToUnlockEverything, so retuning Unlocks moves it automatically and a new
	-- top rung cannot leave this one item short.
	--
	-- IT IS NOT PERSISTED, which is what separates it from the XP fixtures around it. Studio writes
	-- to the REAL DataStore whenever API access is on, so a grant that went through the profile
	-- would permanently bank the XP on the developer's live account and outlive the flag being
	-- switched off. It rides an in-memory offset instead: switch it off, rejoin, and the account is
	-- exactly as it was.
	GiveAllWeapons = false,

	ResetXpOnJoin = false,

	Emplacements = {
		AutoSpawn = {
			Enabled = false,
			Item = "AutoTurret",
			Count = 2,
			Distance = 30,
			Delay = 1.5,
		},
	},

	Dummy = {
		Weapon = "AssaultRifle",
		BurstInterval = 1,
		BurstSize = 3,
		Range = 300,
		Invulnerable = true,
		ParryInterval = 3,
		ParryWindow = 0.6,

		AutoSpawn = {
			Enabled = false,
			Count = 1,
			Distance = 40,
			Spread = 8,
			Delay = 1.5,
		},
	},
}
