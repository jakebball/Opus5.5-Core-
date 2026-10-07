local ViewmodelMotion = require(script.Parent.ViewmodelMotion)

const TUNING = ViewmodelMotion.TUNING

const IDLE_FADE = 0.2
const EQUIP_FADE = 0.05
const LENGTH_WAIT_TIMEOUT = 5
const RUN_CLIP = "Run"
const SPRINT_CLIP = "Sprint"
const SPRINT_FIRE_LOCKOUT = 0.35
const IDLE_CLIP = "Idle"
const STATE_HOLD = "Hold"
const STATE_MOVING = "Moving"
const STATE_SPRINTING = "Sprinting"
const STATE_SIGHTED = "Sighted"
const STATE_LOCOMOTION = {
	[STATE_MOVING] = RUN_CLIP,
	[STATE_SPRINTING] = SPRINT_CLIP,
}
const LOCOMOTION_FADE = 0.2
const LOCOMOTION_MIN_SPEED = 0.5
const LOCOMOTION_MIN_RATE = 0.6
const LOCOMOTION_MAX_RATE = 2

local function locomotionSignature(animationIds)
	if not animationIds then return "" end
	return tostring(animationIds[RUN_CLIP]) .. "|" .. tostring(animationIds[SPRINT_CLIP])
end


return function(FPSViewmodel)

function FPSViewmodel:setLocomotionAnimations(animationIds)
	if locomotionSignature(self.locomotionIds) == locomotionSignature(animationIds) then return end

	self:_releaseLocomotionTracks()
	self.locomotionIds = animationIds
end

function FPSViewmodel:setAnimations(animationIds)
	self:_releaseTracks()
	self.animationIds = animationIds
	if not animationIds then return end

	for clipName in animationIds do
		self:_track(clipName)
	end
	self:_playEquip()
end

function FPSViewmodel:_playEquip()
	if not self.animationIds then return end
	for clipName in self.animationIds do
		self:_track(clipName)
	end

	self:play("Idle", { loop = true, priority = Enum.AnimationPriority.Idle, fade = IDLE_FADE })
	self:play("Equip", { priority = Enum.AnimationPriority.Action, fade = EQUIP_FADE })
end

function FPSViewmodel:_track(name)
	if not self.animator or not self.rig or not self.tracks then return nil end

	local existing = self.tracks[name]
	if existing then return existing end

	if not self.rig:IsDescendantOf(game) then
		return nil
	end

	local animationId = self.animationIds and self.animationIds[name]
	if not animationId or animationId == "" then return nil end

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	animation.Parent = self.rig

	local ok, result = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[FPSViewmodel] LoadAnimation failed", name, result)
		animation:Destroy()
		return nil
	end

	self.tracks[name] = result
	self.animationInstances[name] = animation
	return result
end

function FPSViewmodel:_resolveState(speed)
	if self.adsBlend > 0 and self.adsAttachment and self.adsAttachment.Parent then
		return STATE_SIGHTED
	end
	if speed <= LOCOMOTION_MIN_SPEED then return STATE_HOLD end

	local firing = os.clock() - self.lastRecoilClock < SPRINT_FIRE_LOCKOUT
	local body = self:_findBody()
	local carrying = body ~= nil
		and (body:GetAttribute("Sprinting") == true or body:GetAttribute("SlideActive") == true)
	return if carrying and not firing then STATE_SPRINTING else STATE_MOVING
end

function FPSViewmodel:_enterState(state)
	if state ~= STATE_SIGHTED then return end
	if self.actionClip then
		self:stop(self.actionClip, LOCOMOTION_FADE)
		self.actionClip = nil
	end
end

function FPSViewmodel:_updateAnimationState(speed)
	local state = self:_resolveState(speed)
	if state ~= self.animState then
		self.animState = state
		self:_enterState(state)
	end

	local desired = self:_resolveLocomotionClip(STATE_LOCOMOTION[state])
	for clipName, other in self.locomotionTracks do
		if clipName ~= desired and other.IsPlaying then
			other:Stop(LOCOMOTION_FADE)
		end
	end
	if not desired then return false end

	local track = self:_locomotionTrack(desired)
	if not track then return false end

	if not track.IsPlaying then track:Play(LOCOMOTION_FADE) end
	track:AdjustSpeed(math.clamp(speed / TUNING.RunSpeedRef, LOCOMOTION_MIN_RATE, LOCOMOTION_MAX_RATE))
	return true
end

function FPSViewmodel:_resolveLocomotionClip(name)
	if not name or not self.animationIds then return name end
	if self.animationIds[name] then return name end
	if name == SPRINT_CLIP and self.animationIds[RUN_CLIP] then return RUN_CLIP end
	return name
end

function FPSViewmodel:_locomotionTrack(name)
	if not self.animator or not self.rig or not self.locomotionTracks then return nil end

	local animationId = (self.animationIds and self.animationIds[name])
		or (self.locomotionIds and self.locomotionIds[name])
	if not animationId or animationId == "" then return nil end

	local existing = self.locomotionTracks[name]
	if existing then
		if self.locomotionResolved[name] == animationId then return existing end
		self:_releaseLocomotionTrack(name)
	end

	if not self.rig:IsDescendantOf(game) then return nil end

	local animation = Instance.new("Animation")
	animation.Name = "Locomotion" .. name
	animation.AnimationId = animationId
	animation.Parent = self.rig

	local ok, result = pcall(function()
		return self.animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[FPSViewmodel] locomotion LoadAnimation failed", name, result)
		animation:Destroy()
		return nil
	end

	result.Priority = Enum.AnimationPriority.Movement
	result.Looped = true
	self.locomotionTracks[name] = result
	self.locomotionInstances[name] = animation
	self.locomotionResolved[name] = animationId
	return result
end

function FPSViewmodel:_releaseLocomotionTrack(name)
	local track = self.locomotionTracks[name]
	if track then
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	local animation = self.locomotionInstances[name]
	if animation then animation:Destroy() end
	self.locomotionTracks[name] = nil
	self.locomotionInstances[name] = nil
	self.locomotionResolved[name] = nil
end

function FPSViewmodel:_releaseLocomotionTracks()
	for _, track in self.locomotionTracks or {} do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	for _, animation in self.locomotionInstances or {} do
		animation:Destroy()
	end
	self.locomotionTracks = {}
	self.locomotionInstances = {}
	self.locomotionResolved = {}
end

function FPSViewmodel:_releaseTracks()
	for _, track in self.tracks or {} do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	for _, animation in self.animationInstances or {} do
		animation:Destroy()
	end
	self.tracks = {}
	self.animationInstances = {}
end

-- speed = clipLength / targetDuration spans the clip over exactly the window the game gives it,
-- so a clip fits its weapon's ReloadTime instead of running past the point the rounds are
-- already back in the magazine.
--
-- Length reads 0 until the asset resolves, and a track played on the same frame it was loaded is
-- ALWAYS still 0 — so a scale computed inline silently fell back to 1x on every first play.
-- Apply it now when the length is known, otherwise re-apply the moment it lands.
function FPSViewmodel:_scaleToDuration(track, duration)
	if track.Length > 0 then
		track:AdjustSpeed(track.Length / duration)
		return
	end

	task.spawn(function()
		local deadline = os.clock() + LENGTH_WAIT_TIMEOUT
		while track.Length == 0 and os.clock() < deadline do
			task.wait()
		end
		if track.Length > 0 and track.IsPlaying then
			track:AdjustSpeed(track.Length / duration)
		end
	end)
end

function FPSViewmodel:stop(name, fadeTime)
	local track = self.tracks and self.tracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.1)
	end
end

function FPSViewmodel:play(name, opts)
	if name ~= IDLE_CLIP and self.animState == STATE_SIGHTED then
		self:setAds(false)
	end

	local track = self:_track(name)
	if not track then return nil end
	if name ~= IDLE_CLIP then self.actionClip = name end

	opts = opts or {}
	if opts.priority then track.Priority = opts.priority end
	track.Looped = opts.loop and true or false

	if track.IsPlaying then
		track.TimePosition = 0
	else
		track:Play(opts.fade or 0.1)
	end
	track:AdjustSpeed(1)
	if opts.duration and opts.duration > 0 then
		self:_scaleToDuration(track, opts.duration)
	end

	if track.Length == 0 then
		task.spawn(function()
			local deadline = os.clock() + LENGTH_WAIT_TIMEOUT
			while track.Length == 0 and os.clock() < deadline do
				task.wait()
			end
			if track.Length > 0 and self.tracks and self.tracks[name] == track and track.IsPlaying then
				track:Stop(0)
				track:Play(opts.fade or 0.1)
				track:AdjustSpeed(if opts.duration and opts.duration > 0 then track.Length / opts.duration else 1)
			end
		end)
	end


	return track
end


end
