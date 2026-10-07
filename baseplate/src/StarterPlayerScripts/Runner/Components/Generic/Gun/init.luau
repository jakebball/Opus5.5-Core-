local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local Gun = {}
Gun.__index = Gun
Gun.Tag = "Gun"

Gun.combatants = nil
Gun.canDamage = nil

const FIRE_ACTION = "Fire"
const RELOAD_ACTION = "Reload"
const DEFAULT_FIRE_INTERVAL = 0.12
const RECOIL_BACK = 0.1125
const RECOIL_UP = 0.03
const RECOIL_ROLL = 0.0075
const CAMERA_KICK_PITCH = 0.6
const CAMERA_KICK_YAW = 0.23
const CAMERA_KICK_ROLL = 0.33
const CAMERA_KICK_PUNCH = 1.65

const BULLET_FOLDER = "ClientBulletFX"
const BULLET_SPEED = 300
const HITSCAN_TRACER_SPEED = 800
const ROUND_MAX_LIFETIME = 8
const BULLET_NOSE_ROT = CFrame.Angles(0, math.pi, 0)
const BULLET_SPIN = math.pi * 12
const BULLET_TRANSPARENCY = 0

-- A round that survives its own impact: how hard it comes off the surface it struck, how much
-- downward it is given so it settles rather than sailing, and how fast it tumbles while it falls.
const DROP_KICK_SPEED = 3
const DROP_FALL_SPEED = 2
const DROP_TUMBLE_SPEED = 14

const REFLECT_COLOR = Color3.fromRGB(255, 25, 25)
const REFLECT_TRAIL_LIFETIME = 2

const BULLET_MAX_RANGE = 1000
const BULLET_ASSET = "VFX/Bullet"

const MUZZLE_LIGHT_FADE = 0.1
const MUZZLE_LIGHT_BRIGHTNESS = 8
const MUZZLE_LIGHT_RANGE = 14
const MUZZLE_LIGHT_FORWARD = 1
const MUZZLE_LIGHT_COLOR = Color3.fromRGB(255, 140, 40)

const WEAPON_SOUNDS_ROOT = "Sounds/Weapons"
const DEFAULT_WEAPON = "Default"
const RELOAD_ANIMATION = "Reload"
const RELOAD_EMPTY_ANIMATION = "ReloadEmpty"
const DEFAULT_RELOAD_TIME = 1.5
const HITBOX_TAG = "Hitbox"

local effects = {}

for _, effectModule in script.GunEffects:GetChildren() do
	if effectModule:IsA("ModuleScript") then
		effects[effectModule.Name] = require(effectModule)
	end
end

local function weaponEntry(weaponName)
	local weapons = Gun.getConfig().Weapons
	if not weapons then return nil end
	return (weaponName and weapons[weaponName]) or weapons.Default
end

local function deliveryOf(weaponName)
	local entry = weaponEntry(weaponName)
	return (entry and entry.Delivery) or "Hitscan"
end

local function isProjectile(weaponName)
	local delivery = deliveryOf(weaponName)
	return delivery == "Projectile" or delivery == "Rocket"
end

local function isRocket(weaponName)
	return deliveryOf(weaponName) == "Rocket"
end

local function speedFor(weaponName)
	local entry = weaponEntry(weaponName)
	if not isProjectile(weaponName) then
		return math.max((entry and entry.TracerSpeed) or HITSCAN_TRACER_SPEED, 1)
	end
	local combat = Gun.getConfig().Combat
	local speed = (entry and entry.ProjectileSpeed) or (combat and combat.ProjectileSpeed) or BULLET_SPEED
	return math.max(speed, 1)
end

local function gravityFor(weaponName)
	if isRocket(weaponName) then return 0 end
	if not isProjectile(weaponName) then return 0 end
	local entry = weaponEntry(weaponName)
	local combat = Gun.getConfig().Combat
	local scale = (entry and entry.ProjectileGravityScale) or (combat and combat.ProjectileGravityScale) or 0
	return workspace.Gravity * math.max(scale, 0)
end

local function accelerationFor(weaponName)
	if not isRocket(weaponName) then return nil end
	local entry = weaponEntry(weaponName)
	local combat = Gun.getConfig().Combat
	local acceleration = (entry and entry.RocketAcceleration)
		or (combat and combat.RocketAcceleration) or 0
	return math.max(acceleration, 0)
end

local function maxSpeedFor(weaponName)
	if not isRocket(weaponName) then return nil end
	local entry = weaponEntry(weaponName)
	local maxSpeed = entry and entry.RocketMaxSpeed
	return if maxSpeed and maxSpeed > 0 then maxSpeed else nil
end

local function weaponSound(weaponName, soundName)
	if not weaponName then return nil end
	return Gun.Assets.Get(WEAPON_SOUNDS_ROOT .. "/" .. weaponName .. "/" .. soundName)
end

local function wornWeaponModel(shooter, weaponName)
	local rig
	if shooter and shooter:IsA("Player") then
		local bodies = workspace:FindFirstChild("MovementBodies")
		rig = bodies and bodies:FindFirstChild(shooter.Name .. "_Avatar")
	else
		rig = shooter
	end
	if not rig then return nil end

	local item = rig:FindFirstChild(weaponName)
	if item and item:GetAttribute(Gun.GearDressing.WornAttribute) then
		return item
	end
	return nil
end

local bulletTemplates = {}
local defaultTemplate = nil

local function templateFor(assetPath)
	local cached = bulletTemplates[assetPath]
	if cached ~= nil then return cached end

	local template = Gun.Assets.Get(assetPath)
	if not template then
		warn("[Gun] Bullet asset missing: " .. tostring(assetPath))
		bulletTemplates[assetPath] = false
		return false
	end

	local fadeout = 0
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("Trail") then
			fadeout = math.max(fadeout, descendant.Lifetime)
		end
	end

	-- A round that flickers instead of sitting at one transparency, driven off the ASSET rather than
	-- the weapon: NoseRotation and SpinRate are already read here the same way, and how a tracer
	-- looks belongs to the tracer. No FlickerPeriod attribute means the old constant-transparency
	-- behaviour, so every shipped bullet is untouched.
	local entry = {
		template = template,
		fadeout = fadeout,
		nose = template:GetAttribute("NoseRotation") or BULLET_NOSE_ROT,
		spin = template:GetAttribute("SpinRate") or BULLET_SPIN,
		-- SpinAxis = "Up" swaps the roll about the flight path for a yaw about world up, and drops
		-- the nose with it: a round that spins FLAT has no reason to point where it is going.
		flatSpin = template:GetAttribute("SpinAxis") == "Up",
		-- ImpactDrop = seconds. A round that declares it is not retired when it lands -- it unanchors
		-- where it hit, falls, and is destroyed after that long. Absent means the old behaviour, so
		-- every other round still blinks out on contact.
		dropSeconds = template:GetAttribute("ImpactDrop"),
		-- ExpandTo = final multiple of the authored size, reached over ExpandSeconds and then held.
		-- Absent means a round that never changes size, so every other round is untouched.
		expandTo = template:GetAttribute("ExpandTo"),
		expandSeconds = template:GetAttribute("ExpandSeconds") or 0.2,
		flickerPeriod = template:GetAttribute("FlickerPeriod"),
		flickerMin = template:GetAttribute("FlickerMin") or BULLET_TRANSPARENCY,
		flickerMax = template:GetAttribute("FlickerMax") or 0.7,
	}
	bulletTemplates[assetPath] = entry
	return entry
end

local function bulletEntryFor(weaponName)
	local entry = weaponEntry(weaponName)
	local assetPath = entry and entry.BulletAsset
	-- BulletAsset = false is an explicit "no round in flight". Without it a melee weapon falls
	-- through to defaultTemplate and fires the grey mesh BULLET out of a stick, which is most of why
	-- the batons read as guns. spawnBullet already bails on a nil template.
	if assetPath == false then return nil end
	if assetPath then
		local resolved = templateFor(assetPath)
		if resolved then return resolved end
	end
	return defaultTemplate
end

-- Each entry is { Mount = <part name>, Scale = <number> } and matches EVERY part in the weapon
-- model with that name, so a weapon with two side pods declares one entry rather than two.
local function extraRoundsFor(weaponName)
	local entry = weaponEntry(weaponName)
	local extras = entry and entry.ExtraRounds
	return if type(extras) == "table" and #extras > 0 then extras else nil
end

local function bulletFolder()
	local existing = workspace:FindFirstChild(BULLET_FOLDER)
	if existing then return existing end
	local created = Instance.new("Folder")
	created.Name = BULLET_FOLDER
	created.Parent = workspace
	return created
end

local function setRoundEffectsEnabled(bullet, enabled)
	for _, descendant in bullet:GetDescendants() do
		if descendant:IsA("Trail") or descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		end
	end
end

local function tintBullet(bullet, color, trailLifetime)
	bullet.Color = color
	bullet.Material = Enum.Material.Neon
	for _, descendant in bullet:GetDescendants() do
		if descendant:IsA("Trail") then
			descendant.Color = ColorSequence.new(color)
			if trailLifetime then
				descendant.Lifetime = trailLifetime
			end
		elseif descendant:IsA("Beam") then
			descendant.Color = ColorSequence.new(color)
		elseif descendant:IsA("BasePart") then
			descendant.Color = color
			descendant.Material = Enum.Material.Neon
		end
	end
end

local function localBodyParts()
	local parts = {}
	local bodies = workspace:FindFirstChild("MovementBodies")

	if bodies then
		for _, suffix in { "_Body", "_Avatar" } do
			local part = bodies:FindFirstChild(localPlayer.Name .. suffix)
			if part then
				table.insert(parts, part)
			end
		end
	end

	if #parts == 0 and localPlayer.Character then
		table.insert(parts, localPlayer.Character)
	end

	return parts
end

local function visualExclusions()
	local exclusions = { bulletFolder() }
	for _, part in localBodyParts() do
		table.insert(exclusions, part)
	end
	return exclusions
end

local function newBullet(entry)
	local bullet = entry.template:Clone()
	RunService:SetPredictionMode(bullet, Enum.PredictionMode.Off)
	return bullet
end

-- A round can be more than one part. spawnBullet only ever writes the ROOT's CFrame and parents the
-- clone afterwards, so a joint is still inert when the root moves and a child BasePart would sit at
-- the template origin -- the same ordering trap that made VFX/SonicRing four Beams rather than four
-- welded segments. The child's rigid offset is captured before the root moves and re-applied on
-- every step instead: no joints, no assembly, nothing to get wrong about order.
local function attachedPartsOf(bullet)
	local rootInverse = bullet.CFrame:Inverse()
	local attached = nil
	for _, descendant in bullet:GetDescendants() do
		if descendant:IsA("BasePart") then
			attached = attached or {}
			table.insert(attached, {
				part = descendant,
				offset = rootInverse * descendant.CFrame,
				size = descendant.Size,
			})
		end
	end
	return attached
end

-- Takes either a templateFor entry or a live round -- both carry nose, spin and flatSpin.
local function poseRound(source, position, direction, elapsed)
	if source.flatSpin then
		return CFrame.new(position) * CFrame.Angles(0, elapsed * source.spin, 0)
	end
	return CFrame.lookAt(position, position + direction) * source.nose
		* CFrame.Angles(0, 0, elapsed * source.spin)
end

-- A growing round grows as an ASSEMBLY: each child's rigid offset is a displacement in the
-- root's frame, so it scales with the size or the parts pull apart from their own mounts.
local function poseAttachedParts(attached, rootCFrame, scale)
	if not attached then return end
	for _, entry in attached do
		if scale then
			entry.part.Size = entry.size * scale
			entry.part.CFrame = rootCFrame * (entry.offset + entry.offset.Position * (scale - 1))
		else
			entry.part.CFrame = rootCFrame * entry.offset
		end
	end
end

-- Scaling a round's root Size does NOT scale a ring drawn BETWEEN attachments: an Attachment's
-- Position is in its parent's local space and is unaffected by the part's Size, and a Beam's
-- CurveSize and Width are its own. VFX/SonicRing is four Beams around four attachments, so
-- without this a 75% ring is a 100% ring around a smaller core. Authored values are captured
-- once so repeated scaling cannot compound.
local function scalableGeometryOf(bullet)
	local items = nil
	for _, descendant in bullet:GetDescendants() do
		if descendant:IsA("Attachment") then
			items = items or {}
			table.insert(items, { attachment = descendant, position = descendant.Position })
		elseif descendant:IsA("Beam") then
			items = items or {}
			table.insert(items, {
				beam = descendant,
				curve0 = descendant.CurveSize0,
				curve1 = descendant.CurveSize1,
				width0 = descendant.Width0,
				width1 = descendant.Width1,
			})
		end
	end
	return items
end

local function scaleGeometry(items, scale)
	if not items then return end
	for _, item in items do
		if item.attachment then
			item.attachment.Position = item.position * scale
		else
			item.beam.CurveSize0 = item.curve0 * scale
			item.beam.CurveSize1 = item.curve1 * scale
			item.beam.Width0 = item.width0 * scale
			item.beam.Width1 = item.width1 * scale
		end
	end
end

local liveBullets = {}
local marcherBound = false

local function retireBullet(round)
	liveBullets[round] = nil
	local part = round.part
	if not part then return end
	-- Cancel first: a live infinite tween would keep writing Transparency and the round would never
	-- visually retire.
	if round.flickerTween then
		round.flickerTween:Cancel()
		round.flickerTween = nil
	end
	part.Transparency = 1
	if round.attached then
		for _, entry in round.attached do
			entry.part.Transparency = 1
		end
	end
	setRoundEffectsEnabled(part, false)
	-- Not folded into setRoundEffectsEnabled, because dropRound calls that too and a LANDED round has
	-- to keep its highlight. A retired one must not leave a silhouette drawn through the world for the
	-- length of its fadeout -- the transparency write above already hides it in practice, but that is
	-- a rendering quirk rather than a guarantee.
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("Highlight") then
			descendant.Enabled = false
		end
	end
	task.delay(round.fadeout, function()
		part:Destroy()
	end)
end

-- The alternative to retiring: the round becomes debris instead of blinking out. It is already a
-- purely local effect -- spawned client-side, prediction off, in ClientBulletFX -- so unanchoring it
-- replicates nothing and cannot disagree with the server's hit resolution, which resolved on the
-- trigger frame either way.
local function dropRound(round, result)
	liveBullets[round] = nil
	local part = round.part
	if not part then return end
	if round.flickerTween then
		round.flickerTween:Cancel()
		round.flickerTween = nil
	end
	setRoundEffectsEnabled(part, false)

	-- Seated just clear of the surface along its normal, keeping the round's own orientation. Landing
	-- ON the surface means unanchoring inside the rig it just hit, which ejects it.
	local clearance = part.Size.Magnitude * 0.5
	part.CFrame = CFrame.new(result.Position + result.Normal * clearance)
		* (part.CFrame - part.CFrame.Position)

	-- Welding HERE is safe where welding in the template is not: the parts are already parented and
	-- already in their correct relative places, so a WeldConstraint locks the offset that is wanted
	-- rather than the template origin. See attachedPartsOf.
	if round.attached then
		for _, entry in round.attached do
			entry.part.CanCollide = false
			entry.part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = entry.part
			weld.Parent = part
		end
	end

	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = false
	part.AssemblyLinearVelocity = result.Normal * DROP_KICK_SPEED
		- Vector3.yAxis * DROP_FALL_SPEED
	part.AssemblyAngularVelocity = Vector3.new(
		math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * DROP_TUMBLE_SPEED

	task.delay(round.dropSeconds, function()
		part:Destroy()
	end)
end

local function roundPositionAt(round, elapsed)
	if round.acceleration then
		return Gun.Ballistics.rocketPositionAt(
			round.origin, round.velocity, round.acceleration, round.maxSpeed, elapsed
		)
	end
	return Gun.Ballistics.positionAt(round.origin, round.velocity, round.gravity, elapsed)
end

local function stepBullet(round)
	local part = round.part
	if not part or not part.Parent then
		liveBullets[round] = nil
		return
	end

	local elapsed = os.clock() - round.clockOrigin
	local from = roundPositionAt(round, round.lastElapsed)
	local head = roundPositionAt(round, elapsed)
	round.lastElapsed = elapsed

	local segment = head - from
	local travelled = segment.Magnitude
	if travelled < 0.0001 then return end

	local result = workspace:Raycast(from, segment, round.params)
	local endpoint = result and result.Position or head

	local scale = round.roundScale
	if round.expandTo then
		local progress = math.clamp(elapsed / round.expandSeconds, 0, 1)
		-- Quadratic ease-out: a round that opens slows into its full spread rather than stopping
		-- dead. The cinch's cubic was tried first and front-loads too hard -- 60% of the spread
		-- landed inside three frames, so what the player saw was a round that spawned open.
		scale = round.roundScale * (1 + (round.expandTo - 1) * (1 - (1 - progress) ^ 2))
		part.Size = round.baseSize * scale
		scaleGeometry(round.geometry, scale)
	end

	part.CFrame = poseRound(round, endpoint, segment.Unit, elapsed)
	poseAttachedParts(round.attached, part.CFrame, if scale ~= 1 then scale else nil)
	round.remaining -= travelled

	if result then
		if round.dropSeconds then
			dropRound(round, result)
		else
			retireBullet(round)
		end
		return
	end

	if round.remaining <= 0 or os.clock() >= round.expiresAt then
		retireBullet(round)
	end
end

local function ensureMarcher()
	if marcherBound then return end
	marcherBound = true
	RunService.RenderStepped:Connect(function(deltaTime)
		for round in liveBullets do
			stepBullet(round)
		end
	end)
end

local function spawnBullet(origin, direction, maxRange, options)
	options = options or {}
	local template = bulletEntryFor(options.Weapon)
	if not template then return end
	local unit = direction.Magnitude > 0.0001 and direction.Unit or Vector3.zAxis

	local bullet = newBullet(template)
	local attached = attachedPartsOf(bullet)
	local baseSize = bullet.Size
	-- A round can leave the barrel at a fraction of its authored size -- the Advanced Sonic
	-- Gun's two side pods throw the same ring at 75%. The walk is skipped entirely unless the
	-- round is scaled or grows, so an ordinary round pays nothing for either.
	local roundScale = options.Scale or 1
	local geometry = if roundScale ~= 1 or template.expandTo
		then scalableGeometryOf(bullet)
		else nil
	if roundScale ~= 1 then
		bullet.Size = baseSize * roundScale
		scaleGeometry(geometry, roundScale)
	end
	bullet.CFrame = poseRound(template, origin, unit, 0)
	poseAttachedParts(attached, bullet.CFrame, if roundScale ~= 1 then roundScale else nil)
	if options.Color then
		tintBullet(bullet, options.Color, options.TrailLifetime)
	end
	bullet.Transparency = BULLET_TRANSPARENCY
	bullet.Parent = bulletFolder()

	-- RepeatCount -1 with Reverses is the whole loop: one tween for the round's life, no per-frame
	-- work, and it stops when retireBullet cancels it. Mirrors the hit flicker in
	-- Concert/ShootableNPC, which is a bounded RepeatCount of the same shape.
	local flickerTween = nil
	if template.flickerPeriod and template.flickerPeriod > 0 then
		bullet.Transparency = template.flickerMin
		flickerTween = TweenService:Create(
			bullet,
			TweenInfo.new(template.flickerPeriod, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = template.flickerMax }
		)
		flickerTween:Play()
	end

	local spawnTime = options.SpawnTime or workspace:GetServerTimeNow()
	local clockOrigin = os.clock() - math.max(workspace:GetServerTimeNow() - spawnTime, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = visualExclusions()

	local round = {
		part = bullet,
		attached = attached,
		origin = origin,
		velocity = unit * (options.Speed or BULLET_SPEED),
		gravity = options.Gravity or 0,
		acceleration = accelerationFor(options.Weapon),
		maxSpeed = maxSpeedFor(options.Weapon),
		nose = template.nose,
		spin = template.spin,
		flatSpin = template.flatSpin,
		dropSeconds = template.dropSeconds,
		baseSize = baseSize,
		roundScale = roundScale,
		geometry = geometry,
		expandTo = template.expandTo,
		expandSeconds = template.expandSeconds,
		clockOrigin = clockOrigin,
		lastElapsed = 0,
		remaining = maxRange or BULLET_MAX_RANGE,
		params = params,
		fadeout = options.TrailLifetime or template.fadeout,
		expiresAt = os.clock() + ROUND_MAX_LIFETIME,
		flickerTween = flickerTween,
	}
	liveBullets[round] = true
	ensureMarcher()
	return round
end

const DEFLECT_DODGE_RADIUS = 6
const DEFLECT_DODGE_OFFSET = 1.75

local function dodgeCamera(point, lineUnit)
	local cameraCF = workspace.CurrentCamera.CFrame
	if (point - cameraCF.Position).Magnitude > DEFLECT_DODGE_RADIUS then return point end
	local lateral = cameraCF.RightVector - lineUnit * cameraCF.RightVector:Dot(lineUnit)
	if lateral.Magnitude < 0.001 then
		lateral = cameraCF.UpVector - lineUnit * cameraCF.UpVector:Dot(lineUnit)
	end
	return point + lateral.Unit * DEFLECT_DODGE_OFFSET
end

function Gun.Start()
	setmetatable(Gun, { __index = Gun.BaseClass })
	Gun.InputManager.setup(Gun.GoodSignal)
	Gun.InputManager.bindAction(FIRE_ACTION, { Enum.UserInputType.MouseButton1 })
	Gun.InputManager.bindAction(RELOAD_ACTION, { Enum.KeyCode.R })

	defaultTemplate = templateFor(BULLET_ASSET) or nil

	task.spawn(function()
		Gun.fireRemote = Gun.BaseClass.sharedRemote("Gun", "Fire")
		local bulletRemote = Gun.BaseClass.sharedRemote("Gun", "Bullet")
		if not bulletRemote then
			warn("[Gun] Bullet remote never replicated")
			return
		end
		bulletRemote.OnClientEvent:Connect(function(shooter, origin, direction, weaponName, spawnTime)
			if shooter == localPlayer then return end
			spawnBullet(origin, direction, nil, {
				Weapon = weaponName,
				Speed = speedFor(weaponName),
				Gravity = gravityFor(weaponName),
				SpawnTime = spawnTime,
			})
			Gun.WorldSFX.playAt(weaponSound(weaponName, "Shoot"), origin)
			local effect = effects[weaponName]
			if effect and effect.FireWorld then
				effect.FireWorld(wornWeaponModel(shooter, weaponName))
			end
		end)

		local deflectRemote = Gun.BaseClass.sharedRemote("Gun", "Deflect")
		if deflectRemote then
			deflectRemote.OnClientEvent:Connect(function(startPoint, endPoint)
				local offset = endPoint - startPoint
				if offset.Magnitude < 0.1 then return end
				local lineUnit = offset.Unit
				startPoint = dodgeCamera(startPoint, lineUnit)
				endPoint = dodgeCamera(endPoint, lineUnit)
				offset = endPoint - startPoint
				local distance = offset.Magnitude
				if distance < 0.1 then return end
				spawnBullet(startPoint, offset.Unit, distance, {
					Color = REFLECT_COLOR,
					TrailLifetime = REFLECT_TRAIL_LIFETIME,
				})
			end)
		else
			warn("[Gun] Deflect remote never replicated")
		end
	end)
	Gun.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(Gun.Tag)
		end
	end)
end

function Gun.new(instance)
	local self = setmetatable(Gun.BaseClass.new(instance), Gun)
	if instance ~= localPlayer then return self end

	self.viewmodel = nil
	self.nextShotAt = 0
	self.weaponName = nil
	self.reloadUntil = 0
	self.stunnedUntil = 0
	self.ammo = nil

	self.ammoChanged = Gun.GoodSignal.new()
	self.fired = Gun.GoodSignal.new()
	self.trove:Add(self.fired, "DisconnectAll")
	self.trove:Add(self.ammoChanged, "DisconnectAll")

	self.reloadStarted = Gun.GoodSignal.new()
	self.reloadEnded = Gun.GoodSignal.new()
	self.trove:Add(self.reloadStarted, "DisconnectAll")
	self.trove:Add(self.reloadEnded, "DisconnectAll")

	self.stunned = Gun.GoodSignal.new()
	self.trove:Add(self.stunned, "DisconnectAll")

	self:onRemoteEvent("Stun", function(duration, sourceItemId, soundName)
		if type(duration) ~= "number" or duration <= 0 then return end
		local endsAt = os.clock() + duration
		if endsAt <= self.stunnedUntil then return end
		self.stunnedUntil = endsAt
		self.stunned:Fire(duration)

		if sourceItemId and soundName then
			Gun.LocalSFX.play(weaponSound(sourceItemId, soundName))
		end
	end)

	self:onRemoteEvent("Ammo", function(weaponId, loaded, reserve, magazineSize, reloading, remaining)
		self:_applyAmmo(weaponId, loaded, reserve, magazineSize, reloading, remaining)
	end)
	self:sendNetworkEvent("AmmoSync")

	self.trove:AddPromise(Gun.EntityStore.promiseGetComponent(localPlayer, "FPSViewmodel"):andThen(function(viewmodel)
		self.viewmodel = viewmodel
		viewmodel:setAdsGate(function()
			return self:canAds() and not self:isReloading()
		end)
		-- setWeapon can land before this promise resolves, so re-run the mount here rather than
		-- assuming the viewmodel exists by the time a weapon is equipped.
		self:_mountViewmodelWeapon()
	end))

	self.trove:Add(Gun.InputManager.onActionBegan(RELOAD_ACTION, function()
		self:_reload()
	end), "Disconnect")

	self.trove:Add(RunService.Heartbeat:Connect(function()
		self:_stepFire()
	end))

	return self
end

function Gun:setWeapon(weaponName)
	if weaponName == self.weaponName then return end

	self.weaponName = weaponName
	self:_mountViewmodelWeapon()
	if self.viewmodel and not self:canAds() then
		self.viewmodel:setAds(false)
	end
	if self.reloadUntil > 0 then
		self.reloadEnded:Fire()
	end
	self.reloadUntil = 0
	self.ammo = nil
	self.ammoChanged:Fire(nil)
end

-- Put the weapon in the player's hands. The boilerplate tracked WHICH weapon was firing but
-- never mounted one: nothing in this project called FPSViewmodel:setWeapon, so the rig held
-- nothing and every shot was invisible. A weapon with no `Model` key still fires exactly as
-- before -- the whole fire path nil-guards the viewmodel -- it just stays empty-handed.
--
-- Enable BEFORE mounting: setEnabled(false) unparents the rig, and FPSViewmodel:_track refuses to
-- load a clip onto a rig that is not a descendant of game, so mounting first would silently
-- produce a weapon with no animation tracks.
function Gun:_mountViewmodelWeapon()
	local viewmodel = self.viewmodel
	if not viewmodel then return end

	local entry = self.weaponName and self:_weaponConfig()
	local template = entry and entry.Model and Gun.Assets.Get(entry.Model)
	if not template then
		viewmodel:clearWeapon()
		viewmodel:setEnabled(false)
		return
	end

	viewmodel:setEnabled(true)
	viewmodel:setWeapon(template, entry.ViewmodelAnimations)
end

function Gun:_weaponConfig()
	local weapons = Gun.getConfig().Weapons
	if not weapons then return nil end
	return weapons[self.weaponName] or weapons[DEFAULT_WEAPON]
end

function Gun:canAds()
	local entry = self:_weaponConfig()
	return not entry or entry.CanAds ~= false
end

function Gun:_fireInterval()
	local entry = self:_weaponConfig()
	return (entry and entry.FireInterval) or DEFAULT_FIRE_INTERVAL
end

function Gun:_range()
	local entry = self:_weaponConfig()
	return (entry and entry.Range) or BULLET_MAX_RANGE
end

function Gun:_reloadTime(wasEmpty)
	local entry = self:_weaponConfig()
	if not entry then return DEFAULT_RELOAD_TIME end
	return (wasEmpty and entry.ReloadTimeEmpty) or entry.ReloadTime or DEFAULT_RELOAD_TIME
end

-- How hard the shot moves the CAMERA, as a multiplier on the four boilerplate kick constants.
-- Those constants are shared by every weapon, so a weapon that wants a softer shot scales them
-- from its own config entry rather than editing them and changing every other gun with it.
-- 1 (or an absent key) is the boilerplate feel; 0 is a dead-still camera.
--
-- This is only the camera. The viewmodel's own kick is separate and unscaled: the recoil spring
-- through FPSViewmodel:addRecoil, plus whatever the weapon's "Shoot" clip does.
-- Seconds between pulling the trigger and the round actually leaving. A weapon whose animation has
-- a wind-up -- the slingshot has to tension before it can let go -- would otherwise throw the round
-- while the band is still being drawn. Absent or 0 means fire on the trigger frame, which is every
-- other weapon.
--
-- This moves the DAMAGE too, not just the tracer. Delaying only the visual would be worse: the
-- target's hit reaction would land before the ball left the sling.
function Gun:_fireDelay()
	local entry = self:_weaponConfig()
	local delay = entry and entry.FireDelay
	return if type(delay) == "number" then delay else 0
end

function Gun:_cameraKickScale()
	local entry = self:_weaponConfig()
	local scale = entry and entry.CameraKickScale
	return if type(scale) == "number" then scale else 1
end

function Gun:_weaponSound(soundName)
	return weaponSound(self.weaponName, soundName)
end

function Gun:_effectFor()
	if not self.weaponName then return nil end
	return effects[self.weaponName]
end

function Gun:getAmmo()
	if not self.ammo then return nil end
	return self.ammo.loaded, self.ammo.reserve, self.ammo.magazineSize
end

function Gun:isReloading()
	return os.clock() < self.reloadUntil
end


function Gun:_applyAmmo(weaponId, loaded, reserve, magazineSize, reloading, remaining)
	if weaponId ~= (self.weaponName or DEFAULT_WEAPON) then return end

	if type(loaded) ~= "number" or type(magazineSize) ~= "number" then
		self.ammo = nil
	else
		self.ammo = { loaded = loaded, reserve = reserve, magazineSize = magazineSize }
	end

	if reloading and not self:isReloading() then
		local wasEmpty = loaded ~= nil and loaded <= 0
		local reloadTime = self:_reloadTime(wasEmpty)
		if type(remaining) == "number" and remaining > 0 then
			reloadTime = remaining
		end
		self.reloadUntil = os.clock() + reloadTime
		self.reloadStarted:Fire(reloadTime, wasEmpty)
	end

	if not reloading then
		if self.reloadUntil > 0 then
			self.reloadEnded:Fire()
		end
		self.reloadUntil = 0
		if self.viewmodel then
			self.viewmodel:stop(RELOAD_ANIMATION)
			self.viewmodel:stop(RELOAD_EMPTY_ANIMATION)
		end
	end

	self.ammoChanged:Fire(self:getAmmo())
end

function Gun:isStunned()
	return os.clock() < self.stunnedUntil
end

function Gun:_stepFire()
	if not self.weaponName then return end
	if self:isStunned() then return end
	if not Gun.InputManager.isActive(FIRE_ACTION) then return end
	local now = os.clock()
	if now < self.nextShotAt then return end

	if self.ammo then
		if self:isReloading() then return end
		if self.ammo.loaded <= 0 then
			self:_reload()
			return
		end
		self.ammo.loaded -= 1
		self.ammoChanged:Fire(self:getAmmo())
		if self.ammo.loaded <= 0 and self.viewmodel then
			self.viewmodel:setAds(false)
		end
	end

	self.nextShotAt = now + self:_fireInterval()
	self:_fire()
end

function Gun:_flashMuzzleLight(direction)
	-- A slingshot has no muzzle flash, and neither does a baton. Brightness 0 bails before the
	-- attachment and light are created rather than making an invisible one every shot. Absent key
	-- means the boilerplate brightness, so every other weapon is unchanged.
	local entry = self:_weaponConfig()
	local brightness = if entry and entry.MuzzleLightBrightness ~= nil
		then entry.MuzzleLightBrightness
		else MUZZLE_LIGHT_BRIGHTNESS
	if brightness <= 0 then return end

	local muzzle = self.viewmodel and self.viewmodel:getMuzzle()
	if not muzzle then return end

	local host = self.muzzleLightHost
	if not host or host.Parent ~= muzzle.Parent then
		host = muzzle.Parent:FindFirstChild("MuzzleLightPoint") or Instance.new("Attachment")
		host.Name = "MuzzleLightPoint"
		host.Parent = muzzle.Parent
		self.muzzleLightHost = host
		self.muzzleLight = nil
	end
	host.WorldPosition = muzzle.WorldPosition + direction * MUZZLE_LIGHT_FORWARD

	local light = self.muzzleLight
	if not light or light.Parent ~= host then
		light = host:FindFirstChild("MuzzleLight") or Instance.new("PointLight")
		light.Name = "MuzzleLight"
		light.Range = MUZZLE_LIGHT_RANGE
		light.Shadows = false
		light.Enabled = false
		light.Parent = host
		self.muzzleLight = light
	end

	if self.muzzleLightTween then
		self.muzzleLightTween:Cancel()
	end
	-- Written every flash rather than once at creation: the light instance is reused across weapon
	-- swaps, so a colour set at creation time would be whichever weapon happened to fire first.
	light.Color = (entry and entry.MuzzleLightColor) or MUZZLE_LIGHT_COLOR
	light.Brightness = brightness
	light.Enabled = true
	local tween = TweenService:Create(
		light,
		TweenInfo.new(MUZZLE_LIGHT_FADE, Enum.EasingStyle.Linear),
		{ Brightness = 0 }
	)
	self.muzzleLightTween = tween
	tween.Completed:Once(function()
		if self.muzzleLight == light then
			light.Enabled = false
		end
	end)
	tween:Play()
end

function Gun:_burstMuzzleDebris(origin, direction)
	local entry = self:_weaponConfig()
	local settings = entry and entry.MuzzleDebris
	if not settings then return end

	local options = table.clone(settings)
	options.Origin = origin
	options.Direction = direction
	options.Parent = bulletFolder()
	Gun.DebrisBurst.Fire(options)
end

-- Presentation fires on the trigger frame; the shot itself may not. See Gun:_fireDelay.
function Gun:_fire()
	if self.viewmodel then
		self.viewmodel:addRecoil(RECOIL_BACK, RECOIL_UP, RECOIL_ROLL)
	end

	-- A scale of 0 skips the call outright. Kick() ends with ensureBound(), so passing zeros would
	-- still bind CameraShake's RenderStepped loop on every shot just to have it unbind itself the
	-- next frame once kickAtRest() agrees there is nothing to integrate.
	local kickScale = self:_cameraKickScale()
	if kickScale > 0 then
		local lateral = math.random() * 2 - 1
		Gun.CameraShake.Kick(
			CAMERA_KICK_PITCH * kickScale,
			lateral * CAMERA_KICK_YAW * kickScale,
			lateral * CAMERA_KICK_ROLL * kickScale,
			CAMERA_KICK_PUNCH * kickScale
		)
	end

	local effect = self:_effectFor()
	if effect and self.viewmodel then
		effect.Fire(self.viewmodel)
	end
	if self.viewmodel then
		self.viewmodel:play("Shoot", { priority = Enum.AnimationPriority.Action })
	end

	local fireDelay = self:_fireDelay()
	if fireDelay <= 0 then
		self:_releaseShot()
		return
	end

	-- Bail if the weapon changed while the wind-up was running: unequipping or swapping both rewrite
	-- weaponName, so a shot cannot arrive from a gun that is no longer in hand. `nextShotAt` was
	-- already set on the trigger frame, so the fire interval is measured from the pull, not from here.
	local weaponAtTrigger = self.weaponName
	task.delay(fireDelay, function()
		if self.weaponName ~= weaponAtTrigger then return end
		self:_releaseShot()
	end)
end

-- A shot can be more than one round. Every part named by an ExtraRounds entry gets one, spawned at
-- that part's own Attachment and scaled by the entry, so a weapon with two side pods declares
-- one entry rather than two. They are presentation: the damage is still the single ray
-- _reportLocalHit casts, and they fly PARALLEL to it rather than spreading, because a spread the
-- hit resolution does not share is a lie about where the weapon is pointing.
function Gun:_spawnExtraRounds(direction, spawnTime)
	local extras = extraRoundsFor(self.weaponName)
	if not extras then return end
	local weapon = self.viewmodel and self.viewmodel:getWeapon()
	if not weapon then return end

	local descendants = weapon:GetDescendants()
	for _, extra in extras do
		for _, descendant in descendants do
			if descendant.Name == extra.Mount and descendant:IsA("BasePart") then
				local point = descendant:FindFirstChildOfClass("Attachment")
				spawnBullet(point and point.WorldPosition or descendant.Position, direction, self:_range(), {
					Weapon = self.weaponName,
					Speed = speedFor(self.weaponName),
					Gravity = gravityFor(self.weaponName),
					SpawnTime = spawnTime,
					Scale = extra.Scale,
				})
			end
		end
	end
end

-- The round leaving. Aim is read HERE rather than on the trigger frame, so a weapon with a wind-up
-- shoots where you were pointing when it let go.
function Gun:_releaseShot()
	local cameraCF = workspace.CurrentCamera.CFrame
	local origin, direction = cameraCF.Position, cameraCF.LookVector

	-- Fires here rather than in _fire so a wind-up weapon cracks when it lets go, not when the
	-- trigger is pulled. No FireDelay means the two are the same frame anyway.
	Gun.LocalSFX.play(self:_weaponSound("Shoot"))
	self:_flashMuzzleLight(direction)

	local muzzle = self.viewmodel and self.viewmodel:getMuzzle()
	if muzzle then
		self:_burstMuzzleDebris(muzzle.WorldPosition, direction)
	end
	local spawnTime = workspace:GetServerTimeNow()
	spawnBullet(muzzle and muzzle.WorldPosition or origin, direction, self:_range(), {
		Weapon = self.weaponName,
		Speed = speedFor(self.weaponName),
		Gravity = gravityFor(self.weaponName),
		SpawnTime = spawnTime,
	})
	self:_spawnExtraRounds(direction, spawnTime)
	self.fired:Fire()

	if Gun.fireRemote then
		Gun.fireRemote:FireServer(origin, direction, workspace:GetServerTimeNow())
	end

	self:_reportLocalHit(origin, direction)
end

function Gun:_damagePerShot()
	local entry = self:_weaponConfig()
	return (entry and entry.Damage) or 0
end

-- Half-angle of a melee swing, in degrees, or nil for a ray. See the server half.
function Gun:_meleeArc()
	local entry = self:_weaponConfig()
	local arc = entry and entry.MeleeArc
	return if type(arc) == "number" and arc > 0 then arc else nil
end

-- What a hit from this weapon should read as. Mirrors the server's Gun:damageKind exactly, because
-- the shooter never receives their own hit over the remote -- noteLocalHit suppresses the echo -- so
-- without this the shooter's own hits arrive with damageKind nil and fall back to the default
-- reaction. Everyone ELSE sees the right one. See features/weapons.md.
function Gun:_damageKind()
	local entry = self:_weaponConfig()
	local blast = entry and entry.ImpactBlast

	return (blast and blast.Payload) or (entry and entry.HitKind) or nil
end

function Gun:_hitboxScale()
	local combat = Gun.getConfig().Combat
	return (combat and combat.HitboxScale) or 1
end

function Gun:_localExclusions()
	return visualExclusions()
end

function Gun:_reportLocalHit(origin, direction)
	local range = self:_range()
	local exclusions = self:_localExclusions()
	local excluded = {}
	for _, instance in exclusions do
		excluded[instance] = true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	local worldResult = workspace:Raycast(origin, direction * range, params)

	local candidates = if Gun.combatants then Gun.combatants() else CollectionService:GetTagged(HITBOX_TAG)
	local blockedAt = worldResult and worldResult.Distance or range
	local function reject(candidate)
		if excluded[candidate] then return true end
		if candidate:GetAttribute("Dead") then return true end
		return Gun.canDamage ~= nil and not Gun.canDamage(localPlayer, candidate)
	end

	-- Mirrors the server: a melee weapon sweeps an arc rather than casting a ray, so the client's
	-- prediction agrees with what the server will resolve.
	local meleeArc = self:_meleeArc()
	local combatant, hitPosition
	if meleeArc then
		combatant, hitPosition = Gun.HitscanMath.sweep(origin, direction, {
			Candidates = candidates,
			Scale = self:_hitboxScale(),
			Range = range,
			CosArc = math.cos(math.rad(meleeArc) * 0.5),
			Reject = reject,
			Blocked = function(from, point)
				return (point - from).Magnitude > blockedAt
			end,
		})
	else
		combatant, hitPosition = Gun.HitscanMath.cast(origin, direction, range, {
			Candidates = candidates,
			Scale = self:_hitboxScale(),
			BlockedAt = blockedAt,
			Reject = reject,
		})
	end
	if not combatant then return end

	local hitbox = Gun.EntityStore.getComponent(combatant, HITBOX_TAG)
	if not hitbox then return end
	hitbox:noteLocalHit()
	hitbox.onHit:Fire(
		combatant,
		hitPosition,
		localPlayer,
		direction,
		self:_damagePerShot(),
		Gun.HitscanMath.isHeadshot(combatant, hitPosition),
		nil,
		self:_damageKind()
	)
end

function Gun:_reload()
	if not self.weaponName then return end
	if self:isStunned() then return end
	if not self.ammo then return end
	if self:isReloading() then return end
	if self.ammo.loaded >= self.ammo.magazineSize then return end
	if self.ammo.reserve ~= nil and self.ammo.reserve <= 0 then return end

	local wasEmpty = self.ammo.loaded <= 0
	local reloadTime = self:_reloadTime(wasEmpty)
	self.reloadUntil = os.clock() + reloadTime
	self.reloadStarted:Fire(reloadTime, wasEmpty)
	if self.viewmodel then
		self.viewmodel:setAds(false)
	end
	self:sendNetworkEvent("RequestReload")

	if self.viewmodel then
		local options = {
			priority = Enum.AnimationPriority.Action,
			duration = reloadTime,
		}
		local played = wasEmpty and self.viewmodel:play(RELOAD_EMPTY_ANIMATION, options)
		if not played then			
			self.viewmodel:play(RELOAD_ANIMATION, options)
		end
	end
	Gun.LocalSFX.play(self:_weaponSound("Reload"))
end

return Gun
