---
name: deslopify
description: Sweep a project's user-authored Luau for "slop" and bring it into line with the project's hard rules. Half 1 (every project) — generalized iteration over pairs/ipairs, descriptive variable names. Half 2 (component-architecture projects only) — enforce the project's tech-design.md: no floating singletons, no reinvented modules, component-owned source of truth instead of replication attributes. Approval-gated per rule category; runs on Fable 5.
---

# deslopify

A guided cleanup sweep. It does NOT invent rules — the project's own `tech-design.md` is the authority for Half 2. This skill is the *process*: confirm the model, scope the files, then walk one rule category at a time, presenting a change-list and applying only what the user approves.

Two halves, because not every project uses the component framework:

- **Half 1 — universal Luau hygiene.** Applies to any Luau/Roblox project. Generalized iteration + descriptive names.
- **Half 2 — component-architecture conformance.** Only runs when the project's `tech-design.md` describes the Runner / `Components/` / EntityStore framework. Enforces the structural hard rules.

## Invocation

```
/deslopify              # both halves
/deslopify --half1      # universal hygiene only
/deslopify --half2      # component conformance only
/deslopify <path-or-folder>   # restrict the sweep to a subtree
```

If no scope is given, the sweep covers the whole active project's user-authored code.

## Step 0 — Confirm Fable 5, then get the go-ahead (hard gate)

This is a large mechanical sweep — it belongs on Fable 5 (fast, cheap for bulk edits).

1. Check the active model. If it is **not** `claude-fable-5`, tell the user plainly and ask them to switch (`/model claude-fable-5`) or to explicitly approve running on the current model. Do not silently switch the model yourself.
2. Regardless of model, do not touch a single file until the user has given an explicit "go." State which halves and which scope you're about to run, and wait for confirmation.

## Step 1 — Resolve the user-authored file set (exclude third-party)

The goal is *user-authored* code only. Never edit vendored libraries.

1. **Find the code.** For Roblox projects the source usually lives in Studio, not on disk — use the Studio MCP (`grep_scripts`, `search_files`, `get_script_source`, `set_script_source`). If the project has on-disk source (Rojo, a `src/` tree), use the file tools instead. If neither is available, stop and ask the user how the code is accessed.
2. **Read the project's `tech-design.md`** (follow `index.md` if present) to learn the folder layout and, critically, **which `Shared/Generic` modules are vendored vs. project-built**. Many projects keep both in the same folder (e.g. `Profilestore`, `Promise`, `Spr`, `Trove`, `Zone`, `Icon`, `EmitModule`, `Rain`, `WindShake`, `Octree`, `CameraShake` are vendored; `Assets`, `ConfettiCannon`, `Observers` are project-built).
3. **Exclude from all edits:** anything the docs mark as vendored / "left as upstream ships," third-party packages, and the AdminSystem Package internals. When in doubt whether a module is vendored, ask rather than edit it.

State the resolved file count and the exclusion list before proceeding.

## Approval model — per-category batch

Work **one rule category at a time**, never file-by-file:

1. Scan the whole in-scope file set for that one category.
2. Present the complete change-list: each site as `path:line` with a tight before → after.
3. Wait for the user's approval of the batch (they may strike individual sites).
4. Apply the approved changes, then move to the next category.

For Half 2's behavior-changing refactors, surface any site that needs judgment individually inside its category rather than burying it in a uniform batch.

## Safe-edit protocol (Studio MCP)

The MCP plugin's reliable write path is whole-file overwrite, and it is destructive:

- **Re-read the script's current source immediately before writing it** — never write from a stale snapshot; parallel sessions and the user may have changed it.
- After composing the new source, **validate it compiles** before/after writing via `execute_luau` `loadstring(newSource)` (config-style modules: `loadstring(mod.Source)()`). A failed parse means abort that file and report.
- One file at a time; do not run parallel writes against the same file.
- `set_script_source` overwrites the whole script — include the entire file, not a fragment.

---

# Half 1 — Universal Luau hygiene

## 1a. Generalized iteration (drop `pairs` / `ipairs`)

Luau iterates a table directly. Replace:

- `for key, value in pairs(t) do` → `for key, value in t do` — **always equivalent, safe to batch.**
- `for index, value in ipairs(arr) do` → `for index, value in arr do` — **NOT a blind swap.** `ipairs` stops at the first `nil` and visits only the contiguous array part (1..n); generalized iteration also visits hash-part keys and does not stop at a `nil` hole. Convert an `ipairs` loop **only** when the table is a pure sequential array with no other keys and the code does not rely on stop-at-nil. Present every `ipairs` conversion with that judgment shown; leave anything ambiguous unchanged and flag it.

Sweep `pairs` and `ipairs` as two separate sub-batches so the safe one isn't gated on the risky one.

## 1b. Descriptive variable names

Every variable, parameter, and loop counter gets a name a stranger reads with no context. No single letters and no cryptic abbreviations:

- `i` → `index`, `k`/`v` → `key`/`value`, `dt` → `deltaTime`, `n`/`t`/`f` → `normal`/`tangent`/`fraction`
- `cfg` → `config`, `btn` → `button`, `idx` → `index`, `tbl` → `table`, `p` → `part`/`player` (per context), `c` → `corner`/`character` (per context)

Err verbose. There are no single-letter exceptions in game/component code. Rename within a scope coherently (declaration + every use) and re-validate the file compiles. **Skip vendored libraries entirely** — renaming inside them breaks mergeability with upstream.

This is a behavior-preserving rename, but a careless rename can shadow or collide — present the per-file rename map for approval and compile-check each file after applying.

---

# Half 2 — Component-architecture conformance

Run only if the project's `tech-design.md` describes the Runner / `Components/` / EntityStore framework. If it doesn't, skip Half 2 with a one-line note ("not a component-architecture project — Half 2 skipped").

**The project's `tech-design.md` is the authority.** Read it first and enforce what it states. The canonical checks below are the usual shape; defer to the project doc wherever it's more specific, and respect every carve-out and legacy-exception it records.

## 2a. No floating singleton components

A functional (non-Gui) component must be tagged on a real instance and live and die with it:

- Per-player state → the `Player` (`observePlayer` → `AddTag`).
- Per-object state → that object (a tile Part, an NPC, a plot).
- A transient spawned thing → its own tagged component on the spawned instance via `EntityStore.addComponent`.

Flag any functional component that tags a throwaway `Configuration` purely to host a module-level singleton, or any system that runs everything from `.Start()` and hand-tracks global state. ~99% of components belong on the player or on a gameplay instance.

**Sanctioned exception:** a genuinely server-wide coordinator with no natural host (e.g. a `RoundManager`, `ServerLuck`) may live on a single marker/Configuration — these stay rare and instance-identified. Binding any *other* functional component to a bare Configuration requires explicit user sign-off — surface it as a question, do not auto-rewrite.

## 2b. Don't reinvent a generic or game-specific module

Before any bespoke logic, check whether a `Components/Generic/`, `Components/Gui/`, `Components/<GameName>/`, or `Shared/` module already does it. Flag reimplementations of framework primitives:

- Raw `.Activated` / `InputBegan` on an instance that should carry the `Button` component (use its debounced `triggeredEvent`). *Carve-out:* buttons cloned at runtime from templates and destroyed by the same component may connect `.Activated` directly — check the project's tech-design for its exact wording.
- A hand-rolled step/timer offer ladder instead of the generic `ProductLadder`.
- Tweening `.Visible` directly instead of the `Frame` component's `:open()` / `:close()`.
- `WaitForChild` / dot-index asset chains instead of the shared `Assets` module.
- A local number formatter instead of the shared number util; a fresh ParticleEmitter setup instead of the shared confetti/VFX module.

These are behavior-changing refactors — present each with a concrete before/after and the module it should route through, and apply only what the user approves. If the shared module is close but insufficient, recommend extending it rather than forking a private copy.

## 2c. Source of truth in components, not replication attributes

A component owns its state as fields. Other server scripts read it by fetching the component (`EntityStore.getComponent`) and calling a method (`thing:get()`), never by reading an attribute. When the client needs the value, the server replicates the component to a per-player client copy (the `CustomReplicator` pattern) and the client reads the mirror the same way — not `player:GetAttribute(...)`.

Flag: `SetAttribute` / `GetAttribute` / `GetAttributeChangedSignal` used as a cross-script or cross-boundary data channel where a component method + CR mirror should carry it.

**Carve-out (going-forward rule):** server-wide state that is *identical for every player* and has no behavior may use a single replicated Configuration attribute — one value replicated once per client beats a per-player CR mirror there. **Do not refactor a project's existing attribute-based replication** unless the user asks; respect the legacy exceptions its `tech-design.md` lists (e.g. a per-player `DiceCount` render attribute, a `Board` tile-index mirror). This rule governs *new* code and flags *candidates* for later migration — present them as a list, don't auto-rewrite shipped paths.

## 2d. Seeded architecture rules (report only)

The seed list in `project-setup.md` § Seeded Hard Rules grew on 2026-10-06 with rules learned in other games. Most are design rules no
grep can prove, so this category **only reports** sites for the user to judge, one line each with `path:line` and the
rule; it never rewrites. Check only the rules the project's `tech-design.md` actually carries.

| Rule | Signal to look for |
| --- | --- |
| One loop per system, never one per entity | `Heartbeat:Connect` / `RenderStepped:Connect` / `task.spawn` loops / `while task.wait` inside a component's `new` for a component that has many instances |
| A Robux grant never saves the profile | a function registered as a `Commerce` grant handler that calls a profile save (`:Save(`, `EndSession`, `modifyProfileData` followed by a save) |
| Session state never touches the profile | round/run/match components that call `getProfileData` or write profile fields |
| The client reports intent, never outcomes | client → server remotes whose arguments name results (`won`, `amount`, `reward`, `hit`, item or crop ids) rather than inputs |
| Numbers live in config | numeric literals for prices, rates, durations or odds inside `Components/` (not 0, 1, maths constants or layout) |
| High-rate messages leave batched | `sendNetworkEvent` / `FireClient` inside a per-item loop |
| One writer per shared surface | writes to `Lighting.*`, `workspace.GlobalWind`, `Terrain.Clouds` or a `SoundGroup.Volume` from more than one component |
| Never leave a component tag on a template | not a code check: the `/setup` audit reads it from the live place |

---

## Reporting & logging

When the sweep finishes:

1. Print a per-category summary: sites found, changed, skipped (with reasons), and any flagged-for-user items left unchanged.
2. Only after the user approves the change (global `CLAUDE.md` § Documentation Waits for Approval): if the project keeps an `updatelog.md`, append under today's `## YYYY-MM-DD — <title>` heading what was changed and why (per-category counts + notable files). Don't fabricate an updatelog where none exists.
3. If Half 2 surfaced behavior-changing refactors the user deferred, list them explicitly so they aren't mistaken for "everything's clean."

## Guardrails

- **Never** edit vendored / third-party / AdminSystem-Package code.
- **Never** auto-apply a behavior-changing refactor — propose, then apply on approval.
- Compile-check every file after editing; abort and report a file that won't parse rather than leaving it broken.
- Half 2 enforces the *project's* tech-design.md — if this skill's canonical checks ever disagree with a project's doc, the project's doc wins (and mention the discrepancy so the docs can be reconciled).

## Change Summary

This skill writes to a project, so the change summary rule applies to its output. Canonical copy:
`~/.claude/skills/setup/change-summary.md`.

Close the reply with **2–3 sentences maximum** — what changed, which files or instances were
modified, and the logical choices now live in the code. Any report or verification step this skill
defines above runs first and stays as specified; the summary is what *ends* the reply, not a second
copy of that report.
