local RunService = game:GetService("RunService")

local ViewportUtils = {}

local DEFAULT_ROTATION_SPEED = math.rad(40)
local DEFAULT_TILT = math.rad(-15)
local DEFAULT_FOV = 70
local DEFAULT_PADDING = 1.15
local DEFAULT_AMBIENT = Color3.fromRGB(100, 100, 100)
local DEFAULT_LIGHT_COLOR = Color3.fromRGB(255, 250, 240)
local DEFAULT_LIGHT_DIRECTION = Vector3.new(-0.3, -1, -0.2)

local function prepareClone(model, keepHumanoid)
	local clone = model:Clone()
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
		elseif desc:IsA("BaseScript") then
			desc:Destroy()
		elseif desc:IsA("Humanoid") and not keepHumanoid then
			desc:Destroy()
		end
	end
	return clone
end

local function centreOnOrigin(clone)
	clone.PrimaryPart = nil
	local bboxCF = clone:GetBoundingBox()
	clone.WorldPivot = CFrame.new(bboxCF.Position)
	clone:PivotTo(CFrame.new())
end

function ViewportUtils.setup(viewportFrame, model, options)
	assert(typeof(viewportFrame) == "Instance" and viewportFrame:IsA("ViewportFrame"),
		"ViewportUtils.setup: expected a ViewportFrame as arg 1")
	assert(typeof(model) == "Instance" and model:IsA("Model"),
		"ViewportUtils.setup: expected a Model as arg 2")

	options = options or {}
	local rotationSpeed = options.rotationSpeed or DEFAULT_ROTATION_SPEED
	local tilt = options.tilt or DEFAULT_TILT
	local fov = options.fov or DEFAULT_FOV
	local padding = options.padding or DEFAULT_PADDING
	local rotate = options.rotate ~= false
	local faceAngle = options.faceAngle or 0
	local roll = options.roll or 0
	local yOffset = options.yOffset
	if yOffset == nil then yOffset = model:GetAttribute("ViewportYOffset") end
	if yOffset == nil then yOffset = 0 end

	for _, child in viewportFrame:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") or child:IsA("BasePart") then
			child:Destroy()
		end
	end

	local clone = prepareClone(model, options.keepHumanoid)
	centreOnOrigin(clone)
	local _, size = clone:GetBoundingBox()

	-- A ViewportFrame has no simulation step: parented straight to it, a track reports playing and
	-- never moves. A WorldModel is the container that gives its contents one at runtime. Do NOT reach
	-- for Animator:StepAnimations instead -- it is PluginSecurity and throws from a LocalScript.
	local container = viewportFrame
	if options.worldModel then
		container = Instance.new("WorldModel")
		container.Parent = viewportFrame
	end

	clone.Parent = container

	local radius = size.Magnitude / 2 * padding
	local halfFov = math.rad(fov / 2)
	local distance = radius / math.tan(halfFov)

	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.new(0, 0, 0))
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	viewportFrame.Ambient = options.ambient or DEFAULT_AMBIENT
	viewportFrame.LightColor = options.lightColor or DEFAULT_LIGHT_COLOR
	viewportFrame.LightDirection = (options.lightDirection or DEFAULT_LIGHT_DIRECTION).Unit

	local offsetCF = if yOffset ~= 0 then CFrame.new(0, yOffset, 0) else CFrame.identity
	-- Roll turns the whole picture about the camera's axis, outside the tilt and the spin.
	if roll ~= 0 then
		offsetCF *= CFrame.Angles(0, 0, roll)
	end

	local connection
	if rotate then
		local yaw = faceAngle
		connection = RunService.Heartbeat:Connect(function(deltaTime)
			if not clone.Parent then
				if connection then connection:Disconnect(); connection = nil end
				return
			end
			yaw = (yaw + rotationSpeed * deltaTime) % (math.pi * 2)
			clone:PivotTo(offsetCF * CFrame.Angles(tilt, yaw, 0))
		end)
	else
		clone:PivotTo(offsetCF * CFrame.Angles(tilt, faceAngle, 0))
	end

	local handle = {}
	function handle:Destroy()
		if connection then connection:Disconnect(); connection = nil end
		if clone and clone.Parent then clone:Destroy() end
		if container ~= viewportFrame and container.Parent then container:Destroy() end
		if camera and camera.Parent then camera:Destroy() end
	end
	handle.Model = clone
	handle.Camera = camera

	return handle
end

return ViewportUtils
