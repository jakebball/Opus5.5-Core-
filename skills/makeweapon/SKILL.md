---
name: makeweapon
description: Wire an authored gun Model into the Runner-framework FPS layer — PrimaryPart/root joints, Muzzle + BarrelAttachment + ADSAttachment, the MuzzleFlash part, grip attributes (GripOffset, ViewmodelMount/ViewmodelGrip/ViewmodelGripC1), asset placement under Assets/Models/Weapons, and the Weapons config entry. Use whenever the user invokes /makeweapon, points at a weapon model and asks to "set it up", "wire it in", "make this a gun", or asks for a new weapon's model plumbing in any Runner-framework Roblox FPS project.
---

# makeweapon — wire a weapon Model into the FPS framework

Turn an authored gun Model into a framework-ready weapon asset: correct PrimaryPart and joint anatomy, the named attachments the code searches for, a MuzzleFlash emitter part, the grip attributes both cameras read, the asset moved into `Assets/Models/Weapons/<Name>`, and a `Weapons.<id>` config entry. Animation *uploading* is out of scope — that is the `create-animation` skill; this skill only records which clips the config should reference.

## Step 0 — Preconditions

1. Confirm the active Studio is the place for the **project currently being worked on** (`get_place_info` against the working directory's project docs). Never modify another project's instances.
2. Confirm the FPS layer exists: `game.StarterPlayer.StarterPlayerScripts.Runner.Components.Generic.FPSViewmodel` and a `Gun` (or `HitscanGun`) sibling. If absent, this skill doesn't apply — say so and stop.
3. Resolve the target Model (usually pasted in `workspace`). If the user also has an animation-authoring Folder (rigs named `Viewmodel` / `R15` with `AnimSaves`), locate it — it decides the mount attributes in Step 3.
4. Find the project's reference weapon under `ReplicatedStorage.Assets.Models.Weapons` (e.g. `AssaultRifle`) — its MuzzleFlash part and attribute set are the templates to clone/copy from.

## Step 1 — PrimaryPart and joint anatomy

**The one rule that decides everything: animation Poses bind to the Motor6D whose *Part1* carries the pose's name.** (Documented in `FPSViewmodel:_applyMount` — the joint's own name is free.)

- **If the model was already animated** (an authoring rig exists whose hand/root carries a Motor6D into the gun): the joint's `Part1` in that rig **is** the weapon's root. Set `Model.PrimaryPart` to that part and change nothing else structurally. **Never insert a new neutral root above it** — demoting the animated root to a weld child silently unbinds every pose targeting it.
- **If the model is un-animated** (fresh build): create the rifle-style neutral root — a tiny (~0.07 stud) Part named `Main` hidden inside the body, `Model.PrimaryPart = Main`. It decouples the grip/attachment frame from mesh geometry, so a mesh re-export never moves the grip.
- Either way, the anatomy below the root is: **Motor6D (root → part)** for anything animations pose (bolt, magazine, trigger, slide); **Weld (root → part)** for static geometry. Verify nothing is left floating — `FPSViewmodel.weldLooseParts` catches strays at equip, but a part with no joint path to PrimaryPart becomes its own assembly and drops silently, so weld explicitly.
- Do not rename any animated part — poses bind by name.

## Step 2 — Named attachments (searched recursively, so any welded part can host them)

`FPSViewmodel:_resolveWeaponPoints` does `FindFirstChild(<name>, true)` on the weapon for each of these. Create them (on the root or any welded part), positioned in the model's own space:

| Attachment | Purpose | Placement |
| --- | --- | --- |
| `Muzzle` | Bullet spawn point + muzzle light origin | At the barrel tip, on the bore axis, just inside the tip (the rifle's sits ~0.07 behind the front face) |
| `BarrelAttachment` | Barrel reference the viewmodel reads (`getBarrel`) | On the bore axis, forward section of the barrel |
| `ADSAttachment` | **The eye point in sights.** The camera is moved onto this position (position only — orientation is ignored; the weapon never steers the view) | Dead center on the sight's optical axis: X centered on the bore line, Y on the optic centerline, Z at/just behind the rear lens. Further forward = optic fills more of the screen |
| `GripAttachment` | Grip reference landmark | At the firing-hand grip (optional but the reference weapon carries one) |

A weapon with no `ADSAttachment` simply never aims — that is how melee opts out. Only omit it deliberately.

**Settle which way the barrel points before placing anything.** If an authoring viewmodel rig holds the weapon, dot its `CameraBone` LookVector with the weapon root's Z axis — the player looks down the barrel, so this reads ±1.000 and is decisive. An HRP-facing dot is **not** a substitute (it read 0.000 on a correctly-built rig). With no rig, fall back to anatomy: the magazine sits forward of the trigger, and the scope's rear lens sits over it.

**`ADSAttachment` clearance matters more than it looks:** the camera is placed *at* the attachment, so leave ≥0.3 studs between it and the rear lens. Roblox's near clip plane is ~0.1 studs, and a scope lens inside it renders as clipped-through geometry.

## Step 3 — Grip attributes (how each camera holds the gun)

Set as **attributes on the weapon Model** (CFrame-typed unless noted):

- **`GripOffset`** — third person. The worn model's offset relative to the R15 `RightGripAttachment` (see `GearDressing`). If no authored value exists, copy the reference weapon's as a starting point and note it needs eyeballing in a playtest. `GripC1` is the optional second half — only needed once clips pose the item itself.
- **Viewmodel mount** — first person. The rig's single mount Motor6D (on the viewmodel's HumanoidRootPart, `Part1 = nil` until equip) defaults to its authored C0/C1. Two cases:
  - Animated on the **default mount** (rig's HumanoidRootPart, like the reference rifle): set no attributes; the rig's authored joint already places it.
  - Animated **off a hand** (authoring rig joins e.g. `RightHand → <root>`): set `ViewmodelMount = "RightHand"` (string, the rig part's name), `ViewmodelGrip` = that authoring joint's **C0**, `ViewmodelGripC1` = its **C1** — copied **verbatim as a pair** from the authoring rig's Motor6D.

**Always verify the joint algebra before trusting either value:**

```lua
-- must reproduce the weapon root's real resting CFrame to ~0 studs
local predicted = hand.CFrame * joint.C0 * joint.C1:Inverse()
print((predicted.Position - weaponRoot.Position).Magnitude)
```

If that error is large, **the rig was parked after animating and its offsets are drag residue** — a C1 holding tens of studs of pure translation with identity rotation is the signature. Do **not** substitute identity or any other default: detecting corruption tells you nothing about the true value. Ask the user for a rig with the weapon actually seated in the hand, then re-read and re-verify. (A real authored C1 is typically a stud or two — the root-to-grip pivot offset.)

## Step 4 — MuzzleFlash part

Clone the reference weapon's `MuzzleFlash` part into the model rather than rebuilding:

- An invisible (`Transparency = 1`), non-colliding part named exactly `MuzzleFlash`, direct child of the Model.
- Held by a **WeldConstraint** to the root (the rifle names it `LooseWeld_MuzzleFlash`).
- Its attachments sit at the part's origin with the flash `ParticleEmitter`s (`Enabled = false`, fired by `Emit()` from the weapon's GunEffects module) — so **the part's position is exactly where the flash draws**. Park it ~0.5–0.6 studs **past** the barrel tip so the sprite never clips back into the barrel; slide the part to tune, the emitters ride along.

## Step 5 — Asset placement and config

1. Move the finished Model to `ReplicatedStorage.Assets.Models.Weapons.<Name>`. The Model's `Name` must equal the weapon id used everywhere (config key, sounds folder, worn-model lookups).
2. Sounds live at `Assets/Sounds/Weapons/<Name>/` (`Shoot`, `Reload` at minimum) — create the folder; missing sounds fail silently (`Play()` on an empty SoundId is a no-op), so tell the user which are still empty.
3. Add the `Weapons.<id>` config entry (`Shared/getConfig/Weapons`), mirroring the reference weapon's keys: `Damage`, `FireInterval`, `Range`, `MagazineSize`, `ReloadTime`(/`Empty`), `Kind`, `Slot`, `Model = "Models/Weapons/<Name>"`, plus `Animations` / `ViewmodelAnimations` tables (leave clip ids the user hasn't uploaded yet as comments — never invent asset ids). **Hitscan is the default** — add `Delivery = "Projectile"` (+ `ProjectileSpeed`/`ProjectileGravityScale`) only if the user wants a travelling round.
4. If the weapon needs a bespoke flash/effect, add a ModuleScript named `<Name>` under client `Gun.GunEffects` (copy the reference weapon's as a template). No module = no flash, silently — mention it either way.

## Step 6 — Verify (in a separate call from the writes)

**Wrap every instance creation in a ChangeHistoryService recording**, or Studio discards it when the undo stack next moves — a weapon Model was lost twice this way before the recording fixed it:

```lua
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("BuildWeaponAsset")
-- ... create/clone/parent everything ...
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
```

Then verify in a **later** call, and re-check anything load-bearing:

```lua
-- execute_luau, adapted per weapon
local w = game.ReplicatedStorage.Assets.Models.Weapons.<Name>
print("PrimaryPart:", w.PrimaryPart)
for _, name in { "Muzzle", "BarrelAttachment", "ADSAttachment" } do
	print(name, w:FindFirstChild(name, true) ~= nil)
end
print("MuzzleFlash:", w:FindFirstChild("MuzzleFlash") ~= nil)
for k, v in w:GetAttributes() do print("attr", k, v) end
-- every BasePart must reach PrimaryPart through joints (no silent-drop assemblies)
```

Also confirm the config entry by `loadstring(module.Source)` readback — `require` serves a stale edit-mode cache.

## Step 7 — Report

Summarize: what was set (PrimaryPart, each attachment with its position, attributes with values, MuzzleFlash offset), what is still missing (animation ids, sounds, GunEffects module, playtest of the grips), and remind the user that both `GripOffset` and the viewmodel mount can only be truly judged in a playtest — the user runs all playtests.

Once the user approves the setup (global `CLAUDE.md` § Documentation Waits for Approval), update the project's feature doc (e.g. `features/combat.md` or `features/gear.md`) and `updatelog.md` per project rules.

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
