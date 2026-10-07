---
name: importmeshtools
description: Install and use the robloxMeshTools EditableMesh kit (MeshKit, BuildLib, Shapes, Remesh, CheckUploads, GeodesicDome, PaneTexture) in the Roblox place for the current project, then build low-poly meshes with it by the kit's rules and the user's proven ones. Use whenever the user invokes /importmeshtools, says "use the mesh tools", "use the mesh kit", "use robloxMeshTools", "install the mesh tools", mentions ServerStorage.ModelKit, or asks to model a room, prop, structure or map from Luau code in a project that already builds its meshes with the kit. New 3D models elsewhere go to /blenderassets, the standard pipeline.
---

# importmeshtools — the robloxMeshTools kit in any project

`github.com/MrChickenRocket/robloxMeshTools` (a friend of the user's wrote it for Claude-driven Studio work) builds
low-poly meshes from code with `EditableMesh`, previews them in Edit, and uploads them as real mesh assets. A pinned
copy lives next to this file in `vendor/robloxMeshTools/` (commit in `vendor/robloxMeshTools/VENDORED.md`), and
`meshtools.js` installs it into the open place over the Studio MCP server's HTTP endpoint.

**Invoking this skill, or the user saying "use the mesh tools", is their consent to install the kit into the place
for the project currently being worked on.** It is not consent for any other open place, and not for code fetched
fresh from GitHub: install only the vendored copy.

## Usage

```
/importmeshtools                      install (or confirm) the kit in this project's place, then stand by
/importmeshtools <what to build>      install/confirm, then build it with the kit
/importmeshtools --with examples      also install the Tank/Console/Crate/Platform/ToothedDoor samples + Demo
/importmeshtools update               refresh the vendored copy from upstream (see the last section)
```

## Step 0 — Orient

1. Read the project's `index.md` and `tech-design.md` if present. Their Hard Rules win over anything here, in
   particular on where built models go and how the map is organised. The kit itself is edit-time tooling in
   `ServerStorage.ModelKit` and ships nothing to clients. If the project is on the standard asset pipeline
   (headless Blender, `project-setup.md` § 3D Asset Pipeline) and the user did not ask for the kit by name, build
   new props and models with `/blenderassets` instead.
2. Read the project's art style: `## Project Art Style` at the top of `features/art-direction.md`, or the whole
   art-direction doc in a project that predates the section. Build to it, taking colours by name from the palette
   module it names (a project library such as `mesh-source/<Project>Lib.luau`, pushed as a `ModelKit` StringValue).
   If the section reads **Unset**, settle the style with the user before the first asset
   (`project-setup.md` § Art Style).
3. If the project syncs with Rojo (`*.project.json` in the project root), check whether it manages
   `ServerStorage`. If it does, a Studio-created `ModelKit` would be wiped on the next sync, so ask the user
   where the kit should live before installing.
4. Establish the project's expected PlaceId: from its docs, or from one `execute_luau` call returning
   `game.PlaceId .. "|" .. game.Name`. A PlaceId of 0 means an unpublished place: previews work, uploads do not.

## Step 1 — Install or confirm

Run from this skill's folder (`~/.claude/skills/importmeshtools`):

```bash
node meshtools.js probe
```

Every Studio MCP server on 58741-58750 that answers prints its port, `placeId`, name, whether a playtest is running
and whether a kit is already there (with its `KitCommit`). Several ports usually reach the same Studio; pick one
whose place matches the project. **If the ports show different places, use only a port whose placeId matches.** If
none matches, stop and tell the user which places are open.

```bash
node meshtools.js install --port 58741 --place-id <PlaceId>
```

- It re-probes and refuses on a placeId mismatch or a running playtest (the kit installs into Edit).
- Default set: core (MeshKit, BuildLib, Shapes, Remesh, CheckUploads) plus techniques (GeodesicDome, PaneTexture).
  `--with examples` adds the samples; `--with none` installs core only.
- Already at the vendored commit and verifying clean → it changes nothing. `--force` reinstalls anyway.
- A kit reported as `present, no KitCommit (pre-skill install)` came from a hand install. Reinstalling replaces
  those sources with the vendored ones and keeps `Templates`, `PreviewTemplates`, `Pieces`, `TemplateSrc` and any
  extra StringValues (project libraries). Say so before doing it.
- Verification runs in a **separate** call: every source present, byte length equal to the vendored file, compiles
  under `loadstring`, and a 44-triangle preview box builds at 4 x 1 x 2. Report the verify lines to the user.

`node meshtools.js selftest --port N` runs the whole install into an unparented folder and verifies it in the
same call, which proves the transport without touching the place. Use it when a real install fails verification.

**After a successful install, tell the user to save the place.** The kit lives in the place file.

**Fallback when no port answers** but the `execute_luau` MCP tool works: `node meshtools.js emit --out <scratch>/install.luau`
(about 50 KB), read that file and pass it to `execute_luau` verbatim, then do the same with
`emit --verify-only --out <scratch>/verify.luau` in a separate call. Retyping 50 KB is slow and error-prone, so
this is a last resort; the verify step is what catches a transcription slip.

## Step 2 — Before building anything

Read, in full: `vendor/robloxMeshTools/GOTCHAS.md`, the "How a build goes" and "Using BuildLib" sections of
`vendor/robloxMeshTools/README.md`, and the comment headers of `kit/MeshKit.luau` and `kit/BuildLib.luau` (the API
reference lives there). For domes or alpha glass, also the header of the matching `techniques/` file.

Every build call loads the kit the same way:

```lua
local MK = game:GetService("ServerStorage").ModelKit
local Kit = loadstring(MK.MeshKit.Value)()
local B = loadstring(MK.BuildLib.Value)({
	Kit = Kit, root = workspace.<Build>, origin = CFrame.new(...), prefix = "<Build>",
	preview = true, templates = MK.PreviewTemplates, templateSrc = MK.TemplateSrc,
})
```

## Step 3 — Build rules

The kit's own loop (plan in numbers, one section per call, preview → look → fix, templates for repeats,
probe collision, upload section by section, stop regenerating once a person has hand-edited) is in the README.
These rules come on top of it, and each one was learned from a real failure in the user's projects:

**Transport and persistence**
- No backslash escapes in any Luau you send through the MCP: it unescapes backslashes inconsistently, and `"\n"`
  arrives as a real newline. Use `string.char(10)`, single-quoted strings around double quotes, and
  `string.char(34)` in patterns.
- Keep every piece's source as a `.luau` file in the project folder (e.g. `mesh-source/<Piece>.luau`), and run
  large ones with `node meshtools.js run --port N --file mesh-source/<Piece>.luau`. That is backslash-safe,
  diffable, and survives Studio rolling back plugin-created instances between calls, which has happened.
- Project-wide helpers that later calls reuse go into the kit root as extra StringValues
  (`ModelKit.<Project>MeshLib`) and load with `loadstring`. Never edit the kit's own sources in the place: a
  reinstall replaces them.
- `execute_luau` has delivered one call twice. Make every call idempotent: `B.built` replaces its `Built` child,
  so pieces already are; anything hand-rolled must check before it creates.
- Confirm a build landed with a read in a **later** call, not only from the build call's own return value.

**Geometry and z-fighting**
- **Every visible surface exists once.** Never lay a mesh over existing parts and hide the parts with
  `LocalTransparencyModifier`: LTM resets on a Studio restart while preview meshes persist, and thousands of parts
  then render face-to-face with the meshes. Visuals are meshes, collision is separate invisible clip parts, and
  solids only touch or cross at an angle, never share a same-facing plane.
- **Prove there is no z-fighting with a readback audit, not screenshots.** `AssetService:CreateEditableMeshAsync(part.MeshContent)`
  returns a preview mesh's triangles. Bucket them by normal and plane, then flag same-facing pairs within 0.03
  studs whose slightly shrunk outlines overlap (separating-axis test). Measure plane distance relative to the
  triangles, not as `dot(n, p)` on world coordinates: thousands of studs from the origin, a tiny normal error
  fakes a coplanar pair. About 480k triangles audit in seconds. What it caught that review missed: bands 0.02-0.03
  proud of a surface, mirrored slabs whose end faces overlap at a ridge, beams meeting on one plane at corners.
- **Colour in vertex colours, MeshPart white** (`k.colorFn`, or wrap `kit.face` to record a colour per vertex
  key). One mesh then carries a whole palette; per-colour meshes multiply the upload count.
- **Hollow shells use facade bricks**: mitred front bevel, full sides, no back. 18 triangles against 44 for a
  closed box, which more than halved a canyon's count. At convex corners trim by the perpendicular face's
  thickness, only where that face exists, and recess a brick by shaving its front, never by shifting it.
- **"Mesh extents size too large"** from `CreateMeshPartAsync` means one mesh spans more than 2048 studs. Treat it
  as a coordinate bug until proven otherwise: it once exposed a double-applied origin.

**Templates, destruction and materials**
- Stretchable templates (one mesh cloned and resized) keep uploads to a handful. Build each so its bbox equals the
  nominal size exactly, and give lathes a side count divisible by 4 or the bbox comes out short.
- If the project has a destruction system that voxelises parts by `Size`/`CFrame`, destructible props must be
  **one MeshPart each, with Box collision equal to the old box**. A merged visual over invisible colliders leaves
  the mesh standing while its collider shatters.
- A `MaterialVariant` on a MeshPart covers every face and UVs cannot mask it, so a top-only texture (studs) needs
  its top face as a separate flat MeshPart. Its density is world-constant under resizing, and its tile grid is
  anchored at the mesh origin, which in this kit is the bbox centre: put each face's centre a whole number of
  tiles from its mesh's centre.

**Looking at it**
- **Look with `/assetshot`, never through Studio's camera:** `node ~/.claude/skills/assetshot/shot.js
  <instance path> --out <scratchpad>\shots\<name>` renders the preview offline, with `--focus x,y,z,r` for close-ups.
  Moving the camera or calling `capture_screenshot` breaks every other session working in the place and the user's
  own view. The kit README's own advice to screenshot is overridden here.
- Lighting in Edit is far darker than in Play, so judge colour and lights in Play.

## Step 4 — Upload and hand over

1. Upload section by section (`preview = false`, `templates = MK.Templates`), about 3-4 s per mesh. Uploads go
   to the group when the place is group-owned.
2. Run `loadstring(MK.CheckUploads.Value)(workspace.<Build>)`. It must report 0 previews: a preview mesh looks
   identical in Edit and does not exist in a Play session. Re-run it after any Undo.
3. **Never start or stop a playtest yourself.** Say what to check in Play (the build is present, lighting, walk the
   routes) and ask the user to run it. Studio Play can run on real account data, so look and don't touch.
4. Per the global rules: close with the change summary, and only once the user approves the build (global
   `CLAUDE.md` § Documentation Waits for Approval) update or create the project's `features/<system>.md` and
   append to the project's `updatelog.md`.

## Updating the vendored kit

Only when the user asks. Clone upstream into the scratchpad and diff it against `vendor/robloxMeshTools/`. Show the
user what changed; code is never pulled in unreviewed. On approval, replace the folder wholesale (`git archive HEAD`
into it), rewrite `VENDORED.md` with the new commit, then run `node meshtools.js emit --with techniques,examples --out <scratch>/x.luau`
(it refuses if a source now collides with the backslash sentinel) and `selftest` against an open place. If upstream
adds or renames source files, update the `FILES` table at the top of `meshtools.js`. Places installed from the old
commit show it in `probe`; they update only when the kit is next used there. `/blenderassets` sends this folder's
`kit/MeshKit.luau` with every push and overrides its `bounds` and `build`, so after an update also run
`node ../blenderassets/blend.js selftest` on a built payload.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `probe` prints nothing on any port | No MCP server running, or a non-HTTP setup | Use the `emit` fallback through the `execute_luau` tool |
| Every port times out | The plugin is not attached to any server | Ask the user to click the MCP plugin's toolbar button in Studio |
| `install` refuses: placeId mismatch | The port reaches a different open place | Pick the port whose `probe` line matches, or ask the user to open the project's place |
| verify: `length` on a pre-skill install | Hand installs swapped `"\n"` for `string.char(10)` (+11 bytes each) | Harmless; `install` normalises it to the vendored bytes |
| verify: `missing` right after a clean install | Studio rolled back the created instances | Run `install` again and verify once more; if it repeats, tell the user |
| smoke fails with an EditableMesh / permission error | The place or Studio build lacks EditableMesh access for plugins | Report it; the kit cannot work in that place |
| An `execute_luau` build call errors on a string literal | A backslash escape in the sent Luau | Remove every escape (Step 3), or run the piece from a file with `meshtools.js run` |
