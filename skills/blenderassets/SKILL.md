---
name: blenderassets
description: Author 3D assets for Roblox as Python scripts run in headless Blender, judge them from a rendered four-view contact sheet and geometry checks, then build them in Roblox Studio as vertex-coloured MeshParts, or as painted textured MeshParts (SurfaceAppearance, team tint masks, toon ink outlines, cached GPU bakes), preview or upload, over the Studio MCP. The standard 3D asset pipeline for Roblox projects set up by /setup. Use whenever the user invokes /blenderassets, says "use headless blender", "use Blender", "model it in Blender", or asks for a 3D prop, model or mesh in a Roblox project, unless that project's docs name another way its models are built.
---

# blenderassets: headless Blender for Roblox assets

Each asset is a Python script. `blend.js build` runs it in Blender with no window, renders a four-view contact
sheet, checks the geometry and writes a payload. `blend.js push` builds that payload in Studio as MeshParts. Nothing
is installed into the place: the Roblox side is robloxMeshTools' `MeshKit`, read from the importmeshtools skill's
vendored copy (`../importmeshtools/vendor/robloxMeshTools/kit/MeshKit.luau`) and sent with each call.

**This is the standard.** Roblox projects set up by `/setup` author new mesh assets this way
(`~/.claude/skills/setup/project-setup.md` § 3D Asset Pipeline, and the "3D models are authored in
headless Blender" hard rule it seeds into `tech-design.md`). A project whose docs name another pipeline keeps it.

```
/blenderassets <what to build>
```

`<skill>` below is this folder (`~/.claude/skills/blenderassets`). Pass absolute paths.

## Step 0: Orient

1. Read the project's `index.md` and `tech-design.md`. Their Hard Rules win over this skill. **If they name another
   way models are authored, ask before using Blender.** Pick the Crops, for one, builds every world model from bricks
   baked by FarmLib, because studs only render on real Parts. Ask too when the docs are silent but the project root
   holds another pipeline's source folder (`mesh-source/`, `map-source/`, `world-source/`). Otherwise Blender is the
   default: go ahead.
2. Read the project's art style: `## Project Art Style` at the top of `features/art-direction.md`, or the whole
   art-direction doc in a project that predates the section. Build every asset to it: its shapes, its materials, and
   colours by name from the palette module it names (normally `blender-source/style.py`, imported like any shared
   helper). If the section reads **Unset**, settle the style with the user before the first asset
   (`project-setup.md` § Art Style).
3. Blender 4.1+ must be installed. `blend.js` takes the newest `Program Files\Blender Foundation\Blender X.Y`, then
   Steam, then `blender` on PATH. `--blender PATH` or the `BLENDER` env var overrides.

## Step 1: Write the asset script

- Keep it at `blender-source/<Asset>.py` in the project root (the folder `/setup` creates; make it if missing),
  unless the project names another place. The script is the asset's source of truth: diffable, and re-run to
  regenerate. Helpers shared by a project's assets go in the same folder as a plain module the scripts import
  (`run.py` puts the script's folder on `sys.path`).
- `import blendlib as bl`, start with `bl.reset()`, end with `bl.finish("<Name>", budget=N)`. **Read the API header
  of `<skill>/python/blendlib.py` before the first script.** Everything else is plain `bpy` / `bmesh`. Prefer
  Blender's modifiers and bmesh ops (bevel, mirror, array, solidify, boolean, spin, extrude, inset) to hand-placed
  vertices. That is the point of using Blender. `examples/pumpkin_crate.py` is a worked example.
- **Frame:** Z up, the front faces -Y (Blender's Front view), 1 unit = 1 stud, and the world origin is the pivot,
  so put it at the base centre. Roblox receives `(-x, z, y)`: front -Z, a proper rotation, nothing mirrored.
- **Parts:** each rendering mesh object is one MeshPart, named after the object. Merge objects into one part with
  `bl.roblox(obj, part="Name")`. Set `obj.hide_render = True` on guides so they aren't exported. Modifiers are
  applied on export; never apply them by hand.
- **Sockets and attributes:** `bl.socket(name, at, part, up=, front=)` puts an Attachment on a part (a mount point
  for kit, trails or effects), and `bl.roblox(obj, attributes={...})` sets attributes on its MeshPart. Both travel in
  the payload and are rebuilt on every push, because a push replaces the model and would drop anything added in
  Studio. Verification counts the sockets.
- **Colour:** `bl.paint` / `bl.paint_faces` write sRGB hex into the `Col` corner attribute. An object without one
  takes its material base colours, else white (reported). The MeshPart itself stays white.
- **Roblox settings** per object: `bl.roblox(obj, material="Wood", collision="Hull", collide=True, shadow=False)`,
  Enum names as strings. The defaults are MeshKit's: SmoothPlastic, Box, no collision, shadow on. Visual meshes
  should not collide; collision belongs on separate clip parts (importmeshtools' `GOTCHAS.md` § Collision).
- **Limits:** a part over 20,000 triangles (EditableMesh's cap) is an error, so split it. `budget=` warns above your
  own target.

## Painted textures (when the project's art style paints its assets)

Vertex colour is the default. When the project's art style calls for painted, textured assets (hand-painted,
painted toon), or the user asks for custom textures, use the painted path: the same script, build and push, with
four more modules beside `blendlib` (named *lib so a project's own helpers never shadow them). **Read the header docstring of each before the first painted script.**

| Module | What it gives you |
| --- | --- |
| `paintlib` | `Atlas`: one texture per MeshPart, baked and painted when `bl.finish()` runs |
| `brushlib` | painter recipes (wood, iron, rivets, leather, quilting, team cloth, embroidered bands and tails, coats, hair), `use()` to bind options, and `finish()`: the soft painted look or, with `TOON = True`, the toon pass |
| `shapelib` | deterministic builders for detailed cloth and gear: quilted lofts (`ring_loft(uniform=True)` + `quilt_puffs`), `cloth_band`, `hanging_tail`, `gathered_knot`, `roll_ring`, `channel_dome`, `ellipsoid`, `rounded_box`, `mark_ink_skip` |
| `inklib` | toon ink outlines as inverted hulls: `outline(piece)` |

**Painters come from the cross-project library** (`python/brushes/`, rules in its `README.md`, everything listed
in its generated `CATALOG.md`, each style's swatch sheet in `brushes/swatches/`). The project's art style names a
style profile; `style = brushes.use_style(name, palette=style_module.PALETTE)` activates its finish and palette,
and `style.painter(role, **geometry_options)` gives the brush pinned for that role ("wood", "brass", "team cloth",
"embroidered band"). A role the profile lacks: pick a matching brush from the catalog, else write one in the
project and promote it into the library when the user approves the asset, then `node <skill>/blend.js brushes`
to refresh swatches and catalog. `brushlib` is the same recipes as one flat module, kept for scripts written
before the library.

`examples/painted_crate.py` is the worked example (a style profile from the library, `shapelib`, `inklib`): two atlases, a tinted strap with untinted gold, ink, toon.

- **One texture per MeshPart.** Every piece with the same `roblox_part` goes on the same `Atlas`. A texture is at
  most 1024 square, so give a big asset several atlases, one per part (or per mirrored pair). The build errors if
  a part's pieces sit on two atlases.
- **Team colour** is `Atlas.add(obj, painter, tint=True)`: the part gets SurfaceAppearance `AlphaMode.TintMask`,
  and the painter's alpha is the tint amount. Paint tintable cloth near-white at alpha 1 and anything that keeps
  its own colour (gold embroidery, a crest) at alpha 0. `--tint HEX` on push previews a colour; the game sets it.
- **Speed is built in, as long as geometry is deterministic.** Each atlas bakes as one merged copy of its
  pieces, and the unwrap and bake are cached per atlas in the output folder (`<atlas>.bake.npz`), keyed on its
  geometry and anything within AO reach. A paint-only change rebuilds in seconds; a shape change re-bakes only
  the atlases it can affect. The cache only works if a rebuild reproduces the same mesh: build spheres with
  `bl.sphere` or `shapelib.ellipsoid` (never bmesh's `create_uvsphere`, whose face order changes every run), and read
  vertex normals through bmesh after moving vertices. The build prints each texture as `baked` or `bake cached`;
  `<atlas>.timing.json` has the steps.
- **The sheet shows the real textures** (Workbench, texture colour, tinted parts in a preview blue, back faces
  culled so ink hulls read as outlines). Judge paint from it, then in Studio.
- **Ink outlines** (`inklib`): hulls are hidden while textures bake, or they darken the paint. Cap open tubes (an
  open end shows the hull's black inside), flag buried or underside faces with `ink_skip`, set `no_ink` on pieces
  whose outline only pokes through something else, and skip small pieces. Outlines roughly double the triangles.
- **The payload** is `<Name>.json` in format `blendlib-textured/1`: textured parts carry UVs and a texture, the
  rest (ink, eyes) a solid colour. `push` sends the textures first (RGBA rows into EditableImages, alpha intact),
  then the parts with SurfaceAppearances. `selftest` does not take painted payloads; push a preview instead.
- **`--upload` for painted assets** makes an Image asset per texture and a Mesh asset per part with
  `AssetService:CreateAssetAsync` (no API key; the group owns them in a group-owned place), wires each
  SurfaceAppearance to its image asset, and drops the preview EditableImages. New images go through Roblox
  moderation and can show blank for a few minutes after upload. Verified 2026-10-04 on `examples/painted_crate.py`
  (2 textures, 4 parts, 15 s): read back from Roblox, the images were byte-identical, alpha included, so trim
  painted at alpha 0 stays untinted after upload.

## Step 2: Build and look, every time

```
node <skill>/blend.js build <Asset>.py --out <scratchpad>/<Asset>
```

A run takes about 4 s. It prints the sheet and payload paths, the size in studs (W x H x D in Roblox axes), the
triangles per part, and any warnings. Then:

1. **Read `<Name>_sheet.png`.** Top left is a three-quarter perspective from the front left. Top right is the
   front, bottom left the right side, bottom right the top, all orthographic so proportions read true.
2. **Act on every warning:**
   - open edges: a hole or an unwelded seam;
   - closed but inside out: flip it;
   - zero-area triangles: dropped on export;
   - loose vertices;
   - triangles facing against their normals: this should never happen, so stop and investigate;
   - over budget.
3. Fix the script and rebuild until the sheet reads right. Never call an asset done from numbers alone.

The sheet uses Workbench's studio light and shows colours as authored. Roblox lighting differs, so judge final
colour in Studio, in Play.

## Step 3: Into Studio

```
node <skill>/blend.js probe
node <skill>/blend.js selftest <Name>.json --port N
node <skill>/blend.js push <Name>.json --port N --place-id ID --at x,y,z [--parent Workspace.BlenderImports]
```

- `selftest` builds every part unparented, checks triangle counts and size against Blender's, and destroys it. It
  changes nothing, so use it freely.
- `push` refuses a port whose place isn't `--place-id`, and refuses while a playtest runs. It builds
  `<Name>__incoming` one part per call, verifies it in a separate call, then replaces `<Name>`. If verification
  fails, the old model is untouched and the incoming one stays for inspection. Re-pushing is safe.
- **Previews first.** They look real in Edit but don't exist in Play. To look at one in the place, render it with
  `/assetshot` (`node ~/.claude/skills/assetshot/shot.js Workspace.BlenderImports.<Name> --out
  <scratchpad>\shots\<Name>`). Never move Studio's camera or call `capture_screenshot` to check it, because other
  sessions and the user share that camera.
- **`--upload` only after the user approves the asset.** Parts go to the group when the place is group-owned, at
  about 3-4 s each, and verification requires a `MeshAssetId` on every part. Push again after any Undo.
- **Where it lives.** `--parent` defaults to `Workspace.BlenderImports`, the review area. The approved upload goes
  straight to the model's home: `--parent ReplicatedStorage.Assets.Models --at 0,0,0` for a template the game
  clones through the `Assets` module, or the map for static scenery. Nothing ships from `BlenderImports`.
- **A push replaces the whole model.** Anything added to it in Studio since the last push (attachments, tags,
  prompts, welds, what `/makeweapon` wires) is destroyed with the old copy. Before re-pushing over a model already
  in use, list what it carries beyond its MeshParts and its `BlenderSource`/`Triangles` attributes, and re-apply
  that after the push.
- Never start or stop a playtest. Say what to check and ask the user to run it.

## Rules learned

- Eevee costs about 65 s a run, because every fresh Blender process compiles its shaders. The sheet uses Workbench
  (under a second per view).
- A bevelled curve's end caps are separate faces. `bl.tube` welds them; when you build curves yourself, weld with
  `bmesh.ops.remove_doubles`.
- Negative scale (mirroring) is handled on export, which flips the winding.
- A 19,320-triangle smooth part is a 0.9 MB payload. Single `execute_luau` calls of up to 2.4 MB were tested, so one
  call per part never needs chunking.
- The Studio MCP bridge (`robloxstudio-mcp` 1.4.0) hands a still-running `execute_luau` to the plugin again on
  every 0.5 s poll, so code that yields runs once per half second it lasts. Before blend.js put a one-time token on
  every call (2026-10-04), each 3 s `CreateAssetAsync` ran 5-7 times: a 6-asset crate made about 35 assets and 23
  stacked parts, which the name-based verify passed. A repeat now waits for the first run's result. Anything else
  that yields through the bridge needs the same guard, or `/assetshot`'s start-once job and short polls.
- Painted builds (Joust Tycoon's detailed armour set, five textures, measured 2026-10-04): a paint-only rebuild
  about 28 s including the sheet, a shape change about 2 min before automatic packing. Before the merged bake and
  the cache the same set took 5 to 7 minutes: Blender pays a bake setup per object per pass, so baking 35
  separate pieces was 90 s of overhead per texture where the merged copy takes under 4 s.
- UV packing: Blender's concave packer took 46 s on three bevelled boxes and 22-30 s on quilted shells, with no
  gain over box packing when islands are rectangular. `BLENDLIB_PACK_SHAPE=AUTO` (the default) packs boxes and
  uses the concave packer only when islands fill under 80% of their boxes and box packing used under half the
  texture. Low texture use on a smart-projected loft (a quilted shell used 28-31% with either packer) means its
  islands are poor; authoring the loft's own UVs would roughly double its texel density.
- The bake cache stores normals, AO and curvature at half precision; first builds paint from that same precision, so
  every build of an asset is byte-identical (a toon threshold would otherwise flip a few texels between builds).
- bmesh's `create_uvsphere` changes its face order from run to run; anything keyed on mesh data (the bake cache,
  cached UVs) must not use it. `bl.sphere` and `shapelib.ellipsoid` build spheres by hand for this reason.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `could not start Blender` | not installed, or not found | install 4.1+, or pass `--blender PATH` |
| `blendlib needs Blender 4.1` | an older Blender was picked | pass `--blender` pointing at a 4.1+ exe |
| a Python traceback | an error in the script | fix it; `build` prints the traceback |
| `error part X ... over EditableMesh's 20000` | the part is too dense | split with `roblox(part=...)`, or decimate |
| `probe` prints nothing | no Studio MCP server | ask the user to connect the MCP plugin in Studio |
| `unknown Roblox material` | not an `Enum.Material` name | e.g. `Wood`, `Neon`, `SmoothPlastic` |
| verify FAILED: incoming missing | Studio rolled the instances back | push again |
| `CreateAssetAsync ...` on `--upload` | unpublished place, or no permission | publish the place, or check group permissions |
| several MeshParts with one name, or extra assets, after `--upload` | a blend.js from before 2026-10-04 (no call token) under a bridge that repeats running calls | update blend.js; delete the stacked copies, one part per name |
| `pieces on two atlases` | one part's pieces were added to different atlases | one atlas per part |
| painted build re-bakes every time | geometry differs run to run (`create_uvsphere`, stale normals) | build deterministically; compare `_bake_key()` across two runs |
| gold trim tinted in Studio | texture pushed without alpha, or painted at alpha 1 | paint it at alpha 0; push with this blend.js (RGBA) |
| `CreateEditableImage returned nil` | Studio's EditableImage memory budget | fewer or smaller textures per place session, or upload |

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report. Per the global `CLAUDE.md`, project docs wait until the user approves the asset.
