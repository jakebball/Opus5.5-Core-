# brushes: the cross-project painter library

Painted assets in every project draw their texture recipes from here, so each game adds to one library instead of
starting from nothing. `CATALOG.md` lists every brush and style (generated; read it first). The swatch sheets in
`swatches/<style>.png` show each style's painters on test shapes.

## The three pieces

| Piece | Lives in | Says |
| --- | --- | --- |
| **Brush** | `wood.py`, `metal.py`, `leather.py`, `cloth.py`, `fur.py`, `stone.py`, `roof.py`, `water.py`, `plant.py`, `fibre.py`, `foliage.py`, `food.py`, `fire.py`, `terrain.py` (one module per material family; shared course-laying and tiling-noise helpers in `surface.py`; painter wrappers in `wrap.py`) | how to paint one material. Registered with `@brush(id, version, material, fixture, tint, styles, source, summary, status)` |
| **Style profile** | `styles/<name>.json` | a game's look: its finish (`toon` or soft painted, and the toon numbers), palette, ink settings, and a painter for every **role**, pinned to a brush version, with options |
| **Project pointer** | the project's `features/art-direction.md` | `Style profile: <name>`, plus any project palette entries in `blender-source/style.py` |

## How a painter is chosen, every time

1. Read the project's art style. It names its style profile.
2. When modelling, decide what each piece is made of: its **role** ("wood", "brass", "team cloth", "quilted
   cloth", "embroidered band"...). Roles may be specific ("stone.castle", "stone.dungeon") when one game uses
   several looks of one material.
3. `style.painter(role, **geometry_options)` gives the pinned brush with the profile's options. Pass only what
   the geometry supplies (a band's `along_samples`, a quilt's `scale` and `pitch`, rivet `centres`).
4. **Role missing from the profile:** read `CATALOG.md` for a brush of that material whose `styles` include this
   style (or that would read right under its finish: check the swatch), and add the role to the profile. If none
   fits, write the brush in the project's `blender-source/` first.
5. **When the user approves an asset,** promote the project brushes it used: move each into the family module
   here with full metadata (source = game, asset and date; status approved), add its role to the profile, and run
   `node blend.js brushes` to render its swatch and refresh the catalog.

## Rules

- **A brush's colours are palette names** (`colour("Ash")`) resolved through the active style, so one brush serves
  many palettes. A style's `palette` overrides the defaults in `core.py`; a project adds its own on top with
  `brushes.use_style(name, palette=style.PALETTE)`.
- **The finish belongs to the style, not the brush.** Every recipe ends in `core.finish()`, which applies the active
  style's look. The same wood brush is cel-shaded under `painted-toon` and soft under `soft-painted`.
- **Versions are pinned.** Any change that alters what an existing asset would paint is a new version: keep the old
  function, register the new one as `version=2`, and point only the styles that want it at `@2`. A game rebuilt
  later keeps its look.
- **Variety comes three ways, cheapest first:** a different palette (same brush), different options in the profile
  (same brush), or a new brush (a new look). A profile may map several roles to one brush with different options.
- **`fixture`** names the swatch test shape that gives the brush its geometry: `box`, `cylinder`, `points`, `ring`,
  `sleeve`, `channels`, `band`, `tail`, `knot`, `dome`, and at real castle scale `drum`, `wall`, `cone`, `banner`,
  `valance`, `plane`, `pool`, `bank`, `blades`, `pad`, `heap`, `coil`, `log`, `stump`; at Greenmeadow scale `crown`,
  `limb`, `cord`, `flower`, `leaf`, `spindle`, `toadstool`, `rock`, `drywall`, `rick`, `sheaf`, `field`, `board`,
  `sail`, `sheet`, `bunting`, `basket`, `fruit`, `hearth`, `bolt`, `basin`, `roof`, `tunic`, `hat` (see `swatch.py`).
  A new kind of geometry needs a new fixture.
- **`tile`** is the fixture of a flat-texture brush (`terrain.py`): it paints `painter(tile, **options)` over a
  `terrain.Tile(period)` (the texels of one seamless square, for Terrain MaterialVariants) instead of an atlas
  piece; its swatch is the texture tiled 2 x 2, so a seam shows as a cross.
- **Wrappers are not brushes.** `wrap.py` holds painter combinators (`in_frame`, `baked_tint`, `untinted`,
  `with_alpha`, `banded`, `sooted`, `glowing`): they take painters, so a profile cannot pin them, and they never
  change a brush's own output.
- **`tint=True`** marks brushes that paint team-colour (TintMask) parts: alpha is the tint amount.
- **Only approved work is promoted.** Experiments stay in their project until the user approves the asset, so the
  library holds proven looks only.

## Commands

```
node <skill>/blend.js brushes                 # every style: swatches + CATALOG.md + catalog.json
node <skill>/blend.js brushes --style NAME    # one style
node <skill>/blend.js brushes --role ROLE     # one role's tile in every style (no sheet)
```

Bakes are cached (paintlib), so a re-run after a brush change repaints in seconds.
