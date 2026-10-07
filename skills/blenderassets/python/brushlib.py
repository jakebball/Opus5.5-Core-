"""brushlib: painter recipes for paintlib atlases (the Joust Tycoon "Painted Toon" set, made generic).

A painter is called as painter(context) and returns (N, 3) RGB or (N, 4) RGBA (alpha = TintMask amount on a
tinted part). Bind options with use():

    import brushlib as pt
    atlas.add(shaft, pt.use(pt.wood, axis=1, grime=None))
    atlas.add(sash, pt.use(pt.sash_paint, along_samples=along, half_samples=halves), tint=True)

Colours come by name from PALETTE (sRGB hex). A project points them at its own palette once, before painting:
    pt.PALETTE.update(style.PALETTE)            # names a recipe uses must exist: see PALETTE below

finish() bakes the light into the paint at the end of every recipe. Two looks:
    soft painted (default): a gentle key light, warm top, cool underside, AO and warm convex edges;
    toon (pt.TOON = True): colour 30% more saturated, brightness posterised in 0.09 steps (poster=0.65; 0.3 suits
        broad animal coats), a hard cool shadow band underneath (70%, tinted 18% toward TOON_SHADOW) and a top
        highlight band, from a mostly top-down light (70% up, 30% front-left key) so the bands read from any heading.

Recipes (context first, options after; all colour names default to PALETTE entries):
    wood(axis, base, light, dark, grain, knots, grime, streaks)     grain streaks round an axis, knots, patches
    iron(base, light, dark, rust)                                   mottled metal, scratches, optional rust
    rivets(centres, radius)                                         iron with rivet heads at points
    leather(base, light, dark) / leather_stitched(rows, axis, dash) / saddle_leather(studs)
    team_paint(stripes, rim)                                        near-white cloth for TintMask team colour
    quilt(phase, along, ...) / band_quilt(pitch, origin)            quilting from position
    quilt_coord(scale, pitch, rows, row_offset, dirt_floor, seed)   quilting from PaintCoord: seams exactly in
                                                                    shapelib.quilt_puffs / roll_ring / channel_dome grooves
    sash_paint(along_samples, half_samples, lozenge_step)           embroidered band for shapelib.cloth_band: twill,
                                                                    gold borders and lozenges (gold untinted)
    tail_paint(length, notch, half_top, half_end)                   embroidered swallowtail for shapelib.hanging_tail
    knot_paint                                                      gathered cloth creases (shapelib.gathered_knot)
    placket_paint(half) / patch_paint(cloth, half, length) / binding_paint(centre, pitch)
    belt_paint(rows, studs, count_around, perimeter)                stitched strap with brass studs (ring_loft)
    coat(flow, legs, belly, base, light, dark) / hair(flow)         animal coat and hair strokes
"""

import math

import numpy as np

import paintlib as paint
from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid


PALETTE = {
    "Ash": "B97F45",
    "AshLight": "DDA868",
    "AshDark": "7E4C26",
    "AshGrain": "573117",
    "Iron": "4D525D",
    "IronLight": "A3ACBA",
    "IronDark": "1F2228",
    "Rust": "8A4F2E",
    "Rope": "C9A060",
    "RopeDark": "7A5527",
    "Leather": "7E4321",
    "LeatherLight": "B06B3A",
    "LeatherDark": "3F200F",
    "Linen": "E9D7B0",
    "LinenShade": "B89C70",
    "LinenStitch": "6F5638",
    "Wool": "5F78AE",
    "WoolDark": "3C4F7E",
    "Bay": "9C4E22",
    "BayLight": "C27236",
    "BayDark": "5A2A12",
    "Points": "2A1A12",
    "Muzzle": "5C3828",
    "Blaze": "F2EADB",
    "Feather": "E9DCC4",
    "Hoof": "3A302B",
    "HoofLight": "6B5B50",
    "Eye": "1A1210",
    "TeamBase": "F0F0F0",
    "TeamShade": "A9A9B6",
    "Brass": "C9932E",
    "BrassLight": "F6D47A",
    "Gold": "D8A23E",
    "GoldLight": "FFE28C",
    "GoldDark": "7E5016",
    "Binding": "5B2F17",
    "BindingLight": "8C5330",
    "PatchRed": "A4553F",
    "PatchOlive": "7C7F4C",
}

WARM = "FFE7B8"
COOL = "3C3157"
TOON = False
TOON_SHADOW = "5B4A8C"


def use(painter, **options):
    """Bind options to a recipe: atlas.add(obj, use(wood, axis=1))."""
    if not options:
        return painter
    return lambda context: painter(context, **options)



def colour(name):
    return PALETTE[name]


def posterize(value, levels=7):
    return np.round(value * levels) / levels


def saturate(rgb, amount):
    grey = (rgb @ np.array((0.299, 0.587, 0.114)))[:, None]
    return np.clip(grey + (rgb - grey) * amount, 0.0, 1.0)


def posterize_luma(rgb, step=0.09, softness=0.16, amount=0.65):
    luma = np.maximum(rgb @ np.array((0.299, 0.587, 0.114)), 1e-4)
    scaled = luma / step
    floor = np.floor(scaled)
    stepped = (floor + smoothstep(0.5 - softness, 0.5 + softness, scaled - floor)) * step
    return mix(rgb, np.clip(rgb * (stepped / luma)[:, None], 0.0, 1.0), amount)


def toon_finish(rgb, context, ao_strength, edge_light, poster=0.65):
    # Same light rule as toon.cel (mostly top-down, so the baked shadow reads from any heading),
    # painted over A's texture: posterised paint, a hard cool shadow band and a top highlight band.
    count = context.count
    key = np.array((-0.35, -0.45, 0.82))
    key /= np.linalg.norm(key)
    light = 0.7 * context.normal[:, 2] + 0.3 * (context.normal @ key)
    rgb = posterize_luma(saturate(rgb, 1.3), amount=poster)
    shadow = mix(shade(rgb, 0.7), shade(solid(count, TOON_SHADOW), 0.7), 0.18)
    lit = mix(shadow, rgb, smoothstep(-0.15, -0.09, light))
    lit = mix(lit, np.clip(rgb * 1.12 + 0.04, 0.0, 1.0), smoothstep(0.75, 0.81, light))
    occlusion = smoothstep(0.38, 0.62, np.clip(context.ao, 0.0, 1.0))
    lit = mix(mix(lit, shadow, ao_strength), lit, occlusion)
    return lift(lit, smoothstep(0.1, 0.18, context.edge) * edge_light * 1.2, toward=WARM)


def finish(rgb, context, ao_strength=0.6, light=1.0, edge_light=0.35, top_light=0.22, under_shadow=0.32, poster=0.65):
    if TOON:
        return toon_finish(rgb, context, ao_strength, edge_light, poster)
    count = context.count
    up = context.normal[:, 2]
    key = painted_light(context.normal, strength=0.18 * light, floor=0.9)
    lit = shade(rgb, key)
    lit = mix(lit, np.tile(hex_rgb(WARM), (count, 1)), smoothstep(0.35, 0.95, up) * top_light)
    lit = mix(lit, shade(lit, 0.62), smoothstep(-0.15, -0.85, up) * under_shadow)
    lit = mix(lit, np.tile(hex_rgb(COOL), (count, 1)), smoothstep(-0.2, -0.9, up) * under_shadow * 0.25)
    occlusion = np.clip(context.ao, 0.0, 1.0) ** 1.5
    lit = mix(shade(lit, 0.5), lit, occlusion + (1 - ao_strength) * (1 - occlusion))
    lit = mix(lit, np.tile(hex_rgb(COOL), (count, 1)), (1 - occlusion) * 0.16 * ao_strength)
    convex = smoothstep(0.05, 0.24, context.edge)
    return lift(lit, convex * edge_light, toward=WARM)


def wood(context, axis=2, base="Ash", light="AshLight", dark="AshDark", grain="AshGrain", knots=True, grime=None, streaks=7.0):
    local = context.local
    stretch = [4.0, 4.0, 4.0]
    stretch[axis] = 0.25
    patches = fbm(local, scale=0.7, octaves=2, stretch=[1.0 if index != axis else 0.35 for index in range(3)], seed=2.0)
    rgb = ramp(posterize(np.clip(0.5 + patches * 1.7, 0, 1), 5), [(0.0, colour(dark)), (0.5, colour(base)), (1.0, colour(light))])
    around = np.arctan2(local[:, (axis + 2) % 3], local[:, (axis + 1) % 3])
    wobble = fbm(local, scale=0.9, octaves=3, stretch=[0.35 if index == axis else 1.2 for index in range(3)], seed=1.0)
    phase = around * streaks + wobble * 5.0
    lines = 1 - smoothstep(0.04, 0.2, np.abs(np.sin(phase)))
    fade = smoothstep(-0.25, 0.2, fbm(local, scale=1.1, octaves=2, stretch=[0.3 if index == axis else 1.0 for index in range(3)], seed=3.0))
    rgb = mix(rgb, solid(context.count, colour(grain)), lines * (0.25 + 0.5 * fade))
    fine = 1 - smoothstep(0.02, 0.1, np.abs(np.sin(phase * 3.0 + 1.3)))
    rgb = mix(rgb, solid(context.count, colour(grain)), fine * 0.12)
    if knots:
        knot = smoothstep(0.36, 0.44, fbm(local, scale=2.0, octaves=1, stretch=stretch, seed=9.0))
        ring = smoothstep(0.3, 0.36, fbm(local, scale=2.0, octaves=1, stretch=stretch, seed=9.0)) - knot
        rgb = mix(rgb, solid(context.count, colour(grain)), knot * 0.8 + np.clip(ring, 0, 1) * 0.35)
    if grime is not None:
        rgb = mix(rgb, shade(rgb, 0.55), grime)
    return finish(rgb, context, edge_light=0.22)


def iron(context, base="Iron", light="IronLight", dark="IronDark", rust=True):
    count = context.count
    rgb = solid(count, colour(base))
    variation = fbm(context.pos, scale=2.5, octaves=3, seed=4.0)
    rgb = mix(rgb, solid(count, colour(dark)), np.clip(-variation * 2.4, 0, 1) * 0.55)
    band = smoothstep(0.55, 0.85, context.normal[:, 2]) * (1 - smoothstep(0.96, 1.0, context.normal[:, 2]))
    rgb = mix(rgb, solid(count, colour(light)), band * 0.4)
    scratches = fbm(context.pos, scale=7.0, octaves=2, stretch=(1.0, 7.0, 1.0), seed=6.0)
    rgb = mix(rgb, solid(count, colour(light)), smoothstep(0.42, 0.46, scratches) * 0.35)
    if rust:
        rust_field = fbm(context.pos, scale=3.4, octaves=3, seed=11.0)
        rgb = mix(rgb, solid(count, colour("Rust")), smoothstep(0.24, 0.36, rust_field) * 0.65)
    return finish(rgb, context, ao_strength=0.8, light=1.5, edge_light=0.55, top_light=0.08)


def leather(context, base="Leather", light="LeatherLight", dark="LeatherDark"):
    variation = fbm(context.pos, scale=1.6, octaves=3, seed=21.0)
    rgb = ramp(np.clip(0.55 + variation * 0.7, 0, 1), [(0.0, colour(dark)), (0.55, colour(base)), (1.0, colour(light))])
    scuffs = fbm(context.pos, scale=12.0, octaves=2, seed=23.0)
    rgb = mix(rgb, solid(context.count, colour(light)), smoothstep(0.3, 0.38, scuffs) * 0.55)
    return finish(rgb, context, edge_light=0.55)


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


def stitch_lines(phase, along, width=0.1, dash=0.075, gap=0.5):
    distance = np.abs(phase - np.round(phase))
    groove = 1 - smoothstep(width * 0.5, width, distance)
    dashes = (np.mod(along / dash, 1.0) < gap).astype(np.float64)
    thread = groove * dashes * (1 - smoothstep(0.0, width * 0.45, distance))
    return groove, thread


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


def band_quilt(context, pitch=0.33, origin=2.45):
    pos = context.pos
    phase = (pos[:, 2] - origin) / pitch
    around = np.arctan2(pos[:, 1], pos[:, 0] - np.sign(pos[:, 0]) * 1.5) * 0.6
    return quilt(context, phase, around, dirt_floor=None)


def leather_stitched(context, rows=(), axis=2, dash=0.06, base="Leather", light="LeatherLight", dark="LeatherDark"):
    rgb = leather(context, base=base, light=light, dark=dark)
    for height in rows:
        distance = np.abs(context.pos[:, axis] - height)
        line = 1 - smoothstep(0.012, 0.022, distance)
        along = np.arctan2(context.pos[:, 1], context.pos[:, 0]) * 1.2 if axis == 2 else context.pos[:, 2]
        dashes = (np.mod(along / dash, 1.0) < 0.55).astype(np.float64)
        rgb = mix(rgb, solid(context.count, colour("Rope")), line * dashes * 0.85)
    return rgb


def rivets(context, centres, radius=0.035):
    rgb = iron(context, rust=False)
    distance = paint.dots(context.pos, centres, radius)
    head = 1 - smoothstep(0.85, 1.0, distance)
    spot = 1 - smoothstep(0.0, 0.45, paint.dots(context.pos, [np.asarray(centre) + np.array((0.0, -0.01, 0.012)) for centre in centres], radius))
    rgb = mix(rgb, solid(context.count, colour("IronDark")), head * 0.6)
    return mix(rgb, solid(context.count, colour("IronLight")), spot * 0.9)


def _dashes(distance, run, dash=0.065, duty=0.55):
    return (np.mod(run / dash, 1.0) < duty).astype(np.float64) * (1 - smoothstep(0.0, 0.011, distance))


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


def binding_paint(context, centre, pitch):
    rgb = leather(context, base="Binding", light="BindingLight", dark="LeatherDark")
    distance = np.abs(context.coord[:, 1] - centre)
    return mix(rgb, finish(solid(context.count, colour("Rope")), context, ao_strength=0.4), _dashes(distance, context.coord[:, 0] * pitch, dash=0.05))


def belt_paint(context, rows, studs, count_around, perimeter):
    rgb = leather_stitched(context, rows=rows)
    u = context.coord[:, 0] * count_around
    offset = (u - np.floor(u) - 0.5) * perimeter / count_around
    distance = np.sqrt(offset ** 2 + (context.coord[:, 1] - studs) ** 2) / 0.034
    head = 1 - smoothstep(0.82, 1.0, distance)
    rgb = mix(rgb, finish(solid(context.count, colour("Brass")), context, ao_strength=0.3, edge_light=0.2), head)
    shine = np.sqrt((offset + 0.01) ** 2 + (context.coord[:, 1] - studs - 0.01) ** 2) / 0.034
    return mix(rgb, solid(context.count, colour("BrassLight")), (1 - smoothstep(0.1, 0.45, shine)) * 0.9)


def _gold(across, along, count):
    threads = np.abs(np.sin(along * math.tau / 0.018 + across * 40.0))
    return mix(solid(count, colour("Gold")), solid(count, colour("GoldLight")), threads * 0.55)


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


def knot_paint(context):
    count = context.count
    rgb = solid(count, colour("TeamBase"))
    variation = fbm(context.pos, scale=3.0, octaves=3, seed=45.0)
    rgb = mix(rgb, solid(count, colour("TeamShade")), np.clip(0.5 - variation * 2.4, 0, 1) * 0.35)
    # pointiness sits near 0.5 on smooth cloth and drops in the gathered creases
    crease = smoothstep(0.49, 0.42, context.curvature)
    rgb = mix(rgb, shade(solid(count, colour("TeamShade")), 0.75), crease * 0.6)
    return finish(rgb, context, ao_strength=0.9, edge_light=0.25, top_light=0.06, under_shadow=0.4)


def _streaks(pos, flow, scale=1.0, along=0.35, across=7.0, seed=0.0, octaves=3):
    flow = np.asarray(flow, dtype=np.float64)
    flow /= np.linalg.norm(flow)
    helper = np.array((1.0, 0.0, 0.0)) if abs(flow[0]) < 0.9 else np.array((0.0, 0.0, 1.0))
    first = np.cross(flow, helper)
    first /= np.linalg.norm(first)
    second = np.cross(flow, first)
    coords = np.stack([pos @ flow * along, pos @ first * across, pos @ second * across], axis=1)
    return fbm(coords, scale=scale, octaves=octaves, seed=seed)


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


def hair(context, flow=(0.0, 0.0, -1.0), base="Points", light="BayDark"):
    count = context.count
    strands = _streaks(context.pos, flow, scale=1.6, along=0.25, across=11.0, seed=71.0)
    rgb = mix(solid(count, colour(base)), solid(count, colour(light)), smoothstep(-0.1, 0.4, strands) * 0.75)
    sheen = smoothstep(0.3, 0.9, context.normal[:, 2])
    rgb = mix(rgb, lift(rgb, 0.4, toward="C99A6B"), sheen * 0.35)
    return finish(rgb, context, ao_strength=0.85, edge_light=0.1, top_light=0.12)


def saddle_leather(context, studs=()):
    rgb = leather(context, base="Leather", light="LeatherLight", dark="LeatherDark")
    if studs:
        distance = paint.dots(context.pos, studs, 0.045)
        rgb = mix(rgb, solid(context.count, colour("Brass")), (1 - smoothstep(0.8, 1.0, distance)))
        rgb = mix(rgb, solid(context.count, colour("BrassLight")), (1 - smoothstep(0.0, 0.5, distance)) * 0.8)
    return rgb
