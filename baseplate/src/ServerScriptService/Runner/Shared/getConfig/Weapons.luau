-- Three viewmodel poses cover every weapon in this game, not ten. The clips pose ARMS ONLY -- the
-- weapon rides the rig's RightHand through each model's ViewmodelGrip attribute -- so a pose is a
-- function of how a weapon is HELD, not of which weapon it is. Sidearms share one set, long guns
-- another, batons a third. Sources: ServerStorage.WeaponAnimSaves. See features/weapons.md.
--
-- `Shoot` is the key Gun:_fire plays on every trigger pull, so the baton's swing lives under that
-- name rather than a truer one.
local SIDEARM_POSE = {
	Idle = "rbxassetid://112775286465154",
	Shoot = "rbxassetid://128693630745475",
}
local LONG_GUN_POSE = {
	Idle = "rbxassetid://76504648993005",
	Shoot = "rbxassetid://116010976920778",
}
local BATON_POSE = {
	Idle = "rbxassetid://121842361468236",
	Shoot = "rbxassetid://82473959380238",
}
-- The Slingshot is the one weapon that does not share a pose. Its clips are held lower than the
-- Sidearm hold AND they pose the weapon's own `Pouch` joint -- the draw, the release and the
-- overshoot are keyframes, so they only fit this model.
local SLINGSHOT_POSE = {
	Idle = "rbxassetid://113656803598498",
	Shoot = "rbxassetid://79042127293611",
}

local TASER_MUZZLE_DEBRIS = {
	Count = 10,
	Lifetime = 0.16,
	LaunchSpeed = 26,
	SpeedJitterMin = 0.55,
	SpeedJitterRange = 0.75,
	ConeAngle = 16,
	SpawnRadius = 0.06,
	Size = Vector3.new(0.09, 0.09, 0.09),
	Color = Color3.fromRGB(90, 195, 255),
	Drag = 14,
	GravityScale = 0,
	SpinSpeed = 14,
	Material = Enum.Material.Neon,
}
local SONIC_MUZZLE_DEBRIS = {
	Count = 14,
	Lifetime = 0.2,
	LaunchSpeed = 20,
	SpeedJitterMin = 0.55,
	SpeedJitterRange = 0.75,
	ConeAngle = 28,
	SpawnRadius = 0.06,
	Size = Vector3.new(0.11, 0.11, 0.11),
	Color = Color3.fromRGB(90, 195, 255),
	Drag = 11,
	GravityScale = 0,
	SpinSpeed = 10,
	Material = Enum.Material.Neon,
}
-- The taser's spit exactly, in white -- the Zip-Cuff Launcher and the Beanbag Rifle share it, the
-- way both tasers share the table above. Cloned rather than retyped for the reason HIT_STYLES.Sonic
-- is: two hand-copied sets of the same twelve numbers are two sets that drift.
-- Gun:_burstMuzzleDebris table.clones before it fills in Origin and Direction, so sharing is safe.
local WHITE_MUZZLE_DEBRIS = table.clone(TASER_MUZZLE_DEBRIS)
WHITE_MUZZLE_DEBRIS.Color = Color3.fromRGB(240, 240, 245)

return {
	SharedViewmodelAnimations = {
		Run = "rbxassetid://77731555336956",
		Sprint = "rbxassetid://112929426089969",
	},

	Default = {
		Damage = 20,
		FireInterval = 0.12,
		Range = 1000,
	},

	-- ==== No weapon in this game reloads ==========================================================
	-- NONE of the ten entries below carries MagazineSize, ReloadTime or ReloadTimeEmpty, and that
	-- absence IS the feature: Gun:_magazineFor returns nil without a MagazineSize, so Gun:fire skips
	-- the ammo gate, Gun:reload refuses, the server never publishes an ammo payload, the client's
	-- self.ammo stays nil, and Gun:_reload returns on its first line. Infinite ammo and a dead R key
	-- with no code path to maintain.
	--
	-- The only thing still limiting rate of fire is FireInterval. Adding MagazineSize back to any
	-- entry restores that weapon's magazine and reload wholesale -- the machinery was never removed,
	-- only unused.
	--
	-- The boilerplate weapons further down (AssaultRifle, Sniper, RocketLauncher, ...) keep theirs.
	-- Nothing in this place equips them, and stripping them would be drift to reconcile for nothing.
	-- ==============================================================================================
	Taser = {
		DisplayName = "Taser",
		Description = "- Crowd control",
		Delivery = "Hitscan",
		-- What the shot LOOKS like. Hitscan already resolved on the trigger frame, so the bolt is
		-- pure presentation and TracerSpeed only decides how long it takes to arrive. 600 keeps the
		-- gap between firing and the guest's blue flicker under a quarter second at the far end of
		-- the 150-stud range, and imperceptible at gate distances.
		--
		-- Without a BulletAsset a weapon falls back to VFX/Bullet -- the grey mesh round -- which is
		-- what the taser fired until now. It was never "nothing drawn": it was the wrong thing.
		BulletAsset = "VFX/TaserBolt",
		TracerSpeed = 600,
		-- The stock muzzle light is orange, which is wrong over a blue bolt. Same blue as the bolt
		-- and as the hit flicker in Concert/ShootableNPC.
		MuzzleLightColor = Color3.fromRGB(90, 195, 255),
		MuzzleDebris = TASER_MUZZLE_DEBRIS,
		-- No ADSAttachment on the model and no sights on a taser, so aiming is opted out here
		-- rather than left to fail silently at Gun:canAds.
		CanAds = false,
		Damage = 25,
		FireInterval = 0.4,
		Range = 150,
		Kind = "Weapon",
		Slot = "Primary",
		-- The camera does not move when you shoot, at all. Scales Gun's four camera-kick constants,
		-- and 0 makes Gun skip the CameraShake call outright. A quarter was tried first and was
		-- still too much: most of the stock kick is the YAW/ROLL pair, which is re-randomised per
		-- shot, so the view swung a different way on every trigger pull.
		-- The recoil you DO see is the viewmodel's, which this does not scale -- see features/weapons.md.
		CameraKickScale = 0,
		Model = "Models/Weapons/Taser",
		-- Hold and Shoot only. Equip/Reload have no clips, and FPSViewmodel:_track skips a name
		-- with no id, so the missing ones cost nothing. Run/Sprint are deliberately absent: the
		-- shared locomotion clips were authored for a two-handed rifle hold and fight this pose,
		-- so walking rides ViewmodelMotion's procedural bob instead.
		ViewmodelAnimations = SIDEARM_POSE,
	},


	-- ==== Purchasable weapons ====================================================================
	-- None of these are in getConfig/Items.StartingKit. They reach a player through
	-- Concert/GateKit:grant(itemId) and nothing else -- today only the GiveWeapon admin command
	-- calls it; a shop calls the same method when one exists. See features/weapons.md.
	--
	-- Every Damage/Range/Interval number below is UNKNOWN in the sense features/economy.md uses:
	-- picked to make each weapon feel distinct against 100 guest health, never measured.
	AdvancedTaser = {
		DisplayName = "Advanced Taser",
		Description = "- Three shots instead of four",
		Delivery = "Hitscan",
		-- A tier up from the Taser should LOOK like the Taser. These three had never been written,
		-- so it fired VFX/Bullet -- the grey mesh rifle round -- behind the boilerplate orange flash
		-- at 800 studs/s, none of which the weapon it upgrades has done since 2026-09-01.
		BulletAsset = "VFX/TaserBolt",
		TracerSpeed = 600,
		MuzzleLightColor = Color3.fromRGB(90, 195, 255),
		MuzzleDebris = TASER_MUZZLE_DEBRIS,
		CanAds = false,
		CameraKickScale = 0,
		Damage = 34,
		FireInterval = 0.35,
		Range = 160,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/AdvancedTaser",
		ViewmodelAnimations = SIDEARM_POSE,
	},

	Slingshot = {
		DisplayName = "Slingshot",
		Description = "- Cheap, and it shows",
		Delivery = "Hitscan",
		CanAds = false,
		CameraKickScale = 0,
		-- The round that flies is the same rubber ball that sits in the pouch. 400 is slow enough to
		-- read as a lobbed pellet rather than a tracer, and still lands inside a quarter second at
		-- the 90-stud range -- the shot itself resolved on the trigger frame, so any slower and the
		-- guest would flicker before the ball arrived.
		BulletAsset = "VFX/SlingshotPellet",
		TracerSpeed = 400,
		-- The ball leaves when the band lets go, not when the trigger is pulled. 0.17 is the moment
		-- the Shoot clip's pouch passes the fork on its way forward -- drawn at 0.13, released by
		-- 0.19. This delays the DAMAGE as well as the tracer, so the slingshot has a real wind-up:
		-- a moving target needs slightly more lead than with the other nine weapons.
		FireDelay = 0.17,
		-- No muzzle flash on a slingshot. 0 makes Gun:_flashMuzzleLight bail before it builds one.
		MuzzleLightBrightness = 0,
		Damage = 15,
		FireInterval = 0.55,
		Range = 90,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/Slingshot",
		ViewmodelAnimations = SLINGSHOT_POSE,
	},

	SonicGun = {
		DisplayName = "Sonic Gun",
		Description = "- Fast, short-ranged",
		Delivery = "Hitscan",
		BulletAsset = "VFX/SonicRing",
		TracerSpeed = 450,
		MuzzleLightColor = Color3.fromRGB(90, 195, 255),
		MuzzleDebris = SONIC_MUZZLE_DEBRIS,
		HitKind = "Sonic",
		CanAds = false,
		CameraKickScale = 0,
		Damage = 20,
		FireInterval = 0.30,
		Range = 60,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/SonicGun",
		ViewmodelAnimations = SIDEARM_POSE,
	},

	ZipCuffLauncher = {
		DisplayName = "Zip-Cuff Launcher",
		Description = "- Slow, and it ties them up",
		Delivery = "Hitscan",
		BulletAsset = "VFX/ZipCuffBola",
		-- 330 puts the bola 0.37s out at the full 120 studs, past the "a tracer must not arrive
		-- after the flinch it caused" budget the other four rounds were tuned to. Taken knowingly:
		-- inside the 40 studs this is actually fired at it lands in 0.12s, and the round IS the
		-- weapon here -- a bola nobody can see spin is a grey dot with extra steps.
		TracerSpeed = 330,
		MuzzleDebris = WHITE_MUZZLE_DEBRIS,
		MuzzleLightBrightness = 0,
		-- The baton's reaction plus the cord. HIT_STYLES.ZipCuff in Concert/ShootableNPC is a
		-- table.clone of Impact -- same grey flash, same blunt thud, no shock orb -- with one extra
		-- field, the way Sonic is a clone of Electric with one sound rewritten.
		HitKind = "ZipCuff",
		CanAds = false,
		CameraKickScale = 0,
		Damage = 20,
		FireInterval = 0.9,
		Range = 120,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/ZipCuffLauncher",
		ViewmodelAnimations = SIDEARM_POSE,
	},

	BeanbagRifle = {
		DisplayName = "Beanbag Rifle",
		Description = "- Two shots, at any range",
		Delivery = "Hitscan",
		-- A small white fabric square, flat face leading. Without a BulletAsset this fired
		-- VFX/Bullet, the grey mesh rifle round, out of a less-lethal launcher.
		BulletAsset = "VFX/BeanbagRound",
		-- The Taser's bolt speed exactly, because that is the one round in this game demonstrably
		-- visible at gate range and there is no reason to guess a second number. At 600 the pad
		-- crosses 20 studs in two frames, so what the player reads is the trail's 72-stud streak --
		-- which is why the bolt works at this speed and the first cut of this round, faster and with
		-- a duller trail, was invisible. 0.33s at the full 200 studs.
		TracerSpeed = 600,
		MuzzleDebris = WHITE_MUZZLE_DEBRIS,
		-- A beanbag is not a taser. "Impact" is the Baton's reaction -- grey flash, blunt thud, no
		-- shock orb -- where falling through the default would crackle.
		HitKind = "Impact",
		CanAds = false,
		CameraKickScale = 0,
		Damage = 50,
		FireInterval = 0.85,
		Range = 200,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/BeanbagRifle",
		ViewmodelAnimations = LONG_GUN_POSE,
	},

	NetGun = {
		DisplayName = "Net Gun",
		Description = "- Three shots, very slow",
		Delivery = "Hitscan",
		-- The gun's own net mesh, fired balled up and opening to 3.6x over its first 44 studs --
		-- ExpandTo / ExpandSeconds on the asset, read by Gun.templateFor beside SpinRate.
		BulletAsset = "VFX/Net",
		-- 220 puts the net 0.45s out at the full 100 studs, past the "a tracer must not arrive
		-- after the flinch it caused" budget, and taken knowingly for the Zip-Cuff Launcher's
		-- reason: the round IS the weapon, and a net that opens in four frames is a grey smear.
		-- At the 30 studs the gate actually shoots at it lands in 0.14s, still spreading.
		TracerSpeed = 220,
		-- A gas-driven net launcher is not a firearm; the boilerplate flash is orange and was
		-- wrong over a white net for the reason it was wrong over the Zip-Cuff Launcher's cord.
		MuzzleLightBrightness = 0,
		-- The Taser's reaction plus the net left behind. HIT_STYLES.Net in Concert/ShootableNPC
		-- is a table.clone of Electric with one extra field, the way ZipCuff clones Impact.
		HitKind = "Net",
		CanAds = false,
		CameraKickScale = 0,
		Damage = 25,
		FireInterval = 1.2,
		Range = 100,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/NetGun",
		ViewmodelAnimations = LONG_GUN_POSE,
	},

	AdvancedSonicGun = {
		DisplayName = "Advanced Sonic Gun",
		Description = "- The fastest thing in the kit",
		Delivery = "Hitscan",
		BulletAsset = "VFX/SonicRing",
		-- Three rings, not one. The model carries a MuzzleFlash pod dead centre and TWO called
		-- MuzzleFlashSide at +-0.47 studs; one entry matches every part with that name, so the
		-- pair costs one line. 0.75 is the 25% smaller side ring: 1.28 studs against the main
		-- ring's 1.70. Gun:_spawnExtraRounds spawns them; the damage is still one ray.
		ExtraRounds = {
			{ Mount = "MuzzleFlashSide", Scale = 0.75 },
		},
		TracerSpeed = 500,
		MuzzleLightColor = Color3.fromRGB(90, 195, 255),
		MuzzleDebris = SONIC_MUZZLE_DEBRIS,
		HitKind = "Sonic",
		CanAds = false,
		CameraKickScale = 0,
		Damage = 27,
		FireInterval = 0.28,
		Range = 80,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/AdvancedSonicGun",
		ViewmodelAnimations = LONG_GUN_POSE,
	},

	-- Kind = "Melee" is honest labelling and nothing in this place reads it -- neither half of
	-- Generic/Gun looks at Kind at all, so a baton is a very short-ranged hitscan weapon. The batons
	-- were the first entries with no MagazineSize; as of 2026-09-01 every weapon is.
	Baton = {
		DisplayName = "Baton",
		Description = "- Arm's reach, three hits",
		Delivery = "Hitscan",
		CanAds = false,
		CameraKickScale = 0,
		-- A baton is not a gun and must not look like one. BulletAsset = false stops it firing the
		-- default grey mesh round, MuzzleLightBrightness = 0 stops the orange flash at its tip, and
		-- FireDelay lands the damage on the strike frame of the swing rather than on the click.
		-- Swings an arc rather than casting a ray: 100 degrees of reach in front of you, resolved by
		-- HitscanMath.sweep on both sides. Without this a baton only connects with whatever is dead
		-- centre of the screen, which is what a gun does.
		-- A baton is not a taser, and this one is not: Concert/ShootableNPC keys its hit reaction off
		-- this, and "Impact" is a grey flash and a blunt thud where the default is the blue electric
		-- flicker, the crackle and the shock orb. The Advanced Baton opts back in with "Electric".
		HitKind = "Impact",
		MeleeArc = 100,
		BulletAsset = false,
		MuzzleLightBrightness = 0,
		FireDelay = 0.18,
		Damage = 34,
		FireInterval = 0.55,
		Range = 8,
		Kind = "Melee",
		Slot = "Primary",
		Model = "Models/Weapons/Baton",
		ViewmodelAnimations = BATON_POSE,
	},
	AdvancedBaton = {
		DisplayName = "Advanced Baton",
		Description = "- Arm's reach, two hits, and it shocks",
		Delivery = "Hitscan",
		CanAds = false,
		CameraKickScale = 0,
		-- A baton is not a gun and must not look like one. BulletAsset = false stops it firing the
		-- default grey mesh round, MuzzleLightBrightness = 0 stops the orange flash at its tip, and
		-- FireDelay lands the damage on the strike frame of the swing rather than on the click.
		-- Swings an arc rather than casting a ray: 100 degrees of reach in front of you, resolved by
		-- HitscanMath.sweep on both sides. Without this a baton only connects with whatever is dead
		-- centre of the screen, which is what a gun does.
		-- THIS baton is a stun baton, which is the entire difference between the two tiers beyond
		-- damage: "Electric" is the Taser's own reaction -- the blue flicker, the crackle and the
		-- shock orb -- where the plain Baton's "Impact" is a grey flash and a blunt thud. Written
		-- out rather than left to fall through DEFAULT_HIT_STYLE, so it reads as a decision.
		HitKind = "Electric",
		MeleeArc = 100,
		BulletAsset = false,
		MuzzleLightBrightness = 0,
		FireDelay = 0.18,
		Damage = 50,
		FireInterval = 0.5,
		Range = 9,
		Kind = "Melee",
		Slot = "Primary",
		Model = "Models/Weapons/AdvancedBaton",
		ViewmodelAnimations = BATON_POSE,
	},
	-- ==============================================================================================
	AssaultRifle = {
		DisplayName = "Assault Rifle",
		Description = "- Standard Primary",
		Delivery = "Projectile",
		ProjectileSpeed = 300,
		ProjectileGravityScale = 0.0875,
		Damage = 20,
		FireInterval = 0.12,
		Range = 1000,
		MagazineSize = 30,
		CarveRadius = 2.5,
		ReloadTime = 2.1333,
		ReloadTimeEmpty = 2.8,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/AssaultRifle",
		Animations = {
			Idle = "rbxassetid://124043066794714",
			Equip = "rbxassetid://87679651787037",
			Shoot = "rbxassetid://109791061579443",
			Reload = "rbxassetid://135873803454582",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://94261377418254",
			Equip = "rbxassetid://91510076667658",
			Reload = "rbxassetid://102757987985499",
			ReloadEmpty = "rbxassetid://80718951482487",
		},
	},
	Sniper = {
		DisplayName = "Sniper",
		Description = "- Long Range Primary",
		BulletAsset = "VFX/SniperBullet",
		-- How fast the TRACER crosses the gap, studs/s. Cosmetic: the shot was already resolved
		-- on the trigger frame. Streak length is this times the asset's Trail Lifetime, so
		-- 1400 x 0.45 draws a ~630-stud ribbon -- the whole shot visible at once.
		-- Distinct from ProjectileSpeed, which only a Delivery = "Projectile" weapon reads.
		TracerSpeed = 1400,
		Damage = 90,
		FireInterval = 1.4,
		Range = 1000,
		MagazineSize = 5,
		CarveRadius = 3,
		ReloadTime = 2.5,
		ReloadTimeEmpty = 2.8,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/Sniper",
		Animations = {
			Idle = "rbxassetid://78093005032619",
			Equip = "rbxassetid://92768019495754",
			Shoot = "rbxassetid://125843681680833",
			Reload = "rbxassetid://138543020491019",
			ReloadEmpty = "rbxassetid://92572766894311",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://122324958514576",
			Equip = "rbxassetid://78822634652706",
			Shoot = "rbxassetid://88717267861779",
			Reload = "rbxassetid://130891986239654",
			ReloadEmpty = "rbxassetid://133099582021111",
		},
	},
	RocketLauncher = {
		DisplayName = "Rocket Launcher",
		Description = "- Explosive Primary",
		Delivery = "Rocket",
		CanAds = false,
		ProjectileSpeed = 35,
		-- Thrust in studs/s^2, NOT a fraction of workspace.Gravity. d(t) = 35t + 155t^2 covers the
		-- 1000-stud Range in ~2.43 s, by which point the round is doing ~790 studs/s -- launch and
		-- terminal speed differ by 22x, so the ramp is the thing you read on screen rather than a
		-- flat streak. It is SLOWER in speed than the old 90/260 curve until t = 1.1 s (where
		-- 35 + 310t meets 90 + 260t) and faster after, and still behind in DISTANCE until ~2.3 s,
		-- so the whole flight reads as a late catch-up rather than a shifted constant.
		-- RocketMaxSpeed would cap that (motor burnout); unset, so it accelerates the whole way
		-- and Range is what ends the flight.
		RocketAcceleration = 310,
		BulletAsset = "VFX/Rocket",
		ChamberedRoundPart = "Rocket",
		ImpactBlast = {
			Payload = "Explosive",
			Damage = 110,
			MinDamage = 25,
			BlastRadius = 18,
			CarveRadius = 12,
			SelfDamage = false,
		},
		Damage = 120,
		FireInterval = 1.2,
		Range = 1000,
		MagazineSize = 1,
		ReloadOnFire = true,
		CarveRadius = 3,
		ReloadTime = 3,
		ReloadTimeEmpty = 3,
		Kind = "Weapon",
		Slot = "Primary",
		Model = "Models/Weapons/RocketLauncher",
		Animations = {
			Idle = "rbxassetid://96774706570671",
			Equip = "rbxassetid://122060628939055",
			Shoot = "rbxassetid://127845445532806",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://114364081221757",
			Equip = "rbxassetid://130204803557628",
			Shoot = "rbxassetid://83568296298596",
		},
	},
	Sword = {
		DisplayName = "Sword",
		Description = "- Melee Primary",
		Kind = "Melee",
		Slot = "Primary",
		Damage = 50,
		BackstabDamage = 100,
		Range = 9,
		SwingInterval = 0.85,
		SpeedMultiplier = 1.25,
		DashMultiplier = 1.25,
		ParryWindow = 0.15,
		ParryStun = 1,
		ParryDuration = 1.15,
		ParryCooldown = 1,
		Model = "Models/Weapons/Sword",
		Animations = {
			Idle = "rbxassetid://95322030174727",
			Run = "rbxassetid://71461411104644",
			Equip = "rbxassetid://121544789570500",
			Swing1 = "rbxassetid://140106585214686",
			Swing2 = "rbxassetid://102219991995666",
			Parry = "rbxassetid://97066420187987",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://139899321808664",
			Run = "rbxassetid://119057494566806",
			Equip = "rbxassetid://133046898655138",
			Swing1 = "rbxassetid://74167496981394",
			Swing2 = "rbxassetid://98271604999588",
			Parry = "rbxassetid://135461683150556",
		},
	},
	BuildTool = {
		Kind = "BuildTool",
		Model = "Models/Weapons/BuildTool",
		Animations = {
			Idle = "rbxassetid://98101590631033",
			Equip = "rbxassetid://73177987291104",
			Use = "rbxassetid://109245113974756",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://128384754508574",
			Equip = "rbxassetid://137845289585198",
			Use = "rbxassetid://138130997550917",
		},
	},
	Grenade = {
		DisplayName = "Grenade",
		Description = "- Explosive Secondary",
		Kind = "Throwable",
		Slot = "Secondary",
		FuseTime = 3,
		ThrowCooldown = 1.2,
		ThrowSpeed = 90,
		ThrowLift = 18,
		Damage = 110,
		MinDamage = 25,
		BlastRadius = 18,
		CarveRadius = 12,
		SelfDamage = false,
		Payload = "Explosive",
		DetonateOn = "Fuse",
		ArmedPulse = {
			StartPeriod = 1,
			EndPeriod = 0.14,
			Scale = 1.3,
			Sound = "Tick",
			StartPitch = 0.9,
			EndPitch = 1.5,
		},
		StowAttachment = "WaistCenterAttachment",
		StowOffset = CFrame.new(1.15, -0.05, -0.15) * CFrame.Angles(0, 0, math.rad(-10)),
		Model = "Models/Weapons/Grenade",
		Animations = {
			Idle = "rbxassetid://139293330713482",
			Equip = "rbxassetid://136631593756592",
			Trigger = "rbxassetid://97726344560087",
			TriggerThrow = "rbxassetid://79784062276215",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://98478180583201",
			Equip = "rbxassetid://116521895360121",
			Trigger = "rbxassetid://116832032663414",
			TriggerHold = "rbxassetid://101614050771196",
			TriggerThrow = "rbxassetid://126631934629223",
		},
	},
	Jammer = {
		DisplayName = "Jammer",
		Description = "- Disruptor Secondary",
		Kind = "Gadget",
		Effect = "Jam",
		Slot = "Secondary",
		UseCooldown = 2.15,
		JamRadius = 30,
		JamDuration = 15,
		Model = "Models/Weapons/Jammer",
		StowAttachment = "WaistCenterAttachment",
		StowOffset = CFrame.new(1.02, -0.32, 0) * CFrame.Angles(0, 0, math.rad(-90)),
		Animations = {
			Idle = "rbxassetid://73559650738661",
			Equip = "rbxassetid://73433053720606",
			Use = "rbxassetid://105668733617503",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://123657049488510",
			Equip = "rbxassetid://83939895784797",
			Use = "rbxassetid://118151841546191",
		},
	},
	AutoTurret = {
		DisplayName = "Auto Turret",
		Description = "- Deployable Secondary",
		Kind = "Gadget",
		Effect = "PlaceStructure",
		PlacedModel = "Models/PlacedTurret",
		PlaceRange = 24,
		-- The tag game code queries a placement by. Every placement carries the same COMPONENT
		-- (PlacedStructure, which owns the one-per-player rule); only this tag tells them apart,
		-- which is why a second deployable needs no new class. No PlacedScale: the model is
		-- 4.3 x 4.0 x 5.2, already about chest height on a 5-stud character.
		PlacedTag = "PlacedTurret",
		-- The deployed turret's traverse, read by the PlacedTurret pair. ScanSweep is degrees EACH
		-- WAY from centre, so the arc actually swept is 90. ScanSpeed is degrees per second, and
		-- ScanBroadcastRate is how often the server ships its yaw -- the client eases over
		-- exactly one interval of it, so raising the rate tightens the follow and lowering it
		-- softens the sweep. Both halves read this key, so they cannot disagree about the pacing.
		--
		-- Cost note: this is a per-component remote, so it is one FireAllClients per turret per
		-- tick rather than one batched packet for all of them. At 12 Hz and one turret per player
		-- that is fine; if turret counts ever grow, batching is the lever.
		ScanSweep = 45,
		ScanSpeed = 30,
		ScanBroadcastRate = 12,
		TurretRange = 150,
		TurretFireInterval = 0.25,
		TurretDamage = 10,
		-- How many rounds it holds, and how long it spends refilling once it has run the
		-- magazine dry. It keeps tracking through the reload -- it just cannot shoot -- so a
		-- player who breaks the lock during one buys distance rather than a fresh scan.
		--
		-- Cost note: the loaded count is a reliable broadcast per shot, so a firing turret costs
		-- 1/TurretFireInterval packets a second on top of the yaw stream, and nothing at all
		-- while it is scanning. Read by the PlacedTurret pair and drawn by TurretAmmoGui.
		TurretMagazine = 30,
		TurretReloadTime = 3,
		TurretHealth = 150,
		Slot = "Secondary",
		UseCooldown = 0.9,
		UseEffectDelay = 0.2,
		Model = "Models/Weapons/AutoTurret",
		-- ONE model, both cameras. The authored R15 and Viewmodel weapon folders were geometrically
		-- byte-identical (0.000000 divergence), so k = 1 and no grip C1 needed rescaling -- unlike
		-- the sword, whose two blades were genuinely different sizes. The model carries GripOffset
		-- for the avatar hand and ViewmodelMount/ViewmodelGrip for first person; both authored C1s
		-- were identity, so neither GripC1 nor ViewmodelGripC1 is declared.
		--
		-- ViewmodelMount is "HumanoidRootPart", NOT "RightHand" like every other item here: the
		-- first-person clips were authored off the rig ROOT, so FPSViewmodel re-points the single
		-- mount joint there rather than at a limb.
		--
		-- Where it sits while CARRIED rather than held, through the Grenade's stow mechanism --
		-- but at HALF SIZE, which no other item needs. At true scale the item is 2.03 x 2.47 x
		-- 1.89, bigger than the whole LowerTorso, and the tightest offset clearing the body is
		-- x 1.75 -- hanging 2.85 studs off the centreline, most of a character-width of hardware
		-- on one hip, through which the leg swings. StowScale shrinks the CARRIED copy only;
		-- what you hold is still full size, and the held grip is untouched by it.
		StowAttachment = "WaistCenterAttachment",
		StowScale = 0.5,
		-- MEASURED on a dressed BaseRig at the 0.5 scale, in the WaistCenterAttachment frame --
		-- every clearance below came off a geometry probe, not off arithmetic. The first pass
		-- got y's reasoning a sign out (predicted the item's top at -0.072 when it is +0.072)
		-- and buried the turret 0.058 into LowerTorso. Reading the source would not have caught
		-- it; dressing a rig and measuring did.
		--
		--   rot      TWO axes had to be pinned, and only fixing the first is what made this wrong
		--            three times. The BORE runs along the item's -Y (measured off the bullets'
		--            long axis) and the item's UP runs along its -Z (measured by matching named
		--            parts against PlacedTurret, which is authored standing upright). Pinning
		--            bore -> -Z alone leaves a free roll about the barrel, and the roll it
		--            happened to land on put the turret on its head.
		--
		--            Bore forward AND upright determines the rotation completely -- there is
		--            exactly one -- and it reduces to a single quarter turn about X:
		--              Rz(180) * Ry(180) * Rx(-90)  ==  Rx(180) * Rx(-90)  ==  Rx(90)
		--            Do not "simplify" it back to a yaw; a yaw preserves Y and so can never aim
		--            a -Y bore anywhere but at the floor.
		--   x = 1.56   Outward reach. Two things push it out: standing the turret upright presents
		--            its 0.579 face to the body rather than 0.438, and at THIS height the item
		--            reaches UPPER torso, whose right face is 0.935 against LowerTorso's 0.850.
		--            The inner face lands at 0.981, clearing the ribs by 0.046.
		--   y = -0.30  Hip height, and NOTE THE SIGN: y is negative here, so a LARGER magnitude
		--            sits LOWER. Raising means moving toward zero.
		--
		--            Top sits at 0.247, inside UpperTorso's band (0.115..2.310), which is what
		--            makes 0.935 rather than 0.850 the binding face and why x is 1.56 rather than
		--            ~1.43. The three tiers, since moving y silently changes which applies:
		--              y < -0.533  clears both torso halves; only the leg's 0.792 binds, x ~1.37
		--              y < -0.432  clears UpperTorso; LowerTorso's 0.850 binds,        x ~1.43
		--              y > -0.432  reaches the ribs; UpperTorso's 0.935 binds,         x ~1.51
		--
		--            Note y did NOT survive the last two rotations unchanged and should not be
		--            expected to: the item's up/down half-extents are asymmetric (0.547/0.395)
		--            and swap on a bore flip, while StowOffset positions the ROOT rather than the
		--            bounding box, so holding a constant height across a flip means moving y by
		--            the 0.152 difference.
		--   z = 0      Centred: the item spans -0.661..0.572 against the torso's -0.533..0.577.
		StowOffset = CFrame.new(1.56, -0.30, 0) * CFrame.Angles(math.pi / 2, 0, 0),
		Animations = {
			Idle = "rbxassetid://83782750400408",
			Equip = "rbxassetid://139975595054835",
			Use = "rbxassetid://105643837105732",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://99969723893554",
			Equip = "rbxassetid://123445534550467",
			Use = "rbxassetid://114294176851405",
		},
	},
	ArtilleryShell = {
		Delivery = "Projectile",
		BulletAsset = "VFX/TurfBullet",
		-- Halved from 300 on 2026-08-10. Range goes as v^2, so this is a QUARTER of the reach,
		-- not a half -- see the measured figures below.
		ProjectileSpeed = 150,
		-- FULL gravity, and this is the key the whole weapon turns on. The barrel is fixed at
		-- 35.84 degrees of elevation and only traverses, so the shell is LOBBED -- and the
		-- rifle's 0.0875 scale would carry it 4,975 studs, well past Range, where it would
		-- expire in the air and never blast at all. MEASURED by marching the real trajectory
		-- off the real muzzle frame rather than from the flat-launch formula, which does not
		-- account for the muzzle sitting 23 studs up:
		--
		--   speed 300   465.6 studs   1.91 s   apex 101.7      (before the 2026-08-10 halving)
		--   speed 150   134.8 studs   1.11 s   apex  42.7      (now)
		--
		-- NOTE THE v^2: halving the launch speed QUARTERS the reach, it does not halve it. For
		-- half the original range, 330 studs, the speed wanted is about 212 rather than 150.
		--
		-- Range is FIXED either way and the gunner picks only the BEARING, which is what a
		-- fixed-elevation gun is. Elevation control would be a second axis on the traverse.
		-- Bearing error was 0.00 deg at every heading tried.
		ProjectileGravityScale = 1,
		ImpactBlast = {
			Payload = "Explosive",
			Damage = 110,
			MinDamage = 25,
			BlastRadius = 36,
			CarveRadius = 24,
			SelfDamage = false,
			Debris = { Scale = 2 },
		},
		Damage = 120,
		FireInterval = 3,
		Range = 1000,
		CarveRadius = 3,
	},
	Artillery = {
		DisplayName = "Artillery",
		Description = "- Emplacement Secondary",
		Kind = "Gadget",
		Effect = "PlaceStructure",
		Slot = "Secondary",
		UseCooldown = 1.04,
		UseEffectDelay = 0.2,
		Model = "Models/Weapons/Artillery",
		PlacedModel = "Models/PlacedArtillery",
		PlaceRange = 24,
		PlacedTag = "PlacedArtillery",
		-- NO PlacedScale, deliberately -- it places at the authored 15.7 x 23.6 x 23.2, about six
		-- characters tall. It carried 0.35 until 2026-08-10, on the reasoning that the authored
		-- size was "unplaceable"; that was wrong for a cannon you climb into and man, where the
		-- size IS the point. applyScale no-ops on an absent key, so omitting it is the whole
		-- change. Do not restore the 0.35 without re-checking the seat height, which scales
		-- with it.
		-- The gunner's seat. SeatAttachment names an Attachment on the PLACED model, and the
		-- body is pivoted to its WorldCFrame -- which for a Model-parented attachment resolves
		-- as pivot * CFrame (measured), so it follows the placement.
		SeatAttachment = "SeatingPlace",
		-- Degrees per second the barrel swings toward where the gunner is looking. The turret
		-- tracks at 240, which is right for something that snaps onto a target it has spotted;
		-- 90 is two seconds for a full 180 and reads as heavy machinery you commit to aiming.
		-- This is the AUTHORITATIVE traverse and is not the same number as the client's
		-- interpolation, which smooths between packets and is cosmetic.
		AimSpeed = 90,
		-- How hard the traverse SETTLES onto the aim, as the k in a frame-rate-independent
		-- 1 - e^(-dt*k) ease applied inside the AimSpeed cap. The cap still owns the far half of
		-- a turn -- a 180 still costs its two seconds -- and this only takes over inside roughly
		-- AimSpeed/AimSettle degrees of the target, about 11 degrees at these numbers. That last
		-- stretch is the whole difference between a barrel that glides onto the aim and one that
		-- runs at full speed into the final frame and stops dead.
		--
		-- LOWER drags more. The drag itself comes from the camera, which follows the mouse while
		-- the gun follows the camera; this only shapes the arrival. Omit the key and the traverse
		-- is the bare clamped rate it was before.
		AimSettle = 8,
		AimBroadcastRate = 12,
		ShellWeapon = "ArtilleryShell",
		ShellReloadTime = 3,
		FireAnimation = "rbxassetid://139965566598812",
		TurretYawOffset = math.pi,
		ArtilleryHealth = 400,
		DamageFilter = { "Explosive" },
		SeatPromptText = "Man the cannon",
		SeatPromptExitText = "Dismount",
		SeatPromptHold = 0.5,
		SeatPromptRange = 22,
		SeatAnimation = "rbxassetid://73603743489733",
		-- Carried at half size on the hip, for the same reason as the turret: the held model is
		-- 1.75 x 2.40 x 3.05 and a full-size cannon on a belt is absurd. Measured on BaseRig at
		-- the 0.5 scale, in the WaistCenterAttachment frame:
		--
		--   rot      180 deg YAW, which here is about the BARREL rather than clearance: the long
		--            axis is z (1.53 at half scale) and unyawed it points FORWARD, spearing out
		--            of the character's chest. The yaw swings it behind instead.
		--   x = 1.27   Inner face at 0.8325. The leg's 0.792 binds, not the torso's 0.850, and
		--            only because y drops the item clear of the torso entirely -- see below.
		--   y = -0.35  Top sits at -0.079, under LowerTorso's underside (0.014) by 0.093, so
		--            neither torso half is in the item's band. Raise it and the torso binds and
		--            x has to grow with it.
		--   z = -0.45  Centres the 1.53-long barrel on the hip rather than letting it all hang
		--            off the back: spans -0.761..0.766 against the torso's -0.533..0.577.
		StowAttachment = "WaistCenterAttachment",
		StowScale = 0.5,
		StowOffset = CFrame.new(1.27, -0.35, -0.45) * CFrame.Angles(0, math.pi, 0),
		-- ONE model at the VIEWMODEL scale, following the sword: first person wins, and the
		-- character's cannon is 17.5% smaller than authored (k = 0.82518, measured part-by-part
		-- against Stand at 0.000 deg rotation delta). Unlike the turret, whose two copies were
		-- byte-identical, this one genuinely had to give something up.
		--
		-- BOTH grip frames are carried on each side, and neither could be folded. The two copies
		-- place the invisible Handle root differently inside the assembly, so GripC1 carries that
		-- change of root (offsetVm * offsetR15:Inverse(), holding Stand invariant) -- and it
		-- CANNOT be folded into GripOffset the way the build hammer's was, because the character
		-- clips pose the Handle, so Transform is never identity and the two frames do not
		-- commute. Verified exact to 0.000002 studs in grip-attachment space on a dressed rig.
		--
		-- Uploaded to the place's own group (5837437), each verified loading -- a creator
		-- mismatch uploads fine and then fails SILENTLY with Length stuck at 0.
		Animations = {
			Idle = "rbxassetid://115639793349285",
			Equip = "rbxassetid://100099698728188",
			Use = "rbxassetid://107971466233209",
		},
		ViewmodelAnimations = {
			Idle = "rbxassetid://101961125042392",
			Equip = "rbxassetid://107576109921013",
			Use = "rbxassetid://130244647010186",
		},
	},
}
