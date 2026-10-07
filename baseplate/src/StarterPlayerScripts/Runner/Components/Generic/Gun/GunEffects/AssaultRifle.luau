
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectUtils = require(ReplicatedStorage:WaitForChild("Shared").Generic.EffectUtils)

local AssaultRifle = {}

const FULL_TURN = 360
const FLASH_PART = "MuzzleFlash"

local baseRotations = setmetatable({}, { __mode = "k" })

local function emitFlash(container)
	if not container then return end

	local spin = math.random() * FULL_TURN
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local baseRotation = baseRotations[descendant]
			if not baseRotation then
				baseRotation = descendant.Rotation.Min
				baseRotations[descendant] = baseRotation
			end
			local angle = (baseRotation + spin) % FULL_TURN
			descendant.Rotation = NumberRange.new(angle, angle)
		end
	end

	EffectUtils.Emit(container)
end

function AssaultRifle.Fire(viewmodel)
	if not viewmodel then return end
	emitFlash(viewmodel:getMuzzleFlash())
end

function AssaultRifle.FireWorld(weaponModel)
	if not weaponModel then return end
	emitFlash(weaponModel:FindFirstChild(FLASH_PART))
end

return AssaultRifle
