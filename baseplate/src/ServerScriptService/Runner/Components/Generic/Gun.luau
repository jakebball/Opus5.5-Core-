local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Gun = {}
Gun.__index = Gun
Gun.Tag = "Gun"

Gun.combatants = nil

Gun.absorbs = nil

const ORIGIN_SLOP = 12
const REFLECT_START_OFFSET = 3
const COOLDOWN_TOLERANCE = 0.4
const DEFAULT_FIRE_INTERVAL = 0.12
const DEFAULT_RANGE = 1000
const DEFAULT_RELOAD_TIME = 1.5
const BODY_FOLDER = "MovementBodies"
const BODY_SUFFIX = "_Body"
const AVATAR_SUFFIX = "_Avatar"
const HITBOX_TAG = "Hitbox"
const MUZZLE_NAME = "Muzzle"
const DEFAULT_WEAPON = "Default"
const DEFAULT_DELIVERY = "Hitscan"
const DEFAULT_PROJECTILE_SPEED = 300
const DEFAULT_ROCKET_ACCELERATION = 0
const PROJECTILE_TAG = "Projectile"

function Gun.Start()
	setmetatable(Gun, { __index = Gun.BaseClass })
	Gun.fireRemote = Gun.BaseClass.sharedRemote("Gun", "Fire")
	Gun.bulletRemote = Gun.BaseClass.sharedRemote("Gun", "Bullet")
	Gun.deflectRemote = Gun.BaseClass.sharedRemote("Gun", "Deflect")
	Gun.fireRemote.OnServerEvent:Connect(function(player, origin, direction, firedAt)
		local component = Gun.EntityStore.getComponent(player, Gun.Tag)
		if component then
			component:_onClientFire(origin, direction, firedAt)
		end
	end)
	Gun.Observers.observePlayer(function(player)
		player:AddTag(Gun.Tag)
	end)
end

function Gun.new(instance)
	local self = setmetatable(Gun.BaseClass.new(instance), Gun)
	self.shooter = instance
	self.lastFireAt = 0
	self.weapon = DEFAULT_WEAPON
	self.magazines = {}
	self.infiniteReserve = false
	self.reloadPending = {}
	self.reloadTokens = {}
	self.reloadEndsAt = {}
	self.stunnedUntil = 0

	self.weaponChanged = Gun.GoodSignal.new()
	self.fired = Gun.GoodSignal.new()
	self.reloadStarted = Gun.GoodSignal.new()
	self.stunned = Gun.GoodSignal.new()
	self.trove:Add(self.stunned, "DisconnectAll")
	self.trove:Add(self.weaponChanged, "DisconnectAll")
	self.trove:Add(self.fired, "DisconnectAll")
	self.trove:Add(self.reloadStarted, "DisconnectAll")

	if self:_isPlayerShooter() then
		self:registerRemote("Stun")
		self:registerRemote("Ammo")
		self:onRemoteEvent("AmmoSync", function(player)
			if player ~= self.shooter then return end
			self:_publishAmmo()
		end)
		self:onRemoteEvent("RequestReload", function(player)
			if player ~= self.shooter then return end
			if not self:reload() then
				self:_publishAmmo()
			end
		end)
	end

	return self
end

function Gun:setWeapon(weaponId)
	local resolved = weaponId or DEFAULT_WEAPON
	if resolved == self.weapon then return end

	self.weapon = resolved
	self:_publishAmmo()
	self.weaponChanged:Fire(resolved)
end

function Gun:getWeapon()
	return self.weapon
end

function Gun:setAttacker(attacker)
	self.attacker = attacker
end

function Gun:_combatants()
	if Gun.combatants then return Gun.combatants() end
	return CollectionService:GetTagged(HITBOX_TAG)
end

-- Half-angle of a melee swing, in degrees, or nil for a ray. Absent on every ranged weapon, so
-- they keep casting exactly as before.
function Gun:_meleeArc()
	local entry = self:_weaponConfig()
	local arc = entry and entry.MeleeArc
	return if type(arc) == "number" and arc > 0 then arc else nil
end

function Gun:_hitboxScale()
	local combat = Gun.getConfig().Combat
	return (combat and combat.HitboxScale) or 1
end

function Gun:_rewindStamp(firedAt)
	if not self:_isPlayerShooter() then return nil end
	local combat = Gun.getConfig().Combat
	return Gun.HitscanMath.rewindStamp(firedAt, workspace:GetServerTimeNow(), combat and combat.MaxRewind)
end

function Gun:_volumeAt(rewindStamp)
	if not rewindStamp then return nil end
	local history = Gun.EntityStore.getComponent(workspace, "PositionHistory")
	if not history then return nil end
	return function(candidate)
		return history:volumeAt(candidate, rewindStamp)
	end
end

function Gun:_weaponConfig()
	local weapons = Gun.getConfig().Weapons
	if not weapons then return nil end
	return weapons[self.weapon] or weapons[DEFAULT_WEAPON]
end

function Gun:damagePerShot()
	local entry = self:_weaponConfig()
	return (entry and entry.Damage) or 0
end

function Gun:fireInterval()
	local entry = self:_weaponConfig()
	return (entry and entry.FireInterval) or DEFAULT_FIRE_INTERVAL
end

function Gun:carveRadius()
	local entry = self:_weaponConfig()
	return entry and entry.CarveRadius or nil
end

function Gun:range()
	local entry = self:_weaponConfig()
	return (entry and entry.Range) or DEFAULT_RANGE
end

function Gun:projectileSpeed()
	local entry = self:_weaponConfig()
	local combat = Gun.getConfig().Combat
	local speed = (entry and entry.ProjectileSpeed) or (combat and combat.ProjectileSpeed)
		or DEFAULT_PROJECTILE_SPEED
	return math.max(speed, 1)
end

-- The gravity magnitude a round feels, resolved weapon-over-shared like projectileSpeed. The
-- config stores a fraction of workspace.Gravity so the arc survives a place-gravity change.
function Gun:projectileGravity()
	local entry = self:_weaponConfig()
	local combat = Gun.getConfig().Combat
	local scale = (entry and entry.ProjectileGravityScale) or (combat and combat.ProjectileGravityScale) or 0
	return workspace.Gravity * math.max(scale, 0)
end

-- Rocket thrust in studs/s^2, resolved weapon-over-shared exactly like projectileSpeed. Unlike
-- gravity this is NOT a fraction of anything -- a rocket's motor does not care what the place's
-- gravity is set to, so scaling it to workspace.Gravity would couple two unrelated numbers.
function Gun:rocketAcceleration()
	local entry = self:_weaponConfig()
	local combat = Gun.getConfig().Combat
	local acceleration = (entry and entry.RocketAcceleration)
		or (combat and combat.RocketAcceleration) or DEFAULT_ROCKET_ACCELERATION
	return math.max(acceleration, 0)
end

-- The cruise speed thrust levels off at -- motor burnout. Nil means it never burns out and the
-- round accelerates for its whole flight, which Range ends long before the speed gets silly.
-- Returned as nil rather than math.huge so Ballistics can take its cheaper branch.
function Gun:rocketMaxSpeed()
	local entry = self:_weaponConfig()
	local maxSpeed = entry and entry.RocketMaxSpeed
	return if maxSpeed and maxSpeed > 0 then maxSpeed else nil
end

function Gun:_magazineFor(weaponId)
	local weapons = Gun.getConfig().Weapons
	local entry = weapons and (weapons[weaponId] or weapons[DEFAULT_WEAPON])
	if not entry or not entry.MagazineSize then return nil end

	local magazine = self.magazines[weaponId]
	if not magazine then
		magazine = {
			loaded = entry.MagazineSize,
			reserve = if self.infiniteReserve then nil else entry.ReserveAmmo,
		}
		self.magazines[weaponId] = magazine
	end
	return magazine, entry
end

function Gun:getAmmo()
	local magazine, entry = self:_magazineFor(self.weapon)
	if not magazine then return nil end
	return magazine.loaded, magazine.reserve, entry.MagazineSize
end

function Gun:usesAmmo()
	return self:_magazineFor(self.weapon) ~= nil
end

function Gun:isReloading()
	return self.reloadPending[self.weapon] == true
end

function Gun:reloadRemaining()
	local endsAt = self.reloadEndsAt[self.weapon]
	if not endsAt then return 0 end
	return math.max(endsAt - os.clock(), 0)
end

function Gun:setInfiniteReserve(infinite)
	self.infiniteReserve = infinite == true
	table.clear(self.magazines)
	self:_publishAmmo()
end

function Gun:resetAmmo()
	self:cancelReload()
	table.clear(self.magazines)
	self:_publishAmmo()
end

function Gun:cancelReload(weaponId)
	if weaponId then
		self.reloadTokens[weaponId] = (self.reloadTokens[weaponId] or 0) + 1
		self.reloadPending[weaponId] = nil
		self.reloadEndsAt[weaponId] = nil
		return
	end

	for id in self.reloadPending do
		self.reloadTokens[id] = (self.reloadTokens[id] or 0) + 1
	end
	table.clear(self.reloadPending)
	table.clear(self.reloadEndsAt)
end

function Gun:reload()
	local magazine, entry = self:_magazineFor(self.weapon)
	if not magazine then return false end
	if self:isReloading() then return false end
	if magazine.loaded >= entry.MagazineSize then return false end
	if magazine.reserve ~= nil and magazine.reserve <= 0 then return false end

	local weaponId = self.weapon
	local wasEmpty = magazine.loaded <= 0
	local duration = (wasEmpty and entry.ReloadTimeEmpty) or entry.ReloadTime or DEFAULT_RELOAD_TIME

	self.reloadTokens[weaponId] = (self.reloadTokens[weaponId] or 0) + 1
	local token = self.reloadTokens[weaponId]
	self.reloadPending[weaponId] = true
	self.reloadEndsAt[weaponId] = os.clock() + duration
	self:_publishAmmo()
	self.reloadStarted:Fire(duration, wasEmpty)

	task.delay(duration, function()
		if self.reloadTokens[weaponId] ~= token then return end
		self:_finishReload(weaponId)
	end)
	return true
end

function Gun:_finishReload(weaponId)
	local magazine, entry = self:_magazineFor(weaponId)
	if not magazine then return end

	local wanted = entry.MagazineSize - magazine.loaded
	local moved = if magazine.reserve == nil then wanted else math.min(wanted, magazine.reserve)
	magazine.loaded += moved
	if magazine.reserve ~= nil then
		magazine.reserve -= moved
	end

	self.reloadPending[weaponId] = nil
	self.reloadEndsAt[weaponId] = nil
	if weaponId == self.weapon then
		self:_publishAmmo()
	end
end

function Gun:_publishAmmo()
	if not self:_isPlayerShooter() then return end

	local loaded, reserve, magazineSize = self:getAmmo()
	self:sendNetworkEvent(self.shooter, "Ammo", self.weapon, loaded, reserve, magazineSize,
		self:isReloading(), self:reloadRemaining())
end

function Gun:_isPlayerShooter()
	return self.shooter:IsA("Player")
end

function Gun:_playerPart(suffix)
	local folder = workspace:FindFirstChild(BODY_FOLDER)
	local part = folder and folder:FindFirstChild(self.shooter.Name .. suffix)
	if part then return part end

	local character = self.shooter.Character
	if not character then return nil end
	if suffix == AVATAR_SUFFIX then return character end
	return character:FindFirstChild("HumanoidRootPart")
end

function Gun:muzzlePosition()
	if self:_isPlayerShooter() then
		local body = self:_playerPart(BODY_SUFFIX)
		return body and body.Position or nil
	end

	local muzzle = self.shooter:FindFirstChild(MUZZLE_NAME, true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	local part = self.shooter:FindFirstChild("RightHand") or self.shooter:FindFirstChild("Head")
	return part and part.Position or nil
end

function Gun:_exclusions()
	local exclusions = {}

	if not self:_isPlayerShooter() then
		table.insert(exclusions, self.shooter)
		return exclusions
	end

	for _, suffix in { BODY_SUFFIX, AVATAR_SUFFIX } do
		local part = self:_playerPart(suffix)
		if part then
			table.insert(exclusions, part)
		end
	end
	return exclusions
end

function Gun:_onClientFire(origin, direction, firedAt)
	if typeof(origin) ~= "Vector3" then return end

	local body = self:_playerPart(BODY_SUFFIX)
	if not body then return end
	if not ((origin - body.Position).Magnitude <= ORIGIN_SLOP) then return end

	self:fire(origin, direction, self:_rewindStamp(firedAt), firedAt)
end

function Gun:fire(origin, direction, rewindStamp, firedAt)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return false end
	if not (direction.Magnitude > 0.001) then return false end
	local unit = direction.Unit
	if unit.X ~= unit.X then return false end

	if self:isStunned() then return false end

	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local combat = Gun.getConfig().Combat
	local maxCatchup = (combat and combat.MaxRewind) or 0.25
	local spawnTime = math.clamp(firedAt or serverNow, serverNow - maxCatchup, serverNow)
	if now - self.lastFireAt < self:fireInterval() * COOLDOWN_TOLERANCE then return false end

	local magazine = self:_magazineFor(self.weapon)
	if magazine then
		if self:isReloading() then return false end
		if magazine.loaded <= 0 then return false end
	end

	self.lastFireAt = now
	self.fired:Fire()
	if magazine then
		magazine.loaded -= 1
	end

	Gun.bulletRemote:FireAllClients(self.shooter, origin, unit, self.weapon, spawnTime)

	self:_deliver(origin, unit, {
		Attacker = self.attacker,
		RewindStamp = rewindStamp,
		SpawnTime = spawnTime,
	})
	return true
end

function Gun:_resolveShot(origin, unit, options)
	local attacker = options.Attacker or self.shooter
	local damage = options.Damage
	local absorbable = options.Absorbable ~= false

	local exclusions = self:_exclusions()
	local excluded = {}
	for _, instance in exclusions do
		excluded[instance] = true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions

	local range = options.Range or self:range()
	local worldResult = workspace:Raycast(origin, unit * range, params)
	local blockedAt = worldResult and worldResult.Distance or range

	local function reject(candidate)
		if excluded[candidate] then return true end
		if candidate:GetAttribute("Dead") then return true end
		return Gun.canDamage ~= nil and not Gun.canDamage(attacker, candidate)
	end

	-- A melee weapon sweeps an arc instead of casting a ray: a baton swing should connect with
	-- whatever is in front of you within reach, not only with what is dead centre of the screen.
	-- HitscanMath.sweep is the framework's own primitive for this and was previously unused --
	-- do not write a second one, see the Hitbox Hard Rule.
	local meleeArc = self:_meleeArc()
	local combatant, hitPosition
	if meleeArc then
		combatant, hitPosition = Gun.HitscanMath.sweep(origin, unit, {
			Candidates = self:_combatants(),
			Scale = self:_hitboxScale(),
			VolumeAt = self:_volumeAt(options.RewindStamp),
			Range = range,
			CosArc = math.cos(math.rad(meleeArc) * 0.5),
			Reject = reject,
			Blocked = function(from, point)
				return (point - from).Magnitude > blockedAt
			end,
		})
	else
		combatant, hitPosition = Gun.HitscanMath.cast(origin, unit, range, {
			Candidates = self:_combatants(),
			Scale = self:_hitboxScale(),
			VolumeAt = self:_volumeAt(options.RewindStamp),
			BlockedAt = blockedAt,
			Reject = reject,
		})
	end

	if combatant then
		if absorbable and Gun.absorbs
			and Gun.absorbs(attacker, combatant, hitPosition, unit) then
			return hitPosition, true, true, true
		end
		self:_report(combatant, combatant, hitPosition, unit, attacker, damage)
		return hitPosition, true, true, false
	end

	if not worldResult then return origin + unit * range, false, false end

	local hitboxInstance = Gun.HitscanMath.findHitbox(worldResult.Instance)
	if hitboxInstance
		and not hitboxInstance:GetAttribute("Dead")
		and not (Gun.canDamage and not Gun.canDamage(attacker, hitboxInstance)) then
		self:_report(hitboxInstance, worldResult.Instance, worldResult.Position, unit, attacker, damage)
	end
	return worldResult.Position, true, false
end

function Gun:reflectShot(origin, direction, damage, range)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if not (direction.Magnitude > 0.001) then return end
	local unit = direction.Unit
	if unit.X ~= unit.X then return end

	local endPoint = self:_resolveShot(origin, unit, {
		Damage = damage,
		Range = range,
		Absorbable = false,
	})

	local resolvedEnd = endPoint or (origin + unit * (range or self:range()))
	if Gun.deflectRemote then
		local visualStart = origin + unit * REFLECT_START_OFFSET
		Gun.deflectRemote:FireAllClients(visualStart, resolvedEnd)
	end
end

function Gun:stun(duration, sourceItemId, soundName)
	if type(duration) ~= "number" or duration <= 0 then return end

	local endsAt = os.clock() + duration
	if endsAt <= self.stunnedUntil then return end
	self.stunnedUntil = endsAt

	self:cancelReload(self.weapon)
	self.stunned:Fire(duration)
	if self:_isPlayerShooter() then
		self:sendNetworkEvent(self.shooter, "Stun", duration, sourceItemId, soundName)
	end
end

function Gun:isStunned()
	return os.clock() < self.stunnedUntil
end

-- What a hit from this weapon should read as. Already replicated to every client through
-- Hitbox:reportHit, so Concert/ShootableNPC can pick its reaction off it -- see features/weapons.md.
-- An explosive payload still wins; HitKind is the general case; nil means the default reaction.
function Gun:damageKind()
	local entry = self:_weaponConfig()
	local blast = entry and entry.ImpactBlast

	return (blast and blast.Payload) or (entry and entry.HitKind) or nil
end

function Gun:_report(hitboxInstance, hitInstance, hitPosition, direction, attacker, damage)
	local hitbox = Gun.EntityStore.getComponent(hitboxInstance, "Hitbox")
	if not hitbox then return end
	hitbox:reportHit(
		hitInstance,
		hitPosition,
		attacker or self.shooter,
		direction,
		damage or self:damagePerShot(),
		Gun.HitscanMath.isHeadshot(hitboxInstance, hitPosition),
		self:carveRadius(),
		self:damageKind()
	)
end

Gun.deliveries = {}

function Gun.registerDelivery(name, deliver)
	Gun.deliveries[name] = deliver
end

function Gun:delivery()
	local entry = self:_weaponConfig()
	return (entry and entry.Delivery) or DEFAULT_DELIVERY
end

function Gun:_deliver(origin, unit, options)
	local deliver = Gun.deliveries[self:delivery()] or Gun.deliveries[DEFAULT_DELIVERY]
	if deliver then
		deliver(self, origin, unit, options)
	end
end

Gun.registerDelivery("Hitscan", function(gun, origin, unit, options)
	gun:_resolveShot(origin, unit, options)
end)

Gun.registerDelivery("Projectile", function(gun, origin, unit, options)
	gun:_deliverProjectile(origin, unit, options)
end)

Gun.registerDelivery("Rocket", function(gun, origin, unit, options)
	gun:_deliverProjectile(origin, unit, options, {
		Gravity = 0,
		Acceleration = gun:rocketAcceleration(),
		MaxSpeed = gun:rocketMaxSpeed(),
	})
end)

function Gun:_projectile()
	local host = self._projectileHost
	if not (host and host.Parent) then
		host = Instance.new("Folder")
		host.Name = self.instance.Name .. "_ProjectileHost"
		host.Parent = ServerStorage
		self._projectileHost = host
		self.trove:Add(host)
	end
	local _, component = Gun.EntityStore.addComponent(host, PROJECTILE_TAG)
	return component
end

function Gun:_deliverProjectile(origin, unit, options, flight)
	flight = flight or {}
	local projectile = self:_projectile()
	if not projectile then return end

	local attacker = options.Attacker or self.shooter
	local damage = options.Damage
	local absorbable = options.Absorbable ~= false
	local entry = self:_weaponConfig()
	local blast = entry and entry.ImpactBlast
	local weaponId = self.weapon

	projectile:launch(origin, unit, {
		Speed = self:projectileSpeed(),
		Gravity = flight.Gravity or self:projectileGravity(),
		Acceleration = flight.Acceleration,
		MaxSpeed = flight.MaxSpeed,
		Range = options.Range or self:range(),
		SpawnTime = options.SpawnTime,
		Resolve = function(from, segmentUnit, distance, segmentTime)
			local hitPosition, spent, struckCombatant, absorbed = self:_resolveShot(
				from, segmentUnit, {
					Attacker = attacker,
					Damage = damage,
					Absorbable = absorbable,
					Range = distance,
					RewindStamp = segmentTime,
				})

			if blast and spent and not absorbed then
				if Gun.Grenade then
					Gun.Grenade.detonateAt(hitPosition, {
						Thrower = attacker,
						WeaponId = blast.SoundWeapon or weaponId,
						Config = blast,
					})
				else
					warn("[Gun] ImpactBlast on " .. tostring(weaponId)
						.. " but the Grenade component was never injected")
				end
			end
			return hitPosition, spent, struckCombatant
		end,
	})
end

return Gun
