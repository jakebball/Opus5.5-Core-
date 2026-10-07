---
name: makereactcomponent
description: Convert an authored Roblox GUI instance tree into a stateless react-lua function component and write it as a ModuleScript in workspace. Use whenever the user invokes /makereactcomponent, points at a ScreenGui/Frame and asks to "turn this into a React component", "convert this GUI to react-lua", "codify this", or asks for authored UI to be re-expressed as createElement calls in any Roblox project using react-lua.
---

# makereactcomponent — authored GUI → stateless react-lua component

Take a GUI instance tree the user built by hand in the Explorer and emit an equivalent **stateless function component**: one `React.createElement` tree, no hooks, no state, no side effects. The authored instances are left untouched — this reads them, it does not consume them.

The point is to let someone design visually and ship declaratively. Anything the design does not encode — state, events, conditional children, data — is the caller's job afterwards, and the emitted component must make that easy rather than pretend to solve it.

## Step 0 — Preconditions

1. Confirm the active Studio is the place for the project currently being worked on (`get_place_info` against the working directory's project). If a different place is active, stop and ask — never read or write another project's instances.
2. Locate react-lua. Search for a `Packages` (or `node_modules`-style) folder containing a `React` ModuleScript, then **prove it** rather than trusting the folder name:
   ```lua
   local React = require(packages.React)
   assert(typeof(React.createElement) == "function")
   assert(typeof(React.useState) == "function")  -- absent in Roact 1.x
   ```
   A folder named `Roact` may well contain react-lua, and a folder named `React` may be Roact. `useState` is the discriminator. If only Roact 1.x is present, say so and stop — the emitted code will not run.
3. Record the require path the component will use. Prefer `script:FindFirstAncestor("<PluginOrProjectRoot>").Packages` over a `script.Parent.Parent` chain; a relative chain breaks silently whenever the module moves and fails only when the require finally runs.

## Step 1 — Resolve the target

The argument may be a name (`ToolSuiteFrame`) or a full path (`StarterGui.App.ToolSuiteFrame`). Search `StarterGui` first, then `workspace`, then `ReplicatedStorage`. If nothing matches, or several do, list the candidates and ask — do not guess.

Confirm the target is a `GuiObject` (or a `ScreenGui`, in which case the component renders its children and the caller supplies the host). Refuse anything else.

## Step 2 — Read the tree

Walk the full subtree in one `execute_luau` call and return a serialisable description. Do not make one call per instance — a 40-instance panel becomes 40 round trips.

For each instance capture: `ClassName`, `Name`, and **only the properties that differ from a fresh `Instance.new(ClassName)`**. That default comparison is the single most important rule in this skill. Emitting every property produces hundreds of lines of noise that hides the four values that actually matter, and it bakes in defaults that then silently stop tracking future engine changes.

```lua
local reference = Instance.new(instance.ClassName)
-- for each candidate property: if instance[prop] ~= reference[prop] then emit end
reference:Destroy()
```

**Never emit**: `Parent`, `AbsolutePosition`, `AbsoluteSize`, `AbsoluteRotation`, `AbsoluteContentSize`, `ClassName`, `Name` (it becomes the child key), or anything read-only. Reading some properties throws — wrap each read in `pcall` and skip failures rather than aborting the walk.

## Step 3 — Emission rules

**Structure.** One `local function <Name>(props)` returning a single `React.createElement` call. Children go in the third argument as a table keyed by instance name, so the emitted hierarchy reads like the Explorer.

**Child keys must be unique.** Two siblings named `Frame` are legal in Roblox and illegal as table keys — the second silently overwrites the first and a child vanishes from the render with no error. Detect duplicates and suffix them (`Frame1`, `Frame2`), and report every rename in the summary.

**Datatypes.** Emit the most readable constructor, not the most general:
- `UDim2.fromOffset(x, y)` / `UDim2.fromScale(x, y)` when one pair is zero; `UDim2.new(...)` otherwise
- `UDim.new(scale, offset)`
- `Color3.fromRGB(r, g, b)` with each channel **rounded** — `Color3.new` on a float round-trips to values like `0.29411765` and makes diffs unreadable
- `Vector2.new`, `Rect.new`, `NumberRange.new`
- `Enum.<Type>.<Name>` verbatim
- `NumberSequence` / `ColorSequence`: emit the full keypoint constructor, and flag it in the summary — these are long and usually better authored on the instance

**Events.** A stateless component still has to be clickable. For each `GuiButton` in the tree, emit `[React.Event.Activated] = props.on<ChildName>Activated` and list every generated prop name in the summary. Do not invent hover or press states — those are state, and this component has none.

**Layout children** (`UICorner`, `UIStroke`, `UIPadding`, `UIListLayout`, `UIGridLayout`, `UIAspectRatioConstraint`, …) are ordinary children and emit exactly like anything else.

**Sizes driven by a layout.** A child of a `UIGridLayout` or `UIListLayout` usually has a meaningless `Size` — the layout drives it. Emit it anyway if it differs from the default, but note in the summary which children are layout-driven, or the next reader will "fix" a `Size` that does nothing.

**Style.** Match the project's conventions — read its `CLAUDE.md` / `tech-design.md` first. Absent any, use: `const` for `SCREAMING_SNAKE` constants, no single-letter identifiers (spell out `createElement`; do not use the conventional `e` alias), one space either side of `=`, no vertical alignment, and no comments.

## Step 4 — Write it

Create a `ModuleScript` in `workspace`, named after the source instance, and set its source with `set_script_source`. If a module of that name already exists there, show the user the diff-relevant facts (source length, when it was made) and ask before overwriting.

The authored GUI is **not** deleted, moved, or modified. If the user wants it gone, that is a separate explicit instruction.

## Step 5 — Verify by mounting, not by reading

Never report success from the write succeeding. Mount the emitted component headlessly and compare the result against the source tree:

```lua
local host = Instance.new("ScreenGui")
host.Parent = game:GetService("CoreGui")
local container = Instance.new("Frame")
container.Size = UDim2.fromOffset(sourceWidth, sourceHeight)
container.Parent = host
ReactRoblox.createRoot(container):render(React.createElement(Component))
```

Then walk both trees and compare class, name and child count at every node. Destroy the host afterwards.

Two traps in this step, both of which will otherwise be misread as a broken component:

- **React has not committed immediately after `render`.** A walk in the same call — even after `task.wait(0.5)` — can find an empty container. Read the tree in a **later, separate** call.
- **An in-call write success does not mean the write stayed.** Re-verify the ModuleScript exists with the expected source length in a separate call before reporting done.

Also confirm the source instance still exists and is unmodified.

## Report

State plainly: the module's path, the number of instances converted, every child key that was renamed for uniqueness, every `on*Activated` prop generated, any property that could not be read, and anything flagged as layout-driven or better left authored. If verification found a mismatch, lead with that — a component that mounts to the wrong tree is worse than one that fails to compile, because it looks like it worked.

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
