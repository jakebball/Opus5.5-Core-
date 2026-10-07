local ModelViewport = {}
ModelViewport.__index = ModelViewport
ModelViewport.Tag = "ModelViewport"

const DEFAULT_ZOOM = 1.1
const DEFAULT_ROTATION_SPEED = math.rad(40)
const DEFAULT_TILT = math.rad(-15)
const DEFAULT_FOV = 70

const ATTRIBUTES = { "Zoom", "RotationSpeed", "Tilt", "FOV", "Rotate", "FaceAngle", "Roll",
	"Ambient", "LightColor", "LightDirection" }

function ModelViewport.Start()
	setmetatable(ModelViewport, { __index = ModelViewport.BaseClass })
end

function ModelViewport.new(instance)
	local self = setmetatable(ModelViewport.BaseClass.new(instance), ModelViewport)

	assert(instance:IsA("ViewportFrame"),
		"ModelViewport: tag target must be a ViewportFrame (got " .. instance.ClassName .. ")")

	self.handle = nil
	self.currentModel = nil
	self.overrides = nil

	for _, attr in ATTRIBUTES do
		self.trove:Add(instance:GetAttributeChangedSignal(attr):Connect(function()
			self:_reapply()
		end), "Disconnect")
	end

	-- A Model attribute (a path under ReplicatedStorage.Assets) loads the viewport's own model, so an authored
	-- viewport shows its item with no other code. The StarterGui template is skipped; its PlayerGui copy loads.
	if not instance:IsDescendantOf(game:GetService("StarterGui")) then
		self.trove:Add(instance:GetAttributeChangedSignal("Model"):Connect(function()
			self:_loadAttributeModel()
		end), "Disconnect")
		self:_loadAttributeModel()
	end

	return self
end

function ModelViewport:_opts()
	local zoom = self.instance:GetAttribute("Zoom") or DEFAULT_ZOOM
	if zoom <= 0 then zoom = DEFAULT_ZOOM end
	local opts = {
		padding = 1 / zoom,
		rotationSpeed = self.instance:GetAttribute("RotationSpeed") or DEFAULT_ROTATION_SPEED,
		tilt = self.instance:GetAttribute("Tilt") or DEFAULT_TILT,
		fov = self.instance:GetAttribute("FOV") or DEFAULT_FOV,
		rotate = self.instance:GetAttribute("Rotate") ~= false,
		faceAngle = self.instance:GetAttribute("FaceAngle") or 0,
		roll = self.instance:GetAttribute("Roll") or 0,
		ambient = self.instance:GetAttribute("Ambient"),
		lightColor = self.instance:GetAttribute("LightColor"),
		lightDirection = self.instance:GetAttribute("LightDirection"),
	}
	if self.overrides then
		for key, value in self.overrides do opts[key] = value end
	end
	return opts
end

function ModelViewport:_destroyHandle()
	if self.handle then
		self.handle:Destroy()
		self.handle = nil
	end
end

function ModelViewport:setModel(model, overrides)
	self:_destroyHandle()
	self.currentModel = model
	self.overrides = overrides
	if not model then return end
	self.handle = ModelViewport.ViewportUtils.setup(self.instance, model, self:_opts())
end

function ModelViewport:_loadAttributeModel()
	local path = self.instance:GetAttribute("Model")
	if typeof(path) ~= "string" or path == "" then return end
	local model = ModelViewport.Assets.Get(path)
	if model then
		self:setModel(model, self.overrides)
	end
end

function ModelViewport:getModel()
	return self.handle and self.handle.Model
end

function ModelViewport:getCamera()
	return self.handle and self.handle.Camera
end

function ModelViewport:_reapply()
	if self.currentModel then
		self:setModel(self.currentModel, self.overrides)
	end
end

function ModelViewport:clear()
	self:_destroyHandle()
	self.currentModel = nil
	self.overrides = nil
end

function ModelViewport:destroy()
	self:_destroyHandle()
	self.currentModel = nil
	self.overrides = nil
	self.trove:Clean()
end

return ModelViewport
