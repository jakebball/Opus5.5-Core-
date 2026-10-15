---
name: assetshot
description: Look at any Roblox Studio asset (a model, gun, enemy, prop, map piece, posed rig or a frame of an animation) by rendering it offline in headless Blender, without moving Studio's camera or taking a Studio screenshot, and render an animation clip as a short looping phone-ready MP4 (clip mode) without a playtest. Use it every time an asset needs a visual check in a Roblox project with the Studio MCP attached, including "how does it look", "check the model", "screenshot it", "show me the gun", progress checks while building, before-and-after comparisons, first-person views, animation freeze frames, and "show me the animation", "render the clip as a video", "send a video of the trot". Any number of sessions can use it at once, which is why it replaced the camera.
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
| `--clip RIG=ANIM` | Clip mode: an MP4 of the animation instead of a sheet (§ Clip videos) |

It prints the sheet path, each tile, and what it could not draw. **Read the sheet with the Read tool**, and a single tile
when you need detail. Put `--out` in the session scratchpad; build output never goes in the project.

A project can wrap the command with its own defaults. FPSTowerDefense's `node tools.js shot <Kind>` renders a gun in
first person beside the Stud Driver plus six views, and `node tools.js shot --freeze ...` renders reload freeze frames.
JoustTycoon's `node animation-source/video.js <Clip>[,<Clip>]` renders clip videos of the mounted knight. Use a
project's wrapper when it has one.

## Clip videos

Clip mode reviews an animation as a short looping video without a playtest and without Studio's camera. The clip plays
on a private copy in Edit, every frame is recorded in one Studio call, rendered in headless Blender and encoded to an MP4
a phone plays. Use it instead of freeze frames or a `/demo` playtest to review a clip; the in-engine look in Play stays the
user's to judge.

```
node shot.js <model> --clip <rig>=<animation>[,<animation>] [--clip ...] --out <scratchpad>\video\<name> [options]
node shot.js Workspace.Knight --clip Workspace.Knight.Horse=ServerStorage.Saves.HorseTrot --clip Workspace.Knight.Rider=ServerStorage.Saves.RiderTrot
```

- **What plays:** `<rig>` is anything with an `Animator` inside (an `AnimationController` or `Humanoid` without one gets one
  on the copy). `<animation>` is a `KeyframeSequence` (registered for the session, as the Animation Editor does), an
  `Animation` or `rbxassetid://N`. Rigs joined by welds, such as a rider on a horse, are copied together: pass the model
  that holds both as the target. Without `--pose`, a built-in pose copies the targets 4,000 studs up and plays each
  `--clip` on its copy; a pose script calls `shot.clip{...}` itself (§ Pose scripts).
- **How a frame is sampled:** each track's `TimePosition` is set to the frame's time and its Animator stepped by zero,
  then every part's CFrame is read. That is the Animator's own interpolation (easing, weights, priorities), exact at any
  time, and nothing else advances: `StepAnimations` steps only the Animator it is called on. Against keyframe lerp plus
  forward kinematics (FreezeShot's method) on JoustTycoon's mounted clips, the worst gap over every frame was 0.003 studs.
- **Loops:** a looping clip is sampled once, `round(length × fps)` frames spaced to close the loop, and the video repeats
  it by stream copy (`--loops N`, default about 6 s). A one-shot plays to its end and holds 0.4 s before it repeats.
- **Travel:** a clip whose animation carries a `GroundSpeed` attribute (studs/s) moves forward at that speed with the
  cameras following (`--travel auto`), so a planted foot stays on its square of the checker ground and any slide shows.
  `--travel off` keeps it in place, `--travel N` sets a speed, and `--track off` holds the cameras still while the rig
  crosses (every loop is then rendered). With the cameras following, the checker size is nudged so one loop's travel is a
  whole number of checker periods, which keeps the loop seamless.
- **Ground:** at the lowest point the clip reaches, unless the pose passes `ground` (JoustTycoon passes the horse's
  `Root`, the game's real ground, so a hoof dipping below it shows). `--ground plain|off`, `--grid N`.
- **Cameras:** perspective, 30° (`--fov`), fitted to everything the clip sweeps: `side` (the rig's right), `left`, `chase`
  (behind-left, three-quarter, raised), `chase-right`, `front`, `front-right`, `back` and `top`; default `side,chase`.
- **Output:** `<out>\<clip>.mp4`: H.264 High 4.1, yuv420p, limited range, 30 fps (`--fps`), faststart, no audio, the
  views stacked at 1280×720 each (`--size`, `--layout row|separate`), every frame stamped with the clip, view, clip time
  and speed (`--no-label`). **Read `<clip>_strip.png`**, eight frames of one play, to check the motion; pull an exact
  frame from the MP4 with ffmpeg when one matters. `--keep` keeps the JPEG frames and `<name>_clips.json` (frame times,
  cameras, ground).
- **Engine:** EEVEE at 16 samples (default), about 0.27 s a frame per 720p view on the RTX 3060; `--engine cycles` (8
  samples) takes about 0.38 s. Workbench was tried and dropped: it cannot mix textures with part colours. JoustTycoon's
  Trot (1.23 s, two views) takes about 25 s end to end, SprintCharge (0.83 s) about 18 s.
- Code-driven joints (MagicFx, PennonFx) move only when the pose drives them in `after`, and part sizes are held at
  frame 0.

## Pose scripts

A pose script is Luau run in the edit DataModel, inside the export, before anything is read. It sees a `shot` table:

| Field | Is |
| --- | --- |
| `shot.snap{ label, targets, camera, fov, aspect, frame, views, focus, forward }` | Records every part under `targets` at this instant. `camera` (a CFrame) adds a perspective tile. `views = {}` means no orthographic tiles. Call it once per frame you want |
| `shot.args`, `shot.targets`, `shot.views`, `shot.focus`, `shot.forward` | What the command line passed |
| `shot.find(path)`, `shot.pivot(instance)` | Resolve a dotted path; the world CFrame of a part, attachment, bone, camera or model |
| `shot.temporary(instance)` | Destroyed after the snapshots, even when the script errors. Register every rig or station you build |
| `shot.clip{ label, targets, tracks, fps, duration, loop, root, forward, groundSpeed, ground, cameras, after }` | Records a clip video of every part under `targets` (§ Clip videos). `tracks = { { animator, animation, weight } }`: `animator` is an Animator or an instance holding one, `animation` a KeyframeSequence, Animation, path or asset id. `root` (default the first target's PrimaryPart) sets the origin, heading and travel; `groundSpeed` defaults to a track's `GroundSpeed` attribute; `ground` is a world height; `cameras = { name = { eye, target, fov } }` in the root's frame (X right, Y up, −Z ahead) adds named views. `after(time, step, frame)` runs after the Animators each frame for code-driven joints; the `Transform`s it writes do not move parts in Edit, so the clip places those joints by forward kinematics. It must not yield |
| `shot.studioCamera()` | Studio's camera CFrame, field of view and aspect, read only |
| `shot.warn(text)` | Printed with the result |

Rules for pose scripts, so sessions stay out of each other's way:
- **Build what you pose.** Clone a rig or station far from the action (about 4,000 studs up or out), pose it, snap it
  and register it with `shot.temporary`. Never step, freeze or restart anything another session or the user is watching.
  `shot.clip` enforces it: it refuses an Animator that is not inside a `shot.temporary` copy.
- **Snapshot before anything yields** when timing matters. A snap copies everything it needs at once, so destroying the
  rig straight after is safe. `shot.clip` may wait for its animations to load, then samples every frame without yielding.
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

Shadows follow a back-face-culled shadow map: a face turned away from the light casts none. Before 2026-10-07 Cycles
let such faces cast, so an inverted-hull ink shell baked into the same mesh as its body (JoustTycoon's merged horses)
shadowed the whole body and rendered it black; closed meshes shadow as before. Clip videos draw everything sheets draw,
under EEVEE's lighting (a little brighter than Cycles) on a checker ground.

## Speed and sharing

About 2 s to export, then about 1 s a tile on the RTX 3060 (the first tile is about 3 s). A gun sheet of eight tiles
takes about 15 s. Each export is keyed by its own run id in `_G.AssetShot` and starts once (the MCP bridge hands a
running call to the plugin again every 0.5 s; repeats are ignored), then is polled by short calls and released after.
Every call to Studio costs about 0.5 s whatever its size, so textures travel as base64 (`EncodingService`) in 4 MB
chunks and an image several parts share goes once: Joust Tycoon's painted horse (18 textured parts, two 1024
textures) exports in about 8 s. Asset meshes (`cache/meshes`) and uploaded images (`cache/images-<limit>`, named after
the texture limit so a copy read at another size is never reused) are cached by asset id with atomic writes, so a
second shot of the same uploaded model skips the download. Preview textures are written beside the sheet and removed
after the render. A clip is one export however many frames it has: JoustTycoon's mounted Trot (37 frames, 53 parts)
exports in about 2.5 s once its meshes are cached.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `fetch failed` / `ECONNREFUSED` | the Studio MCP is not on that port | pass `--port`, or check Studio is open with the plugin connected |
| `Studio: ... no service named` / `no X under Y` | a wrong instance path | the path is dotted from the DataModel; check names with the MCP |
| `studio busy; waiting for the export to start` | Studio is slow to take calls, usually because another session is building or uploading | nothing. It waits up to 3 minutes for the export to start instead of sending it again |
| `the export is gone from Studio` / `Studio never started the export` | the plugin restarted mid-export, or Studio stayed busy | run it again once Studio answers |
| `Blender 4.1+ not found` | no Blender | install 4.1+ or pass `--blender` |
| A tile shows nothing | everything in that snapshot was transparent | check `Transparency`; hidden reload props are skipped on purpose |
| `clip: ... is not inside a shot.temporary copy` | the pose tried to animate an original | clone the rig, register the copy with `shot.temporary`, animate the copy |
| `clip: X did not load in 20 s` | an `Animation` whose asset this account cannot read, or Studio is busy | play the KeyframeSequence instead, or check the asset id |
| `cannot be cloned (Archivable is off)` | a player character or a model with Archivable off | clip a copy that can be cloned |
| `ffmpeg not found` | no ffmpeg (the `/demo` skill uses the same one) | `winget install Gyan.FFmpeg`, or set `FFMPEG` |
