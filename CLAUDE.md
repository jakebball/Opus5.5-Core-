# roblox-claude-setup: how it works inside

You are working in the team's Roblox × Claude Code setup repository. This file is the internal map: what every part
is, how the parts talk to each other, which files are generated, and how to change anything without breaking the
chain. `README.md` is the user-facing pitch and install guide; this file is for the agent maintaining the repo.

## 1. The shape of the repo

| Path | What it is | Edited how |
| --- | --- | --- |
| `skills/<name>/` | The 15 Claude Code skills the installer copies into `~/.claude/skills/` | **Generated.** Edit the maintainer's live install, then `node maintainer/export.js` |
| `skills/setup/project-setup.md`, `change-summary.md`, `examples/animation-style.md`, `template/`, `templates/`, `scaffold.js` | The standard `/setup` enforces, the change-summary rule, the worked animation guide, the new-project template (copied by `scaffold.js`), the on-demand doc templates | Generated with the skills, from the maintainer's standards folder |
| `claude/CLAUDE.md` | The team rules block the installer writes into each user's `~/.claude/CLAUDE.md` | By hand. `<projects>` is replaced at install time |
| `claude/personas/*.md` | Opt-in voices (`-Persona jarvis`) prepended to that block | By hand |
| `claude/settings.example.json` | A permissions allowlist and denylist users may merge | By hand |
| `install.ps1`, `install.sh` | The installers (Windows primary) | By hand; keep the two in step |
| `baseplate/RunnerBaseplate.rbxl` | The place every new game starts from | **Built** by `node maintainer/baseplate.js build` |
| `baseplate/src/` | The baseplate as Rojo source (Luau files, `.model.json`, `.meta.json`, a few `.rbxm`) | **Generated** by `maintainer/baseplate.js source`; durable edits go in `maintainer/baseplate-patches.js` |
| `baseplate/default.project.json` | The Rojo project: maps `src/` into services and defines the Workspace baseplate and spawn | By hand |
| `baseplate/extract.json` | What to copy out of a live game place and what to strip | By hand |
| `maintainer/export.js` | Live skills and standards → `skills/`, with path rewriting | By hand |
| `maintainer/baseplate.js`, `baseplate-patches.js` | Live place → `baseplate/src` → `RunnerBaseplate.rbxl` | By hand |
| `docs/setup-breakdown.html` | The team presentation (published as a Claude artifact) | By hand |
| `README.md`, `UPLOAD.md`, `THIRD_PARTY.md` | User docs, publishing steps, credits | By hand |

**Never hand-edit `skills/` or `baseplate/src/`.** Both are regenerated wholesale; an edit there is lost on the next run.

## 2. The two generation pipelines

### Skills: `maintainer/export.js`

1. Copies the `SHIPPED` skills from `--skills` (default `~/.claude/skills`) into `skills/`, after deleting `skills/`.
2. Skips `EXCLUDE`: `__pycache__`, `.pyc`, `assetshot/cache/` (≈700 MB of Studio mesh and image exports),
   `importmeshtools/vendor/robloxMeshTools/` (third party, no license; the installer fetches it), `.env`, `node_modules`.
3. Copies `project-setup.md`, `change-summary.md` and FPSTowerDefense's `features/animation-style.md` from
   `--standards` (default `SETUP_STANDARDS` or `~/Desktop/ClaudeProjets`) into `skills/setup/`.
4. Rewrites every text file (`rewrite()`): the maintainer's absolute paths become `~/.claude/skills/...`,
   `~/.claude/skills/setup/{project-setup,change-summary}.md`, `~/.claude/{.env,CLAUDE.md}` and `<projects>/`.
5. Prepends a "Paths in this document" note to `skills/setup/project-setup.md`.
6. **Fails (exit 1) and lists every line that still contains the maintainer's user name or home path.** Add a rewrite
   rather than editing the output.

### Baseplate: `maintainer/baseplate.js`

1. `extract --place-id ID` (the source game open in Studio; the id is never committed): for each `take`, one
   deferred bridge run clones the subtree **unparented**, strips it (`remove` dotted paths, `keepOnly` per folder,
   `moveChildren` e.g. `Disabled` → `Components.Generic`, `ensureFolders`), serializes it with
   `SerializationService:SerializeInstancesAsync`, base64s it with `EncodingService`, parks it in `_G`, and Node pulls
   it in 900 KB slices into `baseplate/.extract/<out>.rbxm`. The live place is never modified.
2. `source`: builds `.extract/raw.rbxl` from a generated project that mounts the four `.rbxm` files, then runs
   `rojo syncback` against `.extract/sync.project.json` (the real project with project-only nodes such as `Workspace`
   removed, because syncback cannot create them) to write text sources into `baseplate/src/`. Script roots are seeded
   with `init.server.luau` / `init.client.luau` from each take's `class`, or syncback refuses to change a Folder into a
   Script. Then every patch in `maintainer/baseplate-patches.js` is applied; a patch that changes nothing fails the run.
3. `build`: `rojo build default.project.json -o RunnerBaseplate.rbxl`.

`all` runs the three in order. `source` refuses to overwrite `src/` without `--force`.

**What the baseplate contains, and the rule behind it.** Keep what every Runner game shares; drop what one game added.
The 2026-10-06 extract came from Joust Tycoon and was cross-checked against FPSTowerDefense and SecureTheConcert:
Joust's `Components/JoustTycoon`, `Shared/JoustTycoon`, its five configs, two admin commands, 27 UI components, every
StarterGui panel, its models, map, ServerStorage, lighting and material variants were removed; the components Joust had
parked in `Disabled/` were restored to `Components/Generic`. Patches then fix the two known framework bugs (GoodSignal
`Connection.Destroy`, client `Zone:destroy`), reset `Profile` to a minimal template, empty `Monetization`, drop
`NumberUtils.Gold`, and blank the admin `GroupId` / `UserOverrides`. Verify after any change: decode the `.rbxl` and grep
for game names, and compile every script in Studio (`loadstring`, one file per call).

## 3. Installation (`install.ps1` / `install.sh`)

1. Toolchain check: Node ≥ 18, git, `claude`, Blender (newest `Program Files\Blender Foundation\Blender X.Y`, or
   `BLENDER`; on macOS `PATH` or `/Applications/Blender.app`). Problems are collected, never fatal mid-run; exit 1 at the
   end if any.
2. Each `skills/<name>` replaces `~/.claude/skills/<name>`; the old folder is **moved** to
   `~/.claude/backups/roblox-claude-setup-<stamp>/`. The old `assetshot/cache` is moved back (it is expensive to rebuild).
3. robloxMeshTools: GitHub archive of the pinned commit into `importmeshtools/vendor/robloxMeshTools` with a fresh
   `VENDORED.md`. Offline or `-SkipMeshTools`: the backed-up copy is moved back.
4. `CLAUDE.md`: the block between `<!-- roblox-claude-setup:begin -->` and `<!-- roblox-claude-setup:end -->` is
   replaced; everything outside it is kept; the lines after `Known project update logs:` inside the old block (projects
   `/setup` registered) are carried into the new one. A `.bak-<stamp>` copy is written first.
5. Smoke build: `blend.js build examples/pumpkin_crate.py` must print `built PumpkinCrate` with no `warn` / `error`.

`-ClaudeHome` / `--claude-home` points everything at another folder: test installs go there, never into the real home.
Paths longer than 260 characters break Windows file APIs, so test under a short path such as `%TEMP%\rcs-test`.

## 4. Talking to Studio (every tool)

All Studio access goes through the **Studio MCP plugin's HTTP bridge** (boshyxd/robloxstudio-mcp; upstream archived,
fork Chrrxs/robloxstudio-mcp): `POST http://127.0.0.1:<port>/mcp`, JSON-RPC `tools/call` with
`name: "execute_luau"`, `arguments: { code }`. The reply is SSE `data:` lines or a JSON body; `result.content[0].text` is
JSON `{ success, returnValue | error }`. The port is one of 58741-58750 and moves between Studio restarts; several
Studios (or several MCP servers on one plugin) can answer at once.

Bridge behaviour every tool must survive:

- **Repeat delivery.** A still-running call is handed to the plugin again on every 0.5 s poll, so yielding code runs
  repeatedly. Guard every call with a one-time token (`_G[token]`): a repeat waits for the first run and returns its
  result.
- **~30 s call timeout.** Long work starts under `task.defer` with a token and is polled until done.
- **Request size.** Very large single calls fail with "Malformed string" while the plugin parses them; keep a call
  under roughly 120 KB of embedded source and batch.
- **Wrong place.** Check `game.PlaceId` before writing; refuse while `RunService:IsRunning()` (a playtest).
- **Embedding text.** Use a Lua long bracket with a free `=` level; JSON-escaped Windows paths break Lua escapes.

`skills/studio/bridge.js` is the shared implementation (`resolve`, `once`, `onceLua`, `deferred`, `probe`,
`longString`, `findProjectRoot`, `readConfig`). New tools must require it. The four older tools load it as
`studioBridge` (from `../studio/bridge.js`, falling back to their old behaviour if `/studio` is missing) for **port
discovery and the place check**: with no `--port` they call `resolve` with `--place-id` or the project's `studio.json`
`placeId`. They keep their own proven call paths: `blend.js` its `onceLua` + `_G.BlendCalls` guard (push still requires
`--place-id`), `assetshot/shot.js` its start-once job and polling, `itemicon/icon.js` its `_G.ItemIconCalls` guard and
retries (and `resolve({ writes: true })` refuses a playtest when uploading), `importmeshtools/meshtools.js` now wraps
every call in `bridge.onceLua`.

## 5. The skills

### `/setup` (`scaffold.js` + instructions)
New projects are **copied, not written**. `scaffold.js new <Name> [--dir] [--kind roblox|generic] [--pitch] [--place-id]`
copies `skills/setup/template/<kind>/` and fills `{{NAME}}`, `{{NAME_ID}}`, `{{DATE}}`, `{{PITCH}}`, `{{PLACE_LINE}}`, and for
Roblox `{{RULES}}` / `{{RULE_COUNT}}` / `{{CHANGE_SUMMARY}}`, which it reads **at copy time** from
`project-setup.md` § Seeded Hard Rules (the bullets before "Keep this seed in sync") and the Change Summaries pointer
block, so the template cannot drift from the standard. It refuses a non-empty target, runs `git init`, and with
`--place-id` calls `link`: writes `studio.json`, runs `studio/sync.js pull`, and rewrites the `- **Place:**` line of
`index.md`. `places` lists open Studio places (bridge probe); `rules` lists the seeded rule names (the audit diffs a
project against it). `SKILL.md` then asks only what needs a person (pitch, look, animation feel, which place; all
optional), fills only the answered sections, and registers the project. Audit mode reads the whole standard and checks
docs and the live place. **To change what every new project gets:** edit `template/` or the standard's § Seeded Hard
Rules, never a generated project. A new Luau rule also goes into `/deslopify` § 2d.

### `/studio` (`bridge.js`, `sync.js`, `run.js`)
- `sync.js` finds the project by walking up to `studio.json` (`placeId`, `gameSource`, optional `roots`, `steps`,
  `preludes`, `shared`, `sharedFolder`). Layout `game-source/<Root>/<path>/<Name>{.luau|.server.luau|.client.luau}`;
  a script with children is a file plus a same-named folder. Roots: the seven script-bearing services (`Workspace`
  opt-in). Sync bases are SHA-1s of LF-normalised source in `game-source/.sync/<rel>.sha1`, one per script, so parallel
  pushes never race. `push` = compile check (`loadstring`, batched by size) → refuse if Studio's hash ≠ base unless
  `--force` → write (creating missing parent Folders) → read back (an open editor tab silently wins) → update base.
  `pull` never overwrites a disk file whose hash ≠ base. `status` classifies `edited disk` / `edited Studio` /
  `CONFLICT` / `new on disk` / `only Studio`.
- `run.js` builds `local ARGS = {...}` from `--set`, prepends `-- uses:` modules as
  `local Name = (function() ... end)()` and any `preludes` for the file's folder, installs `shared` modules into
  `sharedFolder` (a changed module becomes a **new** ModuleScript, beating Edit-mode's require cache), then runs each
  file through `bridge.deferred`.

### `/blenderassets`
- `blend.js build X.py` spawns `blender -b --factory-startup --python-exit-code 1 -P python/run.py -- X.py OUT`.
  `run.py` puts `python/` and the script's folder on `sys.path` and runs it. The script calls `bl.reset()`, models in
  plain `bpy`/`bmesh`, tags objects with `bl.roblox(obj, part=, material=, collision=, collide=, shadow=, attributes=)`
  and `bl.socket(...)`, and ends with `bl.finish(name, budget=)`, which: runs `paintlib.build_all` if imported →
  converts curves/text to meshes → runs the geometry checks (open edges, loose verts, zero-area, inside-out, part over
  20,000 triangles is an **error**, budget) → renders the four-view Workbench sheet `<Name>_sheet.png` → exports →
  prints `BLENDLIB {json}` (Node parses the last such line).
- **Axes:** Roblox `(x, y, z)` = Blender `(-x, z, y)`; front is Blender −Y → Roblox −Z; mirrored objects flip winding.
- **Payload `blendlib/1`:** `{format, name, source, blender, quantum: 1000, size, triangles, meshes[], sockets[]}`; each
  mesh `{name, material, collision, collide, shadow, attributes, triangles, inverted, v (int ×1000), n (unique normals
  ×1000), c (hex colours), t (9 ints per triangle: v v v n n n c c c, 1-based)}`; each socket `{name, part, p, up,
  front, attributes}`. **`blendlib-textured/1`** adds `uvQuantum: 10000`, `textures{atlas: {file (.rgba), png, width,
  height}}` and per mesh `texture`, `colour`, `tint`, `u`, with `t` as `v v v n n n uv uv uv`.
- **`push`** (needs `--port` and `--place-id`, refuses a playtest): builds `<Name>__incoming` one part per call (MeshKit
  from the vendored robloxMeshTools is inlined into each call, nothing is installed), textures first as EditableImages
  in 192-row base64 chunks, then sockets as Attachments (`BlenderSocket=true`), then **verifies in a separate call**
  and only then swaps it in for `<Name>` with `BlenderSource` and `Triangles` attributes. A failed verify leaves the old
  model untouched. `--upload` makes Mesh and Image assets with `AssetService:CreateAssetAsync` (group creator when the
  place is group-owned).
- **Painted path:** `paintlib.Atlas` (one texture per MeshPart, ≤ 1024²) bakes position, normal, ID, curvature and
  coordinate passes plus AO on the GPU for one merged copy of its pieces, caches them in `<atlas>.bake.npz` under a
  SHA-1 `_bake_key` (geometry, transforms, UVs, neighbours within AO reach, bake settings; **not** the painter), reloads
  from the cache so every build paints from identical float16 data, then calls the painter per texel. `brushes/` is the
  versioned painter library: `@brush("family.name", version=N, ...)` registers `family.name@N`; `styles/<name>.json`
  pins painters to roles; `brushes.use_style(name, palette=)` → `style.painter(role)`. `node blend.js brushes`
  re-renders swatches and **always** rewrites `CATALOG.md` / `catalog.json`. Visual changes to a brush are a new version,
  never an edit. `shapelib` = deterministic cloth/gear builders (never bmesh's `create_uvsphere`: its face order
  changes per run and breaks the cache); `inklib.outline` = inverted-hull toon ink on part `<part>Ink`.

### `/assetshot`
`shot.js` assembles `export.luau` (ARGS, a pose function, a run id), starts it once under `task.defer`, polls
(`PENDING` / `DONE chunks bytes` / `ERROR`), fetches 4 MB chunks and releases the job. In Studio it collects every
BasePart under the targets, describes each (MeshPart content key `asset:` / `local:` / `object:`, SurfaceAppearance,
material variant, decals), reads meshes with `CreateEditableMeshAsync` and images with `CreateEditableImageAsync`
(skipping what Node already caches in `cache/meshes` and `cache/images-<limit>`), and returns snaps (20 numbers per part
per frame). `render.py` rebuilds the scene in Blender Cycles (GPU first), renders labelled tiles (perspective, front,
left, right, back, top, camera, focus) and composes `<name>_sheet.png`. **Icon mode** (`--icon SIZE`) renders one
transparent square orthographic image. Pose scripts (`--pose FILE`, `--arg k=v`) build private posed copies through the
`shot` API (`find`, `pivot`, `temporary`, `studioCamera`, `snap`); they must never touch shared state. Particles,
lights, GUIs and unowned meshes are not drawn (reported).

### `/demo`
`demo.js record <demo.luau>` wraps the demo body with `DemoKit.luau` into `StarterPlayerScripts.__DemoDirector` (plus an
optional `ServerScriptService.__DemoDirectorServer`; both delete themselves outside Studio), brings the Studio window to
the front (PowerShell, `ShowWindow` + `SetForegroundWindow`), records the **whole desktop** with ffmpeg `gdigrab`,
starts the playtest through the bridge's HTTP endpoint (`tools/call` `start_playtest` `{mode: "play"}`), polls
`get_playtest_output` for `[demo] start` / `[demo] done` and forwards `[demo:key] <KeyCode> <hold>` lines as
`simulate_keyboard_input` on `client-1`, then stops the playtest and ffmpeg and removes the scripts in a `finally`.
`process` scans the raw video at 10 fps / 320×180 for **marker flashes**: DemoKit fills the game view magenta for 0.5 s
then green for 0.5 s at the start and the end. A flash is a frame whose pure-magenta share jumps 6 % above the
recording's median and lasts ≤ 1.5 s; the crop box is the solid rows and columns of pixels that are magenta in the
flash and green 0.5 s later, so nothing static on the desktop or in the game can fake it. The clip is trimmed between
the flashes, cropped, scaled to ≤ 1280 wide and encoded H.264 under 24 MB with a poster JPEG. **No flash, no clip**: the
raw desktop recording is deleted (unless `--keep-raw`) and never sent. Claude never calls `start_playtest` itself
(the maintainer's settings deny it); `/demo` is the sanctioned path, used only on the user's request.

### `/itemicon`
`icon.js` runs `shot.js --icon <2×size>`, then `finish.py` (PIL: trim alpha, pad square, dilate + blur an outline,
LANCZOS down). `--upload` writes 128-row base64 chunks into an EditableImage and `CreateAssetAsync`s an Image; the id is
stamped as the model's `IconImage` attribute and recorded in `--manifest` (`ui-source/renders/renders.json`:
`{name: {file, source, assetId}}`). Targets are keyed by their last path segment.

### `/importmeshtools`
Installs the vendored robloxMeshTools sources as StringValues under `ServerStorage.ModelKit` (backslashes sent as a
sentinel), verifies in a separate call (length, compile, a smoke box), and runs Luau files. `/blenderassets` does not
use the installed copy; it inlines `kit/MeshKit.luau` from disk.

### Instruction-only skills
`/create-animation` (Studio `CreateAssetAsync` or Open Cloud `assets/v1`; creator must match the place owner or the
animation never loads; cache `~/.claude/.roblox-animation-creator.json`), `/create-devproduct` and `/create-gamepass`
(Open Cloud, `ROBLOX_OPEN_CLOUD_API_KEY` from `~/.claude/.env`, universe cached in `./.roblox-universe`, optional
registration into the `Monetization` config), `/upload-images` (Open Cloud Decals, then Decal → Image id),
`/makegui`, `/makereactcomponent`, `/makeweapon` (wiring recipes on the Runner framework), `/deslopify` (approval-gated
Hard Rule sweeps).

## 6. The baseplate's Runner framework

- **Boot.** `ServerScriptService.Runner` (Script) moves `Runner.Shared` to `ReplicatedStorage.Shared` and requires
  `EntityStore`. The client `Runner` (LocalScript) requires its own `EntityStore`.
- **EntityStore.** Finds `BaseClass` by the **CollectionService tag `BaseClass`** (keep the tag, or nothing boots).
  `collectComponents` requires every ModuleScript under `Runner/Components/**`; each must have `Tag` (globally unique,
  equal to the module name). Every class gets every `Shared` module (by name, folders flattened), every other
  component class by Tag, `EntityStore` and `BaseClass` injected as fields. **Never `require` an injected module.**
  `Class.Start()` runs once in its own thread; `Observers.observeTag(Tag)` calls `addComponent` for every tagged
  instance (now and later) and `removeComponent` when the tag or instance goes. API: `addComponent(instance, tag, ...)`,
  `removeComponent`, `getComponent`, `findComponent`, `promiseGetComponent`, `removeEntity`,
  `onComponentAdded/Removed`. `Disabled/` beside `Components/` is not scanned: moving a module there switches it off.
- **BaseClass.** `BaseClass.new(instance)` gives `self.instance`, `self.trove` and a per-instance remote folder
  `ReplicatedStorage.ComponentRemotes.<id>`, where `<id>` is a GUID stored in the instance's `ComponentRemoteId`
  attribute. Server: `registerRemote` / `registerUnreliableRemote`, `sendNetworkEvent(player | "All", name, ...)`,
  `onRemoteEvent(name, fn(player, ...))`. Client: `sendNetworkEvent(name, ...)`, `onRemoteEvent`, resolved by promise
  once the folder replicates. `BaseClass.sharedRemote(channel, name)` is the one server-wide channel form. **A tag left
  on a template is inherited by every clone together with its `ComponentRemoteId`, so clones share one remote folder:
  templates carry no component tags.**
- **State to clients** is a component-owned `<Thing>Sync` table sent on change, mirrored by a client component with a
  `changed` signal. Attributes are not a data channel (Hard Rule).
- **`getConfig()`** returns `{ [ModuleName] = require(module) }` for every ModuleScript under `Shared/getConfig`.
- **AdminSystem** (`Setup`, `Config`, `ServerHandler`, `Commands/*`, `Assets/*`): ranks in `Config.Roles` for
  `Config.GroupId`, plus `UserOverrides`; `BlanketEnable` gives everyone admin in Studio only.

## 7. Changing things

- **A skill:** edit it in `~/.claude/skills/<name>`, test it there, run `node maintainer/export.js`, review the diff.
- **A new skill:** create it live, add its name to `SHIPPED` in `maintainer/export.js`, document it in `README.md`
  and § 5 here, and, if `/setup` should seed it, in `project-setup.md`.
- **The standard (`project-setup.md`):** edit the maintainer's copy, export. A new Hard Rule goes into the seed list,
  into every live project's `tech-design.md` that should have it, and into `/deslopify` if it is a Luau rule.
- **A brush or style:** in the live `blenderassets/python/brushes/`, then `node blend.js brushes`, then export.
- **The baseplate:** framework improvements land in a game first; then `node maintainer/baseplate.js all --place-id <ID>` with that game
  open (update `extract.json` for anything new the game added, and `baseplate-patches.js` for durable edits). Decode and
  compile-check before committing `RunnerBaseplate.rbxl`.
- **The installers:** change both; test with `-ClaudeHome "$env:TEMP\rcs-test"` (and `--claude-home /tmp/rcs-sh`), run
  twice to prove re-install keeps user content, and once with `-SkipMeshTools`.

## 8. Rules for this repo

- **Public repository.** Never commit `.env`, API keys, cookies, a user's group or user ids, product ids, or a personal
  path. `export.js` fails on personal paths; grep `[0-9]{7,}` in new config before committing.
- **No third-party code without its license.** robloxMeshTools stays fetched. Libraries in the baseplate are credited in
  `THIRD_PARTY.md`.
- **Never start or stop a playtest, and never move Studio's camera** (render with `/assetshot`). The maintainer tools
  only read the place.
- **Docs follow the user's approval** of a change (global `CLAUDE.md`), except requests that are themselves about docs.

## 9. Known gaps

- `/makegui` still says `Components/Gui` and mentions an MCP `list_roblox_studios` tool; the baseplate uses `Components/UI`.
- `/create-devproduct` and `/create-gamepass` patch `Monetization` with `set_script_source`; in a project with
  `game-source/` they should edit disk and `sync.js push`.
- `/upload-images` trusts the cached creator over the live place (`/create-animation` does the opposite).
- No offline renderer for GUIs; `assetshot` skips them.
- Windows is the only tested platform. `/demo` uses `gdigrab`, so it is Windows-only, and it has not yet recorded a real
  playtest end to end (built and tested offline on 2026-10-07 while Studio was in use).
