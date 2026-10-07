local Collectable = {}
Collectable.__index = Collectable
Collectable.Tag = "Collectable"

local Players = game:GetService("Players")

function Collectable.Start()
	setmetatable(Collectable, { __index = Collectable.BaseClass })
end

function Collectable.new(instance)
	local self = setmetatable({}, Collectable)

	self.trove = Collectable.Trove.new()

	if instance.ClassName == "Model" then

		local hitbox = Instance.new("Part")

		local cframe, size = instance:GetBoundingBox()
		local scale = instance:GetAttribute("HitboxScale") or 1

		hitbox.Size = size * scale
		hitbox.CFrame = cframe
		hitbox.Anchored = false
		hitbox.CanCollide = false
		hitbox.Transparency = 1
		hitbox.CanQuery = true
		hitbox.Parent = instance

		if instance.PrimaryPart then
			local weldConstraint = Instance.new("WeldConstraint")
			weldConstraint.Part0 = hitbox
			weldConstraint.Part1 = instance.PrimaryPart
			weldConstraint.Parent = hitbox
		else
			hitbox.Anchored = true
			warn("[Collectable] No PrimaryPart on model: " .. instance.Name .. " — hitbox anchored")
		end

		self.trove:Add(hitbox)

		self.trove:Add(hitbox.Touched:Connect(function(hit)
			self:touched(hit)
		end))
	else
		local scale = instance:GetAttribute("HitboxScale") or 1
		if scale ~= 1 and instance:IsA("BasePart") then
			local hitbox = Instance.new("Part")
			hitbox.Name = "CollectableHitbox"
			hitbox.Size = instance.Size * scale
			hitbox.CFrame = instance.CFrame
			hitbox.Anchored = instance.Anchored
			hitbox.CanCollide = false
			hitbox.CanTouch = true
			hitbox.CanQuery = true
			hitbox.Transparency = 1
			hitbox.Massless = true
			hitbox.Parent = instance

			if not instance.Anchored then
				local weldConstraint = Instance.new("WeldConstraint")
				weldConstraint.Part0 = hitbox
				weldConstraint.Part1 = instance
				weldConstraint.Parent = hitbox
			end

			self.trove:Add(hitbox)

			self.trove:Add(hitbox.Touched:Connect(function(hit)
				self:touched(hit)
			end))
		else
			self.trove:Add(instance.Touched:Connect(function(hit)
				self:touched(hit)
			end))
		end
	end

	self.playerTouchedEvent = Instance.new("BindableEvent")

	self.instance = instance

	return self
end

function Collectable:touched(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player == nil then return end

	if not self._touchedPlayers then self._touchedPlayers = {} end
	if self._touchedPlayers[player] then return end
	self._touchedPlayers[player] = true

	self.playerTouchedEvent:Fire(player, player.Character)
end

function Collectable:destroy()
	self.trove:Clean()
end

return Collectable