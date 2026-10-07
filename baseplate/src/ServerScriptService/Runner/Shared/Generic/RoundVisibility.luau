local RoundVisibility = {}

const CONFIG_KEY = "ChamberedRoundPart"

local authoredValues = setmetatable({}, { __mode = "k" })

local function applyTo(instance, visible)
	if instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture") then
		local authored = authoredValues[instance]
		if authored == nil then
			authored = instance.Transparency
			authoredValues[instance] = authored
		end
		instance.Transparency = if visible then authored else 1
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") then
		local authored = authoredValues[instance]
		if authored == nil then
			authored = instance.Enabled
			authoredValues[instance] = authored
		end
		instance.Enabled = visible and authored
	end
end

function RoundVisibility.target(weaponModel, itemConfig)
	local partName = itemConfig and itemConfig[CONFIG_KEY]
	if not weaponModel or not partName then return nil end
	return weaponModel:FindFirstChild(partName)
end

function RoundVisibility.set(target, visible)
	if not target then return end

	applyTo(target, visible)
	for _, descendant in target:GetDescendants() do
		applyTo(descendant, visible)
	end
end

return RoundVisibility
