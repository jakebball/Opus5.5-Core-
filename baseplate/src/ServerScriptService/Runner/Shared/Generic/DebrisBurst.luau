local Debris = game:GetService("Debris")

local Assets = require(script.Parent.Assets)

const TEMPLATE_PATH = "VFX/DebrisBurst"
const TEXTURE = "rbxassetid://91809408162145"
const FLIPBOOK_LAYOUT = Enum.ParticleFlipbookLayout.Grid4x4
const HOST_NAME = "DebrisBurstHost"
const CLEANUP_MARGIN = 0.25
const MIN_HOST_EXTENT = 0.05
const NEON_LIGHT_EMISSION = 0.2

const DEFAULT_COUNT = 40
const DEFAULT_LIFETIME = 0.6
const DEFAULT_SIZE = Vector3.new(2, 2, 2)
const DEFAULT_SPEED = 30
const DEFAULT_CONE_ANGLE = 30
const DEFAULT_SPAWN_RADIUS = 2

const FULL_SPHERE_ANGLE = 180
const DOME_ANGLE = 108
-- A cube of edge E spans E*sqrt(3) across its long diagonal, and the atlas render fills about
-- 0.9 of its cell, so a sprite standing in for a part of edge E wants to be E*sqrt(3)/0.9 wide.
const SPRITE_SCALE = math.sqrt(3) / 0.9
const SIZE_KEYPOINTS = 4

local DebrisBurst = {}

local warnedMissingTemplates = {}

local function newEmitter(templatePath)
	local path = templatePath or TEMPLATE_PATH
	local template = Assets.Get(path)
	if template and template:IsA("ParticleEmitter") then
		return template:Clone()
	end

	if not warnedMissingTemplates[path] then
		warnedMissingTemplates[path] = true
		warn(("[DebrisBurst] no ParticleEmitter at Assets/%s — using the built-in look"):format(path))
	end

	local fallback = Instance.new("ParticleEmitter")
	fallback.Texture = TEXTURE
	fallback.FlipbookLayout = FLIPBOOK_LAYOUT
	fallback.FlipbookStartRandom = true
	fallback.FlipbookFramerate = NumberRange.new(0)
	fallback.LightInfluence = 0
	fallback.Transparency = NumberSequence.new(0)
	return fallback
end

local function resolveColor(options)
	local color = options.Color
	if type(color) == "function" then
		color = color(1, 1)
	end
	if typeof(color) == "ColorSequence" then
		return color
	end
	if typeof(color) == "Color3" then
		return ColorSequence.new(color)
	end
	return ColorSequence.new(Color3.new(1, 1, 1))
end

local function resolveAim(options)
	local direction = options.Direction
	if typeof(direction) == "Vector3" and direction.Magnitude > 1e-4 then
		local cone = options.ConeAngle or DEFAULT_CONE_ANGLE
		return direction.Unit, Vector2.new(cone, cone)
	end
	if direction == "fullsphere" then
		return Vector3.yAxis, Vector2.new(FULL_SPHERE_ANGLE, FULL_SPHERE_ANGLE)
	end
	if direction == "sphere" then
		return Vector3.yAxis, Vector2.new(DOME_ANGLE, DOME_ANGLE)
	end
	return Vector3.xAxis, Vector2.new(0, FULL_SPHERE_ANGLE)
end

function DebrisBurst.Fire(options)
	if not options or typeof(options.Origin) ~= "Vector3" then return end

	local count = options.Count or DEFAULT_COUNT
	local lifetime = options.Lifetime or DEFAULT_LIFETIME
	local origin = options.Origin + Vector3.new(0, options.YOffset or 0, 0)

	local axis, spread = resolveAim(options)
	local speed = options.LaunchSpeed or DEFAULT_SPEED
	local lift = options.LaunchUp or 0

	-- Each shard used to launch at `direction * speed + lift * Y`. A ParticleEmitter has no
	-- per-particle velocity offset, so the constant lift is folded into the aim: the axis tilts
	-- toward +Y by atan(lift / speed) and the speed becomes the resultant sqrt(speed^2 + lift^2).
	-- The spread is then capped at 180 minus that tilt so a wide cone rotated upward cannot wrap
	-- back past vertical.
	if lift ~= 0 and speed > 0 then
		local tilt = math.atan2(lift, speed)
		local tiltAxis = axis:Cross(Vector3.yAxis)
		if tiltAxis.Magnitude > 1e-4 then
			axis = CFrame.fromAxisAngle(tiltAxis.Unit, tilt) * axis
		end
		speed = math.sqrt(speed * speed + lift * lift)
		local cap = FULL_SPHERE_ANGLE - math.deg(math.abs(tilt))
		spread = Vector2.new(math.min(spread.X, cap), math.min(spread.Y, cap))
	end

	local jitterMin = options.SpeedJitterMin or 1
	local jitterRange = options.SpeedJitterRange or 0

	-- The part burst tweened Size to nothing on a quadratic ease-in, i.e. size(t) = start * (1 - t^2).
	local startSize = (options.Size or DEFAULT_SIZE).X * SPRITE_SCALE
	local sizeKeypoints = {}
	for index = 0, SIZE_KEYPOINTS do
		local fraction = index / SIZE_KEYPOINTS
		table.insert(sizeKeypoints, NumberSequenceKeypoint.new(fraction, startSize * (1 - fraction * fraction)))
	end

	local spawnRadius = options.SpawnRadius or DEFAULT_SPAWN_RADIUS
	local extent = math.max(spawnRadius * 2, MIN_HOST_EXTENT)

	local host = Instance.new("Part")
	host.Name = options.Name or HOST_NAME
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Locked = true
	host.Transparency = 1
	host.Size = Vector3.new(extent, extent, extent)
	local upHint = math.abs(axis.Y) > 0.99 and Vector3.zAxis or Vector3.yAxis
	host.CFrame = CFrame.lookAt(origin, origin + axis, upHint)

	local emitter = newEmitter(options.Template)
	emitter.Rate = 0
	emitter.Enabled = true
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.SpreadAngle = spread
	emitter.Speed = NumberRange.new(speed * jitterMin, speed * (jitterMin + jitterRange))
	emitter.Lifetime = NumberRange.new(lifetime)
	emitter.Size = NumberSequence.new(sizeKeypoints)
	emitter.Color = resolveColor(options)
	emitter.Acceleration = Vector3.new(0, -workspace.Gravity * (options.GravityScale or 1), 0)

	-- Drag is what makes a burst read as a BURST rather than as a constant-speed spray: velocity
	-- decays exponentially with time constant 1/Drag, so a particle punches out hard, covers about
	-- Speed/Drag studs in total, and then hangs. It also damps the fall to a terminal
	-- gravity/Drag studs/s, which is why a high Drag and a low GravityScale together give a shape
	-- that expands and then sinks gently instead of arcing.
	if options.Drag and options.Drag > 0 then
		emitter.Drag = options.Drag
	end
	emitter.Rotation = NumberRange.new(0, 360)

	if options.Material ~= nil then
		emitter.LightEmission = options.Material == Enum.Material.Neon and NEON_LIGHT_EMISSION or 0
	end

	if options.SpinSpeed and options.SpinSpeed > 0 then
		local degrees = math.deg(options.SpinSpeed)
		emitter.RotSpeed = NumberRange.new(-degrees, degrees)
	end

	host.Parent = options.Parent or workspace
	emitter.Parent = host
	emitter:Emit(count)

	Debris:AddItem(host, lifetime + CLEANUP_MARGIN)
end

return DebrisBurst
