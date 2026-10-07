---
name: setup
description: Create a new project from the team template in seconds (all docs and the seeded Hard Rules prefilled by scaffold.js; only the pitch, look and animation feel are asked, all optional), link its Roblox place, or audit an existing project against the standard — docs, hard rules, the headless-Blender asset pipeline, art and animation style, offline asset checks, code on disk with /studio, template tags, and the economy doc.
---

# Project Setup

The standard is `~/.claude/skills/setup/project-setup.md`; the change summary rule is
`~/.claude/skills/setup/change-summary.md` and applies to this skill's own output. `<skill>` below is this folder
(`~/.claude/skills/setup`); `scaffold.js`, `template/` and `templates/` are in it.

## A new project

New projects are **copied, not written**: `scaffold.js` creates every standard file in about a second, with the seeded
Hard Rules read from `project-setup.md` at copy time. Do not retype or regenerate any of it. Read only
`project-setup.md` § The Project Template and § Setup Checklist, plus § Art Style or § Animation Style if the user
answers that question.

1. **One message, every answer optional.** Ask together:
   - the pitch, in a sentence or two;
   - what the game should look like (if it will be painted, mention the brush library's style profiles:
     `~/.claude/skills/blenderassets/python/brushes/CATALOG.md`, swatches in `brushes\swatches\`);
   - how animation should feel, and where the flair goes;
   - whether its place is open in Studio: run `node <skill>/scaffold.js places` and show the list; never guess which
     place is theirs.
   Skip the questions the user already answered in their request. A non-game project uses `--kind generic` and gets
   only the pitch question.
2. **Scaffold:**
   `node <skill>/scaffold.js new <Name> --dir <projects folder> [--kind generic] [--pitch "<their words>"] [--place-id <id>]`.
   The projects folder is the one named in the user's `CLAUDE.md` (`<projects>/`). It refuses a
   folder that already exists: audit that project instead.
3. **Fill only what was answered**, in the user's words: the look into `features/art-direction.md`
   § Project Art Style (and `blender-source/style.py` from a chosen style profile's palette); the feel into
   `features/animation-style.md`. Leave every unanswered section **Unset**; never invent a style or a pitch. If the user
   describes a game whose models must be real Parts (studded brick art), ask before keeping the Blender rule.
4. **Link the place** if one was given: `--place-id` on `new` does it, or later `node <skill>/scaffold.js link --place-id
   <id>` from the project folder (writes `studio.json`, pulls every script into `game-source/`, records the place in
   `index.md`). Then read the live Runner and note any difference from § Default Roblox Boilerplate in
   `tech-design.md` § Differences from the baseplate. No place yet: say linking is pending.
5. **Register** the project: its update log in the "Known project update logs" list in `~/.claude/CLAUDE.md`, and a
   memory entry (doc index path, update log path, the decisions made, any gotcha).
6. Close with the change summary and what is still Unset.

The machine's toolchain (Blender, ffmpeg, Node, the Studio MCP) is the installer's job, not setup's. Economy, UI and
contract docs are added when the work reaches them (`project-setup.md` § The Project Template), not at setup.

## An existing project (audit)

1. Read `project-setup.md` in full, then audit the project against it — identify what's missing or out of date. **Audit
   the live place too, not only the docs:** with the place open (match its `placeId`), read the Runner's component
   folders, `getConfig` children, the UI folder name and `Disabled/`, and report every difference from the docs and from
   § Default Roblox Boilerplate. Re-run the installer's toolchain checks if anything fails.
2. **Hard Rules:** compare the project's `tech-design.md` with `node <skill>/scaffold.js rules` and offer to add any
   seeded rule it lacks (verbatim from `project-setup.md` § Seeded Hard Rules), never removing a project's own rules.
3. **Code on disk** (§ Code on Disk → Auditing): offer `scaffold.js link --place-id <id>` where there is no
   `studio.json` / `game-source/`; run `studio/sync.js status` where there is (report `CONFLICT`s and unpushed edits,
   never resolve them unasked); list project tools that hand-roll a bridge `fetch` as candidates for `studio/bridge.js`.
4. **Template tags:** list every CollectionService tag on instances under `ReplicatedStorage.Assets`, `ServerStorage`,
   `StarterGui` templates the code clones, and any other template store (read-only). Each breaks **Never leave a
   component tag on a template**; report it with the code that clones it and offer the fix (strip the tag, attach the
   component in code after cloning).
5. **Asset access:** grep for `WaitForChild("Assets")` and module-scope `ReplicatedStorage.Assets.` dot-indexes; both
   migrate to the `Assets` module (`Get/Clone/Children/Expect`). Module-scope `WaitForChild` chains hang the whole Runner
   boot when an asset is renamed.
6. **Constants:** grep for `local [A-Z][A-Z0-9_]* =`; single-assignment `SCREAMING_SNAKE` bindings use `const`
   (convert-then-compile-check is safe; leave vendored `Shared/Generic` alone).
7. **Asset pipeline** (§ 3D Asset Pipeline → Auditing): a project that builds models another way keeps it; one whose
   docs are silent gets an offer (adopt Blender for new assets, or record the pipeline it uses), never a migration.
8. **Art style** (§ Art Style → Auditing): art but no written style gets an offer to codify the style its live assets
   share, never a new one; no art yet gets the setup question.
9. **Animation style** (§ Animation Style → Auditing): approved animations but no guide gets an offer to write one from
   the user's own words about them; none yet gets the setup question.
10. **Asset checks** (§ Asset Checks → Auditing): project skills or tools that move the Studio camera or call
    `capture_screenshot` get an offer to switch to `/assetshot`; game code that moves the camera by design is left alone.
11. **Item pictures:** UIs that show an item with a generic icon or text get an offer to render it with `/itemicon`;
    `ui-source/renders/` should exist.
12. **UI scaling:** list GuiObjects under `StarterGui` and `ReplicatedStorage.Assets.Gui` with a non-zero Offset in
    `Size` or `Position`, every `UIScale` other than `FrameScale`/`ButtonScale`, and scripts that create a `UIScale` or
    fit UI to `ViewportSize`; offer a conversion to Scale with `UIAspectRatioConstraint`, never convert unasked.
13. **Economy:** currency or progression but no economy doc gets an offer to draft one (§ Economy Design Doc, with
    `templates/balance-sim.js`); an existing doc gets the maintenance pass (diff configs, report mismatches, preserve
    `(override: ...)` values).
14. **Change Summaries pointer:** `tech-design.md` must end with the pointer block from `project-setup.md`; an inlined
    copy of `change-summary.md` is a defect, replaced by the pointer.
15. Report findings and offer to fix gaps. Never overwrite existing docs without confirmation.

## No project named

Ask which project to set up or audit.
