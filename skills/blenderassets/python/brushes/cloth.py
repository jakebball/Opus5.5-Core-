"""brushes.cloth: cloth brushes. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import math

import numpy as np

import paintlib as paint
from paintlib import Context, fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

from .core import _dashes, _gold, _streaks, colour, finish, posterize, stitch_lines
from .registry import brush
from .surface import _ring, wall_light
from .wrap import with_alpha



@brush("cloth.team_plain", version=1, material="cloth", fixture="box", tint=True, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Near-white cloth for TintMask team colour, optional stripes or rim shading')
def team_paint(context, stripes=None, rim=None):
    count = context.count
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=2.2, octaves=3, seed=41.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.45)
    if stripes is not None:
        rgb = mix(rgb, solid(count, colour("TeamShade")), stripes * 0.6)
    if rim is not None:
        rgb = mix(rgb, shade(rgb, 0.55), rim)
    lit = shade(rgb, 0.5 + 0.42 * smoothstep(-0.7, 0.9, context.normal[:, 2]))
    return finish(lit, context, ao_strength=0.85, edge_light=0.22, top_light=0.06, under_shadow=0.4)


def quilt(context, phase, along, base="Linen", light="Linen", dark="LinenShade", stitch="LinenStitch", pitch_shading=0.3, dirt_floor=None):
    count = context.count
    variation = fbm(context.pos, scale=1.6, octaves=3, seed=51.0)
    rgb = ramp(posterize(np.clip(0.62 + variation * 1.1, 0, 1), 5), [(0.0, colour(dark)), (0.6, colour(base)), (1.0, colour(light))])
    puff = np.abs(np.sin(np.pi * phase))
    rgb = shade(rgb, 1.0 - pitch_shading + pitch_shading * 1.25 * puff ** 0.6)
    weave = fbm(context.pos, scale=22.0, octaves=1, stretch=(1.0, 1.0, 3.0), seed=53.0)
    rgb = shade(rgb, 0.96 + weave * 0.08)
    groove, thread = stitch_lines(phase, along)
    rgb = mix(rgb, shade(solid(count, colour(dark)), 0.75), groove * 0.85)
    rgb = mix(rgb, lift(solid(count, colour(light)), 0.2), thread * 0.9)
    if dirt_floor is not None:
        grime = smoothstep(dirt_floor + 0.5, dirt_floor, context.pos[:, 2]) * (0.5 + 0.5 * smoothstep(-0.2, 0.3, fbm(context.pos, scale=3.0, octaves=2, seed=55.0)))
        rgb = mix(rgb, shade(rgb, 0.7), grime * 0.45)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.2)


@brush("cloth.quilt_bands", version=1, material="cloth", fixture="sleeve", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Horizontal quilted bands round a vertical sleeve (pitch, origin)')
def band_quilt(context, pitch=0.33, origin=2.45):
    pos = context.pos
    phase = (pos[:, 2] - origin) / pitch
    around = np.arctan2(pos[:, 1], pos[:, 0] - np.sign(pos[:, 0]) * 1.5) * 0.6
    return quilt(context, phase, around, dirt_floor=None)


@brush("cloth.quilt_channels", version=1, material="cloth", fixture="channels", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Quilting driven by PaintCoord: seams exactly in shapelib quilt_puffs / roll_ring / channel_dome grooves, pillow rows, wear, stains')
def quilt_coord(context, scale, pitch, rows=None, row_offset=0.0, base="Linen", light="Linen", dark="LinenShade", stitch="LinenStitch", dirt_floor=None, seed=0.0):
    """Quilting driven by PaintCoord: u * scale is the channel phase (whole numbers on the stitched seams),
    v the height, so the painted seams sit exactly in the modelled grooves. `pitch` is a channel's width in studs."""
    count = context.count
    u = context.coord[:, 0] * scale
    v = context.coord[:, 1]
    coded = context.coord[:, 0] > -0.5
    variation = fbm(context.pos, scale=1.6, octaves=3, seed=51.0 + seed)
    rgb = ramp(posterize(np.clip(0.62 + variation * 1.1, 0, 1), 5), [(0.0, colour(dark)), (0.6, colour(base)), (1.0, colour(light))])
    fraction = u - np.floor(u)
    crest = np.where(coded, np.sin(np.pi * fraction), 1.0)
    seam = np.where(coded, np.minimum(fraction, 1 - fraction) * pitch, 1.0)
    rgb = shade(rgb, 0.84 + 0.2 * crest ** 0.8)
    if rows:
        row_phase = (v - row_offset) / rows
        row = np.where(coded, np.abs(row_phase - np.round(row_phase)) * rows, 1.0)
        pillow = np.where(coded, np.sin(np.pi * (row_phase - np.floor(row_phase))), 1.0)
        rgb = shade(rgb, 0.93 + 0.08 * pillow)
        rgb = mix(rgb, shade(solid(count, colour(dark)), 0.82), (1 - smoothstep(0.008, 0.026, row)) * 0.7)
        rgb = mix(rgb, lift(solid(count, colour(light)), 0.25), _dashes(row, u * pitch) * 0.95)
    weave = fbm(context.pos, scale=22.0, octaves=1, stretch=(1.0, 1.0, 3.0), seed=53.0 + seed)
    rgb = shade(rgb, 0.96 + weave * 0.08)
    worn = smoothstep(0.5, 0.75, fbm(context.pos, scale=3.5, octaves=2, seed=57.0 + seed)) * crest ** 2
    rgb = lift(rgb, worn * 0.2, toward="FFF6E2")
    stain = smoothstep(0.58, 0.7, fbm(context.pos, scale=1.2, octaves=3, seed=59.0 + seed))
    rgb = mix(rgb, shade(rgb * np.array((1.0, 0.93, 0.8)), 0.8), stain * 0.35)
    rgb = mix(rgb, shade(solid(count, colour(dark)), 0.7), (1 - smoothstep(0.01, 0.034, seam)) * 0.85)
    rgb = mix(rgb, lift(solid(count, colour(light)), 0.25), _dashes(seam, v) * 0.95)
    if dirt_floor is not None:
        grime = smoothstep(dirt_floor + 0.45, dirt_floor, context.pos[:, 2]) * (0.5 + 0.5 * smoothstep(-0.2, 0.3, fbm(context.pos, scale=3.0, octaves=2, seed=55.0)))
        rgb = mix(rgb, shade(rgb * np.array((1.0, 0.95, 0.85)), 0.72), grime * 0.5)
    return finish(rgb, context, ao_strength=0.75, edge_light=0.2)


@brush("cloth.placket", version=1, material="cloth", fixture="band", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='A seamed cloth strip with bound edges (shapelib.cloth_band, half width)')
def placket_paint(context, half):
    across, along = context.coord[:, 0], context.coord[:, 1]
    count = context.count
    edge = half - np.abs(across)
    variation = fbm(context.pos, scale=1.6, octaves=3, seed=61.0)
    rgb = ramp(np.clip(0.6 + variation, 0, 1), [(0.0, colour("LinenShade")), (0.6, colour("Linen")), (1.0, colour("Linen"))])
    rgb = mix(rgb, solid(count, colour("Binding")), 1 - smoothstep(0.022, 0.03, edge))
    stitch = np.abs(edge - 0.045)
    rgb = mix(rgb, shade(solid(count, colour("LinenShade")), 0.8), (1 - smoothstep(0.008, 0.02, stitch)) * 0.6)
    rgb = mix(rgb, solid(count, colour("LinenStitch")), _dashes(stitch, along, dash=0.05) * 0.9)
    return finish(rgb, context, ao_strength=0.75, edge_light=0.25)


@brush("cloth.patch", version=1, material="cloth", fixture="band", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='A hand-sewn patch with whip stitches over its edge (cloth colour name, half, length)')
def patch_paint(context, cloth, half, length):
    across, along = context.coord[:, 0], context.coord[:, 1]
    count = context.count
    edge = np.minimum(half - np.abs(across), np.minimum(along, length - along))
    variation = fbm(context.pos, scale=2.4, octaves=3, seed=67.0)
    rgb = shade(solid(count, colour(cloth)), 0.9 + variation * 0.35)
    weave = np.abs(np.sin(across * math.tau / 0.04)) * np.abs(np.sin(along * math.tau / 0.04))
    rgb = shade(rgb, 0.95 + 0.08 * weave)
    rgb = mix(rgb, shade(rgb, 0.7), 1 - smoothstep(0.0, 0.02, edge))
    # big whip stitches over the edge, the way a patch is sewn on by hand
    run = np.where(np.abs(across) > half - 0.06, along, across)
    whip = (np.mod(run / 0.07, 1.0) < 0.3).astype(np.float64) * (1 - smoothstep(0.035, 0.05, edge))
    rgb = mix(rgb, solid(count, "EFE3C4"), whip * 0.95)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("cloth.embroidered_band", version=1, material="cloth", fixture="band", tint=True, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Team cloth band with twill, gold borders and gold lozenges; gold at alpha 0 stays untinted')
def sash_paint(context, along_samples, half_samples, lozenge_step=0.34):
    """Team cloth with a twill weave, a gold border embroidered inside each hem and gold lozenges down the
    middle. Gold is returned with alpha 0 so the castle tint leaves it gold."""
    count = context.count
    across, along = context.coord[:, 0], context.coord[:, 1]
    half = np.interp(along, along_samples, half_samples)
    edge = half - np.abs(across)
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=2.2, octaves=3, seed=41.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    rgb = shade(rgb, 0.96 + 0.06 * np.abs(np.sin((along + across) * math.tau / 0.05)))
    rgb = mix(rgb, solid(count, colour("TeamShade")), (1 - smoothstep(0.0, 0.025, edge)) * 0.55)
    border = smoothstep(0.03, 0.036, edge) * (1 - smoothstep(0.058, 0.064, edge))
    cell = along / lozenge_step
    cell = cell - np.floor(cell) - 0.5
    shape = np.abs(across) / 0.065 + np.abs(cell) * lozenge_step / 0.085
    lozenge = 1 - smoothstep(0.88, 1.0, shape)
    rim = (1 - smoothstep(1.0, 1.16, shape)) - lozenge
    gold = np.clip(np.maximum(border, lozenge), 0.0, 1.0)
    rgb = mix(rgb, _gold(across, along, count), gold)
    rgb = mix(rgb, solid(count, colour("GoldDark")), np.clip(rim, 0, 1) * 0.85)
    lit = finish(rgb, context, ao_strength=0.85, edge_light=0.22, top_light=0.06, under_shadow=0.4)
    alpha = 1 - np.clip(gold + rim, 0.0, 1.0)
    return np.concatenate([lit, alpha[:, None]], axis=1)


@brush("cloth.embroidered_tail", version=1, material="cloth", fixture="tail", tint=True, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Swallowtail cloth tail with gold borders, a gold band and fringe (shapelib.hanging_tail)')
def tail_paint(context, length, notch, half_top, half_end):
    count = context.count
    across, down = context.coord[:, 0], context.coord[:, 1]
    fraction = np.clip(down / length, 0.0, 1.0)
    half = half_top + (half_end - half_top) * fraction
    spread = np.clip(np.abs(across) / np.maximum(half, 1e-3), 0.0, 1.0)
    to_end = (length - notch * (1 - spread)) - down
    edge = half - np.abs(across)
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=2.2, octaves=3, seed=43.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    rgb = shade(rgb, 0.96 + 0.06 * np.abs(np.sin((down + across) * math.tau / 0.05)))
    fringe = 1 - smoothstep(0.05, 0.06, to_end)
    strands = np.abs(np.sin(across * math.tau / 0.024))
    rgb = mix(rgb, shade(rgb, 0.62 + 0.38 * strands), fringe)
    border = smoothstep(0.024, 0.03, edge) * (1 - smoothstep(0.05, 0.056, edge)) * (1 - fringe)
    band = smoothstep(0.075, 0.082, to_end) * (1 - smoothstep(0.118, 0.125, to_end))
    gold = np.clip(np.maximum(border, band), 0.0, 1.0)
    rgb = mix(rgb, _gold(across, down, count), gold)
    lit = finish(rgb, context, ao_strength=0.85, edge_light=0.22, top_light=0.06, under_shadow=0.4)
    return np.concatenate([lit, (1 - gold)[:, None]], axis=1)


@brush("cloth.gathered", version=1, material="cloth", fixture="knot", tint=True, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Gathered cloth: darker creases where pointiness drops (shapelib.gathered_knot)')
def knot_paint(context):
    count = context.count
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=3.0, octaves=3, seed=45.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.35)
    # pointiness sits near 0.5 on smooth cloth and drops in the gathered creases
    crease = smoothstep(0.49, 0.42, context.curvature)
    rgb = mix(rgb, shade(solid(count, colour("TeamShade")), 0.75), crease * 0.6)
    return finish(rgb, context, ao_strength=0.9, edge_light=0.25, top_light=0.06, under_shadow=0.4)


@brush("cloth.heraldic_banner", version=1, material="cloth", fixture="banner", tint=True, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (tower and gatehouse banners and pennants)", summary="Castle-scale heraldic banner on shapelib.hanging_tail: near-white team cloth, gold border, gold bands at the top and above the swallowtail, optional gold lozenge device (emblem); gold at alpha 0 stays gold on every team")
def heraldic_banner(context, length, half_top, half_end, notch, border=0.22, emblem=True):
    """A castle-scale heraldic banner on shapelib.hanging_tail: near-white cloth for the castle colour, a gold
    border, a gold band above the swallowtail and a gold lozenge device, all gold at alpha 0 so it stays gold on
    every castle."""
    count = context.count
    across, down = context.coord[:, 0], context.coord[:, 1]
    fraction = np.clip(down / length, 0.0, 1.0)
    half = half_top + (half_end - half_top) * fraction
    spread = np.clip(np.abs(across) / np.maximum(half, 1e-3), 0.0, 1.0)
    to_end = (length - notch * (1 - spread)) - down
    edge = half - np.abs(across)
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=0.6, octaves=3, seed=43.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    rgb = shade(rgb, 0.97 + 0.04 * np.abs(np.sin((down * 0.7 + across) * math.tau / 0.6)))
    gold_border = smoothstep(border * 0.45, border * 0.55, edge) * (1 - smoothstep(border, border * 1.1, edge))
    top_band = smoothstep(border * 0.9, border, down) * (1 - smoothstep(border * 2.0, border * 2.1, down))
    end_band = smoothstep(border * 2.0, border * 2.1, to_end) * (1 - smoothstep(border * 3.0, border * 3.1, to_end))
    gold = np.maximum(np.maximum(gold_border, top_band), end_band)
    if emblem:
        centre_down = length * 0.42
        size = half_top * 0.55
        lozenge = np.abs(across) / size + np.abs(down - centre_down) / (size * 1.45)
        device = (1 - smoothstep(0.92, 1.0, lozenge)) * smoothstep(0.55, 0.62, lozenge)
        heart = 1 - smoothstep(0.3, 0.36, lozenge)
        gold = np.maximum(gold, np.maximum(device, heart))
    gold = np.clip(gold, 0.0, 1.0)
    rgb = mix(rgb, _gold(across * 0.08, down * 0.08, count), gold)
    lit = finish(rgb, context, ao_strength=0.8, edge_light=0.2, top_light=0.06, under_shadow=0.4)
    return np.concatenate([lit, (1 - gold)[:, None]], axis=1)


@brush("cloth.dagged_valance", version=1, material="cloth", fixture="valance", tint=True, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (curtain wall valance)", summary="Dagged team valance along X that tiles every `period`: near-white cloth, gold band along the top, gold hem following the dags, gold roundel in each dag (gold at alpha 0); lit like a wall turned to every side (surface.wall_light), no edge light on the dag cuts")
def dagged_valance(context, top, pitch, notch, point, period=17.5, hem=0.13, band=(0.07, 0.2)):
    """A dagged cloth valance for TintMask: near-white cloth, a gold band along the top, a gold hem following the
    dags and a gold roundel in each dag, all gold at alpha 0. Dags repeat every `pitch` along X (points at the
    middle of each pitch), hanging `notch` below `top` at the notches and `point` at the tips."""
    count = context.count
    pos = context.pos
    phase = np.mod(pos[:, 0] + period / 2, pitch) / pitch
    tip = 1 - np.abs(2 * phase - 1)
    bottom = top - notch - (point - notch) * tip
    slope = (point - notch) / (pitch / 2)
    above_hem = (pos[:, 2] - bottom) / math.sqrt(1 + slope * slope)
    down = top - pos[:, 2]
    ring = _ring(pos, period)
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(ring, scale=0.6, octaves=3, seed=43.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    # soft vertical folds, one per dag, darker where the cloth turns back between the tips
    rgb = shade(rgb, 0.9 + 0.1 * tip)
    gold_hem = smoothstep(hem * 0.4, hem * 0.5, above_hem) * (1 - smoothstep(hem, hem * 1.12, above_hem))
    gold_band = smoothstep(band[0] * 0.9, band[0], down) * (1 - smoothstep(band[1], band[1] * 1.08, down))
    roundel_centre = top - notch * 0.95
    distance = np.hypot((phase - 0.5) * pitch, pos[:, 2] - roundel_centre)
    roundel = 1 - smoothstep(0.16, 0.19, distance)
    gold = np.clip(np.maximum(np.maximum(gold_hem, gold_band), roundel), 0.0, 1.0)
    rgb = mix(rgb, _gold(pos[:, 0] * 0.08, pos[:, 2] * 0.08, count), gold)
    light = wall_light(context, period / 2)
    # each dag is a separate sheet, so its cut edges would catch edge light; the cloth reads as one piece
    light.edge = np.where(np.minimum(phase, 1 - phase) < 0.05, 0.0, light.edge)
    lit_rgb = finish(rgb, light, ao_strength=0.8, edge_light=0.2, top_light=0.06, under_shadow=0.4)
    return np.concatenate([lit_rgb, (1 - gold)[:, None]], axis=1)


# ---- Greenmeadow cloth (Joust Tycoon, approved 2026-10-05): sailcloth, the fair's striped canvas, bunting and cloth
# bolts, and the villagers' homespun, linen and motley. Copied verbatim from the project's farmpaint.py, fairpaint.py
# and villagerpaint.py, so these paint exactly what the project's copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"
# the festive bunting run's dyes, in the order the pennants repeat
FESTIVE = ("MeadowFairWoad", "MeadowFairSaffron", "MeadowFairMadder", "MeadowFairTeal", "MeadowFairCream", "MeadowFairPlum", "MeadowFairRose")


@brush("cloth.sail_canvas", version=1, material="cloth", fixture="sail", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowWindmill sails)", summary="Sailcloth (object X across the sail, Z out along it to `length`): undyed canvas in sewn cloths `cloths` wide along the sail, a few darker repair patches, grime toward the tip; no baked occlusion (spars would print as bands), both faces lit as the front; wrap with brushes.wrap.in_frame on a turning sail")
def sail_canvas(context, length=12.0, width=3.0, cloths=0.95, seed=1.0):
    """Windmill sail cloth (object space: X across the sail from the whip, Z out along it): undyed canvas sewn in
    cloths `cloths` wide running along the sail, a few darker repair patches, grime gathering toward the tip. The
    baked occlusion is left out: the sail bars in front would print as hard bands, and the sail turns, so real
    shadows move across it in the game. Both faces are lit as the front one (the frame's -Y), so the cloth reads the
    same from behind the mill."""
    count = context.count
    local = context.local
    x, z = local[:, 0], local[:, 2]
    rgb = ramp(posterize(np.clip(0.55 + fbm(local, scale=0.6, octaves=2, seed=seed) * 1.4, 0, 1), 3), [(0.0, colour("MeadowFarmCanvasShade")), (0.6, colour("MeadowFarmCanvas")), (1.0, colour("MeadowFarmCanvas"))])
    seam = np.abs(np.mod(x / cloths + 0.5, 1.0) - 0.5) * cloths
    rgb = mix(rgb, solid(count, colour("MeadowFarmCanvasSeam")), smoothstep(0.03, 0.01, seam) * 0.7)
    weave = np.abs(np.sin(z * 40.0)) * np.abs(np.sin(x * 40.0))
    rgb = shade(rgb, 0.97 + weave * 0.04)
    patch = smoothstep(0.33, 0.36, fbm(local, scale=0.5, octaves=1, seed=seed + 4.0))
    rgb = mix(rgb, mix(solid(count, colour("MeadowFarmCanvasShade")), solid(count, colour("MeadowFarmThatch")), 0.3), patch * 0.8)
    rgb = mix(rgb, shade(rgb, 0.78), smoothstep(length * 0.55, length, z) * 0.45)
    normal = context.normal.copy()
    normal[:, 1] = -np.abs(normal[:, 1])
    open_air = Context(context.pos, normal, np.ones(count), context.curvature, context.edge, context.local, context.coord)
    return finish(rgb, open_air, ao_strength=0.0, edge_light=0.25)


def _fair_weave(rgb, u, v, pitch=0.05, depth=0.06):
    threads = np.abs(np.sin(u / pitch * math.pi)) * 0.5 + np.abs(np.sin(v / pitch * math.pi)) * 0.5
    return shade(rgb, 1 - depth + threads * depth * 1.4)


@brush("cloth.stripe_canvas", version=1, material="cloth", fixture="sheet", tint=True, styles=("painted-toon",), source=MEADOW + " (fair pavilions, stall awnings, cart tarps and tilts; hub storefront stripes)", summary="Near-white canvas for one tinted stripe gore on a sheet whose PaintCoord is (fraction across the gore, studs along): weave, a sewn seam and running stitch inside each long edge (`seam` of the width; 0 for none); pieces without PaintCoord get plain canvas; alpha = stripe_alpha (tinted=False returns RGB). Bake a fixed colour in with brushes.wrap.baked_tint")
def stripe_canvas(context, stripe_alpha=1.0, seam=0.035, weave=0.06, seed=0.0, tinted=True):
    """Near-white canvas for a tinted stripe gore on a propshapes.sheet whose PaintCoord is (fraction across the
    gore, studs along it): weave, and a sewn seam with a running stitch inside each long edge (`seam` of the width).
    Pieces without PaintCoord (a rolled flap) get plain canvas. alpha = stripe_alpha."""
    count = context.count
    across, along = context.coord[:, 0], context.coord[:, 1]
    coded = across > -0.5
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=0.7, octaves=3, seed=131.0 + seed)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    rgb = _fair_weave(rgb, context.pos[:, 0] + context.pos[:, 1], context.pos[:, 2], pitch=weave, depth=0.05)
    if seam > 0:
        edge = np.where(coded, np.minimum(across, 1 - across), 1.0)
        rgb = mix(rgb, shade(rgb, 0.72), (1 - smoothstep(seam * 0.35, seam * 0.6, edge)) * 0.8)
        stitch = (1 - smoothstep(seam * 0.12, seam * 0.24, np.abs(edge - seam))) * (np.mod(along / 0.14, 1.0) < 0.55)
        rgb = mix(rgb, shade(rgb, 0.8), stitch * coded * 0.7)
    lit = finish(rgb, context, ao_strength=0.8, edge_light=0.18, top_light=0.06, under_shadow=0.4)
    return with_alpha(lit, stripe_alpha) if tinted else lit


@brush("cloth.pennant", version=1, material="cloth", fixture="bunting", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowFairBunting; hub well flags)", summary="A bunting pennant `width` x `length` on a PaintCoord of (pennant index x stride + across, drop from the line): woven cloth, the top folded over the line as a stitched sleeve (`hem`), a running stitch inset round the cut edges; tinted near-white at alpha 1, or festive=True dyes each pennant the next of `dyes` (RGB, untinted)")
def pennant(context, width, length, festive=False, hem=0.22, seed=0.0, stride=10.0, dyes=FESTIVE):
    """A bunting pennant on fairkit.pennants' PaintCoord: woven cloth, the top folded over the line as a stitched
    sleeve, a running stitch inset round the cut edges. Tinted: near-white at alpha 1, so the part's colour comes
    through. Festive: each pennant dyed the next colour of `dyes`, untinted."""
    count = context.count
    u, v = context.coord[:, 0], context.coord[:, 1]
    index = np.round(u / stride)
    across = u - index * stride
    if festive:
        rgb = np.zeros((count, 3))
        for slot, name in enumerate(dyes):
            chosen = np.mod(index, len(dyes)) == slot
            rgb[chosen] = solid(int(chosen.sum()), colour(name))
        shade_colour = shade(rgb, 0.78)
    else:
        rgb = solid(count, colour("TeamBase"))
        shade_colour = solid(count, colour("TeamShade"))
    variation = fbm(context.pos, scale=0.9, octaves=3, seed=97.0 + seed)
    rgb = mix(rgb, shade_colour, np.clip(0.5 - variation * 2.4, 0, 1) * 0.3)
    rgb = _fair_weave(rgb, across, v)
    half = np.maximum(width / 2 * (1 - v / length), 1e-3)
    edge = half - np.abs(across)
    sleeve = 1 - smoothstep(hem - 0.02, hem, v)
    rgb = mix(rgb, shade(rgb, 0.86), sleeve)
    seam = 1 - smoothstep(0.012, 0.03, np.abs(v - hem))
    rgb = mix(rgb, shade(rgb, 0.62), seam * 0.8)
    stitch_v = (1 - smoothstep(0.01, 0.022, np.abs(v - hem - 0.07))) * (np.mod(across / 0.1, 1.0) < 0.55)
    inset = (1 - smoothstep(0.012, 0.024, np.abs(edge - 0.09))) * (v > hem + 0.05) * (np.mod(v / 0.1, 1.0) < 0.55)
    thread = np.clip(stitch_v + inset, 0, 1)
    rgb = mix(rgb, lift(rgb, 0.35, toward="FFF6E2"), thread * 0.85)
    rgb = mix(rgb, shade(rgb, 0.8), (1 - smoothstep(0.0, 0.035, edge)) * 0.6)
    lit = finish(rgb, context, ao_strength=0.5, edge_light=0.15, top_light=0.06, under_shadow=0.3)
    return lit if festive else with_alpha(lit, 1.0)


@brush("cloth.bolt", version=1, material="cloth", fixture="bolt", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowFairStall cloth goods)", summary="A bolt of cloth in colour `dye` wound round object X (`radius`): twill along the roll, the wound layers as rings on the end faces round a dark core, optional woven stripes at fractions `stripes` along the roll from its middle")
def bolt(context, dye, radius, stripes=None, seed=0.0):
    """A bolt of dyed cloth wound round object X: twill along the roll, the wound layers showing as rings on the
    end faces, an optional pair of woven stripes (fractions along the roll from its middle)."""
    count = context.count
    local = context.local
    rgb = solid(count, colour(dye))
    variation = fbm(context.pos, scale=1.2, octaves=2, seed=191.0 + seed)
    rgb = mix(rgb, shade(rgb, 0.8), np.clip(0.5 - variation * 2.4, 0, 1) * 0.35)
    rgb = _fair_weave(rgb, local[:, 0] * 0.7 + local[:, 1], local[:, 2] + local[:, 0] * 0.7, pitch=0.035, depth=0.06)
    end = smoothstep(0.75, 0.9, np.abs(context.normal[:, 0]))
    rho = np.hypot(local[:, 1], local[:, 2])
    layers = np.abs(np.sin(rho / 0.045 * math.pi))
    rgb = mix(rgb, mix(shade(rgb, 0.65), rgb, smoothstep(0.0, 0.5, layers)), end)
    rgb = mix(rgb, solid(count, colour("MeadowFairTimberDark")), end * (1 - smoothstep(0.08, 0.1, rho)))
    if stripes is not None:
        for centre in stripes:
            band = 1 - smoothstep(0.04, 0.06, np.abs(np.abs(local[:, 0]) - centre))
            rgb = mix(rgb, solid(count, colour("MeadowFairCream")), band * (1 - end) * 0.85)
    return finish(rgb, context, ao_strength=0.75, edge_light=0.25)


def _garment_surface(context):
    """Studs round and down the piece for weave and folds: a loft's PaintCoord fraction times its girth, else the
    angle about the piece's own vertical axis."""
    local = context.local
    centre = local.mean(axis=0)
    angle = np.arctan2(local[:, 1] - centre[1], local[:, 0] - centre[0])
    coded = context.coord[:, 0] > -0.5
    around = np.where(coded, context.coord[:, 0] * 6.0, (angle + math.pi) / math.tau * 6.0)
    return around, local[:, 2]


def _tabby(around, height, pitch):
    # tabby: warp and weft crossings alternate, so the lit thread is a checker of short dashes
    warp = np.abs(np.sin(around * math.pi / pitch))
    weft = np.abs(np.sin(height * math.pi / pitch))
    over = (np.mod(np.floor(around / pitch) + np.floor(height / pitch), 2.0) < 0.5)
    return np.where(over, warp, weft)


def _hanging_folds(context, around, height, seed, depth):
    # cloth hangs from the shoulders and the belt: soft vertical folds stretched down the piece
    fold = fbm(np.stack([around * 0.9, height * 0.18, np.zeros_like(around)], axis=1), scale=1.6, octaves=3, seed=seed)
    return 1.0 - depth * smoothstep(-0.05, 0.35, -fold)


@brush("cloth.homespun", version=1, material="cloth", fixture="tunic", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowVillagers outfits)", summary="Dyed homespun wool, near-white for the TintMask dye: coarse tabby weave, mottled hand-dyed tone, soft hanging folds, dust toward the hem (grime_below); untinted options at alpha 0: trims [(bottom, top)] tablet-woven chevron bands, stripes (pitch, fraction) and checks (size) of undyed linen, lacing (z_top, z_bottom, half_width) a laced V over a linen shirt; patches and rolled cuffs stay dyed")
def homespun(context, seed=0.0, pitch=0.05, grime_below=None, folds=0.28, mottle=0.35, trims=(), stripes=None, checks=None,
             lacing=None, patches=(), rolled=None):
    """Dyed homespun wool, near-white for the TintMask dye: a coarse tabby weave, mottled hand-dyed tone, soft hanging
    folds, dust toward the hem. Options paint untinted detail at alpha 0:
      trims    [(bottom, top), ...] tablet-woven chevron bands between heights (object space z)
      stripes  (pitch, fraction) vertical stripes of undyed linen
      checks   (size) a check with undyed squares (the jester's hood lining, the goodwife's kerchief)
      lacing   (z_top, z_bottom, half_width) a laced V at the front centre over an undyed linen undershirt
      patches  [(centre (x, y, z), radius), ...] darker darned patches, still dyed
      rolled   (bottom, top) a rolled-up cuff between heights: deeper folds and a shadowed underside, still dyed"""
    count = context.count
    local = context.local
    around, height = _garment_surface(context)
    tone = fbm(local, scale=1.4, octaves=3, seed=301.0 + seed)
    rgb = mix(solid(count, colour("MeadowVillagerDyeBase")), solid(count, colour("MeadowVillagerDyeShade")), np.clip(0.4 - tone * 2.2, 0, 1) * mottle)
    rgb = shade(rgb, 0.93 + 0.1 * _tabby(around, height, pitch))
    rgb = shade(rgb, _hanging_folds(context, around, height, 305.0 + seed, folds))
    if rolled is not None:
        bottom, top = rolled
        across = np.clip((local[:, 2] - bottom) / (top - bottom), 0.0, 1.0)
        band = (local[:, 2] > bottom) & (local[:, 2] < top)
        # a roll of cloth: lit across its crown, shadowed where it tucks under at both edges
        crease = 0.78 + 0.3 * np.sin(across * math.pi) + 0.06 * np.sin(around * 9.0)
        rgb = np.where(band[:, None], shade(rgb, crease), rgb)
    for centre, radius in patches:
        distance = np.linalg.norm(local - np.asarray(centre), axis=1)
        inside = 1 - smoothstep(radius * 0.85, radius, distance)
        rgb = mix(rgb, shade(rgb, 0.8), inside)
    if grime_below is not None:
        dust = smoothstep(grime_below + 0.6, grime_below, local[:, 2]) * (0.6 + 0.4 * fbm(local, scale=4.0, octaves=2, seed=309.0 + seed))
        rgb = mix(rgb, solid(count, colour("MeadowVillagerDyeDeep")), np.clip(dust, 0, 1) * 0.45)
    alpha = np.ones(count)
    undyed = np.zeros(count)
    if stripes is not None:
        stripe_pitch, fraction = stripes
        undyed = np.maximum(undyed, (np.mod(around / stripe_pitch, 1.0) < fraction).astype(np.float64))
    if checks is not None:
        cell = np.floor(local / checks)
        undyed = np.maximum(undyed, (np.mod(cell[:, 0] + cell[:, 1] + cell[:, 2], 2.0) < 0.5).astype(np.float64))
    if undyed.any():
        linen_rgb = shade(solid(count, colour("MeadowVillagerLinen")), 0.93 + 0.1 * _tabby(around, height, pitch))
        rgb = mix(rgb, linen_rgb, undyed)
        alpha = alpha * (1 - undyed)
    if lacing is not None:
        top, bottom, half = lacing
        down = np.clip((top - local[:, 2]) / (top - bottom), 0.0, 1.0)
        opening = half * (1.0 - down)
        front = (local[:, 1] < -0.2) & (local[:, 2] < top + 0.02) & (local[:, 2] > bottom)
        inside = front & (np.abs(local[:, 0]) < opening)
        shirt = shade(solid(count, colour("MeadowVillagerLinen")), 0.8 + 0.2 * down)
        rgb = np.where(inside[:, None], shirt, rgb)
        alpha = np.where(inside, 0.0, alpha)
        # the lace zigzags across the V from eyelet to eyelet
        rungs = (np.mod((local[:, 2] - bottom) / 0.11, 1.0))
        zig = np.abs(np.abs(local[:, 0]) - opening * np.abs(1 - 2 * rungs))
        lace = front & (np.abs(local[:, 0]) < opening + 0.03) & (zig < 0.022)
        rgb = np.where(lace[:, None], solid(count, colour("MeadowVillagerLace")), rgb)
        alpha = np.where(lace, 0.0, alpha)
    for bottom, top in trims:
        band = (local[:, 2] > bottom) & (local[:, 2] < top)
        if not band.any():
            continue
        across = (local[:, 2] - bottom) / (top - bottom)
        chevron = np.abs(np.mod(around / 0.16, 1.0) - 0.5) * 2.0
        pattern = np.abs(across - 0.5) * 2.0
        umber = np.abs(chevron - pattern) < 0.28
        russet = (np.abs(chevron - pattern) > 0.55) & (pattern < 0.6)
        trim = solid(count, colour("MeadowVillagerTrimCream"))
        trim = np.where(umber[:, None], solid(count, colour("MeadowVillagerTrimUmber")), trim)
        trim = np.where(russet[:, None], solid(count, colour("MeadowVillagerTrimRusset")), trim)
        edge = (across < 0.12) | (across > 0.88)
        trim = np.where(edge[:, None], solid(count, colour("MeadowVillagerTrimUmber")), trim)
        rgb = np.where(band[:, None], trim, rgb)
        alpha = np.where(band, 0.0, alpha)
    return with_alpha(finish(rgb, context, ao_strength=0.85, edge_light=0.22, top_light=0.06, under_shadow=0.4), alpha)


@brush("cloth.linen", version=1, material="cloth", fixture="tunic", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowVillagers aprons, coifs, shirts, hose)", summary="Undyed linen (aprons, coifs, shirts): cream with a fine tabby weave, soft hanging folds, a few stains, optional dust (grime_below) and a stitched hem line at `hem` (z); `tone` names another ground colour; alpha 0, so a TintMask dye never reaches it")
def linen(context, seed=0.0, pitch=0.045, folds=0.22, stains=0.3, grime_below=None, hem=None, tone=None):
    """Undyed linen (aprons, coifs, shirts): cream with a fine weave, soft folds, a few stains, an optional stitched
    hem line at `hem` (z). `tone` names another ground colour (fixed wool hose). Alpha 0: the dye never reaches it."""
    count = context.count
    local = context.local
    around, height = _garment_surface(context)
    mottle = fbm(local, scale=1.8, octaves=3, seed=331.0 + seed)
    ground = solid(count, colour(tone or "MeadowVillagerLinen"))
    rgb = mix(ground, shade(ground, 0.8), np.clip(0.35 - mottle * 2.0, 0, 1) * 0.55)
    rgb = shade(rgb, 0.94 + 0.08 * _tabby(around, height, pitch))
    rgb = shade(rgb, _hanging_folds(context, around, height, 335.0 + seed, folds))
    stain = smoothstep(0.34, 0.44, fbm(local, scale=3.4, octaves=3, seed=339.0 + seed))
    rgb = mix(rgb, shade(rgb * np.array((1.0, 0.94, 0.84)), 0.82), stain * stains)
    if grime_below is not None:
        dust = smoothstep(grime_below + 0.5, grime_below, local[:, 2])
        rgb = mix(rgb, solid(count, colour("MeadowVillagerLinenShade")), dust * 0.5)
    if hem is not None:
        line = np.abs(local[:, 2] - hem) < 0.014
        dashes = np.mod(around / 0.07, 1.0) < 0.55
        rgb = np.where((line & dashes)[:, None], solid(count, colour("MeadowVillagerLinenStitch")), rgb)
    return with_alpha(finish(rgb, context, ao_strength=0.8, edge_light=0.25, top_light=0.08, under_shadow=0.35), 0.0)


@brush("cloth.motley", version=1, material="cloth", fixture="tunic", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowVillagers jester)", summary="Mi-parti motley: the half of the piece on `dyed_side` of object x = 0 (+1 or -1) is cloth.homespun (dyed), the other half fixed cream at alpha 0, split down a stitched seam; 0 dyes all of it, 2 none; `bells` are brass bell centres painted on, untinted")
def motley(context, dyed_side=1.0, seed=0.0, pitch=0.05, dags=None, bells=()):
    """The jester's mi-parti: the half of the piece on `dyed_side` of object x = 0 (+1 or -1) is dyed homespun, the
    other half fixed cream motley, split down a stitched seam; 0 dyes all of it and 2 none (a whole arm or leg on one
    side). `bells` are brass bell centres (x, y, z) painted on, untinted. (dags is accepted and unused.)"""
    count = context.count
    local = context.local
    dyed = homespun(context, seed=seed, pitch=pitch, folds=0.22, mottle=0.25)
    around, height = _garment_surface(context)
    cream = mix(solid(count, colour("MeadowVillagerMotley")), solid(count, colour("MeadowVillagerMotleyShade")), np.clip(0.4 - fbm(local, scale=1.4, octaves=3, seed=351.0 + seed) * 2.2, 0, 1) * 0.4)
    cream = shade(cream, 0.93 + 0.1 * _tabby(around, height, pitch))
    cream = with_alpha(finish(cream, context, ao_strength=0.85, edge_light=0.22, top_light=0.06, under_shadow=0.4), 0.0)
    if dyed_side == 0:
        side = np.ones(count, dtype=bool)
    elif abs(dyed_side) > 1:
        side = np.zeros(count, dtype=bool)
    else:
        side = local[:, 0] * dyed_side > 0
    rgba = np.where(side[:, None], dyed, cream)
    seam = np.abs(local[:, 0]) < 0.018 if abs(dyed_side) == 1 else np.zeros(count, dtype=bool)
    rgba = np.where(seam[:, None], with_alpha(finish(solid(count, colour("MeadowVillagerTrimUmber")), context, ao_strength=0.5, edge_light=0.1), 0.0), rgba)
    for centre in bells:
        distance = np.linalg.norm(local - np.asarray(centre), axis=1)
        bell = distance < 0.07
        lit = solid(count, colour("MeadowVillagerBell"))
        lit = mix(lit, solid(count, colour("MeadowVillagerBellLight")), smoothstep(0.03, 0.0, np.linalg.norm(local - (np.asarray(centre) + np.array((0.0, -0.02, 0.025))), axis=1)))
        rgba = np.where(bell[:, None], with_alpha(finish(lit, context, ao_strength=0.4, edge_light=0.3), 0.0), rgba)
    return rgba
