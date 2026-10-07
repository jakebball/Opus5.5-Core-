local RunService = game:GetService("RunService")

const RENDER_NAME = "CameraShake"
const RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 5
const Z_DAMP = 0.3

const KICK_STIFFNESS = 300
const KICK_DAMPING = 26
const KICK_MAX_PITCH = math.rad(4)
const KICK_MAX_YAW = math.rad(2.5)
const KICK_MAX_ROLL = math.rad(3)
const KICK_MAX_PUNCH = 0.35
const KICK_MAX_STEP = 1 / 30
const KICK_REST = 1e-4

local CameraShake = {}

local activeShakes = {}
local bound = false
local kickAngles = Vector3.zero
local kickAngularVelocity = Vector3.zero
local kickPunch = 0
local kickPunchVelocity = 0
local currentOffset = CFrame.identity

local function kickAtRest()
	return kickAngles.Magnitude < KICK_REST
		and kickAngularVelocity.Magnitude < KICK_REST
		and math.abs(kickPunch) < KICK_REST
		and math.abs(kickPunchVelocity) < KICK_REST
end

local function unbind()
	if not bound then return end
	bound = false
	currentOffset = CFrame.identity
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
end

-- Damped harmonic oscillator about zero, semi-implicit Euler: a = -k*x - c*v. An impulse
-- adds to VELOCITY rather than position, so with k = 300 and c = 26 (zeta = 0.75, damped
-- frequency 11.4 rad/s) an impulse v0 peaks at ~0.026*v0 after 0.063 s and is back inside
-- a tenth of that by 0.35 s -- a punch that rises over a few frames, not a one-frame snap.
local function stepKick(deltaTime)
	local step = math.min(deltaTime, KICK_MAX_STEP)
	kickAngularVelocity += (kickAngles * -KICK_STIFFNESS - kickAngularVelocity * KICK_DAMPING) * step
	kickAngles += kickAngularVelocity * step
	kickPunchVelocity += (kickPunch * -KICK_STIFFNESS - kickPunchVelocity * KICK_DAMPING) * step
	kickPunch += kickPunchVelocity * step

	kickAngles = Vector3.new(
		math.clamp(kickAngles.X, -KICK_MAX_PITCH, KICK_MAX_PITCH),
		math.clamp(kickAngles.Y, -KICK_MAX_YAW, KICK_MAX_YAW),
		math.clamp(kickAngles.Z, -KICK_MAX_ROLL, KICK_MAX_ROLL)
	)
	kickPunch = math.clamp(kickPunch, -KICK_MAX_PUNCH, KICK_MAX_PUNCH)

	if kickAtRest() then
		kickAngles, kickAngularVelocity = Vector3.zero, Vector3.zero
		kickPunch, kickPunchVelocity = 0, 0
	end
end

local function step(deltaTime)
	local now = os.clock()
	local shakeX, shakeY, shakeZ = 0, 0, 0
	for index = #activeShakes, 1, -1 do
		local shake = activeShakes[index]
		local elapsed = now - shake.startTime
		if elapsed >= shake.duration then
			table.remove(activeShakes, index)
		else
			local amplitude = shake.amplitude * (1 - elapsed / shake.duration)
			shakeX += math.noise(elapsed * shake.frequency, index, 0) * amplitude
			shakeY += math.noise(0, elapsed * shake.frequency, index) * amplitude
			shakeZ += math.noise(index, 0, elapsed * shake.frequency) * amplitude * Z_DAMP
		end
	end

	stepKick(deltaTime)

	currentOffset = CFrame.new(shakeX, shakeY, shakeZ + kickPunch)
		* CFrame.Angles(kickAngles.X, kickAngles.Y, kickAngles.Z)

	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame * currentOffset
	end

	if #activeShakes == 0 and kickAtRest() then
		unbind()
	end
end

local function ensureBound()
	if bound then return end
	if not RunService:IsClient() then return end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, RENDER_PRIORITY, step)
end

function CameraShake.Shake(amplitude, duration, frequency)
	if not RunService:IsClient() then return end
	table.insert(activeShakes, {
		startTime = os.clock(),
		amplitude = amplitude or 0.5,
		duration = duration or 0.25,
		frequency = frequency or 30,
	})
	ensureBound()
end

function CameraShake.Kick(pitch, yaw, roll, punch)
	if not RunService:IsClient() then return end
	kickAngularVelocity += Vector3.new(pitch or 0, yaw or 0, roll or 0)
	kickPunchVelocity += punch or 0
	ensureBound()
end

function CameraShake.BaseCFrame()
	local camera = workspace.CurrentCamera
	if not camera then return CFrame.identity end
	return camera.CFrame * currentOffset:Inverse()
end

function CameraShake.Stop()
	activeShakes = {}
	kickAngles, kickAngularVelocity = Vector3.zero, Vector3.zero
	kickPunch, kickPunchVelocity = 0, 0
end

return CameraShake
