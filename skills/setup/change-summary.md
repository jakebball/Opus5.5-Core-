# Change Summary Rule

This is the canonical copy. It governs **every project** under the standard project structure and
**every skill** in `~/.claude/skills/`. `/setup` installs a pointer to this file when
scaffolding a new project and verifies the pointer when auditing an existing one.

Projects and skills reference this file — they do not copy it. One rule, one place to edit.

## Where it is installed

| Location | Form |
| --- | --- |
| `~/.claude/CLAUDE.md`, under `# Change Summaries` | **Condensed inline copy** — the one sanctioned duplicate |
| `~/.claude/skills/setup/project-setup.md` | Pointer + the block `/setup` pastes into new projects |
| Every `~/.claude/skills/*/SKILL.md` | Pointer, as a closing `## Change Summary` section |
| Every project's `tech-design.md` | Pointer, as a closing `## Change Summaries` section |
| A project with no `tech-design.md` yet | Pointer at the top of `updatelog.md`, until one exists |

The global `CLAUDE.md` copy is inline **by design**: it is loaded into every session unconditionally
and must be obeyable without opening a second file. It is the only exception — do not "fix" it into a
pointer, and when the rule below changes, update that copy in the same pass. Everywhere else, an
inlined copy is a defect and gets replaced with a pointer.

## The rule

**Every change closes with a summary of 2–3 sentences. Three is a hard ceiling, not a target.**

The summary carries three things:

1. **What changed** — the behaviour or system that is different now.
2. **What was touched** — the files, scripts, modules, or instances modified, by name.
3. **The logical choices** — the decisions now baked into the code that is live in the game, and
   why that path was taken over the obvious alternative.

One sentence carrying all three beats three sentences of padding. If the change genuinely cannot be
described in three sentences, that is a signal the change was too large to land in one pass — say so
rather than writing a fourth sentence.

## Scope

Applies to **all changes**: bug fixes, features, refactors, config edits, asset wiring, and Studio
instance edits. It applies whether the work was done on disk or written into a place through the
Studio MCP. It applies to work done inside a skill (`/makegui`, `/makeweapon`, `/deslopify`, etc.) —
the skill's own output does not exempt it.

It does **not** apply to read-only work: audits, answering questions, reporting findings, or a turn
where nothing was written.

## What this is not

- **Not the updatelog entry.** `updatelog.md` is the durable written record and keeps its own format
  (`## YYYY-MM-DD — Title` plus per-file bullets). This summary is what gets said back in the reply.
  The summary is said at once; the log entry, like every project doc, is written only after the user
  approves the change (global `CLAUDE.md` § Documentation Waits for Approval). Neither replaces the
  other.
- **Not a substitute for flagging problems.** A concern, a blocked step, or something deliberately
  left out is reported separately and does not have to fit inside the three sentences.
- **Not a preamble.** It closes the work. Do not announce what is about to be done in this format.
- **Not a file listing.** Naming six files and nothing else fails the rule — the logical choices are
  the part that carries information the file list cannot.

## Shape

Prose, not a bulleted report. No headings, no tables, no "Files modified:" label. File and instance
names go inline, formatted as links where the file is on disk.

## Examples

**Good** — three sentences, all three elements, no padding:

> Rebirth now multiplies plot income instead of replacing it, so the tier-3 bonus stacks with the
> gamepass rather than overwriting it. Changed `Components/Game/Plot.luau` and the multiplier table
> in `Shared/getConfig/Rebirth.luau`. I stacked it multiplicatively rather than additively because
> the existing gamepass multiplier already reads as a product, and an additive rebirth term would
> have made the two sources non-commutative depending on purchase order.

**Good** — one sentence is fine when the change is small:

> The close button now routes through the `Frame` component's `:close()` instead of writing
> `.Visible` directly in `Components/Gui/ShopPanel.luau`, which restores the open/close tween that
> the raw property write had been silently skipping.

**Bad** — file list with no reasoning, and it runs long:

> I modified `Plot.luau`, `Rebirth.luau`, `PlayerCurrency.luau`, and `Shop.luau`. In `Plot.luau` I
> updated the income function. In `Rebirth.luau` I updated the config table. In `PlayerCurrency.luau`
> I added a new method. In `Shop.luau` I called the new method. Everything should work now.

**Bad** — describes intent instead of what is live, and buries the decision:

> I have made some improvements to the rebirth system to make it feel better for players. There were
> a few options here and I went with the one that seemed cleanest. Let me know if you want it changed.
