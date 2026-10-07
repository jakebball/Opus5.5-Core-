local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EditorMarker = {}
EditorMarker.__index = EditorMarker
EditorMarker.Tag = "EditorMarker"

function EditorMarker.Start()
	setmetatable(EditorMarker, { __index = EditorMarker.BaseClass })
end

function EditorMarker.new(instance)
	local self = setmetatable({}, EditorMarker)

	self.trove = EditorMarker.Trove.new()
	self.instance = instance

	local function setupPart(part)
		part.CanCollide = false
		part.Transparency = 1
	end

	if instance:IsA("BasePart") then
		setupPart(instance)
	elseif instance:IsA("Model") then
		for _,v in instance:GetDescendants() do
			if v:IsA("BasePart") then
				setupPart(v)
			end
		end
	end

	return self
end

function EditorMarker:destroy()
	self.trove:Clean()
end

return EditorMarker