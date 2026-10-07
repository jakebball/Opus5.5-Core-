local UserInputService = game:GetService("UserInputService")

local ViewmodelMotion = {}

ViewmodelMotion.TUNING = {
	AdsSpeed = 12,
	SwayIntensity = 0.03,
	SwayMax = 0.22,
	SwayStiffness = 150,
	SwayDamping = 16,
	SwayDeadzone = 1.5,
	SwayPositionScale = 0.55,
	SwayRoll = 0.6,
	SwayClampBounce = 0.25,
	BobFrequency = 9,
	BobAmplitude = 0.15,
	BobSpeedRef = 16,
	RecoilStiffness = 420,
	RecoilDamping = 41,
	RecoilMaxBack = 0.9,
	RecoilMaxRise = 0.35,
	RecoilMaxPitch = 0.3,
	RecoilMaxRoll = 0.08,
	SwayRecoilBleed = 18,
	RunSpeedRef = 24,
	AdsSwayRetain = 0.2,
}

const TUNING = ViewmodelMotion.TUNING

-- ADS_SNAP closes the asymptote: an exponential approach is 1 - e^(-AdsSpeed*t), which at
-- AdsSpeed 12 reads 0.9975 after half a second and never reaches 1. ADS_STEPS quantises the
-- RENDERED blend only -- quantising the integrator state would deadlock it, because once the
-- per-frame increment falls below half a step the value rounds back to itself and sticks.
const ADS_SNAP = 0.02
const ADS_STEPS = 100

-- Both springs below integrate with semi-implicit Euler, which is only CONDITIONALLY stable.
-- The velocity update carries the factor (1 - damping*dt), so |1 - c*dt| > 1 once dt > 2/c,
-- and the spring term separately needs dt < 2/sqrt(k):
--     recoil  c = 41,  k = 420  ->  dt > 2/41 = 48.8 ms  (damping binds first; 2/sqrt(420) = 97.6 ms)
--     sway    c = 16,  k = 150  ->  dt > 2/16 = 125 ms   (2/sqrt(150) = 163 ms)
-- Past that the damping term FLIPS SIGN and amplifies: at dt = 0.25 s the recoil factor is
-- 1 - 41*0.25 = -9.25, so one hitched frame multiplies recoil velocity by -9.25 and integrates
-- it into position. 1/30 s sits under both limits with margin.
const MAX_FRAME_DELTA = 1 / 30

function ViewmodelMotion.clampDelta(deltaTime)
	return math.min(deltaTime, MAX_FRAME_DELTA)
end

function ViewmodelMotion.stepAds(vm, deltaTime)
	vm.adsAlpha = vm.adsAlpha + (vm.adsTarget - vm.adsAlpha) * math.min(deltaTime * TUNING.AdsSpeed, 1)
	if math.abs(vm.adsTarget - vm.adsAlpha) < ADS_SNAP then
		vm.adsAlpha = vm.adsTarget
	end
	vm.adsBlend = math.round(vm.adsAlpha * ADS_STEPS) / ADS_STEPS
	return vm.adsBlend
end

-- Reflect-and-scale at the travel limit: velocity pushing past SwayMax is negated and
-- multiplied by SwayClampBounce, so the spring rebounds off the stop. A bare clamp freezes
-- the display while the integrator keeps winding, which unwinds as a dead pause.
local function clampSway(position, velocity)
	const LIMIT = TUNING.SwayMax
	local positionX, positionY = position.X, position.Y
	local velocityX, velocityY = velocity.X, velocity.Y
	if math.abs(positionX) > LIMIT then
		if positionX * velocityX > 0 then
			velocityX = -velocityX * TUNING.SwayClampBounce
		end
		positionX = math.clamp(positionX, -LIMIT, LIMIT)
	end
	if math.abs(positionY) > LIMIT then
		if positionY * velocityY > 0 then
			velocityY = -velocityY * TUNING.SwayClampBounce
		end
		positionY = math.clamp(positionY, -LIMIT, LIMIT)
	end
	return Vector2.new(positionX, positionY), Vector2.new(velocityX, velocityY)
end

function ViewmodelMotion.stepSway(vm, deltaTime)
	local delta = UserInputService:GetMouseDelta()
	-- Soft deadzone: subtract the threshold from the magnitude instead of gating on it, so
	-- hand tremor at rest contributes nothing while a real turn keeps its proportionality.
	-- A LockCenter mouse reports small non-zero deltas continuously, and the spring below is
	-- deliberately underdamped, so every one of them became several visible cycles.
	local deltaMagnitude = delta.Magnitude
	delta = if deltaMagnitude > TUNING.SwayDeadzone
		then delta * ((deltaMagnitude - TUNING.SwayDeadzone) / deltaMagnitude)
		else Vector2.zero

	local recoilInfluence = math.clamp(
		vm.recoilRot.X / TUNING.RecoilMaxPitch + vm.recoilPos.Z / TUNING.RecoilMaxBack,
		0, 1
	)
	local swayBleed = math.min(deltaTime * TUNING.SwayRecoilBleed * recoilInfluence, 1)
	vm.swayPos = vm.swayPos * (1 - swayBleed)
	vm.swayVel = vm.swayVel * (1 - swayBleed)

	local swayScale = (1 - vm.adsBlend * (1 - TUNING.AdsSwayRetain)) * (1 - recoilInfluence)
	vm.swayVel = vm.swayVel + Vector2.new(delta.X, delta.Y) * (TUNING.SwayIntensity * swayScale)
	vm.swayVel = vm.swayVel + (vm.swayPos * -TUNING.SwayStiffness - vm.swayVel * TUNING.SwayDamping) * deltaTime
	vm.swayPos = vm.swayPos + vm.swayVel * deltaTime
	vm.swayPos, vm.swayVel = clampSway(vm.swayPos, vm.swayVel)

	return CFrame.new(
		-vm.swayPos.X * TUNING.SwayPositionScale,
		vm.swayPos.Y * TUNING.SwayPositionScale,
		0
	) * CFrame.Angles(vm.swayPos.Y, vm.swayPos.X, -vm.swayPos.X * TUNING.SwayRoll)
end

function ViewmodelMotion.stepBob(vm, deltaTime, speed, locomotionActive)
	local bobScale = if locomotionActive
		then 0
		else math.clamp(speed / TUNING.BobSpeedRef, 0, 1) * (1 - vm.adsBlend)
	if speed > 0.5 then
		vm.bobTime = vm.bobTime + deltaTime * TUNING.BobFrequency
	end
	return CFrame.new(
		math.cos(vm.bobTime) * TUNING.BobAmplitude * bobScale,
		math.abs(math.sin(vm.bobTime)) * TUNING.BobAmplitude * bobScale,
		0
	)
end

-- Containment, not tuning. addRecoil bounds the kick it ADDS, but nothing bounded the
-- integrator's own output, and its clamps were one-sided (math.min) so a large negative
-- passed straight through. Anything that parks these outside the authored envelope puts the
-- viewmodel off-screen, so the state is clamped every step and the velocity that drove it
-- past the stop is dropped rather than left to fight the clamp.
local function containRecoil(vm)
	local position, velocity = vm.recoilPos, vm.recoilVel
	local clampedY = math.clamp(position.Y, -TUNING.RecoilMaxRise, TUNING.RecoilMaxRise)
	local clampedZ = math.clamp(position.Z, -TUNING.RecoilMaxBack, TUNING.RecoilMaxBack)
	if clampedY ~= position.Y or clampedZ ~= position.Z then
		vm.recoilPos = Vector3.new(0, clampedY, clampedZ)
		vm.recoilVel = Vector3.new(
			0,
			if clampedY ~= position.Y then 0 else velocity.Y,
			if clampedZ ~= position.Z then 0 else velocity.Z
		)
	end

	local rotation, rotationVel = vm.recoilRot, vm.recoilRotVel
	local clampedX = math.clamp(rotation.X, -TUNING.RecoilMaxPitch, TUNING.RecoilMaxPitch)
	local clampedRoll = math.clamp(rotation.Z, -TUNING.RecoilMaxRoll, TUNING.RecoilMaxRoll)
	if clampedX ~= rotation.X or clampedRoll ~= rotation.Z then
		vm.recoilRot = Vector3.new(clampedX, 0, clampedRoll)
		vm.recoilRotVel = Vector3.new(
			if clampedX ~= rotation.X then 0 else rotationVel.X,
			0,
			if clampedRoll ~= rotation.Z then 0 else rotationVel.Z
		)
	end
end

function ViewmodelMotion.stepRecoil(vm, deltaTime)
	local stiffness, damping = TUNING.RecoilStiffness, TUNING.RecoilDamping
	vm.recoilVel = vm.recoilVel + (vm.recoilPos * -stiffness - vm.recoilVel * damping) * deltaTime
	vm.recoilPos = vm.recoilPos + vm.recoilVel * deltaTime
	vm.recoilRotVel = vm.recoilRotVel + (vm.recoilRot * -stiffness - vm.recoilRotVel * damping) * deltaTime
	vm.recoilRot = vm.recoilRot + vm.recoilRotVel * deltaTime
	containRecoil(vm)
	return CFrame.new(vm.recoilPos) * CFrame.Angles(vm.recoilRot.X, vm.recoilRot.Y, vm.recoilRot.Z)
end

-- Add a recoil kick. back = studs toward camera, up = pitch radians (muzzle rise),
-- roll = z-twist radians. Kicks POSITION instantly (the punch lands on the shot);
-- the spring in stepRecoil only pulls it back to rest. Clamped so sustained fire
-- accumulates to a controlled maximum instead of climbing forever.
function ViewmodelMotion.addRecoil(vm, back, up, roll)
	vm.lastRecoilClock = os.clock()
	back = back or 0.2
	up = up or 0.05
	roll = roll or 0
	local position = vm.recoilPos + Vector3.new(0, up * 0.5, back)
	local rotation = vm.recoilRot + Vector3.new(up, 0, roll)
	vm.recoilPos = Vector3.new(
		0,
		math.clamp(position.Y, -TUNING.RecoilMaxRise, TUNING.RecoilMaxRise),
		math.clamp(position.Z, -TUNING.RecoilMaxBack, TUNING.RecoilMaxBack)
	)
	vm.recoilRot = Vector3.new(
		math.clamp(rotation.X, -TUNING.RecoilMaxPitch, TUNING.RecoilMaxPitch),
		0,
		math.clamp(rotation.Z, -TUNING.RecoilMaxRoll, TUNING.RecoilMaxRoll)
	)
end

return ViewmodelMotion
