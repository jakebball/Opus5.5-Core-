local PhysicsService = game:GetService("PhysicsService")

return function(FPSViewmodel)

const VIEWMODEL_COLLISION_GROUP = "FPSViewmodel"

local collisionGroupReady = false

local function weldLooseParts(model)
	local primary = model.PrimaryPart
	if not primary then return end

	local jointed = { [primary] = true }
	local changed = true
	while changed do
		changed = false
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Weld") or descendant:IsA("WeldConstraint") or descendant:IsA("Motor6D") then
				local part0, part1 = descendant.Part0, descendant.Part1
				if part0 and part1 then
					if jointed[part0] and not jointed[part1] then
						jointed[part1] = true
						changed = true
					end
					if jointed[part1] and not jointed[part0] then
						jointed[part0] = true
						changed = true
					end
				end
			end
		end
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not jointed[descendant] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = descendant
			weld.Parent = primary
		end
	end
end

local function ensureCollisionGroup()
	if collisionGroupReady then return end
	collisionGroupReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(VIEWMODEL_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(VIEWMODEL_COLLISION_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(VIEWMODEL_COLLISION_GROUP, VIEWMODEL_COLLISION_GROUP, false)
	end)
	pcall(function()
		for _, group in PhysicsService:GetRegisteredCollisionGroups() do
			PhysicsService:CollisionGroupSetCollidable(VIEWMODEL_COLLISION_GROUP, group.name, false)
		end
	end)
end

function FPSViewmodel:_pinNonCollidable(part)
	part.CollisionGroup = VIEWMODEL_COLLISION_GROUP
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

function FPSViewmodel:_buildRig()
	local template = FPSViewmodel.rigTemplate
	if not template then
		warn("[FPSViewmodel] Assets Models/Viewmodel not found — rig not built")
		return
	end

	local rig = template:Clone()
	rig.Name = "ActiveViewmodel"
	self.rig = rig
	self.root = rig.PrimaryPart

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:Destroy() end
	local controller = Instance.new("AnimationController")
	controller.Parent = rig
	local animator = Instance.new("Animator")
	animator.Parent = controller
	self.animator = animator

	if self.root then
		self.root.Anchored = true
	end
	self.weaponJoint = self.root and self.root:FindFirstChild("Main")
	if self.weaponJoint then
		self.mountPart0 = self.weaponJoint.Part0
		self.mountC0 = self.weaponJoint.C0
		self.mountC1 = self.weaponJoint.C1
	end

	ensureCollisionGroup()
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			self:_pinNonCollidable(part)
		end
	end

	self.cameraBone = rig:FindFirstChild("CameraBone")
	self.hipOffset = if self.cameraBone and self.root
		then self.root.CFrame:ToObjectSpace(self.cameraBone.CFrame):Inverse()
		else CFrame.new(0, -1.5, -1.5) * CFrame.Angles(0, math.pi, 0)
	self:_resolveWeaponPoints()

	rig.Parent = self.camera
	self.trove:Add(rig)

	self.trove:Add(rig.AncestryChanged:Connect(function()
		if not self.rig then return end
		if self.rig:IsDescendantOf(game) and self.animationIds and not next(self.tracks) then
			self:_playEquip()
		end
	end), "Disconnect")
end

function FPSViewmodel:_resolveWeaponPoints()
	local source = self.weapon or self.rig
	self.barrel = source and source:FindFirstChild("BarrelAttachment", true) or nil
	self.muzzle = source and source:FindFirstChild("Muzzle", true) or nil
	self.muzzleFlash = source and source:FindFirstChild("MuzzleFlash", true) or nil
	self.adsAttachment = source and source:FindFirstChild("ADSAttachment", true) or nil
end

function FPSViewmodel:setWeapon(template, animationIds)
	self:clearWeapon()
	if not self.rig or not template then return end

	local weapon = template:Clone()
	weldLooseParts(weapon)
	for _, part in weapon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			self:_pinNonCollidable(part)
		end
	end

	weapon:PivotTo(self.root and self.root.CFrame or CFrame.identity)
	weapon.Parent = self.rig
	if self.weaponJoint then
		self:_applyMount(template)
		self.weaponJoint.Part1 = weapon.PrimaryPart or weapon:FindFirstChildWhichIsA("BasePart")
	end
	self.weapon = weapon
	-- A per-equip Heartbeat watchdog used to live here. It was added to the component trove on
	-- every setWeapon, so it was only ever cleaned when the player left: swapping weapons leaked
	-- one connection per equip and it never stopped running after it fired once.
	self:_resolveWeaponPoints()
	self:setAnimations(animationIds)
end

function FPSViewmodel:clearWeapon()
	self:setAnimations(nil)
	self:_restoreMount()
	if self.weaponJoint then
		self.weaponJoint.Part1 = nil
	end
	if self.weapon then
		self.weapon:Destroy()
		self.weapon = nil
	end
	self:_resolveWeaponPoints()
end

function FPSViewmodel:_applyMount(template)
	if not self.weaponJoint or not self.rig then return end

	local mountName = template:GetAttribute("ViewmodelMount")
	local mountGrip = template:GetAttribute("ViewmodelGrip")
	local mountGripC1 = template:GetAttribute("ViewmodelGripC1")
	local mountPart = mountName and self.rig:FindFirstChild(mountName, true)
	if not mountPart or not mountPart:IsA("BasePart") or typeof(mountGrip) ~= "CFrame" then
		self:_restoreMount()
		return
	end

	self.weaponJoint.Part0 = mountPart
	self.weaponJoint.C0 = mountGrip
	-- Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse(), so an authored C1 can only be
	-- dropped while the clips leave the weapon's own Transform at identity. The sword is posed
	-- through this joint in first person, so its C1 has to be carried rather than assumed away.
	self.weaponJoint.C1 = if typeof(mountGripC1) == "CFrame" then mountGripC1 else CFrame.identity
end

function FPSViewmodel:_restoreMount()
	if not self.weaponJoint or not self.mountPart0 then return end

	self.weaponJoint.Part0 = self.mountPart0
	self.weaponJoint.C0 = self.mountC0
	self.weaponJoint.C1 = self.mountC1
end

end
