"""Worked example of a painted, toon-shaded asset: a supply crate with riveted iron bands and an embroidered
team-colour strap. Shows Atlas / the brushes library / shapelib / inklib together:

    node <skill>/blend.js build <skill>/examples/painted_crate.py --out <scratchpad>/PaintedCrate

Two atlases because a MeshPart holds one texture: the crate and its bands share one (part "Crate"), the strap
has its own (part "CrateTeam", tinted in Roblox by SurfaceAppearance.Color, its gold left untinted by alpha 0).
"""

import blendlib as bl
import brushes
import inklib as ink
import paintlib as pl
import shapelib

bl.reset()
style = brushes.use_style("painted-toon")      # the library profile: toon finish, palette, a painter per role
crate_atlas = pl.Atlas("PaintedCrate", size=512, ao_distance=0.6, samples=24)
strap_atlas = pl.Atlas("PaintedCrateStrap", size=256, ao_distance=0.4, samples=24)

crate = shapelib.rounded_box("Crate", (2.0, 2.0, 1.6), at=(0.0, 0.0, 0.8), radius=0.08, segments=2)
bl.roblox(crate, part="Crate")
crate_atlas.add(bl.smooth(crate, 40), style.painter("wood", axis=0, knots=True))
pieces = [crate]
for index, x in enumerate((-0.68, 0.68)):
    band = shapelib.rounded_box(f"Band{index}", (0.16, 2.06, 1.66), at=(x, 0.0, 0.8), radius=0.03, segments=1)
    bl.roblox(band, part="Crate")
    rivets = [(x, side * 1.03, height) for side in (-1, 1) for height in (0.25, 0.8, 1.35)]
    crate_atlas.add(bl.smooth(band, 40), style.painter("rivets", centres=rivets, radius=0.05))
    pieces.append(band)

path = [(0.0, -1.12, 0.14), (0.0, -1.12, 0.9), (0.0, -1.12, 1.4), (0.0, -0.75, 1.7), (0.0, 0.0, 1.72), (0.0, 0.75, 1.7), (0.0, 1.12, 1.4), (0.0, 1.12, 0.9), (0.0, 1.12, 0.14)]
strap = shapelib.cloth_band("Strap", crate, path, [0.42] * len(path), thickness=0.03, lift=0.035, steps=5, across=7)
bl.roblox(strap, part="CrateTeam")
strap_atlas.add(bl.smooth(strap, 40), style.painter("embroidered band", along_samples=list(strap["band_along"]), half_samples=list(strap["band_half_widths"])), tint=True)

for piece in pieces + [strap]:
    ink.outline(piece)
bl.finish("PaintedCrate", budget=6000)
