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

## Design Commitments

None yet.

## Open

- Everything marked **Unset** in these docs.
