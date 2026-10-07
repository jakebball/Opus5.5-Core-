-- FPSViewmodel (client, generic) — a first-person arms/weapon viewmodel pinned to
-- the camera, tuned for the Server-Authority movement model.
--
-- The rig template (Assets.Models.Viewmodel) is cloned under workspace.CurrentCamera
-- with its root ANCHORED and driven by CFrame each frame; its Motor6D limbs follow,
-- with a LoadAnimation track posing on top. Animation ids come from the equipped item's
-- ViewmodelAnimations config table, pushed in by :setWeapon and played by name via
-- :play("Idle" / "Equip" / "Reload" / ...).
--
-- The rig ships with no weapon: its HumanoidRootPart carries an empty `Main` Motor6D
-- (the mount joint, C0/C1 authored with the rig). :setWeapon(template) clones a weapon
-- Model (e.g. Assets.Models.Weapons.AssaultRifle, root part named Main) into the rig
-- and links the joint's Part1 to it, so the existing animations pose it.
--
-- A weapon whose clips were authored off a LIMB rather than the rig root (the build hammer
-- swings from the right hand) re-points that joint instead: `ViewmodelMount` names the rig
-- part, `ViewmodelGrip` carries the C0 authored against it and the optional `ViewmodelGripC1`
-- the authored C1, all attributes on the weapon Model. The authored root mount is restored on clearWeapon, so a weapon without them is
-- mounted exactly as before.
--
-- Enabled by default: Start() tags the LocalPlayer so the component attaches on its
-- own. Combat/round code drives the live instance through the public API:
--   :setAds(bool)         aim-down-sights toggle (also bound to RMB)
--   :addRecoil(b, u, r)   kick the viewmodel on a shot (back, up, roll)
--   :setEnabled(bool)     show/hide the whole viewmodel
--   :setWeapon(t, ids)    mount a weapon Model on the rig's mount joint, with its clips
--   :setAnimations(ids)   adopt a clip set and play its equip into its hold pose
--   :clearWeapon()        unmount the current weapon
--   :play(name, opts)     play a clip of the equipped set by name, returns the track
--   :getBarrel()          the BarrelAttachment (muzzle) for VFX/raycasts
--   :getMuzzle()          the Muzzle Attachment on the equipped weapon
--   :getMuzzleFlash()     the weapon's MuzzleFlash Part (hosts the fire-VFX emitters)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")

local localPlayer = Players.LocalPlayer

local ViewmodelMotion = require(script.ViewmodelMotion)

local FPSViewmodel = {}
FPSViewmodel.__index = FPSViewmodel
FPSViewmodel.Tag = "FPSViewmodel"

const EXTRA_OFFSET = Vector3.new(0, 0, 0)





const TUNING = ViewmodelMotion.TUNING




function FPSViewmodel.Start()
	setmetatable(FPSViewmodel, { __index = FPSViewmodel.BaseClass })
	FPSViewmodel.rigTemplate = FPSViewmodel.Assets.Get("Models/Viewmodel")
	FPSViewmodel.Observers.observePlayer(function(player)
		if player == localPlayer then
			player:AddTag(FPSViewmodel.Tag)
		end
	end)
end

function FPSViewmodel.new(instance)
	local self = setmetatable(FPSViewmodel.BaseClass.new(instance), FPSViewmodel)
	if instance ~= localPlayer then return self end

	self.camera = workspace.CurrentCamera
	self.enabled = true
	self.tracks = {}
	self.animationInstances = {}
	self.animationIds = nil
	self.locomotionTracks = {}
	self.locomotionInstances = {}
	self.locomotionIds = nil
	self.locomotionResolved = {}
	self.lastRecoilClock = 0
	-- The state names belong to ViewmodelAnimator; nil here just means "not resolved yet" and
	-- _updateAnimationState fills it on the first frame.
	self.animState = nil
	self.actionClip = nil
	self.extraOffset = EXTRA_OFFSET

	self.adsAlpha = 0
	self.adsTarget = 0
	self.adsBlend = 0
	self.swayPos = Vector2.zero
	self.swayVel = Vector2.zero
	self.bobTime = 0
	self.recoilPos = Vector3.zero
	self.recoilVel = Vector3.zero
	self.recoilRot = Vector3.zero
	self.recoilRotVel = Vector3.zero

	self:_buildRig()
	self:_bindBody()
	self:_bindInput()
	-- No _bindCamera: StarterPlayer.CameraMode is already LockFirstPerson in this place, and
	-- Generic/FreeCursor owns that property while the cursor is released. A second writer
	-- would snap the camera back mid-inspection.
	self:_bindRender()

	return self
end




-- Start hidden. Nothing in this place wants bare floating arms on screen. Gun:setWeapon and
-- HeldProp:_sync are what turn it on, and only once there is something to hold -- which as of
-- 2026-09-03 is every item in the starting kit.
function FPSViewmodel:_bindBody()
	self:setEnabled(false)
end

function FPSViewmodel:_bindInput()
	self.trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:setAds(true)
		end
	end))
	self.trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:setAds(false)
		end
	end))
end

function FPSViewmodel:_bindRender()
	
	self.trove:Add(RunService.RenderStepped:Connect(function(deltaTime)
		self:_update(deltaTime)
	end))
end

-- The boilerplate's Server-Authority movement bodies (workspace.MovementBodies) were never
-- brought over, so this returned nil forever: _planarSpeed read 0, the bob never ran and the
-- viewmodel sat frozen while you walked. Same fallback Gun:_playerPart already carries.
function FPSViewmodel:_findBody()
	local folder = workspace:FindFirstChild("MovementBodies")
	local body = folder and folder:FindFirstChild(localPlayer.Name .. "_Body")
	if body then return body end

	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function FPSViewmodel:_planarSpeed()
	local body = self:_findBody()
	if not body then return 0 end
	local velocity = body.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

function FPSViewmodel:_alignRootTo(reference, target)
	local referenceCF = reference:IsA("Attachment") and reference.WorldCFrame or reference.CFrame
	return target * self.root.CFrame:ToObjectSpace(referenceCF):Inverse()
end

function FPSViewmodel:_update(rawDeltaTime)
	if not self.enabled or not self.rig or not self.root then return end

	local deltaTime = ViewmodelMotion.clampDelta(rawDeltaTime)

	local camera = workspace.CurrentCamera
	if self.rig.Parent ~= camera then
		self.rig.Parent = camera
	end
	local cameraCF = camera.CFrame

	ViewmodelMotion.stepAds(self, deltaTime)
	local swayCF = ViewmodelMotion.stepSway(self, deltaTime)

	local speed = self:_planarSpeed()
	local locomotionActive = self:_updateAnimationState(speed)
	local bobCF = ViewmodelMotion.stepBob(self, deltaTime, speed, locomotionActive)
	local recoilCF = ViewmodelMotion.stepRecoil(self, deltaTime)

	local offsetCF = CFrame.new(self.extraOffset)
	local viewCF = cameraCF * offsetCF * swayCF * bobCF * recoilCF

	local hipCF
	if self.cameraBone then
		hipCF = self:_alignRootTo(self.cameraBone, viewCF)
	else
		hipCF = viewCF * self.hipOffset
	end

	local sightInRoot = if self.adsBlend > 0 and self.adsAttachment and self.adsAttachment.Parent
		then self.root.CFrame:ToObjectSpace(self.adsAttachment.WorldCFrame)
		else nil

	self.root.CFrame = hipCF

	if sightInRoot then
		local sightPosition = (hipCF * sightInRoot).Position
		camera.CFrame = cameraCF * CFrame.new(cameraCF:PointToObjectSpace(sightPosition) * self.adsBlend)
	end
end

-- Mount a weapon Model on the rig's mount joint (the HumanoidRootPart's `Main` Motor6D,
-- authored with the rig so its C0/C1 place the weapon exactly where the animations
-- expect it). `template` is a weapon Model whose PrimaryPart is the joint target.




function FPSViewmodel:getBarrel()
	return self.barrel
end

function FPSViewmodel:getMuzzle()
	return self.muzzle
end

function FPSViewmodel:getTrack(name)
	return self:_track(name)
end

function FPSViewmodel:getWeapon()
	return self.weapon
end

function FPSViewmodel:getMuzzleFlash()
	return self.muzzleFlash
end

function FPSViewmodel:nudge(offset)
	self.extraOffset = offset
end

function FPSViewmodel:sightBlend()
	if not self.adsAttachment or not self.adsAttachment.Parent then return 0 end
	return self.adsBlend or 0
end

function FPSViewmodel:hasSight()
	return self.adsAttachment ~= nil and self.adsAttachment.Parent ~= nil
end

function FPSViewmodel:setAdsGate(gate)
	self.adsGate = gate
end

function FPSViewmodel:setAds(state)
	if state and self.adsGate and not self.adsGate() then
		state = false
	end
	self.adsTarget = (state and self.enabled) and 1 or 0
end

function FPSViewmodel:setEnabled(state)
	local wasEnabled = self.enabled
	self.enabled = state and true or false
	if self.rig then
		self.rig.Parent = self.enabled and self.camera or nil
	end
	-- MouseIconEnabled is Generic/FreeCursor's to own here; writing it on every equip would undo
	-- a released cursor the moment a weapon came out.

	if self.enabled and not wasEnabled and self.animationIds then
		self:_playEquip()
	end
end

function FPSViewmodel:addRecoil(back, up, roll)
	ViewmodelMotion.addRecoil(self, back, up, roll)
end

function FPSViewmodel:destroy()
	self:_releaseTracks()
	self:_releaseLocomotionTracks()
end

require(script.ViewmodelRig)(FPSViewmodel)
require(script.ViewmodelAnimator)(FPSViewmodel)

return FPSViewmodel
