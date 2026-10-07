# Roblox × Claude Code: the team setup

One install that makes every Roblox project start the same way and build assets fast: a `/setup` standard that writes
the project's docs and hard rules, a headless-Blender asset pipeline, offline renders instead of Studio screenshots,
scripts mirrored on disk, and the templates that let several Claude sub-agents build one game in parallel.

It is the setup behind **Joust Tycoon**, which went from a design conversation to an approved gameplay MVP, with every
gear tier, castle tier, both zones and the full UI built and approved, in four days (2026-10-03 to 2026-10-06).

## What is in the repo

| Path | What it is |
| --- | --- |
| `install.ps1`, `install.sh` | The installers |
| `skills/` | The 15 Claude Code skills, including `/setup` and its standard (`skills/setup/project-setup.md`) |
| `baseplate/RunnerBaseplate.rbxl` | The place every new game starts from: the Runner framework, AdminSystem and asset folders, nothing game-specific |
| `baseplate/src/` | The same baseplate as Rojo source, so changes to it are reviewable |
| `claude/` | The team `CLAUDE.md` rules, the optional JARVIS persona, a permissions example |
| `docs/setup-breakdown.html` | The team presentation |
| `CLAUDE.md` | How everything works inside, for Claude (Opus) maintaining this repo |
| `UPLOAD.md` | How to publish this repo to GitHub |
| `maintainer/` | Regenerates `skills/` and the baseplate from a live install and a live game |

## Requirements

Install these before running the installer. It checks for every one and tells you what is missing.

| Tool | Why you need it | Get it |
| --- | --- | --- |
| **Blender 4.1 or newer** | Builds every 3D asset (`/blenderassets`) and renders every visual check (`/assetshot`, `/itemicon`). Runs headless: you never open it | https://www.blender.org/download |
| **ffmpeg** | Records and encodes feature videos (`/demo`) so you can see a feature working from your phone | `winget install Gyan.FFmpeg` (or run the installer with `-InstallFfmpeg`); macOS `brew install ffmpeg` |
| **Node.js 18 or newer** | Runs every skill's tools | https://nodejs.org |
| **Claude Code** | Runs the skills | https://code.claude.com |
| **Roblox Studio + the Studio MCP plugin** | Every Studio read and write | see Install below |
| **git** | Cloning this repo, and each project's history | https://git-scm.com |
| Rojo 7.5+ (maintainers only) | Rebuilding the baseplate from source | https://rojo.space |

## Install

Windows (primary):

```powershell
git clone <this repo> roblox-claude-setup
cd roblox-claude-setup
powershell -ExecutionPolicy Bypass -File install.ps1 -ProjectsDir "D:\Roblox"
```

macOS / Linux: `./install.sh --projects ~/Roblox` (set `BLENDER` if Blender is not on `PATH`). Add `-Persona jarvis` /
`--persona jarvis` for the optional JARVIS voice.

The installer:

1. checks Node 18+, git, Claude Code, Blender 4.1+ and ffmpeg (`-InstallFfmpeg` installs ffmpeg with winget);
2. copies the 15 skills into `~/.claude/skills/` (any existing copy is moved to `~/.claude/backups/` first, and the
   `/assetshot` mesh cache is kept);
3. fetches [robloxMeshTools](https://github.com/MrChickenRocket/robloxMeshTools) at the pinned commit (it is not
   redistributed here);
4. writes the team rules into `~/.claude/CLAUDE.md` between `roblox-claude-setup` markers, keeping everything else in
   the file and the projects you have registered;
5. smoke-builds a crate in headless Blender to prove the pipeline works on this machine.

Then, by hand, once:

- **Studio MCP plugin:** download from [boshyxd/robloxstudio-mcp releases](https://github.com/boshyxd/robloxstudio-mcp/releases)
  into `%LOCALAPPDATA%\Roblox\Plugins` (upstream was archived 2026-06-06; the maintained fork is
  [Chrrxs/robloxstudio-mcp](https://github.com/Chrrxs/robloxstudio-mcp)). Turn on *Allow HTTP Requests* in each place.
- **Register the server:** `claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest`
- **Optional:** merge `claude/settings.example.json` into `~/.claude/settings.json` (no prompts for the skill scripts
  and read-only Studio tools; playtests and the broken edit endpoints denied). Put `ROBLOX_OPEN_CLOUD_API_KEY=...` in
  `~/.claude/.env` for `/create-devproduct`, `/create-gamepass` and `/upload-images`. Never commit that file.

Start a project: open `baseplate/RunnerBaseplate.rbxl` in Studio, publish it as a new experience, turn on *Allow HTTP
Requests*, then in Claude Code run `/setup MyGame` (details in `baseplate/README.md`).

## What `/setup` gives every project

A new project is **copied from a template, not written**: `scaffold.js` creates every file below in about a second,
with the hard rules read straight from the standard. `/setup` then asks only what needs a person (the pitch, the look,
the animation feel, which Studio place), every answer optional; anything skipped stays **Unset** until the work needs it.

| Layer | What lands in the project | Why |
| --- | --- | --- |
| **Docs skeleton** | `index.md` (pitch, doc index, status), `tech-design.md` (architecture + Hard Rules), `updatelog.md`, `features/` | Every session orients from two files instead of re-reading the codebase; docs are written only after the user approves a change |
| **33 seeded Hard Rules** | Reuse components, check tags, `Assets` module lookups, `const`, no aligned `=`, Scale-only UI, item pictures are rendered models, attach systems to instances, descriptive names, maths-only comments, generalised iteration, component-owned state, Blender for meshes, art style, animation style, offline asset checks, no component tags on templates, server-decided outcomes, Robux grants that never save, permanent save ids, one loop per system, batched messages, one writer per shared surface, ... | The rules that kept getting re-learned, written once and inherited by every project |
| **Art style** | `## Project Art Style` in `features/art-direction.md`, the palette as code in `blender-source/style.py`, optionally a painter-library style profile | Assets built in many sessions stay one game |
| **Animation style** | `features/animation-style.md` from the user's own words, grown from every rejection | Nobody repeats a correction about feel |
| **3D asset pipeline** | `blender-source/`, one Python script per asset | See below |
| **Offline checks** | the `/assetshot` rule | Studio's one camera is shared by every session and the user |
| **Code on disk** | `studio.json`, `game-source/` mirrored by `/studio` | Diffable, reviewable, safe for parallel agents |
| **Economy** | `features/economy.md` with value tags, `tools/balance-sim.js` | One source of truth for numbers, and a sim behind every pacing claim |
| **Templates** | `CONTRACTS.md` for parallel builds, `ui-instances.md`, `ui-backlog.md` | Large passes split cleanly across sub-agents |

`/setup <ExistingProject>` audits instead: it compares the docs **and the live place** against the standard, reports
drift, and offers fixes without overwriting anything unasked.

## The asset pipeline, and why Blender

```
describe the asset ─▶ blender-source/Asset.py ─▶ blend.js build (≈4 s) ─▶ contact sheet + geometry checks
                                                     │                         (fix and rebuild until it reads right)
                                                     ▼
                       blend.js push (preview in Workspace.BlenderImports) ─▶ /assetshot render ─▶ user approves
                                                                                                        │
                       /itemicon (shop / inventory picture) ◀── blend.js push --upload (Mesh + Image assets) ◀┘
```

- **Why Blender at all:** bevel, mirror, array, solidify, boolean and bmesh ops replace hand-placed vertices; every
  build is judged from a rendered four-view sheet before Studio is touched; the script on disk is the asset's source of
  truth, diffable and regenerable, and survives what Studio loses (rolled-back writes, previews that turn to
  checkerboards after a restart). Headless means no window, so any number of sessions build at once.
- **Painted path:** `paintlib` bakes one texture per MeshPart from the model itself, painted by brushes from a
  cross-project library (84 painters, two style profiles: *Painted Toon* and *Soft Painted*); `shapelib` builds cloth
  and quilted gear; `inklib` adds toon outlines; team colours are TintMask SurfaceAppearances. Bakes run on the GPU and
  are cached per texture, so a paint-only change rebuilds in about 28 s instead of 5-7 minutes. Painters written for one
  game are promoted into the library on approval, so each game leaves the next one richer.
- **Into Studio over the MCP:** nothing is installed into the place; `MeshKit` travels with each push. Pushes refuse
  the wrong place and a running playtest, verify every part, and only upload after approval.
- **Looking at work:** `/assetshot` exports the instances read-only and renders a labelled sheet in headless Blender
  (≈15 s for eight views), so it works during a playtest, with Studio minimised, and in parallel. `/itemicon` uses it
  for transparent, outlined UI icons stamped on the model as `IconImage`.

## The skills

| Skill | What it does |
| --- | --- |
| `/setup` | Creates or audits a project to the standard (`skills/setup/project-setup.md`), plus the templates |
| `/studio` | `sync.js`: every script mirrored to `game-source/`, compile-checked pushes with conflict detection; `run.js`: run any Luau file in Studio with ARGS, `-- uses:` modules and long deferred runs; `bridge.js` for new tools; the team's Studio MCP rules |
| `/blenderassets` | The headless-Blender asset pipeline above (`blend.js`, `blendlib`, `paintlib`, `shapelib`, `inklib`, the brush library) |
| `/assetshot` | Offline renders of any asset, posed rig or animation frame, read from Studio without touching its camera |
| `/demo` | A short phone-ready video of a feature running in a real playtest: a scripted demo (walk, camera, captions, real key presses) is recorded with ffmpeg, then trimmed and cropped to the game view. Claude offers one after every gameplay change |
| `/itemicon` | Transparent outlined item icons for UI, uploaded and stamped on the model |
| `/importmeshtools` | robloxMeshTools' EditableMesh kit, for projects that build meshes from Luau |
| `/create-animation` | Upload a KeyframeSequence as an Animation asset (no API key through the MCP) |
| `/create-devproduct`, `/create-gamepass` | Create monetisation products through Open Cloud and register them in the project's config |
| `/upload-images` | Bulk-upload images as Decals through Open Cloud |
| `/makegui` | Wire a ScreenGui into the Runner component framework (`Frame`, `Button`, a Gui component) |
| `/makereactcomponent` | Turn an authored GUI into a react-lua component |
| `/makeweapon` | Wire a gun model into the Runner FPS layer |
| `/deslopify` | Sweep a project's Luau against the Hard Rules, category by category, with approval |

## How much is generic

Measured on Joust Tycoon (2026-10-06):

| Layer | Size | Source |
| --- | --- | --- |
| The skills (generic, this repo) | ≈11,700 lines of tools + 14 skill guides | `/setup` and friends |
| Runner boilerplate and vendored libraries (generic) | ≈34,000 lines | the team baseplate |
| Game code | ≈25,700 lines (server and client components, UI, game Shared modules) | written for the game, mirrored in `game-source/` |
| Asset scripts | 387 Blender scripts, ≈62,800 lines | written for the game with `/blenderassets` |
| Map, UI and animation build scripts | ≈27,000 lines | written for the game, run with `/studio` |
| Docs | 15 feature docs + index + tech design, 43 update-log entries | structure from `/setup`, content from the game |

Everything structural (where things live, how they are built, checked, pushed, documented and approved) came from the
setup; everything in the second half of the table is the game. The setup is what made the second half fast.

## Rules that make it work

- **Docs wait for approval.** A change closes with a 2-3 sentence summary; docs are written once the user says it works.
- **Never start or stop a playtest**, except `/demo` recording a video the user asked for. Claude makes the change, says what to check, and offers a demo; the user plays.
- **Never look through Studio's camera.** Render with `/assetshot`.
- **Scripts and assets live on disk.** Studio runs what was pushed; to change a thing, change its script and run it again.
- **One reference asset before a batch.** Settle the style on one approved asset, then build volume.
- **Parallel agents work to a contract.** Agents edit disk and `check`; one orchestrator pushes, uploads and rebuilds.

## Limits and known gaps

- **Windows first.** Every tool is plain Node and Blender, but only Windows is tested; `/assetshot` reads Roblox's
  install for some content.
- **No offline GUI render.** `/assetshot` does not draw GUIs; check layout by reading sizes through the MCP.
- **The Studio MCP is a third-party plugin** whose upstream is archived. The tools only need its `execute_luau` over
  the HTTP bridge on ports 58741-58750.

## Maintaining this repo

The skills here are exported from a live install, never edited in place:

```
node maintainer/export.js            # re-export from ~/.claude/skills and the standards folder
node maintainer/export.js --dry      # list what would change
```

It rewrites machine paths to portable ones, drops caches and third-party code, and fails if a personal path survives.
`node maintainer/baseplate.js all --place-id <ID>` does the same for the baseplate from a live game (see `CLAUDE.md` § 2).
Third-party notices: `THIRD_PARTY.md`. Publishing: `UPLOAD.md`.
