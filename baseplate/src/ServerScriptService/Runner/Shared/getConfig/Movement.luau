return {
	MaxGroundSpeed = 24, GroundAccel = 10, AirAccel = 12, AirSpeedCap = 4, Friction = 6, StopSpeed = 10,
	JumpVelocity = 42, SprintMultiplier = 1.6, AirGravityScale = 0.55,
	DoubleJumpVelocity = 36, MaxAirJumps = 1,

	SlideBoost = 1.35, SlideMinSpeed = 20, SlideDuration = 0.9, SlideFriction = 0.8, SlideEndSpeed = 8, SlideJumpVelocity = 50,

	AirDashSpeed = 52, AirDashCooldown = 1, AirDashFallCancel = 0.6,

	MoveForce = 60000, ColliderSize = Vector3.new(3.8942453861236572, 6.376707553863525, 2.212198495864868),
	SPAWN = Vector3.new(0, 8, 0), FALL_Y = -50,
	HoverMargin = 1, HoverStiffness = 400, HoverDamping = 40, RayLength = 20, MaxSlopeNormalY = 0.4, WallSkin = 0.5,

	EyeInset = 0.3, SlideCamDip = -2.5, CamLerpSpeed = 12, CamSensitivity = 0.006, CamSendRate = 1 / 30, CamSmoothing = 200, CamSnapDistance = 8,
	TouchLookSensitivity = 1.5,
	FieldOfView = 70,

	AdsFovOffset = -16,

	AirBoostFovImpulse = 90, AirBoostFovStiffness = 90, AirBoostFovDamping = 12,
	AirBoostWindCount = 24, AirBoostWindLife = 0.45, AirBoostWindSpeed = 110,
	AirBoostWindRadius = 6, AirBoostWindStart = 22, AirBoostWindLength = 12,
	AirBoostWindThickness = 0.12, AirBoostWindColor = Color3.fromRGB(235, 245, 255),

	MountCamDistance = 30, MountCamHeight = 12,
	MountCamPitchMin = math.rad(-25), MountCamPitchMax = math.rad(50),
	MountCamCollisionPad = 1.5,

	TorsoPitchMaxUp = math.rad(60), TorsoPitchMaxDown = math.rad(45),
	TorsoPitchWaistShare = 0.6, TorsoPitchNeckShare = 0.4, TorsoPitchLerpSpeed = 14,

	DefaultIdleAnim = "rbxassetid://507766666", DefaultRunAnim = "rbxassetid://507767714",
	RunAnimSpeed = 3, AnimFadeTime = 0.15,
}