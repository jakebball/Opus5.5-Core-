-- AxisSquish: anisotropic part-deformation as a per-instance component. Attach it to a
-- Model/Tool with EntityStore.addComponent(instance, "AxisSquish", options); the returned
-- component captures the rest size/CFrame of every BasePart once, then :apply(scale) squishes
-- the chosen axis (bulging the other two) and :restore() returns to rest. Lifetime is bound to
-- the instance: when the instance is destroyed the component is torn down and parts are restored,
-- so callers never manage a free-floating squish object's lifetime themselves.
--
-- options = {
--   axis = "X" | "Y" | "Z",        -- squished axis (default "Y")
--   anchor = "min" | "center" | "max", -- plane the squished axis collapses toward (default "min")
--   squishTarget = number,         -- scale at full squish, drives the width bulge (default 0.6)
--   widthAtSquish = number,        -- bulge factor on the other two axes at full squish (default 1)
--   sizeOnly = boolean,            -- resize parts about their own centre, skip the CFrame reposition
--                                  --   (welded/unanchored parts whose welds would fight a CFrame move)
--   root = BasePart,               -- capture/apply in this part's object space so the squish rides
--                                  --   along when something re-pivots the model each frame
--   ignore = (part) -> boolean,    -- skip captured parts for which this returns true
-- }
local AxisSquish = {}
AxisSquish.__index = AxisSquish
AxisSquish.Tag = "AxisSquish"

const AXIS_INDEX = { X = 1, Y = 2, Z = 3 }

local function axisValue(vector, axisIndex)
	if axisIndex == 1 then return vector.X end
	if axisIndex == 2 then return vector.Y end
	return vector.Z
end

function AxisSquish.Start()
	setmetatable(AxisSquish, { __index = AxisSquish.BaseClass })
end

function AxisSquish.new(instance, options)
	local self = setmetatable(AxisSquish.BaseClass.new(instance), AxisSquish)
	self:_capture(options)
	self.trove:Add(function()
		self:restore()
	end)
	return self
end

function AxisSquish:_capture(options)
	options = options or {}
	local axisIndex = AXIS_INDEX[options.axis or "Y"] or 2
	local anchorMode = options.anchor or "min"

	self.axisIndex = axisIndex
	self.widthAtSquish = options.widthAtSquish or 1
	self.squishTarget = options.squishTarget or 0.6
	self.sizeOnly = options.sizeOnly == true
	self.root = options.root
	self.progress = 0

	local root = self.root
	local ignore = options.ignore
	local target = self.instance
	local primary = target:IsA("Model") and target.PrimaryPart or nil
	local rootCFrame = root and root.CFrame

	local parts = {}
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root and descendant ~= primary
			and not (ignore and ignore(descendant)) then
			local cframe = rootCFrame and rootCFrame:ToObjectSpace(descendant.CFrame) or descendant.CFrame
			table.insert(parts, { instance = descendant, size = descendant.Size, cframe = cframe })
		end
	end
	self.parts = parts

	local minBound = Vector3.new(math.huge, math.huge, math.huge)
	local maxBound = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, record in parts do
		local half = record.size / 2
		local position = record.cframe.Position
		minBound = minBound:Min(position - half)
		maxBound = maxBound:Max(position + half)
	end
	local center = (minBound + maxBound) / 2
	local anchorBound = if anchorMode == "max" then maxBound elseif anchorMode == "center" then center else minBound

	self.center = center
	self.anchorPlane = axisValue(anchorBound, axisIndex)
end

function AxisSquish:apply(scale)
	local progress = (1 - scale) / (1 - self.squishTarget)
	local bulge = 1 + (self.widthAtSquish - 1) * progress
	self.progress = math.clamp(progress, 0, 1)

	local axisIndex = self.axisIndex
	local center = self.center
	local anchorPlane = self.anchorPlane
	local rootCFrame = self.root and self.root.CFrame
	local sizeOnly = self.sizeOnly

	local scaleX = if axisIndex == 1 then scale else bulge
	local scaleY = if axisIndex == 2 then scale else bulge
	local scaleZ = if axisIndex == 3 then scale else bulge

	local anchorX = if axisIndex == 1 then anchorPlane else center.X
	local anchorY = if axisIndex == 2 then anchorPlane else center.Y
	local anchorZ = if axisIndex == 3 then anchorPlane else center.Z

	for _, record in self.parts do
		local part = record.instance
		if part.Parent then
			local size = record.size
			part.Size = Vector3.new(size.X * scaleX, size.Y * scaleY, size.Z * scaleZ)
			if not sizeOnly then
				local position = record.cframe.Position
				local squishedX = anchorX + (position.X - anchorX) * scaleX
				local squishedY = anchorY + (position.Y - anchorY) * scaleY
				local squishedZ = anchorZ + (position.Z - anchorZ) * scaleZ
				local localCF = record.cframe.Rotation + Vector3.new(squishedX, squishedY, squishedZ)
				part.CFrame = if rootCFrame then rootCFrame * localCF else localCF
			end
		end
	end
end

function AxisSquish:restore()
	self:apply(1)
end

function AxisSquish:destroy()
	self.trove:Clean()
end

return AxisSquish
