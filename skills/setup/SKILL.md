---
name: setup
description: Set up a new project or verify an existing project follows the standard project structure and management rules — docs, hard rules, the headless-Blender asset pipeline, art and animation style, offline asset checks, code mirrored on disk with /studio, and the templates for parallel builds, UI and economy pacing
---

# Project Setup

Read the project setup guide at `~/.claude/skills/setup/project-setup.md` and follow it precisely.

Also read `~/.claude/skills/setup/change-summary.md` — the change summary rule applies
to every project this skill touches and to this skill's own output.

`<skills>` below is `~/.claude/skills`. The templates the steps copy are in this skill's `templates/`
folder: `CONTRACTS.md` (parallel sub-agent builds), `ui-instances.md`, `ui-backlog.md` and `balance-sim.js`.

## Behavior

### If the user specifies a new project name:
1. Read `project-setup.md` in full
2. Walk through the **Setup Checklist** step by step, starting with the **Prerequisites** check (Claude Code, the Studio MCP plugin and server, Blender 4.1+, Node 18+, git, the robloxMeshTools kit); report anything missing with how to install it, and carry on with the rest
3. Ask the user for the project description, any known tech details and, for a game, what it should look like (step 6) before creating files
4. Create all required files and directories
5. For a Roblox project, set up the **3D Asset Pipeline** (headless Blender via `/blenderassets`): create `blender-source/`, run the toolchain smoke build from the Setup Checklist and report the Blender version it used, and make sure the **3D models are authored in headless Blender** rule lands in `tech-design.md` with the rest of the seed. A failed smoke build does not drop the rule; report what to install. If the user describes a game whose models must be built another way (e.g. studded brick art), ask before seeding the rule
6. For a Roblox project, set the **Art Style** per `project-setup.md` § Art Style: write `## Project Art Style` at the top of `features/art-direction.md` from the user's answer (or from a short proposal they approve, or as `**Unset.**` if they want to decide later). If the game will paint its assets, offer the painter library's style profiles first (`~/.claude/skills/blenderassets/python/brushes/CATALOG.md`, with each style's swatch sheet in `brushes\swatches\`): a chosen profile is recorded as `Style profile: <name>` in the section, or a new one is made from a copy of the nearest. Create `blender-source/style.py` for the palette (seeded from the chosen profile's palette), and make sure the **Every new visual asset follows the project art style** rule lands in `tech-design.md` with the rest of the seed
7. For any project that will animate anything, set the **Animation Style** per `project-setup.md` § Animation Style: ask the user how animation should feel and where the flair goes, write `features/animation-style.md` from their answer (or from FPSTowerDefense's guide as a starting point they edit and approve, or as `**Unset.**` if they want to decide later), and make sure the **Every animation follows the project animation style** rule lands in `tech-design.md` with the rest of the seed. Never write animation rules the user did not state
8. For a Roblox project, make sure the **Assets are checked offline, never through Studio's camera** rule lands in `tech-design.md` with the rest of the seed (see **Asset Checks** in `project-setup.md`). Every visual check of an asset in the project goes through `/assetshot`, whatever pipeline builds the models
9. For a Roblox project, make sure the **Item pictures in UI are rendered models** rule lands in `tech-design.md` with the rest of the seed, and create `ui-source/renders/` for `/itemicon`'s output and its `renders.json` manifest. Any UI that shows an in-game item (a shop card, an inventory slot, an index page) shows that item's `/itemicon` render, read from the model's `IconImage` attribute
10. For a Roblox project, make sure the **UI is sized in Scale, never Offset** rule lands in `tech-design.md` with the rest of the seed: every UI is built in Scale with `UIAspectRatioConstraint` on parent frames, and never fitted with `UIScale`
11. If the project has currency / progression, follow the **Economy Design Doc** section in `project-setup.md` to produce `economy.md` (match the project's folder convention — `features/` or `systems/`), and copy `templates/balance-sim.js` (in this skill's folder) to `tools/balance-sim.js` to model its pacing
12. For a Roblox project with a place open in Studio, put the code on disk per **Code on Disk** and Setup Checklist step 9: `node <skills>/studio/sync.js init` then `pull` in the project root, read the live Runner and record its differences from the boilerplate in `tech-design.md`, and fix the two known baseplate bugs. With no place yet, say the step is pending and leave it for the first session that has one
13. For a Roblox project, create `ui-source/renders/`, and note in `index.md` that `features/ui-instances.md` and `features/ui-backlog.md` come from this skill's `templates/` when the first UI is built, and `templates/CONTRACTS.md` when a pass is split across sub-agents (**UI Pipeline**, **Parallel Builds**)
14. Append the **Change Summaries** pointer block to `tech-design.md` verbatim from the **Change Summaries** section of `project-setup.md` — pointer only, never a copy of the rule doc
15. Register the project in memory and CLAUDE.md

### If the user specifies an existing project:
1. Read `project-setup.md` in full
2. Audit the project against the checklist — identify what's missing or out of date. **Audit the live place too, not only the docs:** with the place open (match its `placeId`), read the Runner's component folders, `getConfig` children, the UI folder name and `Disabled/`, and report every difference from the docs and from **Default Roblox Boilerplate**
2a. For Roblox projects, audit code on disk per **Code on Disk → Auditing an existing Roblox project**: offer `studio/sync.js init` + `pull` where there is no `studio.json` / `game-source/`, run `sync.js status` where there is (report `CONFLICT`s and unpushed edits, never resolve them unasked), and list project tools that hand-roll a bridge `fetch` as candidates for `studio/bridge.js`
2b. For Roblox projects, list every CollectionService tag on instances under `ReplicatedStorage.Assets`, `ServerStorage`, `StarterGui` templates the code clones, and any other template store (read-only). Each one breaks the **Never leave a component tag on a template** rule; report it with the code that clones that template, and offer the fix (strip the tag, attach the component in code after cloning). Also compare the project's `tech-design.md` Hard Rules with the seed list and offer to add any seeded rule it lacks, never removing a project's own rules
3. For Roblox projects, audit asset access: grep scripts for `WaitForChild("Assets")` and module-scope `ReplicatedStorage.Assets.` dot-indexes — both must be migrated to the shared `Assets` module (`Assets.Get/Clone/Children/Expect`) per the **Asset lookups** hard rule in `project-setup.md`. Module-scope WaitForChild chains hang the entire Runner boot when an asset is renamed.
4. For Roblox projects, audit constants: grep scripts for `local [A-Z][A-Z0-9_]* =` (Lua pattern `^%s*local%s+[A-Z][A-Z0-9_]*%s*=`) — single-assignment `SCREAMING_SNAKE` bindings must use the `const` keyword per the **Constants** hard rule in `project-setup.md`. Convert-then-compile-check is safe to automate (reassigned names fail to compile under `const`); leave vendored `Shared/Generic` libraries untouched.
5. For Roblox projects, audit the asset pipeline per **3D Asset Pipeline → Auditing an existing Roblox project** in `project-setup.md`. A project that already builds models another way keeps it; one whose docs are silent gets an offer (adopt Blender for new assets, or record the pipeline it already uses), never a migration of existing assets
6. For Roblox projects, audit the art style per **Art Style → Auditing an existing Roblox project** in `project-setup.md`. A project with art but no written style gets an offer to codify the style its live assets already share, never a new one; a project with no art yet gets the setup question
7. Audit the animation style per **Animation Style → Auditing an existing project** in `project-setup.md`: the project needs `features/animation-style.md` and the seeded rule. A project with approved animations but no guide gets an offer to write one from the user's own words about them; one with no animations yet gets the setup question
8. For Roblox projects, audit asset checks per **Asset Checks → Auditing an existing Roblox project** in `project-setup.md`: the seeded rule must be in `tech-design.md`, and project skills or tool scripts that move the Studio camera or call `capture_screenshot` to check work get an offer to switch to `/assetshot` (through a project wrapper with a pose script where the check needs something posed). Game code that moves the camera by design is left alone
9. For Roblox projects, audit item pictures: the **Item pictures in UI are rendered models** rule must be in `tech-design.md`, and `ui-source/renders/` should exist. UIs that show an item with a generic icon or text only get an offer to render the item with `/itemicon`
10. For Roblox projects, audit UI scaling per the **UI is sized in Scale, never Offset** hard rule in `project-setup.md`: the rule must be in `tech-design.md`; in the place, list GuiObjects under `StarterGui` and `ReplicatedStorage.Assets.Gui` whose `Size` or `Position` carries a non-zero Offset, every `UIScale` other than the `Frame`/`Button` components' `FrameScale`/`ButtonScale`, and project scripts that create a `UIScale` or fit UI to `ViewportSize`. Report them and offer a conversion to Scale with `UIAspectRatioConstraint`; never convert without confirmation
11. If the project has currency / progression but no economy doc, offer to draft `economy.md` per the **Economy Design Doc** section
12. If an economy doc exists, run the maintenance pass (scan configs, diff against doc, report mismatches; preserve `(override: ...)` values)
13. Audit the **Change Summaries** pointer: `tech-design.md` must end with the pointer block from `project-setup.md`. Add it if missing. If the project has no `tech-design.md` yet, put the pointer at the top of `updatelog.md` instead. A project that has inlined a full copy of `change-summary.md` is a defect — replace the copy with the pointer so there is one canonical rule
14. Report findings and offer to fix gaps
15. Do not overwrite existing docs without confirmation

### If no project is specified:
Ask the user which project they want to set up or audit.
