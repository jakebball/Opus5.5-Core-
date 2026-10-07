local EffectUtils = {}

function EffectUtils.Emit(instance)
	if EffectUtils.PlayerSettings and not EffectUtils.PlayerSettings.isVfxEnabled() then return end
	for _, emitter in instance:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			local count = emitter:GetAttribute("EmitCount")
			if typeof(count) == "number" then
				task.delay(emitter:GetAttribute("EmitDelay") or 0, function()
					if emitter.Parent then
						emitter:Emit(count)
					end
				end)
			end
		end
	end
end

function EffectUtils.Toggle(instance, state)
	if state and EffectUtils.PlayerSettings and not EffectUtils.PlayerSettings.isVfxEnabled() then
		state = false
	end
	for _, particle in instance:GetDescendants() do
		if particle:IsA("ParticleEmitter") or particle:IsA("Beam") or particle:IsA("Trail") or particle:IsA("PointLight") or particle:IsA("SpotLight") then
			particle.Enabled = state
		end
	end
end

local function configurePart(part, options)
	part.Anchored = options.anchored == true
	part.CanCollide = options.canCollide == true
	if options.transparency ~= nil then
		part.Transparency = options.transparency
	else
		part.Transparency = 1
	end
end

local function scheduleDestroy(instance, lifetime)
	if not lifetime then return end
	task.delay(lifetime, function()
		if instance and instance.Parent then
			instance:Destroy()
		end
	end)
end

local function lockEmittersToPart(instance)
	for _, v in instance:GetDescendants() do
		if v:IsA("ParticleEmitter") then
			v.LockedToPart = true
		end
	end
end

function EffectUtils.PlayWeldedVFX(template, targetPart, lifetime, options)
	options = options or {}
	if not template or not targetPart then return nil end

	local clone = template:Clone()
	clone.CFrame = targetPart.CFrame
	configurePart(clone, options)
	clone.Parent = options.parent or workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = targetPart
	weld.Part1 = clone
	weld.Parent = clone

	lockEmittersToPart(clone)

	if options.toggle then
		EffectUtils.Toggle(clone, true)
	elseif options.emit ~= false then
		EffectUtils.Emit(clone)
	end

	scheduleDestroy(clone, lifetime)
	return clone
end

function EffectUtils.PlayCharacterVFX(template, player, lifetime, options)
	if not template or not player then return nil end
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then return nil end
	return EffectUtils.PlayWeldedVFX(template, root, lifetime, options)
end

function EffectUtils.PlayCharacterSound(soundTemplate, player, options)
	if not soundTemplate or not player then return nil end
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then return nil end
	return EffectUtils.PlayOneShot(soundTemplate, root, options)
end

function EffectUtils.PlayGroundVFX(template, model, options)
	options = options or {}
	if not template or not model then return nil end

	local cf, size = model:GetBoundingBox()
	local clone = template:Clone()
	local footprint = options.footprintFactor or 2
	clone.Size = Vector3.new(
		math.clamp(size.X * footprint, options.minXZ or 3, options.maxXZ or 12),
		clone.Size.Y,
		math.clamp(size.Z * footprint, options.minXZ or 3, options.maxXZ or 12))
	clone.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.Transparency = 1
	clone.Parent = workspace

	task.delay(options.emitDelay or 0.12, function()
		if clone.Parent then
			EffectUtils.Emit(clone)
		end
	end)
	scheduleDestroy(clone, options.lifetime or 4)
	return clone
end

function EffectUtils.PlayCharacterGroundVFX(template, player, options)
	if not template or not player then return nil end
	local character = player.Character
	if not character then return nil end
	return EffectUtils.PlayGroundVFX(template, character, options)
end

function EffectUtils.PlayAtPosition(template, cframe, parent, options)
	options = options or {}
	if not template then return nil end

	local clone = template:Clone()
	if typeof(cframe) == "Vector3" then
		clone.CFrame = CFrame.new(cframe)
	elseif typeof(cframe) == "CFrame" then
		clone.CFrame = cframe
	end
	if options.anchored == nil then options.anchored = true end
	configurePart(clone, options)
	clone.Parent = parent or workspace

	if options.toggle then
		EffectUtils.Toggle(clone, true)
	elseif options.emit ~= false then
		EffectUtils.Emit(clone)
	end

	scheduleDestroy(clone, options.lifetime)
	return clone
end

function EffectUtils.PlayOneShot(soundTemplate, parentPart, options)
	options = options or {}
	if not soundTemplate or not parentPart then return nil end

	local sound = soundTemplate:Clone()
	if options.volume ~= nil then
		sound.Volume = options.volume
	end
	sound.Parent = parentPart
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	return sound
end

return EffectUtils
