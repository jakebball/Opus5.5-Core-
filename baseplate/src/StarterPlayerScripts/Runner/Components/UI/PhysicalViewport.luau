local PhysicalViewport = {}
PhysicalViewport.__index = PhysicalViewport
PhysicalViewport.Tag = "PhysicalViewport"

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

const DEFAULT_DEPTH = 30
const DEFAULT_FIT_PADDING = 1.1
const TICK_PRIORITY = Enum.RenderPriority.Camera.Value + 2
const DEFAULT_ROTATE_SENSITIVITY = 0.5
const DRAG_SURFACE_NAME = "ViewportDragSurface"
const DEFAULT_ROTATE_DAMPING = 4
const VELOCITY_BLEND = 0.6
const MIN_SPIN_VELOCITY = 1

local bindCounter = 0

local function lerp(from, to, alpha)
	return from + (to - from) * alpha
end

local function accumulateBounds(minCorner, maxCorner, referenceFrame, part)
	local relative = referenceFrame:ToObjectSpace(part.CFrame)
	local halfSize = part.Size / 2
	local rightAxis, upAxis, backAxis = relative.RightVector, relative.UpVector, -relative.LookVector
	local extent = Vector3.new(
		math.abs(rightAxis.X) * halfSize.X + math.abs(upAxis.X) * halfSize.Y + math.abs(backAxis.X) * halfSize.Z,
		math.abs(rightAxis.Y) * halfSize.X + math.abs(upAxis.Y) * halfSize.Y + math.abs(backAxis.Y) * halfSize.Z,
		math.abs(rightAxis.Z) * halfSize.X + math.abs(upAxis.Z) * halfSize.Y + math.abs(backAxis.Z) * halfSize.Z
	)
	local center = relative.Position
	local low, high = center - extent, center + extent
	return (if minCorner then minCorner:Min(low) else low), (if maxCorner then maxCorner:Max(high) else high)
end

function PhysicalViewport.Start()
	setmetatable(PhysicalViewport, { __index = PhysicalViewport.BaseClass })
end

function PhysicalViewport.new(instance)
	local self = PhysicalViewport.BaseClass.new(instance)
	setmetatable(self, PhysicalViewport)

	self.frame = instance
	self.depth = instance:GetAttribute("Depth") or DEFAULT_DEPTH
	self.cameraRelative = instance:GetAttribute("CameraRelative") == true
	self.fit = instance:GetAttribute("Fit") == true
	self.fitPadding = instance:GetAttribute("FitPadding") or DEFAULT_FIT_PADDING
	self.model = nil
	self.measureFilter = nil
	self.centerOnExtents = instance:GetAttribute("CenterOnExtents") == true
	self.rotation = CFrame.identity
	self._fitScale = 1
	self._centerOffset = CFrame.identity

	self.mouseRotate = instance:GetAttribute("MouseRotate") == true
	self.rotateSensitivity = instance:GetAttribute("MouseRotateSensitivity") or DEFAULT_ROTATE_SENSITIVITY
	self.rotateDamping = instance:GetAttribute("MouseRotateDamping") or DEFAULT_ROTATE_DAMPING
	self.dragYawVelocity = 0
	self.dragPitchVelocity = 0
	self.dragLastMoveTime = nil
	self.dragRotation = CFrame.identity
	self.dragInput = nil
	self.dragLastPosition = nil
	self.dragTrove = PhysicalViewport.Trove.new()
	self.trove:Add(self.dragTrove)

	bindCounter += 1
	self._bindName = "PhysicalViewport_" .. tostring(bindCounter)

	self.trove:Add(instance:GetAttributeChangedSignal("Depth"):Connect(function()
		self.depth = instance:GetAttribute("Depth") or DEFAULT_DEPTH
		self:_applyFit()
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("CameraRelative"):Connect(function()
		self.cameraRelative = instance:GetAttribute("CameraRelative") == true
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("CenterOnExtents"):Connect(function()
		self.centerOnExtents = instance:GetAttribute("CenterOnExtents") == true
		self:_updateCenterOffset()
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("Fit"):Connect(function()
		self.fit = instance:GetAttribute("Fit") == true
		self:_applyFit()
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("FitPadding"):Connect(function()
		self.fitPadding = instance:GetAttribute("FitPadding") or DEFAULT_FIT_PADDING
		self:_applyFit()
	end))
	self.trove:Add(instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_applyFit()
	end))

	self.trove:Add(instance:GetAttributeChangedSignal("MouseRotate"):Connect(function()
		self:setMouseRotate(instance:GetAttribute("MouseRotate") == true)
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("MouseRotateSensitivity"):Connect(function()
		self.rotateSensitivity = instance:GetAttribute("MouseRotateSensitivity") or DEFAULT_ROTATE_SENSITIVITY
	end))
	self.trove:Add(instance:GetAttributeChangedSignal("MouseRotateDamping"):Connect(function()
		self.rotateDamping = instance:GetAttribute("MouseRotateDamping") or DEFAULT_ROTATE_DAMPING
	end))

	self.trove:Add(instance:GetAttributeChangedSignal("Rotation"):Connect(function()
		self:_applyRotationAttribute()
	end))

	self:_applyRotationAttribute()
	self:_bindMouseRotate()
	self:_applyMouseRotate()

	RunService:BindToRenderStep(self._bindName, TICK_PRIORITY, function(deltaTime)
		self:_updateSpin(deltaTime)
		self:_tick()
	end)
	self.trove:Add(function()
		RunService:UnbindFromRenderStep(self._bindName)
	end)

	return self
end

function PhysicalViewport:setModel(model)
	if model == self.model then
		self:_applyFit()
		self:_tick()
		return
	end

	self:resetScale()
	self.model = model
	self._fitScale = 1
	if model then self:_applyFit() end
	self:_updateCenterOffset()
	self:_tick()
end

function PhysicalViewport:place()
	self:_tick()
end

function PhysicalViewport:setMeasureFilter(filter)
	self.measureFilter = filter
	self:_applyFit()
	self:_updateCenterOffset()
end

function PhysicalViewport:resetScale()
	local model = self.model
	if not model or not model:IsA("Model") then return end
	if self._fitScale > 0 and self._fitScale ~= 1 then
		model:ScaleTo(model:GetScale() / self._fitScale)
	end
	self._fitScale = 1
end

function PhysicalViewport:setRotation(rotation)
	self.rotation = rotation or CFrame.identity
end

function PhysicalViewport:setCameraRelative(enabled)
	self.cameraRelative = enabled and true or false
end

function PhysicalViewport:getModel()
	return self.model
end

function PhysicalViewport:_measureBounds()
	local model = self.model
	if not model or not model:IsA("Model") then return nil, nil end

	if not self.measureFilter then
		local boundingCFrame, size = model:GetBoundingBox()
		return size, model:GetPivot():ToObjectSpace(boundingCFrame).Position
	end

	local pivot = model:GetPivot()
	local minCorner, maxCorner
	for _, child in model:GetChildren() do
		if self.measureFilter(child) then
			if child:IsA("BasePart") then
				minCorner, maxCorner = accumulateBounds(minCorner, maxCorner, pivot, child)
			end
			for _, descendant in child:GetDescendants() do
				if descendant:IsA("BasePart") then
					minCorner, maxCorner = accumulateBounds(minCorner, maxCorner, pivot, descendant)
				end
			end
		end
	end
	if not minCorner then return nil, nil end
	return maxCorner - minCorner, (minCorner + maxCorner) / 2
end

-- Scales the model so its bounding sphere fills the frame at the current depth.
-- Apparent size = (worldRadius / depth); we solve for the scale that makes the
-- model's projected radius match the frame's angular half-extent.
function PhysicalViewport:_applyFit()
	if not self.fit then return end
	local model = self.model
	if not model or not model:IsA("Model") then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	if self._fitScale > 0 and self._fitScale ~= 1 then
		model:ScaleTo(model:GetScale() / self._fitScale)
	end
	self._fitScale = 1

	local measuredSize = self:_measureBounds()
	if not measuredSize then return end
	local radius = measuredSize.Magnitude / 2
	if radius <= 0 then return end

	local viewportSize = camera.ViewportSize
	local frameSize = self.frame.AbsoluteSize
	if viewportSize.Y <= 0 or frameSize.Y <= 0 then return end

	local worldHalfHeight = self.depth * math.tan(math.rad(camera.FieldOfView) / 2) * (frameSize.Y / viewportSize.Y)
	local worldHalfWidth = worldHalfHeight * (frameSize.X / frameSize.Y)
	local scale = math.min(worldHalfHeight, worldHalfWidth) / (radius * self.fitPadding)
	if scale <= 0 then return end

	self._fitScale = scale
	model:ScaleTo(model:GetScale() * scale)
	self:_updateCenterOffset()
end

function PhysicalViewport:_updateCenterOffset()
	self._centerOffset = CFrame.identity
	if not self.centerOnExtents then return end

	local _, center = self:_measureBounds()
	if not center then return end
	self._centerOffset = CFrame.new(-center)
end

function PhysicalViewport:_isFrameVisible()
	local node = self.frame
	while node do
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

function PhysicalViewport:_basePose(camera)
	if not self:_isFrameVisible() then return nil end

	local center = self.frame.AbsolutePosition + self.frame.AbsoluteSize / 2
	local screenGui = self.frame:FindFirstAncestorWhichIsA("ScreenGui")
	if not (screenGui and screenGui.IgnoreGuiInset) then
		center += GuiService:GetGuiInset()
	end
	local ray = camera:ViewportPointToRay(center.X, center.Y)
	local pos = ray.Origin + ray.Direction * self.depth
	-- The model takes the camera's own axes and turns to face it, rather than being AIMED at the
	-- camera's position. Aiming points it back down the ray through the frame's centre, so a frame
	-- 27% across the screen is yawed 22.9 degrees off square and tipped backwards by the camera's
	-- pitch -- 8 to 16 degrees over this game's menu flythrough, animating through a dolly and
	-- snapping at every cut. Copying the rotation stands it upright and square-on in camera space
	-- wherever the frame sits, and it is what _spinBy already assumes when it calls the base pose's
	-- axes the screen's.
	if self.cameraRelative then
		return CFrame.new(pos) * camera.CFrame.Rotation * CFrame.Angles(0, math.pi, 0)
	end
	return CFrame.new(pos)
end

function PhysicalViewport:_tick()
	local model = self.model
	if not model or not model.Parent then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local base = self:_basePose(camera)
	if not base then return end

	local cf = base * self.dragRotation * self.rotation * self._centerOffset
	if model:IsA("BasePart") then
		model.CFrame = cf
	elseif model:IsA("Model") then
		model:PivotTo(cf)
	end
end

-- Opt-in, because every other consumer of this component (the menu character) wants a model
-- that holds the pose it was given.
-- The resting angle as Euler degrees on the frame, so how a model sits is tuned in the
-- Explorer alongside the rest of the panel's look rather than being a constant in a consumer.
-- setRotation stays the code-side entry point and simply loses to a later attribute change.
function PhysicalViewport:_applyRotationAttribute()
	local rotation = self.frame:GetAttribute("Rotation")
	if typeof(rotation) ~= "Vector3" then return end

	self:setRotation(CFrame.Angles(
		math.rad(rotation.X),
		math.rad(rotation.Y),
		math.rad(rotation.Z)
	))
end

function PhysicalViewport:setMouseRotate(enabled)
	enabled = enabled == true
	if enabled == self.mouseRotate then return end

	self.mouseRotate = enabled
	self:_applyMouseRotate()

	if not enabled then
		self.dragInput = nil
		self:resetRotation()
	end
end

function PhysicalViewport:isMouseRotating()
	return self.dragInput ~= nil
end

function PhysicalViewport:resetRotation()
	self.dragYawVelocity = 0
	self.dragPitchVelocity = 0
	self.dragRotation = CFrame.identity
end

function PhysicalViewport:_applyMouseRotate()
	self.dragTrove:Clean()

	if not (self.mouseRotate and self.frame:IsA("GuiObject")) then return end

	local stale = self.frame:FindFirstChild(DRAG_SURFACE_NAME)
	if stale then
		stale:Destroy()
	end

	local surface = self.dragTrove:Add(Instance.new("TextButton"))
	surface.Name = DRAG_SURFACE_NAME
	surface.Size = UDim2.fromScale(1, 1)
	surface.BackgroundTransparency = 1
	surface.Text = ""
	surface.AutoButtonColor = false
	surface.ZIndex = self.frame.ZIndex
	surface.Parent = self.frame

	self.dragTrove:Add(surface.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		self.dragInput = input
		self.dragLastPosition = Vector2.new(input.Position.X, input.Position.Y)
		self.dragLastMoveTime = os.clock()
		self.dragYawVelocity = 0
		self.dragPitchVelocity = 0
	end))
end

function PhysicalViewport:_bindMouseRotate()
	if not self.frame:IsA("GuiObject") then return end

	self.trove:Add(UserInputService.InputChanged:Connect(function(input)
		if not self.dragInput then return end
		local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
		if not (isMouseMove or input == self.dragInput) then return end

		local position = Vector2.new(input.Position.X, input.Position.Y)
		local previous = self.dragLastPosition
		self.dragLastPosition = position
		if not previous then return end

		self:_applyDrag(position - previous)
	end))

	self.trove:Add(UserInputService.InputEnded:Connect(function(input)
		if not self.dragInput then return end
		if input == self.dragInput or input.UserInputType == self.dragInput.UserInputType then
			self.dragInput = nil
			self.dragLastPosition = nil
		end
	end))
end

function PhysicalViewport:_applyDrag(delta)
	local yawDegrees = delta.X * self.rotateSensitivity
	local pitchDegrees = -delta.Y * self.rotateSensitivity

	self:_spinBy(yawDegrees, pitchDegrees)

	local now = os.clock()
	local elapsed = now - (self.dragLastMoveTime or now)
	self.dragLastMoveTime = now
	if elapsed <= 0 then return end

	self.dragYawVelocity = lerp(self.dragYawVelocity, yawDegrees / elapsed, VELOCITY_BLEND)
	self.dragPitchVelocity = lerp(self.dragPitchVelocity, pitchDegrees / elapsed, VELOCITY_BLEND)
end

-- The accumulated orientation is a CFrame composed one increment at a time, NOT a stored yaw and
-- pitch. Left-multiplying applies each increment in the frame immediately outside it -- the base
-- pose, whose axes are the screen's -- so horizontal drag turns about screen-up and vertical drag
-- about screen-right however far the model has already been turned.
--
-- Storing Euler angles is what forced the old pitch limit: pitch has to stop before vertical, or
-- the yaw axis collapses onto the view axis and horizontal drag degenerates into roll. Accumulated
-- rotations have no such pole, so the model spins freely and endlessly on both axes and there is
-- nothing left to clamp.
function PhysicalViewport:_spinBy(yawDegrees, pitchDegrees)
	if yawDegrees == 0 and pitchDegrees == 0 then return end

	local composed = CFrame.Angles(math.rad(pitchDegrees), math.rad(yawDegrees), 0) * self.dragRotation

	local right = composed.RightVector.Unit
	local up = composed.UpVector
	up = (up - right * up:Dot(right)).Unit
	self.dragRotation = CFrame.fromMatrix(Vector3.zero, right, up)
end

-- The throw. Velocity ALWAYS bleeds off, but only carries the model while the pointer is up: that
-- way holding still mid-drag decays it to nothing, so letting go after a pause does not fling, and
-- the release inherits whatever the last moments of movement actually were.
--
-- Decay is exponential in real time (e^-kt) rather than a per-frame multiplier, so the model coasts
-- for the same duration at 30fps as at 240.
function PhysicalViewport:_updateSpin(deltaTime)
	if not self.mouseRotate or deltaTime <= 0 then return end
	if self.dragYawVelocity == 0 and self.dragPitchVelocity == 0 then return end

	if not self.dragInput then
		self:_spinBy(self.dragYawVelocity * deltaTime, self.dragPitchVelocity * deltaTime)
	end

	local decay = math.exp(-self.rotateDamping * deltaTime)
	self.dragYawVelocity *= decay
	self.dragPitchVelocity *= decay

	if math.abs(self.dragYawVelocity) < MIN_SPIN_VELOCITY then
		self.dragYawVelocity = 0
	end
	if math.abs(self.dragPitchVelocity) < MIN_SPIN_VELOCITY then
		self.dragPitchVelocity = 0
	end
end

function PhysicalViewport:destroy()
	self.trove:Clean()
end

return PhysicalViewport
