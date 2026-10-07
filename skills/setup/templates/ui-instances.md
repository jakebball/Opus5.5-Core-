# UI Instances

Which instance in the place is which feature's UI, what builds it and what drives it. Look here before touching a
GUI, and update a row whenever one is built, renamed or wired. The look is `art-direction.md` § UI, and what is left to
build is `ui-backlog.md`.

Every GUI is built by a script in `ui-source/` that deletes and rebuilds its instances, so change the script, never
the instance. Run one with `node ~/.claude/skills/studio/run.js ui-source/<Script>.luau`. Components live in the
client's UI components folder, with disk copies in `game-source/`.

**Status:** **Planned** means named here, not built. **Built** means styled and approved, with sample content and no
game data. **Wired** means its component drives it from real game state.

## ScreenGuis (`StarterGui`)

| Instance | Feature | What it shows | Built by | Component | DisplayOrder | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `HudGui` | HUD | <what> | `<Builder>.luau` | `HudGui` | 0 | Planned |

## Templates (`ReplicatedStorage.Assets.Gui`)

| Template | Cloned by | What it is | Built by | Status |
| --- | --- | --- | --- | --- |

## Built at runtime

| Instance | Built by | Where | What |
| --- | --- | --- | --- |

## Item renders (`ui-source/renders/`)

`/itemicon` renders, stamped on each model as `IconImage`; the manifest is `ui-source/renders/renders.json`.
