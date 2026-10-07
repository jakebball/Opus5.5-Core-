local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RewardFlyer = {}

local localPlayer = Players.LocalPlayer

const OVERLAY_NAME = "RewardFlyerOverlay"
const DEFAULT_DISPLAY_ORDER = 60
const DEFAULT_FLY_DURATION = 0.55
const DEFAULT_SPAWN_SCALE = 0.06
const DEFAULT_POP_MULTIPLIER = 1.9
const DEFAULT_ARC_HEIGHT = 0.18
const DEFAULT_SPIN_DEGREES = 0
const DEFAULT_GAP = 0.04
const POP_TIME_FRACTION = 0.28
const POP_TIME_CAP = 0.12
const LAND_POP_TIME = 0.12
const LAND_POP_MULTIPLIER = 1.35
const FALLBACK_VIEWPORT = Vector2.new(1024, 576)
const FALLBACK_SOURCE = Vector2.new(0.5, 0.5)
const FALLBACK_TARGET = Vector2.new(0.5, 0.92)

local function viewportSize()
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end
	return FALLBACK_VIEWPORT
end

local function ensureOverlay(displayOrder)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end
	local overlay = playerGui:FindFirstChild(OVERLAY_NAME)
	if not overlay then
		overlay = Instance.new("ScreenGui")
		overlay.Name = OVERLAY_NAME
		overlay.IgnoreGuiInset = true
		overlay.ResetOnSpawn = false
		overlay.DisplayOrder = displayOrder
		overlay.Parent = playerGui
	elseif displayOrder > overlay.DisplayOrder then
		overlay.DisplayOrder = displayOrder
	end
	return overlay
end

local function centreScaleOf(guiObject, viewport)
	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return Vector2.new(
		(position.X + size.X * 0.5) / math.max(1, viewport.X),
		(position.Y + size.Y * 0.5) / math.max(1, viewport.Y)
	)
end

local function resolveScale(object, explicitPosition, viewport, fallback)
	if object and object.Parent then
		return centreScaleOf(object, viewport)
	end
	if typeof(explicitPosition) == "Vector2" then
		return explicitPosition
	end
	if typeof(explicitPosition) == "UDim2" then
		return Vector2.new(explicitPosition.X.Scale, explicitPosition.Y.Scale)
	end
	return fallback
end

local function arcControlBetween(startScale, targetScale, arcHeight)
	return Vector2.new(
		(startScale.X + targetScale.X) * 0.5,
		(startScale.Y + targetScale.Y) * 0.5 - arcHeight
	)
end

function RewardFlyer.fly(flight, parentTrove)
	local onImpact = flight.onImpact
	local overlay = ensureOverlay(flight.displayOrder or DEFAULT_DISPLAY_ORDER)
	if not overlay or not flight.icon then
		if onImpact then onImpact() end
		return
	end

	local viewport = viewportSize()
	local startScale = resolveScale(flight.sourceObject, flight.sourcePosition, viewport, FALLBACK_SOURCE)
	local targetScale = resolveScale(flight.targetObject, flight.targetPosition, viewport, FALLBACK_TARGET)

	local flyDuration = flight.flyDuration or DEFAULT_FLY_DURATION
	local spawnScale = flight.spawnScale or DEFAULT_SPAWN_SCALE
	local popScale = spawnScale * (flight.popMultiplier or DEFAULT_POP_MULTIPLIER)
	local spinDegrees = flight.spinDegrees or DEFAULT_SPIN_DEGREES
	local arcHeight = flight.arcHeight or DEFAULT_ARC_HEIGHT

	local flyer = Instance.new("ImageLabel")
	flyer.Name = "RewardFlyer"
	flyer.BackgroundTransparency = 1
	flyer.Image = flight.icon
	flyer.AnchorPoint = Vector2.new(0.5, 0.5)
	flyer.Position = UDim2.fromScale(startScale.X, startScale.Y)
	flyer.Size = UDim2.fromScale(0, 0)
	flyer.Rotation = 0
	flyer.ZIndex = 10
	if flight.iconColor then flyer.ImageColor3 = flight.iconColor end
	flyer.Parent = overlay

	if flight.gradient then
		local gradient = Instance.new("UIGradient")
		gradient.Color = flight.gradient
		gradient.Rotation = flight.gradientRotation or 90
		gradient.Parent = flyer
	end

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = flyer

	local flyerTrove = parentTrove:Extend()
	flyerTrove:Add(flyer)

	local popTime = math.min(POP_TIME_CAP, flyDuration * POP_TIME_FRACTION)
	local popTween = TweenService:Create(flyer,
		TweenInfo.new(popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(popScale, popScale) })
	popTween:Play()
	popTween.Completed:Connect(function()
		if not flyer.Parent then return end
		local settleTime = math.max(0, flyDuration - popTime)
		if settleTime <= 0 then
			flyer.Size = UDim2.fromScale(spawnScale, spawnScale)
			return
		end
		TweenService:Create(flyer,
			TweenInfo.new(settleTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(spawnScale, spawnScale) }):Play()
	end)

	if spinDegrees ~= 0 then
		TweenService:Create(flyer,
			TweenInfo.new(flyDuration, Enum.EasingStyle.Linear),
			{ Rotation = spinDegrees }):Play()
	end

	local control = flight.arcControl or arcControlBetween(startScale, targetScale, arcHeight)

	local landed = false
	local function land()
		if landed then return end
		landed = true
		flyer.Position = UDim2.fromScale(targetScale.X, targetScale.Y)
		if onImpact then onImpact() end
		local landSize = spawnScale * LAND_POP_MULTIPLIER
		local landPop = TweenService:Create(flyer,
			TweenInfo.new(LAND_POP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(landSize, landSize), ImageTransparency = 1 })
		landPop:Play()
		landPop.Completed:Connect(function()
			flyerTrove:Destroy()
		end)
	end

	-- Quadratic Bezier B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2.
	local startedAt = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not flyer.Parent then
			connection:Disconnect()
			return
		end
		if flight.trackTarget and flight.targetObject and flight.targetObject.Parent then
			targetScale = centreScaleOf(flight.targetObject, viewportSize())
			control = flight.arcControl or arcControlBetween(startScale, targetScale, arcHeight)
		end
		local alpha = math.clamp((os.clock() - startedAt) / flyDuration, 0, 1)
		local oneMinus = 1 - alpha
		local px = oneMinus * oneMinus * startScale.X + 2 * oneMinus * alpha * control.X + alpha * alpha * targetScale.X
		local py = oneMinus * oneMinus * startScale.Y + 2 * oneMinus * alpha * control.Y + alpha * alpha * targetScale.Y
		flyer.Position = UDim2.fromScale(px, py)
		if alpha >= 1 then
			connection:Disconnect()
			land()
		end
	end)
	flyerTrove:Add(connection, "Disconnect")
end

function RewardFlyer.flyMany(opts, parentTrove)
	local flights = opts.flights or {}
	local total = #flights
	if total == 0 then
		if opts.onComplete then opts.onComplete() end
		return
	end

	local completed = 0
	local function markComplete()
		completed += 1
		if completed >= total and opts.onComplete then
			opts.onComplete()
		end
	end

	local function buildFlight(index, chainNext)
		local flight = table.clone(flights[index])
		flight.flyDuration = flight.flyDuration or opts.flyDuration
		flight.spawnScale = flight.spawnScale or opts.spawnScale
		flight.popMultiplier = flight.popMultiplier or opts.popMultiplier
		flight.arcControl = flight.arcControl or opts.arcControl
		flight.arcHeight = flight.arcHeight or opts.arcHeight
		flight.spinDegrees = flight.spinDegrees or opts.spinDegrees
		flight.displayOrder = flight.displayOrder or opts.displayOrder
		if flight.trackTarget == nil then flight.trackTarget = opts.trackTarget end

		local userImpact = flight.onImpact
		flight.onImpact = function()
			if userImpact then userImpact() end
			markComplete()
			if chainNext then chainNext() end
		end
		return flight
	end

	if opts.stagger then
		for index = 1, total do
			task.delay((index - 1) * opts.stagger, function()
				RewardFlyer.fly(buildFlight(index, nil), parentTrove)
			end)
		end
		return
	end

	local gap = opts.gap or DEFAULT_GAP
	local function launch(index)
		local function chainNext()
			if index >= total then return end
			if gap > 0 then
				task.delay(gap, function() launch(index + 1) end)
			else
				launch(index + 1)
			end
		end
		RewardFlyer.fly(buildFlight(index, chainNext), parentTrove)
	end
	launch(1)
end

return RewardFlyer
