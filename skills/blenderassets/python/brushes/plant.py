"""brushes.plant: grass, wildflowers, water plants, toadstools, crops and greenery. Each is painter(context,
**options) -> RGB; see brushes/README.md. A flower head, leaf or toadstool is its own piece, so `context.local` is
that piece's own frame; `rotation` options take the piece's rotation (3x3) so its underside is found in that frame."""

import math

import numpy as np

from paintlib import Context, fbm, lift, mix, ramp, shade, smoothstep, solid

from .core import colour, finish, posterize
from .registry import brush
from .surface import _hash, _local_normal, run_frame, tiled_fbm

SOURCE = "Joust Tycoon castle (Rebirth 0), 2026-10-05 (moat banks)"


@brush("plant.turf", version=1, material="grass", fixture="bank", tint=False, styles=("painted-toon",), source=SOURCE, summary="A grassy bank lip on tiling noise: posterised turf with light tufts and blade flecks on top, bare earth where it turns down steeply; period, swap/along as stone.ashlar_tiled")
def turf(context, period=(21.0, 0.0, 0.0), swap=False, along=0.0):
    """A grassy bank lip: posterised turf on top with lighter tufts and blade flecks, bare earth where it turns
    down steeply or sits in shadow. swap and along as for stone.ashlar_tiled."""
    count = context.count
    pos, _ = run_frame(context.pos, None, swap, along)
    patches = tiled_fbm(pos, 0.6, 3, period, 71.0)
    rgb = ramp(posterize(np.clip(0.5 + patches * 1.6, 0, 1), 3), [(0.0, colour("CastleGrassDark")), (0.5, colour("CastleGrass")), (1.0, colour("CastleGrassLight"))])
    blades = tiled_fbm(pos * np.array((1.0, 6.0, 1.0)), 2.2, 2, period, 73.0)
    rgb = mix(rgb, solid(count, colour("CastleGrassLight")), smoothstep(0.18, 0.3, blades) * 0.6)
    rgb = mix(rgb, solid(count, colour("CastleGrassDark")), smoothstep(-0.18, -0.3, blades) * 0.5)
    steep = smoothstep(0.75, 0.45, context.normal[:, 2])
    earth = mix(solid(count, colour("CastleEarth")), solid(count, colour("CastleEarthDark")), smoothstep(0.0, 0.3, tiled_fbm(pos, 2.0, 2, period, 79.0)))
    rgb = mix(rgb, earth, steep)
    return finish(rgb, context, ao_strength=0.6, edge_light=0.15)


@brush("plant.reed", version=1, material="plant", fixture="blades", tint=False, styles=("painted-toon",), source=SOURCE, summary="Reed blades: dark at the waterline (base_z) to a pale tip over `height`, with lengthwise streaks")
def reed(context, base_z, height):
    """Reed blades: dark at the waterline to a pale tip, with lengthwise streaks."""
    count = context.count
    rise = np.clip((context.pos[:, 2] - base_z) / height, 0, 1)
    rgb = ramp(rise, [(0.0, colour("CastleReedDark")), (0.35, colour("CastleReed")), (1.0, colour("CastleReedLight"))])
    streak = np.sin((context.local[:, 0] + context.local[:, 1]) * 60.0)
    rgb = shade(rgb, 0.94 + 0.08 * (streak > 0.4))
    return finish(rgb, context, ao_strength=0.4, edge_light=0.2)


@brush("plant.lily_pad", version=1, material="plant", fixture="pad", tint=False, styles=("painted-toon",), source=SOURCE, summary="A lily pad seen from above: green, lighter rim and radial veins from its object origin, dark underside")
def lily(context):
    """A lily pad seen from above: green with a lighter rim and radial veins from its centre (object space)."""
    count = context.count
    x, y = context.local[:, 0], context.local[:, 1]
    radius = np.hypot(x, y)
    angle = np.arctan2(y, x)
    rgb = mix(solid(count, colour("CastleLily")), solid(count, colour("CastleLilyLight")), smoothstep(0.3, 0.6, radius) * 0.5)
    veins = 1 - smoothstep(0.04, 0.12, np.abs(np.sin(angle * 5.5)))
    rgb = mix(rgb, solid(count, colour("CastleLilyLight")), veins * smoothstep(0.05, 0.15, radius) * 0.6)
    rgb = mix(rgb, solid(count, colour("CastleLilyDark")), smoothstep(-0.3, -0.7, context.normal[:, 2]))
    return finish(rgb, context, ao_strength=0.3, edge_light=0.25)


# ---- Greenmeadow ground cover, crops and greenery (Joust Tycoon, approved 2026-10-05). Copied verbatim from the
# project's coverpaint.py, farmpaint.py, fairpaint.py and hubpaint.py, so these paint exactly what the project's
# copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


def _two_sided(context, amount=0.75):
    """A copy of context whose downward normals are folded up by `amount`, so a petal's back takes the toon light
    as if lit through the petal instead of the full shadow band (a thin flower head is seen from below as often as
    from above)."""
    normal = context.normal.copy()
    down = normal[:, 2] < 0
    normal[down, 2] = -normal[down, 2] * amount
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-6)
    return Context(context.pos, normal, context.ao, context.curvature, context.edge, context.local, context.coord)


def _sky_lit(context, up=0.85):
    """A copy of context with its normals bent toward the sky, the way stylised grass is lit: a thin blade or stem
    takes the light as part of the sward instead of flipping to the shadow band on whichever side faces away from
    the key."""
    normal = context.normal * (1 - up) + np.array((0.0, 0.0, 1.0)) * up
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-6)
    return Context(context.pos, normal, context.ao, context.curvature, context.edge, context.local, context.coord)


@brush("plant.petals", version=1, material="flower", fixture="flower", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover wildflowers)", summary="A star-shaped flower head in its own frame (radius, petal_count; offset turns the petals): petals dark toward the eye and light at the tips, a vein down each petal, creases into the notches, an eye with a darker ring, green sepals and a paler back underneath; two-sided light; blush tints the tips")
def petals(context, base, light, dark, eye, eye_ring, radius, petal_count, eye_size=0.3, offset=0.0, rotation=None,
           sepal="MeadowFlowerSepal", vein=0.35, blush=None):
    """A flower head built by covershapes.star_head in its own frame: petals darker toward the eye and light at the
    tips, a vein stroke down each petal, a crease into each notch, the eye with a darker ring, green sepals and a
    darker petal back underneath."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    reach = np.hypot(local[:, 0], local[:, 1]) / radius
    angle = np.arctan2(local[:, 1], local[:, 0]) - offset
    rgb = ramp(np.clip(reach, 0, 1), [(0.0, colour(dark)), (eye_size + 0.08, colour(dark)), (0.52, colour(base)), (0.86, colour(light)), (1.0, colour(light))])
    if blush:
        rgb = mix(rgb, solid(count, colour(blush)), smoothstep(0.8, 1.0, reach) * 0.55)
    # petal centres sit half a petal past each notch: |cos(n/2 * angle)| is 0 on a centre line, 1 in a notch
    across = np.abs(np.cos(angle * petal_count / 2))
    rgb = mix(rgb, solid(count, colour(light)), (1 - smoothstep(0.03, 0.12, across)) * smoothstep(eye_size, 0.7, reach) * vein)
    rgb = mix(rgb, solid(count, colour(dark)), smoothstep(0.9, 0.99, across) * smoothstep(eye_size, 0.55, reach) * 0.6)
    eye_rgb = mix(solid(count, colour(eye)), solid(count, colour(eye_ring)), smoothstep(eye_size * 0.55, eye_size * 0.9, reach))
    speck = fbm(local * 22.0, scale=1.0, octaves=1, seed=3.0)
    eye_rgb = shade(eye_rgb, 0.92 + 0.16 * (speck > 0.15))
    rgb = mix(rgb, eye_rgb, 1 - smoothstep(eye_size * 0.92, eye_size * 1.05, reach))
    under = smoothstep(-0.05, -0.35, normal[:, 2])
    back = mix(mix(solid(count, colour(light)), solid(count, colour(base)), 0.6), solid(count, colour(sepal)), 1 - smoothstep(0.3, 0.5, reach))
    rgb = mix(rgb, back, under)
    return finish(rgb, _two_sided(context, 1.0), ao_strength=0.3, edge_light=0.25)


@brush("plant.clover_head", version=1, material="flower", fixture="dome", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover clover)", summary="A round head of florets (clover): posterised pink, paler floret tips, greener at the base underneath (rotation gives the piece's frame)")
def clover_head(context, rotation=None):
    """A clover's round head of florets: pink, paler at the tips of the florets, darker and greener at the base."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    florets = fbm(local * 9.0, scale=1.0, octaves=2, seed=11.0)
    rgb = ramp(posterize(np.clip(0.5 + florets * 1.8, 0, 1), 3), [(0.0, colour("MeadowFlowerCloverDark")), (0.5, colour("MeadowClover")), (1.0, colour("MeadowFlowerCloverLight"))])
    rgb = mix(rgb, solid(count, colour("MeadowFlowerSepal")), smoothstep(-0.45, -0.85, normal[:, 2]) * 0.8)
    return finish(rgb, context, ao_strength=0.4, edge_light=0.3)


@brush("plant.stem", version=1, material="plant", fixture="blades", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover flower stems)", summary="Flower stems: dark at the ground (base_z) to fresh green near the head (`top` studs up), a thin lengthwise streak, lit as part of the sward")
def stem(context, top, base_z=0.0, ao=0.5):
    """Flower stems: dark at the ground to fresh green near the head, with a thin lengthwise streak."""
    count = context.count
    rise = np.clip((context.pos[:, 2] - base_z) / top, 0, 1)
    rgb = ramp(rise, [(0.0, colour("MeadowLeafDark")), (0.3, colour("MeadowLeaf")), (1.0, colour("MeadowLeafLight"))])
    streak = np.sin((context.local[:, 0] - context.local[:, 1]) * 70.0)
    rgb = shade(rgb, 0.95 + 0.07 * (streak > 0.5))
    return finish(rgb, _sky_lit(context, 0.6), ao_strength=ao, edge_light=0.15)


@brush("plant.leaf", version=1, material="leaf", fixture="leaf", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover basal leaves)", summary="A lance leaf along its own +X from the origin (`length`): darker at the base, light toward the tip, a pale midrib and side veins, a darker underside")
def leaf(context, length, rotation=None):
    """A basal leaf built along its own +X (covershapes.leaf): darker at the base, light toward the tip, a pale
    midrib and side veins, a darker underside."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    along = np.clip(local[:, 0] / length, 0, 1)
    rgb = ramp(along, [(0.0, colour("MeadowLeafDark")), (0.35, colour("MeadowLeaf")), (0.9, colour("MeadowLeafLight"))])
    midrib = 1 - smoothstep(0.008, 0.02, np.abs(local[:, 1]))
    rgb = mix(rgb, solid(count, colour("MeadowGrassSun")), midrib * 0.55 * smoothstep(0.05, 0.2, along))
    veins = 1 - smoothstep(0.0, 0.18, np.abs(np.sin((local[:, 0] - np.abs(local[:, 1]) * 1.6) * 38.0)))
    rgb = mix(rgb, solid(count, colour("MeadowLeafLight")), veins * 0.25 * smoothstep(0.02, 0.04, np.abs(local[:, 1])))
    rgb = mix(rgb, solid(count, colour("MeadowLeafDeep")), smoothstep(-0.1, -0.5, normal[:, 2]) * 0.45)
    return finish(rgb, context, ao_strength=0.5, edge_light=0.2)


@brush("plant.clover_leaf", version=1, material="leaf", fixture="pad", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover clover)", summary="A three-lobed clover leaf in its own frame (radius): leaf green with the pale chevron band of white clover, darker underside")
def clover_leaf(context, radius, rotation=None):
    """A three-lobed clover leaf on its own frame: leaf green with the pale chevron band of white clover."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    reach = np.hypot(local[:, 0], local[:, 1]) / radius
    rgb = mix(solid(count, colour("MeadowLeafDark")), solid(count, colour("MeadowLeaf")), smoothstep(0.1, 0.35, reach))
    rgb = mix(rgb, solid(count, colour("MeadowLeafLight")), smoothstep(0.75, 0.95, reach) * 0.6)
    chevron = (1 - smoothstep(0.05, 0.11, np.abs(reach - 0.55))) * 0.7
    rgb = mix(rgb, solid(count, colour("MeadowFlowerChevron")), chevron)
    rgb = mix(rgb, solid(count, colour("MeadowLeafDeep")), smoothstep(-0.1, -0.5, normal[:, 2]) * 0.45)
    return finish(rgb, context, ao_strength=0.4, edge_light=0.2)


@brush("plant.grass_blades", version=1, material="grass", fixture="blades", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover tufts and reeds)", summary="Tall grass blades on a tuft's own frame (base at local z 0, `height` tall): cool dark root, grass green up the blade, a sunlit tip a step lighter than the terrain grass; lit as part of the sward")
def grass_blades(context, height, sun=1.0, seed=0.0):
    """Tall grass blades on a tuft's own frame (its base at local z 0): a cool dark root, grass green up the blade
    and a sunlit tip a step lighter than the terrain grass, so the tuft reads as a painted stroke above it."""
    count = context.count
    local = context.local
    rise = np.clip(local[:, 2] / height, 0, 1)
    rgb = ramp(rise, [(0.0, colour("MeadowGrassCool")), (0.14, colour("MeadowGrassDark")), (0.38, colour("MeadowGrass")), (0.68, colour("MeadowGrassLight")), (0.95, colour("MeadowGrassSun"))])
    streaks = fbm(np.stack([local[:, 0] * 14.0, local[:, 1] * 14.0, local[:, 2] * 1.2], axis=1), scale=1.0, octaves=2, seed=seed + 5.0)
    rgb = mix(rgb, solid(count, colour("MeadowGrassSun")), smoothstep(0.15, 0.3, streaks) * 0.35 * sun * smoothstep(0.3, 0.6, rise))
    rgb = mix(rgb, solid(count, colour("MeadowGrassDark")), smoothstep(-0.15, -0.3, streaks) * 0.3)
    return finish(rgb, _sky_lit(context, 0.7), ao_strength=0.55, edge_light=0.2)


@brush("plant.seed_head", version=1, material="grass", fixture="spindle", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover seeded tufts)", summary="A ripe grass seed head: straw with darker husk lines")
def seed_head(context):
    """A ripe grass seed head: straw with darker husk lines."""
    count = context.count
    lines = np.abs(np.sin(context.local[:, 2] * 55.0 + context.local[:, 0] * 20.0))
    rgb = mix(solid(count, colour("MeadowCoverSeed")), solid(count, colour("MeadowCoverSeedDark")), (lines > 0.75) * 0.6)
    return finish(rgb, context, ao_strength=0.4, edge_light=0.3)


@brush("plant.bulrush", version=1, material="plant", fixture="spindle", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover reeds)", summary="A bulrush head on its own frame (local z along it, `length`): velvet brown, a lighter top band, faint nap")
def bulrush(context, length):
    """A bulrush head on its own frame (local z along it): velvet brown, a lighter top band, faint rings."""
    count = context.count
    along = np.clip(context.local[:, 2] / length, 0, 1)
    rgb = ramp(along, [(0.0, colour("MeadowCoverBulrushDark")), (0.25, colour("MeadowCoverBulrush")), (0.85, colour("MeadowCoverBulrushLight")), (1.0, colour("MeadowCoverBulrush"))])
    nap = fbm(context.local * 30.0, scale=1.0, octaves=1, seed=7.0)
    rgb = shade(rgb, 0.93 + 0.12 * (nap > 0.1))
    return finish(rgb, context, ao_strength=0.4, edge_light=0.25)


@brush("plant.toadstool_cap", version=1, material="fungus", fixture="toadstool", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover toadstools and fairy ring)", summary="A toadstool cap in its own frame (radius): lighter crown, darker rim, pale spots at `spots` (points in the cap's frame, spot_size), cream gills underneath; fly agaric by default, base/light/dark recolour it")
def toadstool_cap(context, radius, spots, rotation=None, spot_size=0.075, base="MeadowCoverToadstool",
                  light="MeadowCoverToadstoolLight", dark="MeadowCoverToadstoolDark"):
    """A toadstool cap on its own frame (a fly agaric by default): lighter on the crown, darker at the rim, pale
    spots at `spots` (points in the cap's frame), cream gills underneath."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    reach = np.hypot(local[:, 0], local[:, 1]) / radius
    rgb = ramp(np.clip(reach, 0, 1), [(0.0, colour(light)), (0.45, colour(base)), (0.95, colour(dark))])
    if spots:
        nearest = np.full(count, np.inf)
        for centre in spots:
            nearest = np.minimum(nearest, np.linalg.norm(local - np.asarray(centre), axis=1))
        rgb = mix(rgb, solid(count, colour("MeadowCoverSpot")), 1 - smoothstep(spot_size * 0.8, spot_size, nearest))
    gills = np.abs(np.sin(np.arctan2(local[:, 1], local[:, 0]) * 18.0))
    gill_rgb = mix(solid(count, colour("MeadowCoverGill")), solid(count, colour("MeadowCoverGillDark")), (gills > 0.7) * 0.7)
    gill_rgb = mix(gill_rgb, solid(count, colour("MeadowCoverGillDark")), 1 - smoothstep(0.15, 0.35, reach))
    rgb = mix(rgb, gill_rgb, smoothstep(-0.2, -0.5, normal[:, 2]))
    return finish(rgb, context, ao_strength=0.5, edge_light=0.3)


@brush("plant.toadstool_stalk", version=1, material="fungus", fixture="spindle", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover toadstools)", summary="A toadstool stalk on its own frame (`height` up local z): cream, shaded at the foot with an earthy base")
def toadstool_stalk(context, height):
    """A toadstool stalk: cream, shaded at the foot and under the cap's skirt."""
    count = context.count
    rise = np.clip(context.local[:, 2] / height, 0, 1)
    rgb = mix(solid(count, colour("MeadowCoverStalkShade")), solid(count, colour("MeadowCoverStalk")), smoothstep(0.0, 0.35, rise))
    rgb = mix(rgb, solid(count, colour("MeadowEarth")), (1 - smoothstep(0.0, 0.12, rise)) * 0.5)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.2)


def _strokes(first, second, pitch, length, width, seed, wrap):
    """Short brush strokes, one per jittered cell of `pitch` (first, second), each `length` long and `width` wide,
    laid roughly along the second axis with a per-cell slant. Returns the stroke's coverage (1 on it) and its cell
    tone (0..1). wrap: cell counts per tile on each axis, so strokes and tones repeat with the tile."""
    raw_a = np.floor(first / pitch[0])
    raw_b = np.floor(second / pitch[1] + 0.5 * np.mod(raw_a, 2.0))
    cell_a = np.mod(raw_a, wrap[0])
    cell_b = np.mod(raw_b, wrap[1])
    centre_a = (raw_a + 0.2 + 0.6 * _hash(cell_a, cell_b, seed)) * pitch[0]
    centre_b = (raw_b - 0.5 * np.mod(raw_a, 2.0) + 0.25 + 0.5 * _hash(cell_b, cell_a, seed + 1.0)) * pitch[1]
    slant = (_hash(cell_a, cell_b, seed + 2.0) - 0.5) * 0.8
    da = first - centre_a
    db = second - centre_b
    across = da * np.cos(slant) - db * np.sin(slant)
    along = da * np.sin(slant) + db * np.cos(slant)
    taper = np.clip(1 - np.abs(along) / (length / 2), 0, 1)
    coverage = smoothstep(width * 0.5 * np.sqrt(taper) + 0.012, width * 0.5 * np.sqrt(taper) - 0.012, np.abs(across)) * (taper > 0)
    return coverage, _hash(cell_a, cell_b, seed + 3.0)


@brush("plant.wheat_field", version=1, material="crop", fixture="field", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowWheat tiles and edge fringe)", summary="Standing wheat that repeats every `period` studs in X and Y: on top, rows along X `row_pitch` apart of slanted ear-head strokes in three golds, dark troughs, broad diagonal wind bands; on walls (a cut edge or fringe), stalk strokes darkening from `crest` to a green-brown `foot` under a band of ears; occlusion painted from height, never baked, so tiles always match")
def wheat_field(context, period=16.0, foot=-0.4, crest=2.2, row_pitch=4.0 / 3.0):
    """Standing wheat (MeadowWheat): on top, rows along X `row_pitch` apart, each a crowd of slanted ear-head strokes
    in three golds over a straw ground, a dark trough between rows, and broad soft bands of light and shade rolling
    diagonally across the field like wind over the crop. On the walls (a field's cut edge, or the MeadowWheatEdge
    fringe), close stalk strokes darkening to a green-brown foot under a band of ears. Every pattern repeats every
    `period` studs in X and Y. Occlusion is painted from height, never baked, so an edge piece standing beside a
    tile never darkens it and every tile matches every other."""
    count = context.count
    pos, normal = context.pos, context.normal
    noise_period = (period, period, 0.0)
    noise = lambda scale, octaves, seed_value: tiled_fbm(pos, scale, octaves, noise_period, seed_value)
    x, y, z = pos[:, 0], pos[:, 1], pos[:, 2]
    top = normal[:, 2] > 0.45
    wall_u = np.where(np.abs(normal[:, 0]) > np.abs(normal[:, 1]), y, x)

    row_phase = np.mod((y + period / 2) / row_pitch, 1.0)
    trough = smoothstep(0.32, 0.0, np.minimum(row_phase, 1 - row_phase))
    ground = mix(solid(count, colour("MeadowStrawDark")), solid(count, colour("MeadowFarmWheatEar")), 0.45)
    top_rgb = ground
    # pitches divide the period exactly, so the strokes close on the tile edge
    for layer, (pitch, seed, tones) in enumerate((((0.32, 0.64), 11.0, ("MeadowFarmWheatEar", "MeadowStraw")),
                                                  ((0.25, 0.5), 23.0, ("MeadowStrawDark", "MeadowFarmWheatEar")),
                                                  ((0.4, 0.8), 37.0, ("MeadowStraw", "MeadowFarmWheatEarLight")))):
        wrap = (round(period / pitch[0]), round(period / pitch[1]))
        coverage, tone = _strokes(x, y, pitch, pitch[1] * 0.95, 0.11, seed, wrap)
        stroke_rgb = mix(solid(count, colour(tones[0])), solid(count, colour(tones[1])), posterize(tone, 2))
        top_rgb = mix(top_rgb, stroke_rgb, coverage)
    stalk_lines = 1 - smoothstep(0.0, 0.25, np.abs(np.sin((x + 0.06 * noise(1.3, 2, 3.0)) / 0.17 * math.pi)))
    top_rgb = mix(top_rgb, solid(count, colour("MeadowFarmWheatGap")), stalk_lines * trough * 0.5)
    top_rgb = mix(top_rgb, shade(top_rgb, 0.62), trough * 0.75)
    wind = np.sin(math.tau * (x / period + 2 * y / period) + 0.6) + 0.6 * np.sin(math.tau * (2 * x / period - y / period) + 2.1)
    wind = wind + 0.5 * noise(0.2, 2, 41.0)
    top_rgb = mix(top_rgb, shade(top_rgb, 0.84), smoothstep(-0.2, -1.1, wind) * 0.8)
    top_rgb = lift(top_rgb, smoothstep(0.3, 1.2, wind) * 0.16, toward=colour("MeadowFarmWheatEarLight"))
    patch = noise(0.19, 2, 3.0)
    top_rgb = mix(top_rgb, solid(count, colour("MeadowFarmWheatStem")), smoothstep(-0.15, -0.4, patch) * 0.25)
    top_rgb = shade(top_rgb, 0.85)

    rise = np.clip((z - foot) / (crest - foot), 0, 1)
    stalk_rgb = ramp(rise, [(0.0, colour("MeadowEarthDark")), (0.12, colour("MeadowFarmWheatFoot")), (0.4, colour("MeadowFarmWheatStem")), (0.72, colour("MeadowStrawDark")), (1.0, colour("MeadowStraw"))])
    phase = (wall_u + 0.05 * noise(1.1, 2, 5.0)) / 0.13
    stroke = np.abs(np.sin(phase * math.pi))
    tone = _hash(np.floor(phase), 3.0, 13.0)
    stalk_rgb = shade(stalk_rgb, 0.88 + tone * 0.22)
    stalk_rgb = mix(stalk_rgb, shade(stalk_rgb, 0.55), (1 - smoothstep(0.0, 0.4, stroke)) * (0.75 - rise * 0.35))
    stalk_rgb = lift(stalk_rgb, smoothstep(0.85, 1.0, stroke) * 0.22 * rise, toward=colour("MeadowStraw"))
    band = smoothstep(crest - 0.8, crest - 0.4, z + 0.18 * noise(1.4, 2, 7.0))
    side_coverage, side_tone = _strokes(wall_u, z, (0.2, 0.5), 0.45, 0.13, 29.0, (round(period / 0.2), 1000))
    head_rgb = mix(solid(count, colour("MeadowFarmWheatEar")), solid(count, colour("MeadowFarmWheatEarLight")), posterize(side_tone, 2))
    ear_ground = mix(solid(count, colour("MeadowStrawDark")), solid(count, colour("MeadowFarmWheatGap")), 0.3)
    wall_rgb = mix(stalk_rgb, mix(ear_ground, head_rgb, side_coverage), band)

    rgb = np.where(top[:, None], top_rgb, wall_rgb)
    top_ao = 1 - trough * 0.35
    wall_ao = 0.4 + 0.6 * smoothstep(foot + 0.2, crest - 0.3, z)
    ao = np.where(top, top_ao, wall_ao)
    lit = Context(pos, normal, ao, context.curvature, np.where(top, context.edge * 0.4, 0.0), context.local, context.coord)
    return finish(rgb, lit, ao_strength=0.7, edge_light=0.25)


@brush("plant.wheat_ear", version=1, material="crop", fixture="spindle", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowWheat ears)", summary="One modelled wheat ear (object Z along it, `length`): gold, darker toward the stalk, grain notches across it, a pale tip")
def wheat_ear(context, length=0.9):
    """One ripe ear (a farmshapes.bipyramid, object Z along it): gold, darker toward the stalk, with grain notches
    across it and a pale tip."""
    count = context.count
    along = np.clip(context.local[:, 2] / length, 0, 1)
    rgb = ramp(along, [(0.0, colour("MeadowStrawDark")), (0.45, colour("MeadowFarmWheatEar")), (0.85, colour("MeadowStraw")), (1.0, colour("MeadowFarmWheatEarLight"))])
    notches = np.abs(np.sin(along * 7.0 * math.pi))
    rgb = mix(rgb, shade(rgb, 0.8), (1 - smoothstep(0.0, 0.3, notches)) * 0.5)
    return finish(rgb, context, ao_strength=0.4, edge_light=0.3)


def _hex(value):
    return np.array([int(value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)])


@brush("plant.garland", version=1, material="greenery", fixture="cylinder", tint=False, styles=("painted-toon",), source=MEADOW + " (hub well wreaths)", summary="A festive garland of greenery: posterised leaf greens studded with poppy, buttercup, daisy and cornflower dots, wound with a cream ribbon round object `along_axis`")
def garland(context, along_axis=2, seed=0.0):
    """A festive garland of greenery: leaf greens in clumps, studded with poppy, buttercup, daisy and cornflower
    dots and wound with a cream ribbon."""
    count = context.count
    leaf = ramp(posterize(np.clip(0.5 + fbm(context.pos, scale=4.0, octaves=2, seed=seed + 71.0) * 1.8, 0, 1), 3), [(0.0, colour("MeadowLeafDark")), (0.5, colour("MeadowLeaf")), (1.0, colour("MeadowLeafLight"))])
    cell = np.floor(context.pos * 3.2)
    pick = np.mod(np.sin(cell[:, 0] * 12.9898 + cell[:, 1] * 78.233 + cell[:, 2] * 37.719 + seed) * 43758.5453, 1.0)
    centre = (cell + 0.5) / 3.2
    near = np.linalg.norm(context.pos - centre, axis=1) < 0.11
    rgb = leaf
    for low, high, name in ((0.0, 0.12, "MeadowPoppy"), (0.12, 0.22, "MeadowButtercup"), (0.22, 0.32, "MeadowDaisy"), (0.32, 0.4, "MeadowCornflower")):
        chosen = near & (pick >= low) & (pick < high)
        rgb[chosen] = _hex(colour(name))
    ribbon = np.abs(np.sin(context.local[:, along_axis] * 2.6 + np.arctan2(context.local[:, 1], context.local[:, 0]))) < 0.16
    rgb = mix(rgb, solid(count, "F0E6CC"), ribbon * 0.9)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.25)


@brush("plant.fronds", version=1, material="greenery", fixture="dome", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowFairStall carrot tops)", summary="Feathery green fronds (carrot tops) streaked along object X, darker where they bunch at the crown (local x near 0)")
def fronds(context, seed=0.0):
    """Carrot tops: feathery green fronds streaked along object X, darker where they bunch at the crown."""
    count = context.count
    local = context.local
    streak = np.abs(np.sin(local[:, 1] * 38.0 + local[:, 2] * 25.0 + np.sin(local[:, 0] * 6.0 + seed) * 2.0))
    rgb = mix(solid(count, colour("MeadowFairCabbageDark")), solid(count, colour("MeadowFairCabbage")), smoothstep(0.2, 0.8, streak))
    rgb = mix(rgb, solid(count, colour("MeadowFairAppleGreen")), smoothstep(0.85, 1.0, streak) * 0.6)
    rgb = mix(rgb, solid(count, colour("MeadowFairCabbageDark")), (1 - smoothstep(0.0, 0.25, local[:, 0])) * 0.6)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.25)
