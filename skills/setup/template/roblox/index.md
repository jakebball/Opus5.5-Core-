# {{NAME}}

{{PITCH}}

- **Place:** {{PLACE_LINE}}
- **Status ({{DATE}}):** set up from the team template; nothing built yet.

## The Core Loop

**Unset.** Written when the design is settled.

## Documentation Index

| Doc | Purpose |
| --- | --- |
| `index.md` | This file: the pitch, the loop, the doc index and what is open |
| `tech-design.md` | Architecture, naming, networking, persistence and the Hard Rules. Authoritative |
| `updatelog.md` | Chronological log of every change |
| `features/art-direction.md` | **The binding art style for every new asset** (opens with § Project Art Style) |
| `features/animation-style.md` | **The binding animation style for every animation** |
| `blender-source/` | One headless-Blender script per 3D asset (`/blenderassets`); `style.py` is the palette |
| `game-source/` | Every script in the place, mirrored by `/studio` (`studio.json` holds the place id) |
| `ui-source/` | GUI builder scripts; `renders/` holds `/itemicon` renders and `renders.json` |
| `demo-source/` | `/demo` scripts, one per feature, kept as reusable video checks |

Added as the work reaches them: `features/economy.md` and `tools/balance-sim.js` (currency or progression),
`features/ui-instances.md` and `features/ui-backlog.md` (the first UI), a `CONTRACTS.md` (a pass split across
sub-agents). Templates for each are in `~/.claude/skills/setup/templates/`.

## Reading Order

New to the project: `index.md` → `tech-design.md` → the one feature doc your task touches. Do not bulk-read
`features/`.

## Delegation

The orchestrating session runs Opus 5.5 at medium effort and hands work to these agent types (user-level presets in
`~/.claude/agents/`). Pick by the work, not the size:

| Agent type | Model, effort | Use for |
| --- | --- | --- |
| `asset-pipeline` | Opus 5.5, max | Art and the asset pipeline: Blender models, painting, decimation and LOD tiers, uploads, mesh swaps, rigs, animation, item icons |
| `perf-optimizer` | Opus 5.5, max | Complex optimisation: unclear frame-time, triangle, draw-call, memory or script-time causes, fixes spanning several systems, the `/perfbudget` loop |
| `feature-dev` | Opus 5.5, medium | Code that needs judgment: gameplay features, components, UI wiring, bug fixes, refactors, and pipeline tooling with a clear pass/fail check |
| `builder` | Sonnet 5.5, medium | Mechanical jobs the brief fully specifies, with clear checks: map and dressing rebuilds, attribute passes, config changes, re-running a pipeline step. Stops and reports anything needing a judgment call |
| `scout` | Sonnet 5.5, low | Read-only lookups and measurements in Studio: counting instances, reading attributes, measuring tris and LOD state. Editing and Studio-changing tools are blocked (`disallowedTools`). Plain file searches go to the built-in `Explore` |

## Design Commitments

None yet.

## Open

- Everything marked **Unset** in these docs.
