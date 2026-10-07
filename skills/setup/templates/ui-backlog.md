# UI Backlog

Every UI the current feature set needs, as a checklist to work through. Drawn up <date> from the feature docs. Tick an
item when it is built and approved, and move what it settles into the feature doc it cites. Which instance each UI is,
built or planned, is `ui-instances.md`.

## Before building any of it

- **Style:** <the approved UI style, `art-direction.md` § UI>. Build with the project's shared UI blocks
  (`ui-source/Kit.luau` or equivalent), never a one-off look.
- **Scale only:** every Size and Position in Scale, one `UIAspectRatioConstraint` per group's parent frame, no
  `UIScale` (`tech-design.md` hard rule).
- **Variants before volume:** build two or three labelled variants of the first panel, let the user pick, then build
  the rest to the winner.
- **Wiring:** panels follow `/makegui` (`Frame` on `Main`, `Button` on `Close`); components read the client mirrors,
  never attributes.
- **Item pictures** are `/itemicon` renders read from the model's `IconImage`; glyph icons are for actions and stats only.
- **Checking:** list every GuiObject's Size and Position through the MCP (read-only) and look for Offset, clipping
  (`TextFits`, children outside their parent) and misaligned edges; the user judges the final look in Play.

## Done

- [ ] ...

## Phase 1: the core loop

Without these a player cannot play the loop.

- [ ] **<UI>** (`<feature>.md` § <section>): what it shows, where, what it reads.

## Phase 2: progression and settings

- [ ] ...

## Phase 3: polish and social

- [ ] ...

## Last: monetisation

- [ ] **Robux shop** (`economy.md` § Robux Economy).

## Decisions the user must make

- <open question> (blocks: <items>)
