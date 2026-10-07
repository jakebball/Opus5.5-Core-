# The team baseplate

`RunnerBaseplate.rbxl` is the place every new game starts from. It holds:

- **The Runner framework** on both sides: `EntityStore`, `BaseClass`, 32 server and 38 client Generic components, the
  UI primitives (`Button`, `Frame`, `Slot`, `ModelViewport`, `PhysicalViewport`, `PlayerHeadshot`, `RainbowGradient`),
  `Shared/Generic` (42 libraries) and `Shared/getConfig` (16 default configs).
- **The AdminSystem** with the generic commands (`Ban`, `Unban`, `Kick`, `ResetPlayerData`, `WorldEvent`, `GiveWeapon`).
- **`ReplicatedStorage.Assets`** with the standard folders, the FPS rig and viewmodel, the hotbar template, the shared
  VFX and the shared sound library.
- **A classic Workspace:** a 512 × 512 grid baseplate with its top at Y = 0 and a 12 × 12 spawn.

Nothing game-specific is in it: no game components, configs, GUIs, models, maps or lighting. The full inventory is
`skills/setup/project-setup.md` § Default Roblox Boilerplate.

## Start a game from it

1. Open `RunnerBaseplate.rbxl` in Roblox Studio.
2. *File > Publish to Roblox As…* → *Create new experience* (owner: your group, if the game is a group game).
3. *Game Settings > Security*: turn on **Allow HTTP Requests** (the Studio MCP bridge needs it) and, if the game saves
   data, **Enable Studio Access to API Services**.
4. In `ServerScriptService.AdminSystem.Config`, set `GroupId` and add yourself to `UserOverrides`.
5. In Claude Code, with the place open and the Studio MCP connected: `/setup <GameName>`. Step 9 mirrors every script
   to the project's `game-source/` with `/studio`.

## How it is made

The baseplate is source, not a hand-kept file. `src/` is Rojo source (Luau files, `.model.json`, `.meta.json` and a few
`.rbxm` for meshes and rigs); `default.project.json` maps it into the services and defines the Workspace parts.

```
rojo build default.project.json -o RunnerBaseplate.rbxl      # rebuild the place from src/
node ../maintainer/baseplate.js all --place-id <ID>          # re-extract from a live game, then rebuild
```

`extract.json` says what is copied out of the live game and what is stripped; `../maintainer/baseplate-patches.js`
holds the edits re-applied after every extract (the GoodSignal and Zone fixes, the minimal Profile, the empty
Monetization, the blank admin ids). `../CLAUDE.md` § 2 explains the pipeline.

Extracted 2026-10-06 from Joust Tycoon, keeping only what Joust Tycoon, FPSTowerDefense and SecureTheConcert share.
Third-party libraries inside it are credited in `../THIRD_PARTY.md`.
