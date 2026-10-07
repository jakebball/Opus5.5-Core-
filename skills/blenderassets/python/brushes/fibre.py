"""brushes.fibre: plant-fibre brushes: loose hay and straw, packed bales, ricks and sheaves, burlap sacking, rope,
wicker and plaited straw. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md. `rotation`
options take the object's world rotation matrix (3x3) so a painter can read normals in the object's own frame."""

import math

import numpy as np

from paintlib import fbm, lift, mix, ramp, shade, smoothstep, solid

from .core import _streaks, colour, finish, posterize
from .registry import brush
from .surface import _fraction, _local_normal, tiled_fbm
from .wrap import with_alpha

SOURCE = "Joust Tycoon castle (Rebirth 0), 2026-10-05 (courtyard dressing: supply pile, hay cart, trough)"


def _hay_rgb(context, flow, cross, strands, seed, base="CastleHay", light="CastleHayLight", dark="CastleHayDark",
             gap="CastleHayGap", green="CastleHayGreen"):
    count = context.count
    pos = context.local
    pick = smoothstep(-0.1, 0.1, fbm(pos, scale=0.7, octaves=2, seed=seed + 3.0))
    first = _streaks(pos, flow, scale=1.0, along=0.1, across=strands, seed=seed + 1.0, octaves=3)
    second = _streaks(pos, cross, scale=1.0, along=0.1, across=strands, seed=seed + 2.0, octaves=3)
    field = first * (1 - pick) + second * pick
    fine = _streaks(pos, flow, scale=1.0, along=0.1, across=strands * 2.2, seed=seed + 4.0, octaves=1) * (1 - pick) + _streaks(pos, cross, scale=1.0, along=0.1, across=strands * 2.2, seed=seed + 5.0, octaves=1) * pick
    tone = np.clip(0.55 + field * 1.6 + fine * 1.4, 0, 1)
    rgb = ramp(posterize(tone, 4), [(0.0, colour(dark)), (0.42, colour(base)), (0.78, colour(light)), (1.0, colour(light))])
    wave = np.abs(np.sin((field + fine * 0.5) * 55.0))
    rgb = mix(rgb, solid(count, colour(gap)), (1 - smoothstep(0.0, 0.18, wave)) * 0.65)
    rgb = lift(rgb, smoothstep(0.9, 0.98, np.abs(np.sin((field + fine * 0.5) * 55.0 + 1.4))) * 0.45, toward=colour(light))
    rgb = mix(rgb, solid(count, colour(green)), smoothstep(0.22, 0.42, fbm(pos, scale=0.9, octaves=2, seed=seed + 7.0)) * 0.35)
    return rgb


@brush("fibre.hay", version=1, material="straw", fixture="heap", tint=False, styles=("painted-toon",), source=SOURCE, summary="Loose hay or straw: tangled strands in two directions (flow, cross; object space), posterised gold, dark gaps between strands, greener patches")
def hay(context, flow=(1.0, 0.25, 0.1), cross=(0.2, 1.0, 0.6), strands=13.0, seed=0.0):
    """Loose hay or straw: tangled strands in two directions, posterised gold, dark gaps between strands."""
    rgb = _hay_rgb(context, flow, cross, strands, seed)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("fibre.hay_bale", version=1, material="straw", fixture="box", tint=False, styles=("painted-toon",), source=SOURCE, summary="A packed bale: strands along object `axis`, stubbly cut ends, twine bands at `bands` (object-space positions along the axis)")
def hay_bale(context, rotation=None, axis=0, bands=(-0.45, 0.45), twine=0.055, seed=0.0):
    """A packed bale: strands along `axis` (object space), stubbly cut ends, two twine bands at `bands`."""
    count = context.count
    normal = _local_normal(context, rotation)
    flow = [0.0, 0.0, 0.0]
    flow[axis] = 1.0
    cross = list(flow)
    cross[(axis + 1) % 3] = 0.35
    rgb = _hay_rgb(context, flow, cross, 14.0, seed)
    end = smoothstep(0.6, 0.8, np.abs(normal[:, axis]))
    stubble = posterize(np.clip(0.5 + fbm(context.local, scale=7.0, octaves=2, seed=seed + 11.0) * 2.2, 0, 1), 3)
    stub_rgb = ramp(stubble, [(0.0, colour("CastleHayDark")), (0.5, colour("CastleHay")), (1.0, colour("CastleHayLight"))])
    stub_rgb = mix(stub_rgb, solid(count, colour("CastleHayGap")), (1 - smoothstep(0.0, 0.25, np.abs(np.sin(fbm(context.local, scale=9.0, octaves=1, seed=seed + 13.0) * 30.0)))) * 0.5)
    rgb = mix(rgb, stub_rgb, end)
    along = context.local[:, axis]
    near = np.full(count, np.inf)
    for band in bands:
        near = np.minimum(near, np.abs(along - band))
    cord = (1 - smoothstep(twine * 0.7, twine, near)) * (1 - end * 0.6)
    twist = np.abs(np.sin((context.local[:, (axis + 1) % 3] + context.local[:, (axis + 2) % 3]) * 30.0 + along * 20.0))
    cord_rgb = mix(solid(count, colour("CastleRopeDark")), solid(count, colour("CastleRope")), twist)
    rgb = mix(rgb, cord_rgb, cord)
    rgb = shade(rgb, 1 - (1 - smoothstep(twine, twine * 2.2, near)) * 0.25 * (1 - cord))
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("fibre.burlap", version=1, material="cloth", fixture="dome", tint=False, styles=("painted-toon",), source=SOURCE, summary="Coarse burlap sacking: open basket weave (pitch) with dark holes, slubs, stains, dusty tops; seam=(axis, value) adds a stitched seam in object space")
def burlap(context, rotation=None, pitch=0.12, seam=None, stencil=None):
    """Coarse burlap sacking: an open basket weave with dark holes, slubs, dusty tops and stains.
    seam: (axis, value) draws a stitched seam line in object space. (stencil is accepted and unused.)"""
    count = context.count
    local = context.local
    normal = np.abs(_local_normal(context, rotation))
    dominant = np.argmax(normal, axis=1)
    u = np.where(dominant == 0, local[:, 1], local[:, 0])
    v = np.where(dominant == 2, local[:, 1], local[:, 2])
    a, b = u / pitch, v / pitch
    over = np.mod(np.floor(a) + np.floor(b), 2.0)
    thread = np.where(over > 0.5, np.sin(np.pi * _fraction(b)), np.sin(np.pi * _fraction(a)))
    hole = (1 - smoothstep(0.06, 0.16, np.minimum(_fraction(a), 1 - _fraction(a)))) * (1 - smoothstep(0.06, 0.16, np.minimum(_fraction(b), 1 - _fraction(b))))
    variation = fbm(local, scale=1.1, octaves=3, seed=71.0)
    rgb = ramp(posterize(np.clip(0.55 + variation * 1.6, 0, 1), 4), [(0.0, colour("CastleBurlapDark")), (0.5, colour("CastleBurlap")), (1.0, colour("CastleBurlapLight"))])
    rgb = shade(rgb, 0.84 + thread * 0.22)
    rgb = mix(rgb, solid(count, colour("CastleBurlapWeave")), hole * 0.75)
    slub = smoothstep(0.3, 0.42, _streaks(local, (1.0, 0.0, 0.0), along=0.3, across=12.0, seed=73.0, octaves=1))
    rgb = lift(rgb, slub * 0.18, toward=colour("CastleBurlapLight"))
    stain = smoothstep(0.18, 0.36, fbm(local, scale=0.8, octaves=3, seed=77.0))
    rgb = mix(rgb, shade(rgb, 0.72), stain * 0.5)
    dust = smoothstep(0.55, 0.9, context.normal[:, 2]) * smoothstep(-0.1, 0.3, fbm(local, scale=2.0, octaves=2, seed=79.0))
    rgb = lift(rgb, dust * 0.25, toward=colour("CastleGrain"))
    if seam is not None:
        axis, value = seam
        distance = np.abs(local[:, axis] - value)
        line = 1 - smoothstep(0.03, 0.05, distance)
        stitch = line * (np.mod((local[:, (axis + 1) % 3] + local[:, (axis + 2) % 3]) / 0.09, 1.0) < 0.55)
        rgb = mix(rgb, shade(rgb, 0.7), line * 0.6)
        rgb = mix(rgb, solid(count, colour("CastleRopeLight")), stitch * 0.8)
    return finish(rgb, context, ao_strength=0.85, edge_light=0.25)


def _rope_rgb(count, phase, groove):
    strand = np.abs(np.sin(np.pi * phase))
    rgb = ramp(posterize(strand, 3), [(0.0, colour("CastleRopeDark")), (0.55, colour("CastleRope")), (1.0, colour("CastleRopeLight"))])
    return mix(rgb, shade(solid(count, colour("CastleRopeDark")), 0.7), groove)


@brush("fibre.rope_coil", version=1, material="rope", fixture="coil", tint=False, styles=("painted-toon",), source=SOURCE, summary="A coil of rope modelled as one stretched torus round object Z: stacked loops `rope` thick from z = base, each laid with three-strand twist")
def rope_coil(context, base=0.0, rope=0.24, major=0.8, pitch=0.2):
    """A coil of rope built as one stretched torus round object Z: stacked loops `rope` thick from z = base,
    each laid with three-strand twist."""
    count = context.count
    local = context.local
    arc = np.arctan2(local[:, 1], local[:, 0]) * major
    loop = (local[:, 2] - base) / rope
    within = _fraction(loop)
    radial = np.hypot(local[:, 0], local[:, 1]) - major
    phase = (arc + within * rope * 1.6 + radial * 0.8) / pitch
    groove = 1 - smoothstep(0.04, 0.14, np.minimum(within, 1 - within))
    rgb = _rope_rgb(count, phase, groove * 0.9)
    rgb = shade(rgb, 0.92 + 0.12 * fbm(local, scale=1.5, octaves=2, seed=83.0))
    return finish(rgb, context, ao_strength=0.85, edge_light=0.25)


@brush("fibre.rope", version=1, material="rope", fixture="cylinder", tint=False, styles=("painted-toon",), source=SOURCE, summary="A plain laid rope or cord whose length runs along object `axis` (twist pitch in studs)")
def rope(context, axis=2, pitch=0.16):
    """A plain rope or cord whose length runs along object `axis`."""
    local = context.local
    along = local[:, axis]
    around = np.arctan2(local[:, (axis + 2) % 3], local[:, (axis + 1) % 3])
    phase = along / pitch + around / math.pi * 1.5
    rgb = _rope_rgb(context.count, phase, 0.0)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.25)


# ---- Greenmeadow straw, rope and wickerwork (Joust Tycoon, approved 2026-10-05). Copied verbatim from the
# project's farmpaint.py, fairpaint.py and villagerpaint.py, so these paint exactly what the project's copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("fibre.rick", version=1, material="straw", fixture="rick", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowHay haystack; MeadowWindmill cap and shed roof)", summary="A round haystack about a vertical axis through `centre`: fresh gold hay in rough horizontal layers on the body, a weathered thatch cap above `eave` combed down the slope, measured round at `radius` with noise that repeats once round (no seam); eave far below the piece paints all thatch (a round thatched roof)")
def rick(context, centre=(0.0, 0.0), eave=3.75, radius=3.0, seed=5.0):
    """A round haystack (MeadowHay): on the body, fresh gold hay in rough horizontal layers with dark gaps between the
    strands; above `eave`, a weathered thatch cap combed down the slope. Strands are measured round the stack
    (angle x radius) and up it, with noise that repeats once round, so there is no seam."""
    count = context.count
    pos = context.pos
    around = np.arctan2(pos[:, 1] - centre[1], pos[:, 0] - centre[0]) * radius
    period = (math.tau * radius, 0.0, 0.0)
    z = pos[:, 2]
    layers = np.stack([around * 0.12, z, np.zeros(count)], axis=1)
    combed = np.stack([around, z * 0.1, np.zeros(count)], axis=1)
    wobble = tiled_fbm(np.stack([around, z, np.zeros(count)], axis=1), 0.6, 2, period, seed)
    body_field = tiled_fbm(layers + wobble[:, None] * 0.15, 9.0, 3, (period[0] * 0.12, 0.0, 0.0), seed + 1.0)
    body_tone = np.clip(0.55 + body_field * 1.7, 0, 1)
    body_rgb = ramp(posterize(body_tone, 4), [(0.0, colour("CastleHayDark")), (0.42, colour("CastleHay")), (0.8, colour("CastleHayLight")), (1.0, colour("CastleHayLight"))])
    body_wave = np.abs(np.sin(body_field * 40.0))
    body_rgb = mix(body_rgb, solid(count, colour("CastleHayGap")), (1 - smoothstep(0.0, 0.2, body_wave)) * 0.55)
    body_rgb = mix(body_rgb, solid(count, colour("CastleHayGreen")), smoothstep(0.2, 0.42, tiled_fbm(np.stack([around, z, np.zeros(count)], axis=1), 0.5, 2, period, seed + 3.0)) * 0.3)

    cap_field = tiled_fbm(combed + wobble[:, None] * 0.25, 7.0, 3, period, seed + 5.0)
    cap_tone = np.clip(0.55 + cap_field * 1.7, 0, 1)
    cap_rgb = ramp(posterize(cap_tone, 4), [(0.0, colour("MeadowFarmThatchDark")), (0.42, colour("MeadowFarmThatch")), (0.8, colour("MeadowFarmThatchLight")), (1.0, colour("MeadowFarmThatchLight"))])
    cap_wave = np.abs(np.sin(cap_field * 34.0))
    cap_rgb = mix(cap_rgb, solid(count, colour("MeadowFarmThatchGap")), (1 - smoothstep(0.0, 0.22, cap_wave)) * 0.6)
    weather = smoothstep(0.1, 0.4, tiled_fbm(np.stack([around, z, np.zeros(count)], axis=1), 0.4, 2, period, seed + 7.0))
    cap_rgb = mix(cap_rgb, solid(count, colour("MeadowFarmLichenDark")), weather * 0.25)

    cap = smoothstep(eave - 0.08, eave + 0.08, z)
    rgb = mix(body_rgb, cap_rgb, cap)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("fibre.sheaf", version=1, material="straw", fixture="sheaf", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowHay stook)", summary="One bound sheaf of cut wheat standing up world Z: straw strokes up its length, a twine binding at `waist`, a head of ripe ears above `ear_line`, cut stalk ends on the foot")
def sheaf(context, waist=1.2, ear_line=2.25, seed=0.0):
    """One bound sheaf of cut wheat standing upright-ish (world Z up its length): cut stalk ends on the foot, straw
    strokes up the sides, a twine binding round the waist, a head of ripe ears above `ear_line`."""
    count = context.count
    pos = context.pos
    z = pos[:, 2]
    strokes = _streaks(pos, (0.0, 0.0, 1.0), scale=1.0, along=0.15, across=14.0, seed=seed + 1.0, octaves=2)
    tone = np.clip(0.55 + strokes * 1.8, 0, 1)
    stalk = ramp(posterize(tone, 4), [(0.0, colour("MeadowStrawDark")), (0.45, colour("MeadowFarmWheatStem")), (0.75, colour("MeadowStraw")), (1.0, colour("MeadowFarmWheatEarLight"))])
    stalk = mix(stalk, solid(count, colour("MeadowFarmWheatGap")), (1 - smoothstep(0.0, 0.2, np.abs(np.sin(strokes * 40.0)))) * 0.45)
    heads = _streaks(pos, (0.2, 0.1, 1.0), scale=1.0, along=1.6, across=9.0, seed=seed + 3.0, octaves=2)
    head_tone = posterize(np.clip(0.5 + heads * 1.8, 0, 1), 3)
    head = ramp(head_tone, [(0.0, colour("MeadowStrawDark")), (0.5, colour("MeadowFarmWheatEar")), (1.0, colour("MeadowFarmWheatEarLight"))])
    head = mix(head, solid(count, colour("MeadowFarmWheatGap")), (1 - smoothstep(0.0, 0.25, np.abs(np.sin(heads * 30.0)))) * 0.55)
    rgb = mix(stalk, head, smoothstep(ear_line - 0.1, ear_line + 0.15, z))
    rgb = mix(rgb, solid(count, colour("CastleRopeDark")), smoothstep(0.1, 0.07, np.abs(z - waist)))
    foot = context.normal[:, 2] < -0.5
    rgb = np.where(foot[:, None], mix(solid(count, colour("MeadowFarmWheatStem")), solid(count, colour("MeadowFarmWheatGap")), 0.4), rgb)
    return finish(rgb, context, ao_strength=0.75, edge_light=0.25)


@brush("fibre.laid_rope", version=1, material="rope", fixture="cord", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowFairBunting lines, pavilion guys, cart and wagon ties)", summary="A laid rope on a tube's PaintCoord (fraction round, studs along): three-strand twist that stays on the rope however the line sags; tinted=True returns alpha 0 so it keeps its colour on a TintMask part")
def laid_rope(context, pitch=0.16, tinted=False):
    """A laid rope on fairkit.rope's PaintCoord (fraction round, studs along): three-strand twist that stays on the
    rope however the line sags. On a tinted part it is painted at alpha 0, so it keeps its own colour."""
    u, v = context.coord[:, 0], context.coord[:, 1]
    phase = v / pitch + u * 3.0
    rgb = _rope_rgb(context.count, phase, 0.0)
    lit = finish(rgb, context, ao_strength=0.5, edge_light=0.2)
    return with_alpha(lit, 0.0) if tinted else lit


@brush("fibre.wicker", version=1, material="wicker", fixture="basket", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowFairStall baskets)", summary="A woven basket round object Z from z = base to base + height: over-under weavers in rows `rows` tall stepping half a spoke a row (spokes round), dark gaps, a plaited rim band `rim` deep at the top")
def wicker(context, height, rows=0.16, spokes=18, rim=0.12, base=0.0):
    """A woven basket round object Z from z = base to base + height: over-under weavers in rows `rows` tall that
    step half a spoke each row, darker gaps between, a plaited rim band `rim` deep at the top."""
    count = context.count
    local = context.local
    z = local[:, 2] - base
    angle = np.arctan2(local[:, 1], local[:, 0])
    row = np.floor(z / rows)
    phase = angle / math.tau * spokes + row * 0.5
    cell = np.abs(np.mod(phase, 1.0) - 0.5) * 2
    swell = 1 - cell ** 2
    rgb = mix(solid(count, colour("MeadowFairWickerDark")), solid(count, colour("MeadowFairWicker")), smoothstep(0.0, 0.5, swell))
    rgb = mix(rgb, solid(count, colour("MeadowFairWickerLight")), smoothstep(0.75, 1.0, swell) * 0.6)
    gap = 1 - smoothstep(0.0, 0.08, np.minimum(np.mod(z / rows, 1.0), 1 - np.mod(z / rows, 1.0)))
    rgb = mix(rgb, solid(count, colour("MeadowFairWickerDark")), gap * 0.8)
    band = smoothstep(height - rim - 0.01, height - rim + 0.01, z)
    plait = np.abs(np.sin(angle * spokes * 1.5 + z * 18.0))
    rim_rgb = mix(solid(count, colour("MeadowFairWicker")), solid(count, colour("MeadowFairWickerLight")), plait)
    rgb = mix(rgb, rim_rgb, band)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.25)


@brush("fibre.plaited_straw", version=1, material="straw", fixture="hat", tint=True, styles=("painted-toon",), source=MEADOW + " (MeadowVillagers farmhand's hat)", summary="A hat sewn from a spiral of plaited straw round an axis through `centre` (object space): concentric plait rows (`pitch`) on crown and brim, each a herringbone of lit strands, dark gaps between rows; alpha 0, so it keeps its paint on a TintMask part")
def plaited_straw(context, centre=(0.0, 0.0), pitch=0.07, seed=0.0):
    """A hat sewn from a spiral of plaited straw: concentric plait rows round the hat's axis (on the crown and brim
    alike), each a herringbone of short lit strands, dark gaps between rows, a few broken strands. Alpha 0."""
    count = context.count
    local = context.local
    radius = np.hypot(local[:, 0] - centre[0], local[:, 1] - centre[1])
    angle = np.arctan2(local[:, 1] - centre[1], local[:, 0] - centre[0])
    steep = np.abs(context.normal[:, 2]) < 0.55
    row_coord = np.where(steep, local[:, 2] / pitch, radius / pitch)
    row = np.floor(row_coord)
    within = row_coord - row
    along = angle * np.maximum(radius, 0.15) / (pitch * 0.55)
    herring = np.abs(np.mod(along + np.where(np.mod(row, 2.0) < 0.5, within, -within), 1.0) - 0.5) * 2.0
    rgb = mix(solid(count, colour("MeadowVillagerStraw")), solid(count, colour("MeadowVillagerStrawLight")), smoothstep(0.55, 0.85, herring))
    rgb = mix(rgb, solid(count, colour("MeadowVillagerStrawDark")), smoothstep(0.35, 0.1, herring) * 0.7)
    gap = (within < 0.12) | (within > 0.92)
    rgb = np.where(gap[:, None], solid(count, colour("MeadowVillagerStrawGap")), rgb)
    sun = fbm(context.pos, scale=2.0, octaves=2, seed=371.0 + seed)
    rgb = shade(rgb, 0.92 + 0.16 * sun)
    return with_alpha(finish(rgb, context, ao_strength=0.8, edge_light=0.3, top_light=0.1), 0.0)
