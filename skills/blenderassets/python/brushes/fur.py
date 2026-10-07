"""brushes.fur: fur brushes. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import math

import numpy as np

import paintlib as paint
from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

from .core import _dashes, _gold, _streaks, colour, finish, posterize, stitch_lines
from .registry import brush
from .wrap import with_alpha



@brush("fur.coat_strokes", version=1, material="fur", fixture="dome", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Animal coat: posterised patches, directional hair strokes along flow, optional belly lightening and dark leg points')
def coat(context, flow=(0.0, 1.0, -0.35), legs=False, belly=True, base="Bay", light="BayLight", dark="BayDark"):
    count = context.count
    pos = context.pos
    patches = fbm(pos, scale=0.42, octaves=3, seed=61.0)
    rgb = ramp(posterize(np.clip(0.54 + patches * 1.1, 0, 1), 6), [(0.0, colour(dark)), (0.55, colour(base)), (1.0, colour(light))])
    strokes = _streaks(pos, flow, seed=63.0)
    rgb = shade(rgb, 1.0 + strokes * 0.16)
    fine = _streaks(pos, flow, scale=3.0, along=0.25, across=9.0, seed=65.0, octaves=2)
    rgb = mix(rgb, solid(count, colour(light)), smoothstep(0.25, 0.45, fine) * 0.22)
    if belly:
        rgb = mix(rgb, lift(rgb, 0.18, toward="E8B07A"), smoothstep(-0.3, -0.85, context.normal[:, 2]) * smoothstep(4.4, 3.4, pos[:, 2]) * 0.6)
    if legs:
        points = smoothstep(2.15, 1.55, pos[:, 2])
        hair = _streaks(pos, (0.0, 0.0, 1.0), seed=67.0)
        dark_leg = shade(solid(count, colour("Points")), 1.0 + hair * 0.25)
        rgb = mix(rgb, dark_leg, points)
    # light posterising here: the coat's big patches turn blotchy when pushed as hard as the gear
    return finish(rgb, context, ao_strength=0.7, edge_light=0.12, top_light=0.2, under_shadow=0.28, poster=0.3)


@brush("fur.hair_strands", version=1, material="fur", fixture="dome", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Mane and tail strands along flow with a sheen on top')
def hair(context, flow=(0.0, 0.0, -1.0), base="Points", light="BayDark"):
    count = context.count
    strands = _streaks(context.pos, flow, scale=1.6, along=0.25, across=11.0, seed=71.0)
    rgb = mix(solid(count, colour(base)), solid(count, colour(light)), smoothstep(-0.1, 0.4, strands) * 0.75)
    sheen = smoothstep(0.3, 0.9, context.normal[:, 2])
    rgb = mix(rgb, lift(rgb, 0.4, toward="C99A6B"), sheen * 0.35)
    return finish(rgb, context, ao_strength=0.85, edge_light=0.1, top_light=0.12)


# ---- Greenmeadow (Joust Tycoon, approved 2026-10-05). Copied verbatim from the project's villagerpaint.py.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("fur.trim", version=1, material="fur", fixture="ring", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowVillagers merchant's collar and hem)", summary="Squirrel-grey fur trim on a collar or hem: soft clumped tufts, pale tips, dark roots; alpha 0, so it keeps its paint on a TintMask part")
def trim(context, seed=0.0):
    """Squirrel-grey fur on a robe's collar and hem: soft clumped tufts, pale tips, dark roots. Alpha 0."""
    count = context.count
    local = context.local
    clumps = fbm(local, scale=9.0, octaves=3, seed=381.0 + seed)
    rgb = mix(solid(count, colour("MeadowVillagerFurDark")), solid(count, colour("MeadowVillagerFur")), smoothstep(-0.35, 0.05, clumps))
    rgb = mix(rgb, solid(count, colour("MeadowVillagerFurLight")), smoothstep(0.1, 0.4, clumps))
    return with_alpha(finish(rgb, context, ao_strength=0.9, edge_light=0.15, top_light=0.1), 0.0)
