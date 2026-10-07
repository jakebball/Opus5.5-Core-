"""brushes.leather: leather brushes. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import math

import numpy as np

import paintlib as paint
from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

from .core import _dashes, _gold, _streaks, colour, finish, posterize, stitch_lines
from .registry import brush



@brush("leather.scuffed", version=1, material="leather", fixture="box", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Scuffed leather in three tones')
def leather(context, base="Leather", light="LeatherLight", dark="LeatherDark"):
    variation = fbm(context.pos, scale=1.6, octaves=3, seed=21.0)
    rgb = ramp(np.clip(0.55 + variation * 0.7, 0, 1), [(0.0, colour(dark)), (0.55, colour(base)), (1.0, colour(light))])
    scuffs = fbm(context.pos, scale=12.0, octaves=2, seed=23.0)
    rgb = mix(rgb, solid(context.count, colour(light)), smoothstep(0.3, 0.38, scuffs) * 0.55)
    return finish(rgb, context, edge_light=0.55)


@brush("leather.stitched", version=1, material="leather", fixture="ring", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Leather with dashed stitch rows at given heights (rows, axis)')
def leather_stitched(context, rows=(), axis=2, dash=0.06, base="Leather", light="LeatherLight", dark="LeatherDark"):
    rgb = leather(context, base=base, light=light, dark=dark)
    for height in rows:
        distance = np.abs(context.pos[:, axis] - height)
        line = 1 - smoothstep(0.012, 0.022, distance)
        along = np.arctan2(context.pos[:, 1], context.pos[:, 0]) * 1.2 if axis == 2 else context.pos[:, 2]
        dashes = (np.mod(along / dash, 1.0) < 0.55).astype(np.float64)
        rgb = mix(rgb, solid(context.count, colour("Rope")), line * dashes * 0.85)
    return rgb


@brush("leather.studded_strap", version=1, material="leather", fixture="ring", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Stitched strap with brass studs round a uniform ring loft (rows, studs height, count_around, perimeter)')
def belt_paint(context, rows, studs, count_around, perimeter):
    rgb = leather_stitched(context, rows=rows)
    u = context.coord[:, 0] * count_around
    offset = (u - np.floor(u) - 0.5) * perimeter / count_around
    distance = np.sqrt(offset ** 2 + (context.coord[:, 1] - studs) ** 2) / 0.034
    head = 1 - smoothstep(0.82, 1.0, distance)
    rgb = mix(rgb, finish(solid(context.count, colour("Brass")), context, ao_strength=0.3, edge_light=0.2), head)
    shine = np.sqrt((offset + 0.01) ** 2 + (context.coord[:, 1] - studs - 0.01) ** 2) / 0.034
    return mix(rgb, solid(context.count, colour("BrassLight")), (1 - smoothstep(0.1, 0.45, shine)) * 0.9)


@brush("leather.binding", version=1, material="leather", fixture="ring", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Dark leather binding with a centre stitch line on a ring loft (centre height, pitch = perimeter)')
def binding_paint(context, centre, pitch):
    rgb = leather(context, base="Binding", light="BindingLight", dark="LeatherDark")
    distance = np.abs(context.coord[:, 1] - centre)
    return mix(rgb, finish(solid(context.count, colour("Rope")), context, ao_strength=0.4), _dashes(distance, context.coord[:, 0] * pitch, dash=0.05))


@brush("leather.saddle", version=1, material="leather", fixture="box", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Saddle leather with optional brass studs at points')
def saddle_leather(context, studs=()):
    rgb = leather(context, base="Leather", light="LeatherLight", dark="LeatherDark")
    if studs:
        distance = paint.dots(context.pos, studs, 0.045)
        rgb = mix(rgb, solid(context.count, colour("Brass")), (1 - smoothstep(0.8, 1.0, distance)))
        rgb = mix(rgb, solid(context.count, colour("BrassLight")), (1 - smoothstep(0.0, 0.5, distance)) * 0.8)
    return rgb
