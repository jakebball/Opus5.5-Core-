local RunService = game:GetService("RunService")

const RIG_PROVIDERS = { "BotShooter", "TargetDummy" }

local WeaponAnimation = {}
WeaponAnimation.__index = WeaponAnimation
WeaponAnimation.Tag = "WeaponAnimation"

const TRACK_PREFIX = "Weapon"
const HOLD_PRIORITY = Enum.AnimationPriority.Action
const ACTION_PRIORITY = Enum.AnimationPriority.Action2
const FADE_TIME = 0.15
const DEFAULT_FIRE_INTERVAL = 0.12
const IDLE_CLIP = "Idle"
const RUN_CLIP = "Run"
const HOLD_FADE = 0.2
const RUN_SPEED = 4

local activeAnimations = {}

local function trackName(clipName)
	return TRACK_PREFIX .. clipName
end

function WeaponAnimation.Start()
	setmetatable(WeaponAnimation, { __index = WeaponAnimation.BaseClass })
	WeaponAnimation.Observers.observePlayer(function(player)
		player:AddTag(WeaponAnimation.Tag)
	end)
	RunService.Heartbeat:Connect(WeaponAnimation._stepLocomotion)
end

function WeaponAnimation.new(instance)
	local self = setmetatable(WeaponAnimation.BaseClass.new(instance), WeaponAnimation)
	self.registered = {}
	self.rebuildQueued = false
	self.released = false

	self:_bindRig()
	task.defer(function()
		if self.released then return end
		self:_bindHeldItems()
		self:_bindMelee()
	end)
	self:_bindGun()
	self:_bindThrown()

	self.moving = false
	activeAnimations[self] = true

	return self
end

function WeaponAnimation:_bindRig()
	if not self.instance:IsA("Player") then
		self.rig = self.instance
		self:_scheduleRebuild()
		return
	end

	self.trove:AddPromise(WeaponAnimation.EntityStore.promiseGetComponent(self.instance, "CustomServerAvatar"):andThen(function(avatarComponent)
		self.trove:Add(avatarComponent.onAvatarSpawned:Connect(function(_body, avatar)
			self.rig = avatar
			self:_scheduleRebuild()
		end), "Disconnect")

		self.rig = avatarComponent:getAvatar()
		self:_scheduleRebuild()
	end))
end

function WeaponAnimation:_heldItemProvider()
	if self.instance:IsA("Player") then return "GearBackpack" end
	for _, tag in RIG_PROVIDERS do
		if self.instance:HasTag(tag) then return tag end
	end
	return nil
end

function WeaponAnimation:_bindHeldItems()
	local providerTag = self:_heldItemProvider()
	if not providerTag then return end

	self.trove:AddPromise(WeaponAnimation.EntityStore.promiseGetComponent(self.instance, providerTag):andThen(function(provider)
		self.trove:Add(provider.heldItemsChanged:Connect(function(heldItems)
			self:_setHeldItems(heldItems)
		end), "Disconnect")

		self:_setHeldItems(provider:getHeldItems())
	end))
end

function WeaponAnimation:_setHeldItems(heldItems)
	local gearConfig = WeaponAnimation.getConfig().Weapons
	local resolved = nil
	for _, itemId in heldItems or {} do
		local itemConfig = gearConfig[itemId]
		if itemConfig and itemConfig.Model then
			resolved = itemId
			break
		end
	end

	if resolved == self.weapon then return end
	self.weapon = resolved
	self:_scheduleRebuild()
end

function WeaponAnimation:playUse()
	self:_playClip("Use", nil, 0)
end

function WeaponAnimation:_bindGun()
	self.trove:AddPromise(WeaponAnimation.EntityStore.promiseGetComponent(self.instance, "Gun"):andThen(function(gun)
		self.trove:Add(gun.fired:Connect(function()
			self:_playClip("Shoot", self:_fireInterval(), 0)
			self:_setChamberedRound(false)
			self:_armChamberedMarker()
		end), "Disconnect")
		self.trove:Add(gun.reloadStarted:Connect(function(duration, wasEmpty)
			self:_playClip(self:_reloadClip(wasEmpty), duration, FADE_TIME)
		end), "Disconnect")
	end))
end

function WeaponAnimation:_bindMelee()
	local providerTag = self:_meleeProvider()
	if not providerTag then return end

	self.trove:AddPromise(WeaponAnimation.EntityStore.promiseGetComponent(self.instance, providerTag):andThen(function(melee)
		if melee.swung then
			self.trove:Add(melee.swung:Connect(function(clipName)
				self:_playClip(clipName, nil, 0)
			end), "Disconnect")
		end
		if melee.parried then
			self.trove:Add(melee.parried:Connect(function()
				self:_playClip("Parry", nil, 0)
			end), "Disconnect")
		end
	end))
end

function WeaponAnimation:_bindThrown()
	if not self.instance:IsA("Player") then return end

	self.trove:AddPromise(WeaponAnimation.EntityStore.promiseGetComponent(self.instance, "ThrownWeapon"):andThen(function(thrown)
		self.trove:Add(thrown.pulled:Connect(function()
			self:_playClip("Trigger", nil, 0)
		end), "Disconnect")
		self.trove:Add(thrown.thrown:Connect(function()
			self:_playClip("TriggerThrow", nil, 0)
		end), "Disconnect")
	end))
end

function WeaponAnimation:_meleeProvider()
	if self.instance:IsA("Player") then return "MeleeWeapon" end
	for _, tag in RIG_PROVIDERS do
		if self.instance:HasTag(tag) then return tag end
	end
	return nil
end

function WeaponAnimation:_chamberedRound()
	local rig
	if self.instance:IsA("Player") then
		local bodies = workspace:FindFirstChild("MovementBodies")
		rig = bodies and bodies:FindFirstChild(self.instance.Name .. "_Avatar")
	else
		rig = self.instance
	end
	if not rig or not self.weapon then return nil end

	local item = rig:FindFirstChild(self.weapon)
	if not (item and item:GetAttribute(WeaponAnimation.GearDressing.WornAttribute)) then
		return nil
	end
	return WeaponAnimation.RoundVisibility.target(item, self:_weaponConfig())
end

function WeaponAnimation:_setChamberedRound(visible)
	local target = self:_chamberedRound()
	if not target then return end
	WeaponAnimation.RoundVisibility.set(target, visible)
end

function WeaponAnimation:_armChamberedMarker()
	if self.chamberedArmed or not self.animator then return end

	local itemConfig = self:_weaponConfig()
	if not (itemConfig and itemConfig.ChamberedRoundPart) then return end

	local track = self.animator:getTrack(trackName("Shoot"))
	if not track then return end
	self.chamberedArmed = true

	local markerName = itemConfig.ChamberedRoundMarker or "RocketAppears"
	self.trove:Add(track:GetMarkerReachedSignal(markerName):Connect(function()
		self:_setChamberedRound(true)
	end), "Disconnect")
	self.trove:Add(track.Stopped:Connect(function()
		self:_setChamberedRound(true)
	end), "Disconnect")
end

function WeaponAnimation:_weaponConfig()
	if not self.weapon then return nil end
	return WeaponAnimation.getConfig().Weapons[self.weapon]
end

function WeaponAnimation:_reloadClip(wasEmpty)
	if wasEmpty and table.find(self.registered, "ReloadEmpty") then
		return "ReloadEmpty"
	end
	return "Reload"
end

function WeaponAnimation:_fireInterval()
	local weaponConfig = self:_weaponConfig()
	return (weaponConfig and weaponConfig.FireInterval) or DEFAULT_FIRE_INTERVAL
end

function WeaponAnimation:_scheduleRebuild()
	if self.rebuildQueued then return end
	self.rebuildQueued = true

	task.defer(function()
		self.rebuildQueued = false
		self:_rebuild()
	end)
end

function WeaponAnimation:_rebuild()
	if self.released then return end
	self:_clearTracks()

	local rig = self.rig
	if not rig or not rig.Parent then return end

	local weaponConfig = self:_weaponConfig()
	local clips = weaponConfig and weaponConfig.Animations
	if not clips then return end

	local _, animator = WeaponAnimation.EntityStore.addComponent(rig, "Animator")
	if not animator then return end
	self.animator = animator
	self.animatorRig = rig

	for clipName, animationId in clips do
		if animationId and animationId ~= "" then
			animator:registerAnimation(trackName(clipName), animationId)
			table.insert(self.registered, clipName)
		end
	end

	self:_applyHold(FADE_TIME)
	self:_playClip("Equip", nil, FADE_TIME)
end

function WeaponAnimation:_clearTracks()
	if self.animator and self.animatorRig and self.animatorRig.Parent then
		for _, clipName in self.registered do
			self.animator:unregisterAnimation(trackName(clipName), FADE_TIME)
		end
	end

	table.clear(self.registered)
	self.animator = nil
	self.animatorRig = nil
	self.holdClip = nil
end

function WeaponAnimation:_playClip(clipName, targetDuration, fadeTime)
	if not self.animator then return end
	if not table.find(self.registered, clipName) then return end

	local name = trackName(clipName)
	local track = self.animator:getTrack(name)
	if not track then return end

	-- speed = clipLength / targetDuration makes the clip span exactly the window the game gives
	-- it: a 1.85 s reload plays over a 2 s ReloadTime, and a 0.2 s recoil compresses into the
	-- 0.12 s FireInterval instead of being cut off and restarted partway through every shot.
	local speed = 1
	if targetDuration and targetDuration > 0 and track.Length > 0 then
		speed = track.Length / targetDuration
	end

	track:Stop(0)
	self.animator:playAnimation(name, fadeTime, false, ACTION_PRIORITY)
	track:AdjustSpeed(speed)
end

function WeaponAnimation:_applyHold(fadeTime)
	if not self.animator then return end

	local wanted = IDLE_CLIP
	if self.moving and table.find(self.registered, RUN_CLIP) then
		wanted = RUN_CLIP
	end
	if wanted == self.holdClip then return end

	if self.holdClip then
		local previous = self.animator:getTrack(trackName(self.holdClip))
		if previous then previous:Stop(fadeTime) end
	end
	self.holdClip = nil

	if not table.find(self.registered, wanted) then return end
	self.animator:playAnimation(trackName(wanted), fadeTime, true, HOLD_PRIORITY)
	self.holdClip = wanted
end

function WeaponAnimation:_updateLocomotion()
	if not self.animator then return end

	local rig = self.animatorRig
	local rootPart = rig and (rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart"))
	if not rootPart then return end

	local velocity = rootPart.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > RUN_SPEED
	if moving == self.moving then return end

	self.moving = moving
	self:_applyHold(HOLD_FADE)
end

function WeaponAnimation._stepLocomotion()
	for component in activeAnimations do
		component:_updateLocomotion()
	end
end

function WeaponAnimation:destroy()
	self.released = true
	activeAnimations[self] = nil
	self:_clearTracks()
end

return WeaponAnimation
