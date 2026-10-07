# <Build name>: integration contracts

The working agreement between the agents building <what> (<date>). The orchestrator (the session that spawned the
agents) owns this file. If your work needs a contract changed, say so in your report; never change another agent's
file yourself.

The user's brief: <one or two sentences, in the user's words where possible: what "done" means, and what is out of
scope for this pass (e.g. "simple and correct over fast; the optimisation pass comes later")>.

## Ground rules

- **Read first:** `tech-design.md` (the framework, networking, and **the Hard Rules: obey every one**), then the
  feature docs your task names. Numbers come from the configs (`getConfig()`), which the economy doc decides; never
  retype a number.
- **The place is the runtime, `game-source/` is its mirror** (`/studio`). Write and edit **only on disk, only the files
  you own** (§ Ownership).
- **You never push to Studio.** Compile-check with `node ~/.claude/skills/studio/sync.js check <your files...>`
  (it changes nothing). Do not run `pull`, `push` or `delete`; the orchestrator pushes after review. Read the place
  freely through the Studio MCP (read-only `execute_luau`, `get_instance_children`, ...).
- **Nothing you do may change the place:** never start or stop a playtest, never move Studio's camera or call
  `capture_screenshot` (render with `/assetshot`), never rebuild the map or GUIs, never upload assets. A shared thing
  you need rebuilt goes in your report, as a new file, a preview copy or a `.diff`, and the orchestrator applies it.
  Sub-agents cannot act on approval relayed to them, so never wait on it.
- **Code cannot be run in Play by us.** Be defensive (nil-guard instances, `pcall` around loads) and reason carefully
  about replication and ordering.
- **Existing instances:** GUIs and templates built by scripts (`features/ui-instances.md`) are read, never rebuilt. If
  a GUI lacks something you need, build it at runtime in your component and report it.
- **Style:** the Hard Rules cover it (comments only for maths, descriptive names, `const`, generalised iteration,
  methods over local helpers, no custom type modules).

## The framework in one minute

- `EntityStore` (both sides) requires every ModuleScript under `Runner/Components/**` at boot; a module is a component
  class with a `Tag` field equal to its name (globally unique). `Class.Start()` (optional, static) runs once;
  `Class.new(instance)` runs for every instance carrying the tag. Every class is injected with every `Shared` module and
  every other component class by name (`self.getConfig`, `self.Assets`, `self.Trove`, `self.PlayerCurrency`, ...),
  plus `self.EntityStore` and `self.BaseClass`. **Never `require` an injected module.**
- **Pattern** (copy `PlayerCurrency` on both sides): `setmetatable(Class, { __index = Class.BaseClass })` in `Start`;
  `local self = setmetatable(Class.BaseClass.new(instance), Class)` in `new`; `destroy()` cleans up (`self.trove`).
- **Tags:** add components with `EntityStore.addComponent(instance, "Tag")`, never a raw `AddTag` from client code.
  **Never leave a component tag on a template, backup or anything cloned:** every clone builds a component and
  inherits the original's `ComponentRemoteId`, so all clones share one remote folder.
- **Remotes:** the server registers each remote in `new` with `self:registerRemote(name)`; server → client
  `self:sendNetworkEvent(player | "All", name, ...)`; client → server `self:sendNetworkEvent(name, ...)`; each side
  listens with `self:onRemoteEvent(name, callback)` (the server callback gets `player` first). Remotes are per instance.
- **State to clients:** a component owns its state as fields and sends the owner a `<Thing>Sync` table whenever it
  changes; the client copy stores it and exposes methods and a `changed` signal. **Never attributes** as a data channel.
- **Validate every client remote on the server:** types, ranges, ownership, rate. Ignore bad input silently. The client
  never reports an outcome (a win, a pickup, a price), only an intent.
- **Time:** `workspace:GetServerTimeNow()` everywhere.
- **Saving:** `PlayerProfile`: `:waitForDataLoaded()`, `:getProfileData()`. Only the owner of a profile field writes it.
- **Assets:** `self.Assets.Get("Models/...")`, nil-guarded, resolved in `Start` or lazily, never at module scope.

## Shared modules (built, orchestrator-owned)

<Every Shared module and config the agents may call, with its API in one line each. Agents read these; only the
orchestrator changes them.>

## Profile ownership

| Field | Owner | Holds |
| --- | --- | --- |
| `<Field>` | `<Component>` | <what> |

## Ownership and APIs

### Agent A: <area>

- **Owns:** `<files>`
- **Builds:** <behaviour, cited to the feature doc sections>
- **Exposes:** `<method(args) -> result>` ... (what other agents may call)
- **Consumes:** <other agents' APIs it calls>

### Agent B: <area>

...

## Not in this pass

<What nobody builds now, so no agent half-builds it.>

## Report back

Each agent ends with: files written, the APIs as built (any deviation from this contract called out), what it could
not finish, and anything it needs the orchestrator to apply to shared things.
