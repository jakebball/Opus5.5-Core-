# Project Setup & Management

> **Paths in this document:** `~/.claude/skills` is your Claude Code skills folder (`%USERPROFILE%\.claude\skills` on Windows) and `<projects>` is the folder you keep projects in, recorded in your `~/.claude/CLAUDE.md` by the installer.

This document defines how all projects under `<projects>/` are set up and managed. Every project must follow these standards.

## Prerequisites (once per machine)

The standard leans on a small toolchain. `/setup` checks it on every new project and names what is missing.

| Tool | Why | Check |
| --- | --- | --- |
| Claude Code | runs the skills | `claude --version` |
| Roblox Studio + the Studio MCP plugin ([boshyxd/robloxstudio-mcp](https://github.com/boshyxd/robloxstudio-mcp)), with the MCP server added to Claude Code as `robloxstudio` | every Studio read and write, and the HTTP bridge (`127.0.0.1:58741-58750/mcp`) the Node tools call | `node ~/.claude/skills/studio/sync.js probe` |
| Blender 4.1+ | `/blenderassets` builds, `/assetshot` and `/itemicon` renders (headless, no window) | the smoke build in step 6 |
| Node 18+ | every skill script (global `fetch`, no npm packages) | `node --version` |
| git | the project history, and `game-source/` diffs | `git --version` |
| robloxMeshTools ([MrChickenRocket/robloxMeshTools](https://github.com/MrChickenRocket/robloxMeshTools)) | `MeshKit`, sent with every `/blenderassets` push; lives in `~/.claude/skills/importmeshtools/vendor/robloxMeshTools/` | that folder exists |

## Default Roblox Boilerplate (inherited by every new place)

Every new place is started from the **team baseplate**: `RunnerBaseplate.rbxl` in the setup repo (`baseplate/`), built
with Rojo from `baseplate/src/` and extracted from a live game by `maintainer/baseplate.js` with every game-specific
part removed. It holds the **Runner framework** + **AdminSystem** + **standard asset folders**. When scaffolding a project,
assume this layout exists in Studio and reference it in `tech-design.md` (lists below are the baseplate as of 2026-10-06):

### Server — `game.ServerScriptService.Runner` (Script)
- `EntityStore` (ModuleScript) — tag-based ECS-hybrid registry; auto-instantiates components, injects siblings/Shared by name. Never `require()` injected modules.
- `BaseClass` (ModuleScript) — base for component classes (`new`, lifecycle hooks, per-instance remotes, `sharedRemote`).
- `Components/Generic/` — drag-and-drop portable components (do NOT add game-specific named-object grants here):
  - **Player layer**: `PlayerProfile`, `PlayerCurrency`, `PlayerNotify` (toasts with a kind: Success, Error, Warning, Info), `PlayerPolicy`, `Character`, `CharacterMovement`, `ChatTag`, `GroupMembership`, `PositionHistory`
  - **Items**: `Inventory`, `HotbarAssignment`, `Collectable`
  - **Commerce and live ops**: `Commerce`, `ProductLadder`, `Subscription`, `SeasonPass`, `Quests`, `Funnels`, `LiveConfig`
  - **Combat**: `Gun`, `WeaponAnimation`, `FireCycleReload`, `Hitbox`, `Projectile`, `ProjectilePhysics`, `Ragdoll`
  - **NPC and AI**: `NPC`, `BehaviourTreeRunner`
  - **World**: `Animator`, `WorldEffects`, `MusicCatalog`
  - **Telemetry**: `ServerFpsLogger`
  - **Actions** (Configuration container)
- `Shared/getConfig` — auto-discovers child ModuleScripts. Default configs: `Analytics`, `BehaviourTree`, `Combat`, `Debug`, `LiveConfig`, `Monetization` (empty), `Movement`, `Music`, `NPCs`, `Performance`, `ProductLadders`, `Profile` (a minimal template: `Currencies.Coins`, `Inventory`, `HotbarGuids`, `EquippedItems`, `TotalXp`, `LastSeen`, `OnboardingComplete`, `SeasonPass`, `Quests`; `ProfileVersion` 1), `Progression`, `ServerAuth`, `Subscriptions`, `Weapons`. A game adds its own configs beside them.
- `Shared/Generic/` — utility libraries (do not duplicate; reuse). Third-party ones are credited in the setup repo's `THIRD_PARTY.md`:
  - **Observers/**: `observeAttribute`, `observeCharacter`, `observeLocalCharacter`, `observePlayer`, `observeProperty`, `observeTag`
  - **Async / events**: `GoodSignal`, `Trove`, `Promise`
  - **Persistence**: `Profilestore`
  - **Spatial**: `Zone` (ZonePlus), `Octree`, `GroundSampler`, `PathFollower`
  - **Tweening and motion**: `Spr`, `UITween`, `CameraShake`, `Letterbox`
  - **Numbers and colour**: `NumberUtils`, `LevelGradient`, `ColorSequenceUtils`
  - **Input**: `InputManager`, `DragManager`
  - **Assets / VFX**: `Assets`, `EffectUtils`, `ViewportUtils`, `DebrisBurst`, `ConfettiCannon`, `EmitModule`, `Shine`, `RewardFlyer`
  - **Combat maths**: `Ballistics`, `HitscanMath`, `ProjectileBody`, `ProjectileCodec`
  - **Audio**: `LocalSFX`, `WorldSFX`, `SoundWindow`
  - **Rigs and rounds**: `RigPool`, `AvatarRandomizer`, `RoundVisibility`
  - **Environment**: `WindLines`, `WindShake`, `Rain`
  - **AI**: `BehaviorTreeCreator`
  - **UI lib**: `Icon` (TopbarPlus)
  - `getInstance`

### Client — `game.StarterPlayer.StarterPlayerScripts.Runner` (LocalScript)
- `EntityStore`, `BaseClass` — same shape as server.
- `Components/Generic/`:
  - **Player mirrors**: `PlayerCurrency`, `Inventory`, `HotbarAssignment`, `PlayerPolicy`, `GroupMembership`, `ChatTag`
  - **Commerce and live ops**: `Commerce`, `ProductLadder`, `ShopTransactions`, `Subscription`, `SeasonPass`, `Quests`, `LiveConfig`, `PlayerInviter`, `ServerIndicator`
  - **Camera and movement**: `CharacterMovement`, `OverShoulderCamera`, `CinematicShell`, `Spectator`, `FreeCursor`
  - **Combat**: `Gun`, `FPSViewmodel`, `ChamberedRound`, `Hitbox`, `ProjectilePhysicsClient`, `Ragdoll`
  - **World and spatial**: `Zone`, `ProximityHighlight`, `ProximityPrompt`, `ProximityTrigger`, `WorldEffects`, `AxisSquish`, `EditorMarker`
  - **NPC / animation / audio**: `NPC`, `Animator`, `MusicPlayer`, `MusicCatalog`
  - **Settings**: `Settings` (a game with its own settings panel moves it to `Disabled/`)
- `Components/UI/`: client UI components live here, **not** in `Generic/` and **not** in `Components/<GameName>/`. (Older docs and the first version of the seed rule call it `Components/Gui/`; use whichever the place actually has, and record it in `tech-design.md`.) The baseplate ships the UI primitives `Button` (debounced `triggeredEvent`), `Frame` (tweened open/close, owns `.Visible`), `Slot`, `ModelViewport`, `PhysicalViewport`, `PlayerHeadshot` and `RainbowGradient`. Any new component whose only job is to drive a ScreenGui / GuiObject — HUD readouts, panels, prompts, toasts, popup menus — belongs here. Rule of thumb: if the component's `instance` is a GuiObject (Frame / ScreenGui / TextLabel / ImageButton / etc.) or it tags a Player only to mirror UI state, it's a Gui component. Game logic components that happen to push to an attribute the UI reads stay in `Components/<GameName>/`.

### Turning boilerplate off, and known boilerplate bugs
- **`Disabled/`:** a generic component that fights the game is moved out of `Components/` into a `Disabled/` folder beside it in that Runner, where `EntityStore` does not load it. Bring it back by moving it into `Components/` again, and list what is disabled in `tech-design.md`. Never delete boilerplate to turn it off.
- **Latent bugs fixed in the team baseplate** (a place made from an older template still has them; fix them there at setup):
  - `trove:Add(goodSignal:Connect(...))` throws, because GoodSignal's `Connection` has no `Destroy`. Fix: give `Connection` a `Destroy` alias of `Disconnect` in `Shared/Generic/GoodSignal`.
  - The client `Zone` component's `destroy` is empty, so ZonePlus zones leak when a zone instance goes away. Fix: destroy the zone and disconnect its signals there. Do not put Zone signal connections in a Trove.
- **Check against the place:** each new project reads the live Runner (component lists, `getConfig` children, the UI folder name) at setup and records any difference from this section in its `tech-design.md` § Inherited Framework. The place wins over this document.

### AdminSystem — `game.ServerScriptService.AdminSystem`
- `Setup` (Script), `Config` (ModuleScript: set `GroupId` and `UserOverrides` per game; group ranks in `Roles` get admin), `ServerHandler` (ModuleScript)
- `Commands/` — generic commands: `Ban`, `Unban`, `Kick`, `ResetPlayerData`, `WorldEvent`, `GiveWeapon`. **Game-specific give-commands are project-owned** — add your grant kinds (e.g., `GiveGold`, `GiveResource`) beside them in the project.
- `Assets/` — `AdminClient` (LocalScript), `AdminPanel` ScreenGui template, `GlobalMessage` ScreenGui, `GlobalMessageItem` / `AdminListItem` Frame templates.

### ReplicatedStorage layout — `game.ReplicatedStorage.Assets`
- `Models/` — game models (preloaded for client); seeded with `BaseRig` and `Viewmodel` (the FPS layer's)
- `Misc/` — uncategorized
- `Gui/` — UI templates (`HotbarItem` is seeded; add per-project)
- `VFX/` — particle / beam templates (`DebrisBurst`, `Bullet` seeded)
- `Sounds/UI/` — `Click`, `FrameOpen`, `FrameClose`, `ButtonHover`, `Error`
- `Sounds/Misc/` — `PurchaseSuccessful`, `CollectMoney`, `RoundStart`, countdowns and more; `Sounds/Weapons/`, `Sounds/Plot/` and `Sounds/Concert/` hold the shared sound library
- `Sounds/Music/` — background music
- `Tool/` — Tool instance templates
- `Animations/` — KeyframeSequence / Animation assets

### Workspace
- Default: `Camera`, `Terrain`, `Baseplate` (512×512 anchored slab, top at `Y=0`), `SpawnLocation` (12×12, centred on the baseplate). Project-specific maps / zones added under Workspace as the game develops — replace the baseplate with the real map when ready.

### UI conventions
- **Scaling** — every UI is sized and positioned in Scale with `UIAspectRatioConstraint` on parent frames, never Offset and never a fitting `UIScale`. The full rule is the seeded hard rule **UI is sized in Scale, never Offset** below.
- **Currency / membership glyphs** — when a price or label needs the **Robux** badge, embed Unicode codepoint **U+E002** inline (`"\u{E002}"`). For the **Premium** membership star, use **U+E001** (`"\u{E001}"`). Both are Private-Use-Area glyphs bundled with Roblox's default font family — no external font asset required. They inherit `TextColor3` like any other character. Example: `priceLabel.Text = "\u{E002}49"` renders as the Robux badge followed by `49`.
- Shorthand the user uses across all projects: **"Roblox glyph" / "Robux glyph" = `\u{E002}`**, **"Premium glyph" = `\u{E001}`**. Mention either by name and the glyph is the intended substitution.

### What this means for `tech-design.md`
Every new project's `tech-design.md` MUST:
1. Declare the Runner framework as the architecture (server + client entry points above).
2. Reference the existing generic components by name — design new game-specific components as additions to `Components/<GameName>/`, not by re-implementing what's already in `Generic`.
3. Note the AdminSystem is present and that game-specific give-commands are project-owned (not framework).
4. Default to `ReplicatedStorage.Assets.<Subfolder>` for asset locations rather than inventing new paths.
5. Declare headless Blender as the 3D asset pipeline (`blender-source/`, built with `/blenderassets`), per **3D Asset Pipeline** below.
6. Point every new asset at the project's art style through the seeded **Every new visual asset follows the project art style** rule, per **Art Style** below.

## 3D Asset Pipeline — headless Blender

**Every Roblox project authors its new 3D mesh assets in headless Blender**, through the `/blenderassets` skill
(`~/.claude/skills/blenderassets/`). Each asset is a Python script: `blend.js build` runs it in Blender
with no window, renders a four-view contact sheet, checks the geometry and writes a payload, and `blend.js push`
builds that payload in the place as MeshParts over the Studio MCP: vertex-coloured by default, or painted (textured)
for a project whose art style paints its assets. Nothing is installed into the
place; the Roblox side is robloxMeshTools' `MeshKit`, borrowed from the `importmeshtools` skill's vendored copy and
sent with each call. The skill's `SKILL.md` is the how-to, the seeded hard rule (**3D models are authored in
headless Blender**, below) carries the obligations into each project, and this section is the standard itself.

- **Toolchain:** Blender 4.1+ (`blend.js` takes the newest under `Program Files\Blender Foundation`; `--blender PATH`
  or the `BLENDER` env var overrides), Node 18+, and the Studio MCP plugin attached for `push`.
- **Layout:** one script per asset at `blender-source/<Asset>.py` in the project root. Helpers shared by a project's
  assets are a plain module in the same folder, imported directly (the runner puts the script's folder on
  `sys.path`). Build output (sheet PNG, payload JSON) goes to the session scratchpad and is never kept in the
  project: a build regenerates it in seconds.
- **Covers** any static mesh: props, structures, vehicles, weapon bodies, character gear, scenery pieces. **Does not
  cover** plain `Part`s (collision clips, trigger zones, spawn pads, greybox), UI, VFX, animations, skinned meshes,
  or art that must stay real Parts (studs only render on Parts). Those keep their usual tooling.
- **Painted path:** when the art style paints its assets (hand-painted, painted toon), the same scripts add
  `paintlib` atlases: textures generated from the model by painters from the `brushes` library (picked by role
  from the art style's style profile), cloth and quilting builders (`shapelib`) and toon outlines (`inklib`).
  Bakes run on the GPU and are cached per texture, so a paint-only change rebuilds in seconds. The skill's
  `SKILL.md` § Painted textures is the how-to; Joust Tycoon's starter set (2026-10-04) is the first worked use.
- **Precedence:** a project that already builds its models another way keeps that way, and says so in its docs.
  Pick the Crops bakes studded brick models with FarmLib; other projects generate meshes from Luau with the mesh
  kit (`mesh-source/`, `map-source/`). Existing assets are never migrated to Blender just to conform.

**Auditing an existing Roblox project:**
1. Find where the project says how 3D models are authored: `tech-design.md`, `index.md`, or a feature doc.
2. If it names Blender, check `blender-source/` exists. If it names another pipeline, report it as the project's
   deliberate choice and change nothing.
3. If the docs are silent, look for a pipeline anyway: source folders (`mesh-source/`, `map-source/`,
   `world-source/`), generator scripts, a `ServerStorage.ModelKit` in the place. Report what you find and offer the
   choice: adopt Blender for new assets (seed the hard rule, create `blender-source/`), or record the existing
   pipeline in `tech-design.md` as the project's rule.
4. Run the toolchain smoke build (Setup Checklist, **Set Up the 3D Asset Pipeline**) and report the Blender version
   it used, or what is missing.

## Art Style

**Every Roblox project writes down one art style, and every new visual asset is built to it without being asked.**
The style is the `## Project Art Style` section at the top of `features/art-direction.md` (in `systems/` for a
project that uses that folder, and the seeded rule's path follows it). The seeded hard rule (**Every new visual asset
follows the project art style**, below) is what sends work there: feature docs are read on demand, but
`tech-design.md` is read at every session start and by both asset skills before they build. FPSTowerDefense's is the
worked example.

The section is short and covers:

1. **The look** — a sentence or two a stranger could picture, its motifs, and any reference (a game, an era, a toy
   line).
2. **Construction** — shape language (massing, bevels, level of detail), scale in studs (character and door height),
   and what is never done (e.g. no PBR, no imported textures).
3. **Materials** — the few `Enum.Material`s and `MaterialVariant`s allowed, and what each is for. A wide material
   palette reads as an asset flip, not a style.
4. **Palette** — named colours grouped by role. **The palette is code:** a module among the pipeline's shared helpers
   is its source of truth, and the section names it. On the standard pipeline that is `blender-source/style.py`, a
   `PALETTE` dict of named sRGB hex strings that asset scripts import and hand to `blendlib` (`colour=P["brick"]`).
   Assets pick colours by name, and a new colour goes into the module first, never inline in one asset.
5. **Readability** — what signals what, if the game needs signals: the player's side, the enemy's, interactables,
   hazards. A colour reserved for one owner is stated as reserved.
6. **Effects, UI and 2D art** — how VFX, decals, icons and UI panels carry the style; the palette at minimum.
7. **Reference assets** — the one to three approved asset sources that best show the style, to copy conventions
   from. Empty until the first asset is approved.

- **At setup**, ask what the game should look like. Write the section from the user's words, or propose a short style
  from the game's description and write it once they approve. If they want to decide later, the section reads
  `**Unset.**`, and the first asset request settles it with the user before anything is built.
- **Painted styles start from the painter library.** When the game will paint its assets, show the user the style
  profiles in `~/.claude/skills/blenderassets/python/brushes/` (`CATALOG.md`, and each profile's swatch sheet in `swatches/`). A profile
  they pick is recorded in the section as `Style profile: <name>`, and its palette seeds `style.py`; a new look starts
  as a copy of the nearest profile under a new name. Every painted asset then takes its painters from the profile by
  role, and painters written for the game are promoted into the library when the user approves the asset
  (`brushes/README.md`), so each game leaves the library richer for the next.
- **Settle it on one asset before a batch.** Build one reference asset and get it approved before building volume.
  Pick the Crops restyled after the user rejected its first pass (meshes with a self-drawn stud texture, and a
  sculpted farmer), and everything built in that pass was rework.
- **Changing it** takes the user's say-so, and existing assets are not rebuilt to a new style unless asked. A
  superseded style stays documented below the live one, marked parked, and is used only when the user names it.

**Auditing an existing Roblox project:**
1. Look for `## Project Art Style` in the project's art-direction doc, and for the seeded rule in `tech-design.md`.
2. If the project has art but no written style, offer to codify the style its live assets already share, read from
   their generators or palette module. Never write a style that contradicts shipped assets. If more than one style
   is in use, ask which is live.
3. If it has no art yet, ask the setup question.
4. Check that the palette is code and that the section names its module. Report colour literals in asset scripts as
   drift, and do not rewrite shipped assets unasked.

## Animation Style

**Every project that animates anything writes down one animation style, determined by the user, and every new
animation of any kind follows it without being asked.** The style is `features/animation-style.md` (in `systems/` for
a project that uses that folder). It covers viewmodel clips, weapon parts and reloads, character and enemy clips,
props, effects, and UI motion and tweens. The seeded hard rule (**Every animation follows the project animation
style**, below) is what sends work there, from any skill or by hand. FPSTowerDefense's guide is the worked example
(`~/.claude/skills/setup/examples/animation-style.md`).

The guide covers:

1. **The look** — the feel in a sentence or two, in the user's words (e.g. "one smooth springy movement, never stops
   except on an impact").
2. **The rules** — each one traced to something the user asked for or turned down, quoted in their words: how
   continuous motion is, where it may stop dead, anticipation and follow-through, how much flair goes where (e.g. a
   regular reload with the most flair and a reduced tactical one), and whether physical-looking motion is
   simulated or authored.
3. **The toolkit** — how motion is built in this project: keys and how frames between them are filled, which eases
   are allowed where, springs, kicks, wobbles.
4. **Values that worked** — beat spacing, speeds, spring settings and reaction sizes from approved animations.
5. **Checks before showing** — the per-frame traces and the views a clip must pass: speed and pops, stops, joint
   turns per frame, frames per turn of a spin, first-person or gameplay-camera freeze frames.
6. **Reference implementations** — the approved animations to copy. Empty until the first is approved.

- **At setup**, ask the user how animation should feel and where the flair goes, then write the guide from their
  words. FPSTowerDefense's guide may be offered as a starting point for them to edit, never written in unasked. If
  they want to decide later, the guide reads `**Unset.**` and the first animation request settles it with the user
  before anything is animated.
- **Grow it from rejections.** When the user turns an animation down, the rejection goes into the rules in their
  words, with the fix, in the same pass as that change's docs. The guide exists so the user never repeats a
  correction.
- **Changing it** takes the user's say-so, and existing animations are not redone to a new style unless asked.

**Auditing an existing project:**
1. Look for `features/animation-style.md` and for the seeded rule in `tech-design.md`.
2. If the project has approved animations but no guide, offer to write one from what the user said about them
   (the update log and feature docs hold their words). Never invent rules the user did not state.
3. If it has no animations yet, ask the setup question.

## Asset Checks — offline, never the Studio camera

**Every Roblox project checks how its assets look by rendering them offline with `/assetshot`**
(`~/.claude/skills/assetshot/`), never by moving Studio's camera. It holds whatever pipeline the project
builds its models with (Blender, the mesh kit, hand-placed Parts), because it reads the finished instances out of
Studio. The seeded hard rule (**Assets are checked offline, never through Studio's camera**, above) carries it into each
project; the skill's `SKILL.md` is the how-to.

- **How it works:** one read-only call exports the asset's parts, meshes and colours from Studio. Headless Blender
  renders a labelled sheet in the session scratchpad: a 3/4 view and orthographic views, plus any camera, Studio's own
  view (read, never moved) and close-ups the call asks for. About 15 s for eight views.
- **Why it is the standard:** several sessions often build in one place at once. The Studio camera is the one thing
  they cannot share, and `capture_screenshot` only works in Edit with the viewport showing. A rendered sheet works
  during a playtest, with Studio minimised, and in parallel.
- **Project wrappers:** a project that keeps posed views (a weapon in first person, reload freeze frames) wraps the
  command with a pose script that builds private copies of what it poses, far from the action, and never steps or
  freezes shared state. FPSTowerDefense's `node tools.js shot` is the worked example.
- **Limits:** meshes and textures the user does not own (Roblox's catalog gear) draw as boxes or untextured, and
  particles, lights and GUIs are not drawn; the report names each. The final in-engine look is the user's to judge in
  Play.

**Auditing an existing Roblox project:**
1. Look for the seeded rule in `tech-design.md`. Add it if missing.
2. Grep the project's skills (`.claude/skills/`) and tool scripts for checks that move the camera:
   `CurrentCamera.CFrame =`, `Camera.Focus`, `capture_screenshot`, "screenshot". Leave game code alone, since the
   game's own cameras move the camera by design. For each tooling hit, offer to switch it to `/assetshot`, through a
   project wrapper with a pose script where the check needs something posed.

## Code on Disk — `/studio`

**Every Roblox project keeps every script in the place mirrored on disk in `game-source/`**, through the `/studio`
skill (`~/.claude/skills/studio/`). `sync.js` pulls the place's scripts to files, pushes disk edits back
one file at a time after a compile check, refuses to overwrite a script someone changed in Studio since the last sync,
and reads every push back. The disk copy is the one edited, diffed, reviewed and committed; the place runs what was
pushed. Joust Tycoon is the worked example: its gameplay layer was built in one pass by five sub-agents editing disk in
parallel while one orchestrator pushed.

- **Why:** Studio is a bad place to keep the only copy of code. Writes over the bridge can roll back, an open script tab
  overwrites programmatic edits, nothing is diffable, and two agents editing one script in Studio clobber each other.
- **Build scripts are the source of truth for what they build.** A map, a GUI, a preview or a migration is a Luau file
  on disk run with `node ~/.claude/skills/studio/run.js <file>.luau [--set KEY=VALUE]` (ARGS, `-- uses:` modules,
  deferred long runs that never start twice). To change the thing, change the script and run it again; never hand-edit
  its output in Studio. Named build pipelines, kit preludes and shared modules go in the project's `studio.json`.
- **New Node tools use `bridge.js`** from the skill (port discovery by placeId, run-once tokens, deferred runs, the
  playtest guard) instead of another hand-written `fetch` to the bridge.
- **Studio MCP rules:** the skill's `SKILL.md` § Studio MCP rules is the team's list of what the bridge does wrong
  (repeat deliveries, stale `require` and `get_script_source`, broken edit endpoints, clobbering editor tabs, rolled-back
  writes). Every session that touches Studio follows it.

**Auditing an existing Roblox project:** if there is no `studio.json` / `game-source/`, offer `sync.js init` and a
`pull`. If the project keeps code another way (Rojo, a `tools/push.js`), report it and leave it unless the user wants to
switch. Report project tools that hand-roll their own bridge `fetch` as candidates for `bridge.js`.

## Parallel Builds — sub-agents to a contract

Large passes (a whole gameplay layer, a family of assets, a set of castles) go fastest as several sub-agents working at
once, each owning its own files. They only work if the agreement is written first:

- **The contract:** the orchestrator writes `<area>/CONTRACTS.md` from `~/.claude/skills/setup/templates/CONTRACTS.md`
  before spawning anyone: the ground rules, the framework in one minute, the shared modules, who owns each profile
  field, and per agent the files it owns and the API it exposes.
- **Agents edit disk and `check`; only the orchestrator pushes, uploads, rebuilds shared things or starts anything in
  the place.** Sub-agents cannot act on approval relayed to them, so anything shared they need comes back as a new file,
  a preview copy or a `.diff` for the orchestrator to apply.
- **One agent per family for art**, each to the art style and the family's own palette module; the orchestrator
  reviews every sheet before anything is uploaded.
- **Audit after:** the orchestrator (or a fresh reviewer agent) reads every agent's work against the contract and the
  Hard Rules before pushing, and fixes or bounces what fails.

## UI Pipeline

- **Builders on disk:** every ScreenGui and Gui template is built by a script in `ui-source/` that deletes and rebuilds
  it (run with `/studio`'s `run.js`), sharing one kit of blocks and themes as a `studio.json` prelude. The look is
  `features/art-direction.md` § UI; settle it on labelled variants of one panel before building the rest.
- **Docs:** when the first UI is built, add `features/ui-instances.md` (which instance is which, what builds it, what
  drives it, its status) and `features/ui-backlog.md` (every UI the features need, in phases), from the templates in
  `~/.claude/skills/setup/templates/`. Panels are wired with `/makegui`.
- **Item pictures** are `/itemicon` renders (the seeded rule), kept in `ui-source/renders/` with `renders.json`.
- **Checking a GUI:** `/assetshot` does not draw GUIs. Check layout by reading Sizes, Positions and `TextFits` through
  the MCP (read-only), never by taking Studio screenshots; the final look is the user's to judge in Play.

## Directory Structure

Every project must have the following at its root:

```
<project-name>/
├── index.md          # Documentation index — lists all doc files and their purpose
├── tech-design.md    # Hard rules: naming, architecture, patterns, forbidden practices
├── updatelog.md      # Chronological log of all changes
├── features/         # One MD file per feature/system (e.g., features/inventory.md); art-direction.md opens with the art style; animation-style.md holds the animation style
├── blender-source/   # Roblox projects: one headless-Blender script per 3D asset (/blenderassets), plus style.py (the palette)
├── game-source/      # Roblox projects: every script in the place, mirrored by /studio sync.js (.sync/ is git-ignored)
├── studio.json       # Roblox projects: the placeId every tool checks, plus run.js steps, preludes and shared modules
├── ui-source/        # Roblox projects with UI: the GUI builder scripts, and renders/ for /itemicon
├── tools/            # Project tools, e.g. tools/balance-sim.js (the economy's pacing sim)
└── ...               # Project-specific files (map-source/, animation-source/, configs)
```

## Setup Checklist (New Project)

When setting up a new project, complete these steps in order:

### 1. Create the Project Directory
- Create a folder in `<projects>/` with the project name, and `git init` it
- Check the **Prerequisites** table above and report anything missing (the Blender check is the smoke build in step 6)

### 2. Create `index.md`
- Title: project name
- Brief description (1-2 sentences) of what the project is
- Table or list of all documentation files with one-line descriptions
- Keep this updated as docs are added

### 3. Create `tech-design.md`
- **Architecture overview**: How the project is structured (folders, entry points, frameworks). For Roblox projects, default to the **Default Roblox Boilerplate** above — reference the Runner framework + AdminSystem + asset layout that ships in every baseplate. Do not redocument what's already framework-default; note only what differs or what game-specific components live under `Components/<GameName>/`.
- **Naming conventions**: Casing rules for variables, functions, modules, constants
- **Hard rules**: Anything that must always or never be done (e.g., "no require() for injected modules", "use os.time() not tick()")
- **Networking / data flow**: How client-server communication works (if applicable)
- **Data persistence**: How data is saved/loaded (if applicable)
- **Change Summaries**: a closing section pointing at `~/.claude/skills/setup/change-summary.md` (see **Change Summaries** below). Paste the pointer block verbatim — do not restate the rule at length or copy the doc into the project.

Seed every new project's `tech-design.md` with these standard rules (paste verbatim into the Hard Rules section):

- **Reuse existing components** — before connecting raw input events (`InputBegan`, `Activated`, etc.) on an instance, check if it already has a component (e.g., `Button`). Use that component's API (e.g., `triggeredEvent`) instead. If the component isn't attached yet, use `EntityStore.addComponent()`. More broadly, before writing any logic check whether a generic, Gui, game-specific, or `Shared/` module already does it and reuse that instead of a bespoke reimplementation — drive timed escalating offers through `ProductLadder` (don't hand-roll a step/timer ladder), open and close panels through the `Frame` component's `:open()` / `:close()` (don't tween `.Visible`), resolve assets through the `Assets` module, format numbers through the shared number util (don't write a local formatter). If the existing module is close but insufficient, extend it rather than forking a private copy.
- **Check tags before touching behavior** — before modifying any instance's behavior (setting `.Visible`, writing a property, wiring an event), inspect its CollectionService tags (`instance:GetTags()` or Studio's Tag view). If an existing component owns that surface (e.g., `Frame` wraps `.Visible` with a tweened open/close, `Button` wraps `.Activated` with debounced `triggeredEvent`), go through its API instead of the raw property. Raw writes silently break the component's invariants (lost animation, stale state) and create drift between places that do vs. don't go through the component.
- **Asset lookups go through the shared `Assets` module — never `WaitForChild` / dot-index chains** — anything under `ReplicatedStorage.Assets` is fetched via the injected `Assets` sibling: `MyComponent.Assets.Get("VFX/Plot/Burst")` (nil + path-pinpointing warn on miss), `.Clone(path)`, `.Children(path)`, or `.Expect(path)` for assets whose absence is a programmer error. Shared modules (not auto-injected) `require(Generic.Assets)` directly. Components resolve templates inside `Start()` (sibling/Shared injection happens before Start) into module-locals, or lazily at the use site — NEVER at module scope. Why: EntityStore's collect pass `require`s every component module synchronously, so one module-scope `WaitForChild` on a renamed/deleted asset yields forever and stalls the ENTIRE Runner boot on that side; a module-scope dot-index (`ReplicatedStorage.Assets.Gui.X`) hard-errors the require instead. Callers nil-guard `Get`/`Clone` results so a missing asset degrades to a logged no-op instead of a hang. When auditing an existing project, grep for `WaitForChild("Assets")` and module-scope `ReplicatedStorage.Assets.` — both are migration targets.
- **Use built-in types only** — when type annotations clarify intent, use the primitives Luau already gives you (`string`, `number`, `boolean`, `Instance`, `Folder`, `Part`, etc.). Do not author a custom Types module or invent type aliases (`Types.ComponentData`, `Types.EntityState`, etc.). Hand-written type tables drift from the runtime shape, add a require dependency for zero runtime benefit, and turn into stale documentation the first time a field is added or renamed. If a type is too complex to express with primitives, prefer leaving it unannotated.
- **Methods over local helpers in components** — when a helper function operates on a component instance's state (anything that would otherwise take `record` or `self` as its first argument), write it as an instance method (`function MyComponent:_helper(...)`) instead of a `local function helper(self, ...)`. Reasons: (a) you get `self` for free instead of plumbing it through every call site; (b) sibling components can call public methods (`other:doThing()`) — they can never reach a `local` helper; (c) prefixing private helpers with `_` keeps them syntactically scoped to the class without making them invisible to other authors. Use a leading `local` function only for genuine pure utilities that don't touch component state (e.g., `local function anchorAll(inst)` on a generic Instance), or for static class-level functions whose first arg is the class itself (e.g., `function Component._heartbeat(dt)` iterating the module-level registry).
- **Constants are declared `const`, not `local`** — Luau's `const` keyword (shipped mid-2026) makes reassignment a compile-time error. Every single-assignment `SCREAMING_SNAKE` binding uses it, module-scope and function-scope alike: `const GRANT_INTERVAL = 15 * 60`. Notes: `const` guards the *binding* only — fields of a table held by a const name can still mutate; the Lua 5.4 `local x <const>` attribute syntax is NOT supported. Vendored libraries under `Shared/Generic` are left as upstream ships them. When auditing an existing project, grep for `local [A-Z][A-Z0-9_]* =` — every hit is a migration target, and the compiler self-polices (converting a name that IS reassigned fails to compile, so convert-then-compile-check is safe to automate).
- **No vertical alignment of `=` (or any operator)** — use exactly one space on each side of `=` regardless of surrounding lines. Do not pad with extra spaces to make a column of equal-signs line up across consecutive assignments. Why: one rename forces every neighboring line's padding to be re-adjusted, turning a one-line conceptual change into an N-line diff that inflates `git blame` noise and creates merge conflicts that aren't really conflicts. This applies to `local x = ...` blocks, property assignments (`anchor.Size = ...`), and table constructors. The user has explicitly flagged the aligned style as ugly — always write the traditional single-space form.
- **UI components live in `Components/UI/`, not `Generic/` or `Components/<GameName>/`** — any client component whose `instance` is a GuiObject (ScreenGui / Frame / TextLabel / ImageButton / …) or whose only job is to mirror state into a UI surface belongs under the client's UI components folder (`Components/UI/` in every current place; a place that still has `Components/Gui/` uses that, and `tech-design.md` says which). Game logic components that happen to write attributes the UI reads stay in `Components/<GameName>/`. Rule of thumb: if removing the component would only change what shows on screen (not what the game DOES), it's a Gui component. The seeded folder already holds the UI primitives (`Button`, `Frame`, `Slot`, `ModelViewport`, `PhysicalViewport`, `PlayerHeadshot`, `RainbowGradient`); add `HUD`, panels, prompts, toasts, etc. here. This rule is client-only — there is no server `Components/Gui/`.
- **UI is sized in Scale, never Offset, and holds its shape with `UIAspectRatioConstraint`, never `UIScale`** — every GuiObject's `Size` and `Position` is authored in Scale (`UDim2.fromScale`, Offset 0), so a UI takes the same share of every screen. A group that must keep its shape (a menu column, a button, a card, a panel) gets one `UIAspectRatioConstraint` on its **parent frame**, and everything inside sizes and positions in Scale relative to that frame, so one constraint holds the whole group instead of one on every leaf. Layout objects follow suit: `UIListLayout` padding, `UIGridLayout` `CellSize` / `CellPadding`, `UIPadding` and `UICorner` radius are all Scale. Text uses `TextScaled = true` with a `UITextSizeConstraint` capping `MaxTextSize`, so it shrinks with its box. **Never add a `UIScale` to fit, size or resize UI**, and never write a script that scales UI to the viewport. The only `UIScale`s allowed are the ones the boilerplate's `Frame` and `Button` components create for their open and hover springs (`FrameScale`, `ButtonScale`); an authored `UIScale` on a `Frame`- or `Button`-tagged instance would be taken over by that component anyway. Pixel exceptions, because they have no Scale form: `UIStroke.Thickness` and drop/lip offsets of a few pixels. Keep them small, and expect them to read slightly heavier on phones. Why: the user's rule (2026-10-06, "dont use UIScale its dumb"): Scale plus aspect constraints lays out correctly on every device with no code, while a `UIScale` fit needs a script to drive it and hides layout mistakes at the one resolution it was designed at.
- **Item pictures in UI are rendered models** — any UI that shows an in-game item (a shop card, an inventory slot, an index or collection page, a reward popup) shows that item's own picture: its model rendered with the `/itemicon` skill (transparent, square, outlined), uploaded, and stamped on the model as its `IconImage` attribute. UI code reads `model:GetAttribute("IconImage")` from the template it already uses, never a hand-kept table of ids. Renders and the `renders.json` manifest live in `ui-source/renders/`. Generic glyph icons are for actions and stats (a buy button, a coin, a power stat), never for an item that has a model. Re-render with `--force` when a model changes. Why: the user asked for shops to show "an image label of the rendered lance" (2026-10-06); a player recognises an item by its look, and a rendered model always matches what they will wear or ride.
- **Attach systems to instances — no floating services** — a system should be a component tagged on the instance it acts on, with its lifecycle tied to that instance, NOT a module-level singleton that runs everything from `.Start()` and tracks global state by hand. Per-player state attaches to the Player (`observePlayer` → `AddTag`); per-object state attaches to that object (a wall, an NPC, a pickup); a transient spawned thing (a projectile in flight) becomes its OWN tagged component on the spawned instance via `EntityStore.addComponent(instance, "Thing", ...)` — never a `task.delay`/closure captured inside the spawner. Why: the framework's tag-removed observer frees the component automatically when its instance dies (no leaks, no orphaned work when a player leaves mid-action), siblings can reach it through `EntityStore.getComponent(instance, ...)`, and the spawned thing is a first-class entity you can tag/query/inspect instead of hidden state. Genuinely global coordinators (e.g. a `RoundManager` state machine) are the documented exception — even then, tie them to a single marker/Configuration instance so they still have an instance identity, and keep them rare.
- **Descriptive variable names — never single-letter or cryptic** — every variable, parameter, and loop counter gets a name a stranger can read with no surrounding context. No `local c = ...`, no `local p = Instance.new(...)`, no `for i = 1, n`. Write `local corner`, `local part`, `for index = 1, count`. There are **no** single-letter exceptions in game/component code — this includes loop indices (`index`, not `i`), delta-time (`deltaTime`, not `dt`), and math intermediates (`normal`/`tangent`/`fraction`, not `n`/`t`/`f`). Why: code is read far more than it's written, and the next coder (or you in six months) should never reverse-engineer what `b`, `t`, or `v` held. Scope: applies to game-authored code and the boilerplate components under `Components/`. Vendored third-party libraries under `Shared/Generic/` (`Spr`, `Trove`, `Profilestore`, `Rain`, `Octree`, `WindShake`, `CameraShake`, etc.) are left exactly as upstream ships them so they stay mergeable — do not rename inside them.
- **Comment sparingly — only genuinely math-based code gets a comment** — a comment survives ONLY if it states non-obvious *mathematics* a reader could not reconstruct at a glance: an actual formula, equation, or derivation (trig like `atan2`/`asin`, vector/CFrame geometry, easing/interpolation coefficients, bezier control points, bit/byte packing offsets, probability/weighting, cost/XP curve equations). Everything else is noise that balloons file size and drifts out of date — **delete it**: file-header prose, function/method doc-comments, constant labels (`-- a safety floor`, `-- max attempts`), section-divider banners, inline narration (`-- loop over players`, `-- tween it in`), why/ordering/gotcha/Roblox-API-quirk notes, and descriptions of *trivial* arithmetic (a division, a `math.max`, a percentage — the code already says it). Naming a constant or restating a line is NOT a math comment. The bar is "could a competent reader reconstruct this from the code alone?" — if yes, no comment. Allowed exceptions (these are not comments-about-code): `--!strict`/`--!native`/`--!nonstrict` directives, `--[[ ]]` that comments OUT code, comments carrying a URL / asset id / credit / license, and short action flags (`-- TODO: real product id`, `-- TESTING — revert to 100 before ship`). Why: self-documenting code (good names per the rule above, small methods) conveys intent better than prose, and a comment that isn't load-bearing math is pure maintenance liability — it inflates file size and makes the next edit's diff larger than the conceptual change.

- **Prefer generalized iteration — drop `pairs` / `ipairs`** — Luau iterates a table directly: write `for key, value in someTable do`, not `for key, value in pairs(someTable) do`; `for index, value in someArray do`, not `... in ipairs(someArray) do`. It is as fast or faster and reads cleaner. Correctness caveat: `pairs` → generalized iteration is always equivalent; `ipairs` is NOT a blind swap — `ipairs` stops at the first `nil` and visits only the contiguous array part (1..n), while generalized iteration also visits hash-part keys and won't stop at a `nil` hole. Convert an `ipairs` loop only when the table is a pure sequential array with no other keys and the code doesn't rely on stop-at-nil. Vendored `Shared/Generic` libraries are left as upstream ships them.
- **Source of truth lives in components, not attributes** — a component owns its state as fields; other server scripts read it by fetching the component (`EntityStore.getComponent`) and calling a method (`thing:get()`), never by reading an attribute. When the client needs that state, the server replicates the component to a per-player client copy (the `CustomReplicator` pattern) and the client reads the mirrored component the same way — not `player:GetAttribute(...)`. Why: attributes broadcast every change as an individual replication event, a shared-instance attribute leaks per-player state to every client (or costs N× bandwidth), and method access keeps one authoritative read path instead of scattered `GetAttribute` calls that drift. Carve-out: server-wide state that is *identical for every player* and has no behavior may use a single replicated Configuration attribute — one value replicated once per client beats a per-player `CustomReplicator` mirror there. When auditing an existing project, flag `SetAttribute`/`GetAttribute` used as a cross-script or cross-boundary data channel as a migration candidate, but do not refactor shipped attribute paths without the user's say-so.
- **3D models are authored in headless Blender** — every new mesh asset (prop, structure, vehicle, weapon body, character gear, scenery piece) is a Python script at `blender-source/<Asset>.py`, built with `/blenderassets`: `blend.js build` renders a four-view contact sheet and checks the geometry, and `blend.js push` builds it in the place as MeshParts, vertex-coloured by default, or painted (textured, through `SurfaceAppearance`) when the project's art style paints its assets, using the skill's painted path (`paintlib`, `shapelib`, `inklib`, and painters from the `brushes` library, picked by role from the art style's style profile). The script is the asset's source of truth: to change a model, change its script and push again, never adjust the pushed copy in Studio. Previews go to `Workspace.BlenderImports` for review; `--upload` only once the user approves (a painted upload also makes an Image asset per texture), straight into the model's home (`ReplicatedStorage.Assets.Models` for a template cloned through `Assets`, or the map for static scenery). Previews do not exist in Play, so nothing ships from `BlenderImports`. A push replaces the whole model, so wiring added to it in Studio (attachments, tags, prompts, welds) is re-applied after each push or kept off the generated model. Not covered, and made the usual way: plain `Part`s (collision clips, zones, spawn pads, greybox), UI, VFX, animations, skinned meshes. Why: Blender's modifiers and mesh ops (bevel, mirror, array, boolean, solidify) replace hand-placed vertex code, every build is judged from a rendered sheet before Studio is touched, and a script on disk survives what Studio loses (rolled-back writes, preview meshes that turn to checkerboards after a restart).
- **Every new visual asset follows the project art style** — the style is `## Project Art Style` at the top of `features/art-direction.md`. Read it before authoring any model, prop, structure, character, weapon, map dressing, VFX, decal, icon or UI art, and build to it without being asked. Colours come by name from the palette module the section names (`blender-source/style.py` on the standard pipeline); a new colour goes into that module first, never inline in one asset. While the section reads **Unset**, settle the style with the user before building the first asset. A parked style is used only when the user names it, and the live style changes only on the user's say-so. Why: assets built across many sessions drift apart without one written reference, and `features/art-direction.md` is a feature doc that nothing reads unless this rule sends you there.

- **Every animation follows the project animation style** — the style is `features/animation-style.md`. Read it before making or changing any animation of any kind (viewmodel clips, weapon parts and reloads, character and enemy clips, props, effects, UI motion and tweens), whether by hand or through any skill (`/create-animation`, a project's own animation skills), and build to it without being asked. While the guide reads **Unset**, settle the style with the user before the first animation. When the user turns an animation down, add the rejection and its fix to the guide in their words. Why: motion built across many sessions drifts apart without one written reference, and the user should never have to repeat a correction about feel.

- **Assets are checked offline, never through Studio's camera** — every visual check of any asset (a model, prop, weapon, character, map piece, posed rig or animation frame) is rendered with the `/assetshot` skill. `node ~/.claude/skills/assetshot/shot.js <instance path...> --out <scratchpad>\shots\<name>` reads the asset out of Studio without changing anything and renders a labelled sheet of views in headless Blender; read the sheet. A project may wrap it with its own defaults, such as a first-person pose for weapons, through a pose script that builds private copies of what it poses. Never set `workspace.CurrentCamera` or call `capture_screenshot` to look at work. `capture_screenshot` is only for when the user asks to see their own screen, and the final in-engine look is the user's to judge in Play. Why: Studio has one viewport and one camera, shared by every session working in the place. A session that moves the camera ruins every other session's screenshots and the user's own view, and `capture_screenshot` only works in Edit with the viewport showing. Rendering offline lets any number of sessions check assets at once, during a playtest or with Studio minimised.

**Keep this seed in sync with shipped projects.** When a project adds a new hard rule to its own `tech-design.md`, add it to this seed list too (and vice-versa) so every future project inherits it — the seed and the per-project tech-design hard-rule sets must not drift. The `/deslopify` skill enforces a subset of these rules against existing code; when this list grows, extend that skill's checks to match. (That covers Luau rules only: the 3D asset, art style, animation style and asset check rules are checked by the `/setup` audit, not by `/deslopify`.)

### 4. Create `updatelog.md`
- Empty file with just the project title header
- Entries will be appended as work is done (see Update Log Format below)

### 5. Create `features/` Directory
- Add one MD file per major feature or system
- Each file should describe: purpose, how it works, key implementation details, interactions with other systems

### 6. Set Up the 3D Asset Pipeline (Roblox projects)
- Create `blender-source/` in the project root (see **3D Asset Pipeline**). The Blender hard rule reaches
  `tech-design.md` with the rest of the seed in step 3.
- Smoke-test the toolchain on this machine, writing to the session scratchpad:
  `node ~/.claude/skills/blenderassets/blend.js build ~/.claude/skills/blenderassets/examples/pumpkin_crate.py --out <scratchpad>\PumpkinCrate`.
  It must print `built PumpkinCrate` with no `warn` or `error` lines. Report the Blender version it names. A
  missing or pre-4.1 Blender fails here, at setup, instead of in the middle of the first asset; finish the rest of
  the setup, keep the rule, and tell the user what to install.
- Nothing goes into the place: `MeshKit` travels with each push.
- Asset checks: the **Assets are checked offline, never through Studio's camera** rule reaches `tech-design.md` with
  the rest of the seed in step 3. `/assetshot` renders with the same Blender the smoke build found, so nothing else is
  installed. Its first real use needs the place open with the Studio MCP connected.

### 7. Set the Art Style (Roblox projects)
- Ask the user what the game should look like, then write `## Project Art Style` at the top of
  `features/art-direction.md` per **Art Style**: from their words, from a short proposal they approve, or as
  `**Unset.**` if they want to decide later.
- Create `blender-source/style.py` holding the palette as named sRGB hex strings (`PALETTE = {}` while the style is
  unset), and name it in the section as the palette's source of truth.
- List `features/art-direction.md` in `index.md`. The art style rule reaches `tech-design.md` with the rest of the
  seed in step 3.

### 8. Set the Animation Style
- Ask the user how animation should feel and where the flair goes, then write `features/animation-style.md` per
  **Animation Style**: from their words, from FPSTowerDefense's guide as a starting point they edit and approve, or
  as `**Unset.**` if they want to decide later.
- List `features/animation-style.md` in `index.md`. The animation style rule reaches `tech-design.md` with the rest of
  the seed in step 3.

### 9. Put the Code on Disk (Roblox projects, once the place exists)
- With the place open in Studio and the MCP plugin connected: `node ~/.claude/skills/studio/sync.js init`
  in the project root (writes `studio.json` with the place's `placeId`, `game-source/`, `.gitattributes`,
  `.gitignore`), then `sync.js pull`. Record the place id in `index.md`.
- Read the live Runner while you are there (component lists, `getConfig` children, the UI folder name, anything in
  `Disabled/`) and record every difference from **Default Roblox Boilerplate** in `tech-design.md`. Fix the two
  known baseplate bugs (**Turning boilerplate off, and known boilerplate bugs**) on disk and push them.
- Note in `tech-design.md` § 1 that `game-source/` is the copy to edit, and which tools generate scripts (those are
  regenerated, never hand-edited).
- No place yet: skip this step and say so; the first session with a place runs it.

### 10. Seed the Templates (as the work reaches them)
- Economy: when the economy doc is written, copy `~/.claude/skills/setup/templates/balance-sim.js` to
  `tools/balance-sim.js` and model the core loop in it, so every pacing number in the doc has a sim behind it.
- UI: create `ui-source/renders/` now; add `features/ui-instances.md` and `features/ui-backlog.md` from the templates
  when the first UI is built (**UI Pipeline**).
- Parallel builds: `templates/CONTRACTS.md` when a pass is split across sub-agents (**Parallel Builds**).

### 11. Register in Memory
- Add the project to `MEMORY.md` with:
  - Documentation index path
  - Update log path
  - Key conventions (brief)
  - Any critical gotchas

### 12. Register in CLAUDE.md
- Add the project's update log path to the "Known project update logs" list in `CLAUDE.md`

## Documentation Waits for Approval

Every project doc (`features/*.md`, `updatelog.md`, `index.md`, `tech-design.md`, the economy doc)
is written **only after the user confirms a change was made properly**, so no tokens go into
documenting work that turns out wrong. The reply that makes a change still closes with its change
summary, plus one line saying the docs are pending approval; on approval, all of that change's docs
are written in one pass. Requests that are themselves about docs are done straight away. The full
rule lives in the global `CLAUDE.md` (§ Documentation Waits for Approval) and overrides any "update
the docs first" instruction in a project.

## Update Log Format

Every code change gets an entry in `updatelog.md`, written once the user has approved the change:

```markdown
## YYYY-MM-DD — Short Title

- `FileName.lua` — What changed and why
- `OtherFile.lua` — What changed and why
```

- Use the current date heading; add to existing day section if one exists
- Be concise but specific — someone should understand what happened without reading the diff

## Change Summaries

Every project — and every skill — follows the change summary rule. The canonical copy lives at
`~/.claude/skills/setup/change-summary.md`; read it there rather than reproducing it.

In short: **after any change, close with 2–3 sentences maximum** covering what changed, which files
were modified, and the logical choices now live in the code. This is separate from the `updatelog.md`
entry — the log is the durable record, the summary is what gets said back in the reply. Both happen:
the summary at once, the log entry after the user approves the change.

Every project's `tech-design.md` ends with this pointer block, pasted verbatim:

```markdown
## Change Summaries

Every change closes with a **2–3 sentence maximum** summary: what changed, which files were
modified, and the logical choices now live in the code. This is separate from the `updatelog.md`
entry — the log is the durable record, the summary is what gets said back in the reply.

Full rule (canonical, do not copy — read it there):
`~/.claude/skills/setup/change-summary.md`
```

A project with no `tech-design.md` yet carries the pointer at the top of `updatelog.md` until one
exists. The `/setup` audit checks for the pointer and adds it if missing.

## Working on an Existing Project

Before starting work on any project:

1. Read `index.md` to understand the project and find relevant docs
2. Read `tech-design.md` for hard rules you must follow
3. Read only the feature docs relevant to your current task
4. Check the tail of `updatelog.md` for recent context

## Adding a New Feature/System

1. Follow all rules in `tech-design.md` while building it
2. Once the user approves it, create a file in `features/` describing the feature
3. Update `index.md` to include the new doc
4. Log all changes in `updatelog.md`

## Project Hygiene

- Keep docs in sync with reality — update docs once the user approves an implementation change
- Never let `index.md` go stale; it's the entry point for understanding the project
- `tech-design.md` is authoritative — if code contradicts it, the code is wrong (unless the design needs updating, in which case update the design first)

---

## Economy Design Doc

Every project with in-game currency or progression gets an economy doc. It is the single source of truth for every income rate, cost, multiplier, and time-to-milestone estimate. System/feature docs describe *mechanism* ("plots pay every N seconds, stacked multipliers"); the economy doc owns the *numbers* and the pacing model.

### Location
- Match the project's existing convention: `features/economy.md` or `systems/economy.md`. Detect which folder the project uses; do not introduce a new one.
- Link it from `index.md` like any other system/feature doc.
- Add a one-line pointer in `tech-design.md` under a **Balance & Tuning** heading so future work on the codebase finds it.

### Value tags (required on every numeric value in the doc)
- `(auto)` — computed from code, no human override
- `(override: <reason>)` — human-set; explain why the auto value was wrong
- `(unknown — <assumption>)` — couldn't compute; what was assumed instead
- `(target: <value>)` — design intent if different from current

Rule: a diff that changes a number without updating its tag is a review-fail signal. Tags stay greppable for balance passes (`grep "(override"` lists every human-set knob).

### Authoring pass (first time the doc is created)
1. Scan the codebase for economy inputs. Roblox projects typically mean:
   - All config modules (Brainrots/Rarities/Boards/Upgrades/Monetization/ServerLuck/StarterPack/etc.)
   - Utility modules holding formulas (SpeedUtils, RebirthUtils, SlotUtils, LevelingUtils, CarryUtils)
   - Per-tick income components (Plot, PlotSlot, Spawner, Collectable)
   - Currency grant call sites (Commerce, product handlers, PlayerCurrency:addCoins)
   - Cooldowns, durations, respawn timers, rate limits
2. Draft the doc from the template below.
3. For every numeric value, compute an auto-estimate and tag it `(auto)`. Where a formula is ambiguous or depends on playtest assumptions, tag `(unknown — <assumption>)`.
4. Present the draft to the user. Ask which auto values are wrong. Replace flagged values with `(override: <reason>)`.
5. Write the doc. Add a row to `index.md`. Add the one-line pointer to `tech-design.md`.
5a. Model the core loop in `tools/balance-sim.js` (from `~/.claude/skills/setup/templates/balance-sim.js`):
    a seeded Monte-Carlo player that prints median, p10 and p90 time to each milestone, with every knob overridable from
    the environment. The Progression Pacing table quotes the sim, and a tuning change re-runs it.
6. Append an entry to `updatelog.md` under today's heading.

### Maintenance pass (re-run after the doc exists)
Any balance-affecting code change must update the matching row in the economy doc and append a "Tuning Change Log" entry cross-referencing the `updatelog.md` date heading. When re-running the `/setup` audit:
1. Re-scan configs and compute fresh auto-values.
2. Diff against the doc's current numbers. Report every mismatch.
3. `(override: ...)` values — leave alone, warn on mismatch.
4. `(auto)` values — update in place and add a Tuning Change Log entry pointing at today's updatelog heading.
5. Never silently overwrite an `(override)` value.

### Template

```
# <Project> — Economy Design Doc

## 0. Status & Legend
- Last tuning pass: <date> | doc version: <n> | game version tag: <if any>
- Value tags: (auto) | (override: <why>) | (unknown — <assumption>) | (target: <value>)

## 1. Currencies
For each currency:
- Symbol, persistence field, cap (if any), conversion rules

## 2. Income Sources
Subsection per source. Required fields:
- Name & trigger
- Base value (raw numeric, pre-multiplier)
- Rate (per-second / per-run / per-spawn / per-hour-AFK)
- Multiplier stack (every multiplier that hits this value, in order)
- Config/code path with line numbers
- Dependencies / gates

## 3. Sinks (Coins)
Subsection per sink. Required fields:
- Name (upgrade, unlock, purchase)
- Cost curve (formula or table of first N tiers)
- Currency
- Effect per tier (quantified)
- Payback / ROI window at representative income rates
- Config/code path with line numbers
- Gated by (level, rebirth, gamepass)

## 4. Multiplier Stack Reference
One scannable table: every multiplier, source, range, what it applies to.

## 5. Robux Economy
- Gamepasses (id, price, effect, estimated coin-value)
- Developer products (id, price, grant, Robux/coin ratio if coin grant)
- Starter pack (price, window, contents, effective discount %)
- Temporary buffs (duration, effect, price-per-minute)

## 6. Progression Pacing
Milestone table:
| Milestone | Coin cost | Active play | AFK | With top bundle | Notes |
Rows for each meaningful gate (first upgrade, every major unlock, "game complete").

## 7. Balance Targets & Hypotheses
- Target session length
- Target time-to-first-milestone / time-to-completion
- Which knob moves which metric (the designer's mental model)
- Open questions (gaps in data, assumptions that need playtest)

## 8. Tuning Change Log
Reverse-chronological. Each entry:
- Date | updatelog.md anchor | Values changed (old → new) | Expected effect | Observed effect (filled in after playtest)
```
