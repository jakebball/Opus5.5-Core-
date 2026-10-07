# {{NAME}} — Technical Design

Authoritative. If code contradicts this document, the code is wrong — unless the design itself needs to change, in
which case update this document first and then the code.

## 1. Inherited Framework

The place starts from the team baseplate (`RunnerBaseplate.rbxl`): the Runner framework, the AdminSystem and the
standard asset folders, described in `~/.claude/skills/setup/project-setup.md` § Default Roblox Boilerplate. Do not
re-document or re-implement what already ships; only additions and deviations are described here.

- **Entry points:** server `game.ServerScriptService.Runner` (Script), client
  `game.StarterPlayer.StarterPlayerScripts.Runner` (LocalScript). Both host `EntityStore` (tag-driven component
  registry; injects every `Shared` module and every component class by name) and `BaseClass`. **Never `require()` an
  injected module** — take it off `self`.
- **Game code** goes in `Components/{{NAME_ID}}/` on each side; client UI components in `Components/UI/`; game Shared
  modules in `Shared/{{NAME_ID}}/`; game configs beside the defaults in `Shared/getConfig/`.
- **Turned-off boilerplate** moves to the Runner's `Disabled/` folder (not loaded), never deleted. List it here.
- **AdminSystem:** generic commands only; the game's give-commands are added in `AdminSystem/Commands/`.
- **Assets** live in `ReplicatedStorage.Assets.<Models|Misc|Gui|VFX|Sounds|Tool|Animations>` and are fetched through
  the `Assets` module.
- **Code on disk:** `game-source/` mirrors every script in the place (`/studio`'s `sync.js`); it is the copy that is
  edited, reviewed and committed. Generated scripts are listed here and regenerated, never hand-edited.
- **3D assets** are authored in headless Blender (`blender-source/`, `/blenderassets`), to the art style.

### Differences from the baseplate

None recorded yet. `/setup` fills this from the live place once it is linked.

## 2. Game-Specific Code

Nothing built yet. Each component gets a row as it is built.

| Component | Side | Tagged on | Owns |
| --- | --- | --- | --- |

## 3. Naming Conventions

- **Modules / components / classes** — `PascalCase`, matching the instance name exactly.
- **Functions and methods** — `camelCase`. Private helpers get a leading underscore: `_resolveRound`.
- **Locals and parameters** — `camelCase`, descriptive, never single-letter.
- **Constants** — `SCREAMING_SNAKE_CASE`, declared with `const`.
- **Tags** — `PascalCase`, identical to the component module name.
- **Attributes** — `PascalCase`, for editor-authored data only, never cross-script messaging.
- **Config keys** — `PascalCase`.
- **Asset paths** — `Assets.Get("Models/Folder/Name")`, slash-delimited, never dot chains.

## 4. Networking & Data Flow

- **The server is authoritative** for every outcome, reward, purchase and currency change; the client reports intent.
- **State to clients:** a component owns its state as fields and sends its owner a `<Thing>Sync` table when it
  changes; the client mirror stores it and exposes methods and a `changed` signal. Shared state goes to everyone the
  same way. Never attributes as a data channel.
- **Remotes are per instance** (`registerRemote` under the instance's `ComponentRemoteId`); server-wide channels use
  `BaseClass.sharedRemote`.
- **Every client request is validated** on the server: types, ranges, ownership, rate. Bad input is ignored silently.
- **Time** is `workspace:GetServerTimeNow()` everywhere.

## 5. Data Persistence

`Profilestore` through `PlayerProfile`, template `Shared/getConfig/Profile` (`Reconcile()`d on load). Each saved field
has exactly one owning component:

| Field | Owner | Holds |
| --- | --- | --- |
| `Currencies.Coins` | `PlayerCurrency` | The default currency |

## 6. Balance & Tuning

Every rate, cost, multiplier and pacing estimate will live in `features/economy.md`, the single source of truth for
numbers, with `tools/balance-sim.js` behind its pacing table. Feature docs describe mechanism only.

## 7. Hard Rules

{{RULES}}

### Project-specific hard rules

None yet.

{{CHANGE_SUMMARY}}
