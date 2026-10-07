---
name: assetshot
description: Look at any Roblox Studio asset (a model, gun, enemy, prop, map piece, posed rig or a frame of an animation) by rendering it offline in headless Blender, without moving Studio's camera or taking a Studio screenshot. Use it every time an asset needs a visual check in a Roblox project with the Studio MCP attached, including "how does it look", "check the model", "screenshot it", "show me the gun", progress checks while building, before-and-after comparisons, first-person views and animation freeze frames. Any number of sessions can use it at once, which is why it replaced the camera.
---

# assetshot — see an asset without touching Studio's camera

Studio has one viewport and one camera. `capture_screenshot` needs that camera, works only in Edit with the viewport
showing, and every session that moves the camera ruins the next session's screenshot and the user's own view. assetshot
reads the asset out of Studio (read-only) and renders it in Blender on disk instead. Each session gets its own pictures,
so any number can work at once, during the user's playtest, or with Studio minimised.

## The rule

- **Never move `workspace.CurrentCamera` and never call `capture_screenshot` to check an asset.** Use assetshot.
- `capture_screenshot` stays for one case only: the user asks to see what is on their own screen. Read the camera, never
  set it.
- The real in-engine look is the user's to judge, in Play. assetshot is how you check your own work before that.

## Command

```
node ~/.claude/skills/assetshot/shot.js <instance path...> --out <scratchpad>\shots\<name> [options]
```

Instance paths are dotted from the DataModel: `Workspace.Maps.Lobby`, `ReplicatedStorage.Assets.Models.Weapons.SMG`,
`ServerStorage.ModelKit.GreyoutPreviewTemplates.Guns.SMG`. Several targets render together in one frame.

| Option | Does |
| --- | --- |
| `--views a,b,c` | `persp`, `persp-back`, `persp-right`, `persp-back-right`, `front`, `back`, `left`, `right`, `top`, `bottom`. Default: persp, front, left, right, back, top. Orthographic except the `persp` ones |
| `--forward -z` | which way the asset faces, so front, back, left and right mean what they should: `-z` (Roblox's LookVector, the default), `+z`, `-x`, `+x` |
| `--camera PATH` | also render from that instance's CFrame: a Camera, part, attachment, bone or model pivot. `--fov N` sets its vertical field of view (default 70) |
| `--view studio` | render from Studio's current camera, read without moving it: "what am I looking at" |
| `--focus x,y,z[,r[,dx,dy,dz]]` | a close-up of a point in the asset's frame, `r` studs across, looking from `dx,dy,dz`. Repeat it for each join or detail. It replaces scaled-up copies built for close-ups |
| `--frame PATH` | the frame that views and focus points are measured in (default: the first target's pivot) |
| `--pose FILE` | a Luau script run in Studio first; it poses things and calls `shot.snap{...}` (below) |
| `--arg key=value` | handed to the pose script as `shot.args.key`; repeatable |
| `--image-limit N` | the largest texture side read from Studio (default 1024, Roblox's own cap). Bigger textures are averaged down; a lower limit gives a quicker, softer sheet |
| `--icon SIZE` | Icon mode: one square, transparent, orthographic render per target, fitted tight, with no labels and no sheet. `--icon-view`, `--icon-roll`, `--icon-padding` and `--icon-file` shape it. `/itemicon` drives this to make UI item pictures; use that skill rather than calling it directly |
| `--samples N` | Cycles samples per tile (default 24); `--name`, `--port` (default 58741 or `STUDIO_PORT`), `--blender PATH`, `--keep` keeps `scene.json` and the preview textures |

It prints the sheet path, each tile, and what it could not draw. **Read the sheet with the Read tool**, and a single tile
when you need detail. Put `--out` in the session scratchpad; build output never goes in the project.

A project can wrap the command with its own defaults. FPSTowerDefense's `node tools.js shot <Kind>` renders a gun in
first person beside the Stud Driver plus six views, and `node tools.js shot --freeze ...` renders reload freeze frames.
Use a project's wrapper when it has one.

## Pose scripts

A pose script is Luau run in the edit DataModel, inside the export, before anything is read. It sees a `shot` table:

| Field | Is |
| --- | --- |
| `shot.snap{ label, targets, camera, fov, aspect, frame, views, focus, forward }` | Records every part under `targets` at this instant. `camera` (a CFrame) adds a perspective tile. `views = {}` means no orthographic tiles. Call it once per frame you want |
| `shot.args`, `shot.targets`, `shot.views`, `shot.focus`, `shot.forward` | What the command line passed |
| `shot.find(path)`, `shot.pivot(instance)` | Resolve a dotted path; the world CFrame of a part, attachment, bone, camera or model |
| `shot.temporary(instance)` | Destroyed after the snapshots, even when the script errors. Register every rig or station you build |
| `shot.studioCamera()` | Studio's camera CFrame, field of view and aspect, read only |
| `shot.warn(text)` | Printed with the result |

Rules for pose scripts, so sessions stay out of each other's way:
- **Build what you pose.** Clone a rig or station far from the action (about 4,000 studs up or out), pose it, snap it
  and register it with `shot.temporary`. Never step, freeze or restart anything another session or the user is watching.
- **Snapshot before anything yields** when timing matters. A snap copies everything it needs at once, so destroying the
  rig straight after is safe.
- Never move the camera.

## How faithful it is

Measured against a Studio screenshot of the same camera on 2026-10-03. Framing, part placement, vertex colours, part
colours and lighting matched closely. So did the stud material, which is projected along each part's own axes at its
`MaterialVariant`'s `StudsPerTile`, through the bounding-box centre, as Studio does.

| Approximated | Not drawn (listed under "not drawn") | Drawn as the part's box (listed under "boxes") | Untextured (listed under "untextured") |
| --- | --- | --- | --- |
| Sky, atmosphere and bloom; Neon glow; Glass and other materials' textures | Particles, beams, trails, lights, fire and smoke, GUIs, highlights, terrain, tiled `Texture`s | Meshes `EditableMesh` may not read (Roblox's catalog gear and other assets the user does not own), unions, MeshParts whose mesh content is gone | Images `EditableImage` may not read (assets the user does not own) |

The stock face and other `rbxasset://` textures come from the local Roblox install. Meshes are single-sided, like
Roblox's. Painted assets from `/blenderassets` render with their textures, at their own size up to `--image-limit`:
a live `EditableImage` (a preview) is read straight from memory and an uploaded image by its asset id, so a preview
and its upload render the same (measured 2026-10-04). Preview meshes keep their UVs, and `AlphaMode` is honoured:
`TintMask` tints by alpha with `SurfaceAppearance.Color` (gold trim at alpha 0 stays gold),
`Overlay` lays the texture over the part colour, `Opaque` ignores alpha, `Transparency` cuts the surface. When the
sheet shows a box where an item should be, the report line says why. Check that item in Play rather
than treating the box as a fault in the model.

## Speed and sharing

About 2 s to export, then about 1 s a tile on the RTX 3060 (the first tile is about 3 s). A gun sheet of eight tiles
takes about 15 s. Each export is keyed by its own run id in `_G.AssetShot` and starts once (the MCP bridge hands a
running call to the plugin again every 0.5 s; repeats are ignored), then is polled by short calls and released after.
Every call to Studio costs about 0.5 s whatever its size, so textures travel as base64 (`EncodingService`) in 4 MB
chunks and an image several parts share goes once: Joust Tycoon's painted horse (18 textured parts, two 1024
textures) exports in about 8 s. Asset meshes (`cache/meshes`) and uploaded images (`cache/images-<limit>`, named after
the texture limit so a copy read at another size is never reused) are cached by asset id with atomic writes, so a
second shot of the same uploaded model skips the download. Preview textures are written beside the sheet and removed
after the render.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `fetch failed` / `ECONNREFUSED` | the Studio MCP is not on that port | pass `--port`, or check Studio is open with the plugin connected |
| `Studio: ... no service named` / `no X under Y` | a wrong instance path | the path is dotted from the DataModel; check names with the MCP |
| `studio busy; waiting for the export to start` | Studio is slow to take calls, usually because another session is building or uploading | nothing. It waits up to 3 minutes for the export to start instead of sending it again |
| `the export is gone from Studio` / `Studio never started the export` | the plugin restarted mid-export, or Studio stayed busy | run it again once Studio answers |
| `Blender 4.1+ not found` | no Blender | install 4.1+ or pass `--blender` |
| A tile shows nothing | everything in that snapshot was transparent | check `Transparency`; hidden reload props are skipped on purpose |
