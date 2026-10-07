---
name: studio
description: Keep a Roblox place's scripts on disk and drive Studio from Node over the Studio MCP bridge. `sync.js` mirrors every script to `game-source/` and pushes disk edits back one file at a time with compile checks and conflict detection; `run.js` runs any Luau file in Studio with ARGS, `-- uses:` modules and deferred long runs, so build scripts on disk are the source of truth for maps, GUIs and previews. Also the team's rules for working through the Studio MCP safely. Use whenever the user invokes /studio, says "sync the scripts", "pull the place", "push this file", "run this luau in studio", asks to edit game code in a project that has `studio.json` / `game-source/`, or when several agents will edit one place's code at once.
---

# studio: code on disk, Studio over the bridge

Two Node tools (Node 18+, no packages) and one shared bridge module, `<skill>/bridge.js`, that every tool here uses.
`<skill>` is this folder (`~/.claude/skills/studio`). Both tools find the project by walking up from the current directory
to its `studio.json`, so run them from anywhere inside the project.

```
node <skill>/sync.js init | probe | pull [prefix] | push <file...> [--force] | check <file...> | status [prefix] | delete <file...>
node <skill>/run.js <file.luau | step>... [--set KEY=VALUE]... [--port N]
```

## Why code lives on disk

Studio is a bad place to keep the only copy of the code: writes made over the bridge can roll back, an open script
tab overwrites programmatic edits, nothing is diffable, and two agents editing one script in Studio silently clobber
each other. With `game-source/` the disk copy is the one edited, reviewed and committed; the place runs what was pushed.
Joust Tycoon built its whole gameplay layer this way, with five sub-agents editing disk in parallel and one
orchestrator pushing (`setup/templates/CONTRACTS.md` is the contract they worked to).

## sync.js

- **`init`** writes `studio.json` (the `placeId` of the one place open in Studio, and `gameSource`), creates
  `game-source/`, and adds `*.luau text eol=lf` to `.gitattributes` and `game-source/.sync/` to `.gitignore`.
  Then **`pull`** mirrors every script.
- **Layout:** `game-source/<Root>/<path>/<Name>.luau` is a ModuleScript, `.server.luau` a Script, `.client.luau` a
  LocalScript. A script with children is a file plus a folder of the same name. Roots: `ServerScriptService`,
  `StarterPlayerScripts`, `StarterCharacterScripts`, `ReplicatedFirst`, `ReplicatedStorage`, `ServerStorage`,
  `StarterGui` (`Workspace` only when listed in `studio.json` `"roots"`).
- **`push`** compile-checks first (nothing is pushed if any file fails), refuses a file whose Studio copy changed
  since it was last synced (pull, merge, push again; `--force` overrides), writes it, then **reads it back**: a write
  that did not stick is reported (an open script editor tab in Studio overwrites `.Source`; close it and push again).
- **`pull`** never overwrites a disk file with unpushed edits; it reports it. **`status`** lists `edited disk`,
  `edited Studio`, `CONFLICT`, `new on disk` and `only Studio`. **`check`** compile-checks in Studio and changes nothing.
- Sync bases live in `game-source/.sync/`, one file per script, so parallel pushes of different files never race.

**Working rules**
- Edit the disk file, then `push` exactly the files you changed. Never edit a mirrored script in Studio through the MCP
  (`set_script_source`, `edit_script_lines`); if someone did, `pull` before you edit.
- **Sub-agents `check`, the orchestrator `push`es.** In a parallel build each agent owns its files (the contract says
  which), edits on disk and runs `check`; only the orchestrating session pushes, after reviewing.
- Generated scripts (anything a tool writes) say so in the project's `tech-design.md` and are regenerated, never
  hand-edited.

## run.js

Runs Luau files in Studio so that **a script on disk is the source of truth for anything built in the place**: the map
(a greybox that deletes and rebuilds `Workspace.Map`), every GUI (a builder per ScreenGui), previews, migrations.

- `--set KEY=VALUE` becomes `local ARGS = {...}` (numbers and booleans converted).
- A `-- uses: <path from the project root>.luau` line in the file prepends that module as
  `local <Name> = (function() ... end)()`, so build scripts share libraries without installing them.
- `studio.json` can add, all optional:
  ```json
  {
    "placeId": 123,
    "gameSource": "game-source",
    "steps": { "map": ["map-source/Greybox.luau", "map-source/Terrain.luau"], "ui": ["ui-source/HudGui.luau"] },
    "preludes": [{ "folder": "ui-source", "file": "ui-source/Kit.luau" }],
    "shared": [{ "file": "map-source/Roads.luau" }],
    "sharedFolder": "game.ServerScriptService.Runner.Shared.MyGame"
  }
  ```
  `steps` names lists of files (`node run.js map ui`); `preludes` prepend a kit to every file in a folder; `shared`
  modules are installed into `sharedFolder` before the run, so the game and the build scripts read one definition.
- Every run is deferred inside Studio under a token and polled: builds longer than the bridge's ~30 s timeout finish and
  report, and the bridge's repeat deliveries never start a run twice. Long builds still `task.wait()` now and then; a
  build that held Studio for over 30 s without yielding has crashed it.

## bridge.js (for any new Node tool)

`require("<skill>/bridge.js")` instead of writing another `fetch` to the bridge:
`resolve({ placeId, writes })` finds the port (58741-58750, it moves) whose open place is the project's, refusing
ambiguity and, for writers, a running playtest; `once(port, code)` runs short code exactly once; `deferred(port, code)`
runs long code exactly once; `longString(text)` embeds any text safely in Luau.

## Studio MCP rules (learned across the team's projects)

1. **Every call can be delivered more than once.** The bridge re-hands a still-running call to the plugin every 0.5 s.
   Use `bridge.js` (token-guarded), and make every write absolute and idempotent ("set X to 5", never "add 5 to X").
2. **Check the place before writing.** Several Studios can share one MCP server and the port moves between restarts:
   match `game.PlaceId` first (`resolve` does). Never write while a playtest runs.
3. **Yielding code goes in `task.defer`/`task.spawn` and is polled** (`deferred`); a yielding call's output is otherwise
   lost or repeated.
4. **`require` in Edit serves stale cached modules.** To test a changed module, `loadstring(module.Source)()` it, or
   install it as a new ModuleScript (`run.js` shared modules do).
5. **Read `.Source`, not `get_script_source`**, which can serve stale text. `set_script_source` replaces the whole
   script and cannot be undone, so re-read immediately before writing (better: use `sync.js push`).
6. **Broken or unreliable endpoints:** `edit_script_lines`, `find_and_replace_in_scripts`, `get_script_analysis`. Use
   `sync.js` for code and `execute_luau` for everything else. `grep_scripts` has no `|` alternation and searches
   source, not names.
7. **Backslashes are double-unescaped in transit** through the source-setting tools (`\n` arrives as a newline); embed
   text with `longString` through `execute_luau` instead.
8. **An open script editor tab clobbers programmatic `.Source` writes.** `push` reads back and reports it.
9. **Writes can vanish or roll back between calls.** Verify a write in a later call before building on it.
10. **`Destroy` through `execute_luau` cannot be undone with Ctrl+Z.** Snapshot first (clone into `ServerStorage`)
    when destroying anything not regenerated from disk.
11. **The MCP cannot read a live playtest.** Instrument with `print`s and ask the user to paste the Output; never start
    or stop a playtest yourself.
12. **Uploads:** `AssetService:CreateAssetAsync` returns the result enum first, then the id; read the id back from the
    instance; asset names over 50 characters fail; an Animation whose creator is not the place's owner (user or group)
    silently never loads.
13. **Never look through Studio's camera** to check work: render offline with `/assetshot` (it is shared by every
    session and the user).

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`. Close the reply with **2–3 sentences maximum**: what changed, which files
or instances were modified, and the logical choices now live in the code.
