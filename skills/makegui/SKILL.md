---
name: makegui
description: Wire a ScreenGui panel into the Roblox boilerplate component framework — tags the ScreenGui as [Name]Gui, the Main frame as Frame, the Close button as Button, and generates the Components/Gui client component that owns open/close. Use whenever the user invokes /makegui, points at a ScreenGui and asks to "hook it up", "componentize it", "make a gui component for it", or asks for a new panel's open/close wiring in any Runner-framework Roblox project.
---

# makegui — wire a ScreenGui panel into the component framework

Turn an authored ScreenGui panel into a fully wired Gui component on the Default Roblox Boilerplate (Runner framework). The result: an edit-time-tagged ScreenGui, a `Frame`-tagged Main panel with sprung open/close, a `Button`-tagged Close button that closes it, and a `Components/Gui/<Name>Gui` ModuleScript exposing `:open()` / `:close()` / `:toggle()`.

This skill is for **modal panels** (shops, settings, quest windows). It is NOT for persistent always-on HUDs — those don't open/close, often need `ResetOnSpawn = true`, and usually already have an owning component. If the target looks like a HUD or already carries a component tag, stop and confirm with the user first.

## Step 0 — Preconditions

1. Confirm the active Studio is the place for the **project currently being worked on** (`list_roblox_studios` / `get_place_info`, compared against the working directory's project). If a different place is active, stop and ask — never tag another project's instances.
2. Confirm the place runs the boilerplate: `game.StarterPlayer.StarterPlayerScripts.Runner.Components.Generic.Frame` and `...Generic.Button` must exist. If they don't, this skill doesn't apply — say so and stop.
3. Resolve the target ScreenGui. The argument may be a name (`Quests`) or a path. Look under `game.StarterGui`. If nothing matches or several do, list candidates and ask.

## Step 1 — Derive the component name

- `baseName` = the ScreenGui's `Name` with any trailing `Gui` stripped (never produce `SettingsGuiGui`).
- Component name **and** tag = `baseName .. "Gui"` — `Gui` suffix exactly, never `GUI`. Module `Name` must equal the tag verbatim (EntityStore resolves components by module name).
- Tags are globally unique across the `Components/` tree. `grep_scripts` for an existing module of that name; if one exists, stop and ask — two same-named modules silently shadow each other.

## Step 2 — Inspect the ScreenGui

- Expect a child Frame named `Main` (the panel). If absent, list the children and ask which frame is the panel — do not guess.
- Search `Main`'s descendants for a GuiButton named `Close` (usually an ImageButton). If none exists, skip button wiring and say so in the summary.

## Step 3 — Tag (edit time, in Studio)

Tags must be applied at **edit time** — a component inside a ScreenGui that self-tags at runtime breaks after respawn, and edit-time tags survive the StarterGui → PlayerGui clone.

| Instance | Tag |
| --- | --- |
| ScreenGui | `<Name>Gui` (the component tag) |
| `Main` frame | `Frame` |
| `Close` button | `Button` |

Use `add_tag`, then verify with `get_tags`. If duplicate-named siblings exist anywhere on the path, `add_tag` silently picks the first — disambiguate via `execute_luau` with `CollectionService:AddTag` and a property predicate instead.

Do NOT add a UIScale to Main or Close — the `Frame` and `Button` components create and own their own (`FrameScale` / `ButtonScale`); a second one is ignored and misleads.

## Step 4 — ScreenGui properties

- `ResetOnSpawn = false` (modal panels don't rebuild per spawn).
- `ScreenGui.Enabled = true` — visibility is owned by the `Frame` component via `Main.Visible`; never toggle the ScreenGui.
- `Main.Visible = false` so the panel boots closed. (`Frame.new` treats authored `Visible = true` as open-on-boot — only leave it true if that's intended.)
- Optional: set a `FrameGroup` string attribute on `Main` to put the panel in a mutual-exclusion group (opening one member closes the others — e.g. `"Shops"`). Ask the user if unclear; default to no group.

## Step 5 — Generate the component

Create a ModuleScript at `game.StarterPlayer.StarterPlayerScripts.Runner.Components.Gui.<Name>Gui` (`create_object` then `set_script_source`; create the `Components/Gui` Folder first if the project doesn't have one yet). This is the exact shape — substitute `QuestsGui`:

```lua
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local QuestsGui = {}
QuestsGui.__index = QuestsGui
QuestsGui.Tag = "QuestsGui"

function QuestsGui.Start()
	setmetatable(QuestsGui, { __index = QuestsGui.BaseClass })
end

function QuestsGui.new(instance)
	local self = setmetatable(QuestsGui.BaseClass.new(instance), QuestsGui)

	if not instance:IsDescendantOf(localPlayer) then
		return self
	end

	self.frame = nil

	local main = instance:WaitForChild("Main")
	self.trove:AddPromise(QuestsGui.EntityStore.promiseGetComponent(main, "Frame"):andThen(function(frame)
		self.frame = frame
	end))

	local closeButton = main:FindFirstChild("Close", true)
	if closeButton then
		self.trove:AddPromise(QuestsGui.EntityStore.promiseGetComponent(closeButton, "Button"):andThen(function(button)
			self.trove:Add(button.triggeredEvent:Connect(function()
				self:close()
			end), "Disconnect")
		end))
	end

	return self
end

function QuestsGui:open()
	if self.frame then
		self.frame:open()
	end
end

function QuestsGui:close()
	if self.frame then
		self.frame:close()
	end
end

function QuestsGui:toggle()
	if not self.frame then return end
	if self.frame.instance.Visible then
		self.frame:close()
	else
		self.frame:open()
	end
end

function QuestsGui:destroy()
	self.trove:Clean()
end

return QuestsGui
```

Why each piece is the way it is:

- **`IsDescendantOf(localPlayer)` guard** — an edit-time tag on a StarterGui descendant constructs TWO component instances (StarterGui template + PlayerGui copy); only the PlayerGui copy gets wired. The template instance returns an inert shell.
- **`promiseGetComponent`, never `getComponent`** — the `Frame`/`Button` components attach from their own tag observers and may not exist yet when this constructor runs. `trove:AddPromise` cancels the wait on destroy.
- **`triggeredEvent:Connect(...)` troved with the explicit `"Disconnect"` method name** — it's a GoodSignal connection; Trove's auto-probe trips GoodSignal's strict metatable without it.
- **No resolver override on `BaseClass.new`** — the component is purely client-side. If it later needs server remotes, pass `{ remoteInstance = localPlayer }` (per-player server component) or `{ remoteId = "<SharedId>" }` (shared-broadcast) per the project's networking conventions.
- Boilerplate house rules apply: `const` for constants, descriptive names, no comments, generalized iteration.

If no Close button was found, omit the `closeButton` block entirely.

## Step 6 — Docs

Follow the current project's doc policy where the files exist (skip any that don't), and only after the user approves the wiring (global `CLAUDE.md` § Documentation Waits for Approval):

- Add the new component to the `Components/Gui/` roster in the project's `tech-design.md`.
- Create or update `features/<kebab-name>.md` describing the panel (instance layout, tags, open/close flow).
- Append an entry to the project's `updatelog.md`.

## Step 7 — Hand off for playtest

Never start a playtest yourself. Summarize what was wired and ask the user to verify:

- Panel is closed at boot (no flash of the panel on spawn).
- Opening it (via whatever caller exists — note if none does yet, `:open()` has no invoker until one is wired, e.g. a topbar icon or another component) springs it in with the open sound.
- The Close button springs it away with the close sound.

Remind yourself: playtests do not hot-reload client scripts, and an open Script editor tab in Studio can clobber MCP source writes — if the new module was open in an editor tab, have the user close it before playtesting.

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
