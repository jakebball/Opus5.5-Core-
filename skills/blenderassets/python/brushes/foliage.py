"""brushes.foliage: leaf masses and bark. Each is painter(context, **options) -> RGB; see brushes/README.md.

Leaf clumps are cells of 3D Worley noise on the world position: each cell is one clump of leaves, lit on the side
that faces up along the surface and shaded toward its lower rim, with dark gaps between clumps, so a crown reads as
overlapping scallops of leaves under the toon pass's own shadow and highlight bands. Every noise can repeat along X
(period), so a hedge segment's paint meets the next copy's exactly.

Copied verbatim from Joust Tycoon's Greenmeadow foliage painters (blender-source/world/foliage/foliagepaint.py;
approved 2026-10-05), so the library brushes paint exactly what the project's copies paint."""

import numpy as np

from paintlib import lift, mix, ramp, shade, smoothstep, solid

from .core import colour, finish, posterize, saturate
from .registry import brush
from .surface import tiled_fbm

SOURCE = "Joust Tycoon Greenmeadow, 2026-10-05"

NEIGHBOURS = np.array([(dx, dy, dz) for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)], dtype=np.float64)
TOWARD_LIGHT = np.array((-0.3, -0.4, 1.0)) / np.linalg.norm((-0.3, -0.4, 1.0))
# the world sits a notch less saturated than characters; the toon finish adds its own saturation on top
WORLD_SATURATION = 0.88


def _cell_hash(cells, seed):
    value = np.sin(cells[:, 0] * 127.1 + cells[:, 1] * 311.7 + cells[:, 2] * 74.7 + seed * 19.19) * 43758.5453
    return value - np.floor(value)


def _features(points, cell, period, jitter, seed):
    if period:
        count = max(1, round(period / cell))
        cell = period / count
    else:
        count = 0
    scaled = np.asarray(points, dtype=np.float64) / cell
    base = np.floor(scaled)
    for offset in NEIGHBOURS:
        cells = base + offset
        keyed = cells.copy()
        if count:
            keyed[:, 0] = np.mod(keyed[:, 0], count)
        jittered = np.stack([_cell_hash(keyed, seed + 1.0 + axis) for axis in range(3)], axis=1)
        yield (cells + 0.5 + (jittered - 0.5) * jitter) * cell, _cell_hash(keyed, seed + 7.0), cell


def shingles(points, normal, cell, period=0.0, reach=0.85, teeth=7, seed=0.0, tooth=0.07, jitter=0.9):
    """Leaf clumps laid like roof shingles on 3D jittered cells: each clump is a disc `reach` cells across round its
    feature point, its rim scalloped into `teeth` leaf tips, and where discs overlap the one nearer the light lies
    on top. Returns (v, edge, ident, centre): v is -1 at the clump's lower rim to +1 at its top, edge 1 on its rim,
    ident a 0..1 id per clump, centre its feature point (studs). With period > 0 everything repeats along X."""
    count = len(points)
    tangent = TOWARD_LIGHT - normal * (normal @ TOWARD_LIGHT)[:, None]
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-6)
    best = np.full(count, -np.inf)
    nearest = np.full(count, np.inf)
    v = np.zeros(count)
    edge = np.zeros(count)
    ident = np.zeros(count)
    centre = np.zeros((count, 3))
    fallback = np.zeros((count, 3))
    fallback_ident = np.zeros(count)
    for feature, key, size in _features(points, cell, period, jitter, seed):
        offset = points - feature
        flat = offset - normal * np.einsum("ij,ij->i", offset, normal)[:, None]
        distance = np.linalg.norm(flat, axis=1)
        across = np.einsum("ij,ij->i", flat, tangent)
        side = np.einsum("ij,ij->i", flat, np.cross(normal, tangent))
        angle = np.arctan2(side, across)
        radius = size * reach * (0.85 + 0.3 * key) * (1.0 + tooth * np.cos(angle * teeth + key * 6.0))
        covered = distance < radius
        priority = feature @ TOWARD_LIGHT + key * 0.05
        take = covered & (priority > best)
        best = np.where(take, priority, best)
        v = np.where(take, across / radius, v)
        edge = np.where(take, distance / radius, edge)
        ident = np.where(take, key, ident)
        centre = np.where(take[:, None], feature, centre)
        closer = distance < nearest
        nearest = np.where(closer, distance, nearest)
        fallback = np.where(closer[:, None], feature, fallback)
        fallback_ident = np.where(closer, key, fallback_ident)
    missing = ~np.isfinite(best)
    ident = np.where(missing, fallback_ident, ident)
    centre = np.where(missing[:, None], fallback, centre)
    edge = np.where(missing, 1.0, edge)
    v = np.where(missing, -1.0, v)
    return v, edge, ident, centre


@brush("foliage.leaf_dabs", version=1, material="leaves", fixture="crown", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowTrees crowns, MeadowShrubs bushes and hedges)", summary="One leaf mass (crown lobe, bush, hedge clump) as shingled leaf-cluster dabs over a warm sunlit cap, the lit body and a hard cool shadow band below `band` that scallops with the dabs; read in the lobe's own frame over its `radii` (underside squashed by `under`); `cell` is the dab size in studs; blossoms [(petal, eye or None for a berry)] at blossom_rate; period > 0 repeats along X (a hedge)")
def leaf_dabs(context, radii, under=0.7, cell=2.0, period=0.0, band=0.22, base="MeadowLeaf", light="MeadowLeafLight",
              dark="MeadowLeafDark", shade_name="MeadowLeafShade", deep="MeadowLeafDeep", sun="MeadowLeafSun",
              gap="MeadowLeafGap", flecks=0.14, blossoms=None, blossom_rate=0.0, seed=0.0, ao_strength=0.6):
    """One leaf mass (a crown lobe, a bush, a hedge clump) painted as leaf-cluster dabs over three big zones read in
    the lobe's own frame (context.local over its radii, the underside squashed by `under`): a warm sunlit cap, the
    lit body, and a hard cool shadow band below `band` whose edge follows the dabs, so it scallops like hanging
    leaves. Each dab is a shingle (above): lit along its top, a thin dark crescent at its lower rim. blossoms: a list
    of (petal, eye) colour names; blossom_rate of the lit dabs carry a five-petal flower (a berry when eye is None).
    With period > 0 the dabs repeat along X (a hedge)."""
    count = context.count
    pos, normal, local = context.pos, context.normal, context.local
    radii = np.asarray(radii, dtype=np.float64)
    origin = pos - local

    def height(points):
        scaled = points[:, 2] / radii[2]
        return np.where(scaled < 0.0, scaled / under, scaled)

    v, edge, ident, centre = shingles(pos, normal, cell, period, reach=0.8, teeth=7, seed=seed, tooth=0.14, jitter=0.65)
    dab_height = height(centre - origin)
    texel_height = height(local)
    span = (period, 0.0, 0.0)
    wobble = tiled_fbm(pos, 0.35, 2, span, seed + 11.0) * 0.12

    shadowed = smoothstep(band + 0.03, band - 0.03, dab_height * 0.65 + texel_height * 0.35 + wobble)
    capped = smoothstep(0.42, 0.52, dab_height * 0.6 + texel_height * 0.4 + wobble) * smoothstep(0.2, 0.5, normal[:, 2])

    tone = tiled_fbm(pos, 0.07, 2, span, 3.0 + seed)
    body = mix(solid(count, colour(dark)), solid(count, colour(base)), 0.55 + smoothstep(-0.1, 0.1, tone) * 0.3)
    body = shade(body, 0.96 + (ident - 0.5) * 0.1)

    # each dab: a scallop of lit leaves over the darker body, its lower rim left in the body tone
    dab = smoothstep(0.93, 0.78, edge) * smoothstep(-0.55, -0.15, v)
    lit = mix(body, solid(count, colour(base)), 0.75)
    lit = mix(lit, solid(count, colour(light)), smoothstep(0.1, 0.7, v) * 0.45 + capped * 0.35)
    rgb = mix(body, lit, dab)
    rim = smoothstep(0.82, 0.97, edge) * smoothstep(0.1, -0.4, v)
    rgb = mix(rgb, solid(count, colour(dark)), rim * 0.55)

    rgb = mix(rgb, solid(count, colour(sun)), capped * dab * 0.14)
    fleck = (ident < flecks) & (normal[:, 2] > 0.25)
    rgb = mix(rgb, solid(count, colour(sun)), fleck * capped * dab * smoothstep(0.2, 0.55, v))

    cool = mix(solid(count, colour(shade_name)), solid(count, colour(deep)), rim * 0.7)
    cool = mix(cool, lift(cool, 0.1, toward=colour(dark)), dab * smoothstep(0.1, 0.6, v) * 0.7)
    rgb = mix(rgb, cool, shadowed)

    if blossoms and blossom_rate > 0:
        chosen = np.floor(np.mod(ident * 7919.0, 1.0) * len(blossoms)).astype(np.int64)
        flowered = (ident > 1.0 - blossom_rate) & (shadowed < 0.5)
        # a flower sits at the middle of its dab (edge, measured on the surface, is 0 there)
        flat = pos - centre
        flat -= normal * np.einsum("ij,ij->i", flat, normal)[:, None]
        angle = np.arctan2(flat[:, 1] + flat[:, 2] * 0.5, flat[:, 0] - flat[:, 2] * 0.3)
        petals = 0.5 + 0.16 * np.cos(angle * 5.0)
        for index, (petal, eye) in enumerate(blossoms):
            mine = flowered & (chosen == index)
            if eye is None:
                berry = mine & (edge < 0.26)
                rgb = mix(rgb, solid(count, colour(petal)), berry)
                rgb = mix(rgb, lift(solid(count, colour(petal)), 0.5), berry & (edge < 0.08))
                continue
            rgb = mix(rgb, solid(count, colour(petal)), mine & (edge < petals))
            rgb = mix(rgb, solid(count, colour(eye)), mine & (edge < 0.15))

    occluded = smoothstep(0.55, 0.2, context.ao)
    rgb = mix(rgb, solid(count, colour(gap)), occluded * 0.5)
    return finish(saturate(rgb, WORLD_SATURATION), context, ao_strength=ao_strength, edge_light=0.08)


@brush("foliage.bark", version=1, material="bark", fixture="limb", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowTrees trunks and limbs)", summary="Ridged bark on a limb loft's PaintCoord (fraction around, studs along): `fissures` dark vertical cracks round the limb broken every `pitch` studs or so, lit ridges between, moss creeping up from the ground below moss_below (moss=None for none)")
def bark(context, fissures=11.0, pitch=0.9, base="MeadowBark", light="MeadowFoliageBarkRidge", dark="MeadowBarkDark",
         fissure="MeadowFoliageBarkFissure", moss="MeadowMoss", moss_below=1.6, seed=0.0):
    """Ridged bark from the limb loft's PaintCoord (fraction around, studs along): `fissures` dark vertical cracks
    round each limb, broken every `pitch` studs or so, lit ridges between them, moss creeping up from the ground."""
    count = context.count
    around = context.coord[:, 0]
    along = context.coord[:, 1]
    has_coord = around > -1.0
    angle = np.where(has_coord, around, 0.0)
    wobble = tiled_fbm(np.stack([angle * 4.0, along * 0.35, np.full(count, seed)], axis=1), 1.0, 2) * 0.6
    phase = angle * fissures + wobble
    distance = np.abs(phase - np.round(phase))
    broken = tiled_fbm(np.stack([np.round(phase) * 3.1, along / pitch, np.full(count, seed + 2.0)], axis=1), 1.0, 2)
    crack = (1.0 - smoothstep(0.06, 0.17, distance)) * smoothstep(-0.25, 0.05, broken)
    ridge = smoothstep(0.32, 0.48, distance)
    tone = tiled_fbm(context.pos, 0.6, 3, (0.0, 0.0, 0.0), seed + 5.0)
    rgb = ramp(posterize(np.clip(0.5 + tone * 1.4, 0.0, 1.0), 3), [(0.0, colour(dark)), (0.5, colour(base)), (1.0, colour(base))])
    rgb = mix(rgb, solid(count, colour(light)), ridge * 0.55)
    rgb = mix(rgb, solid(count, colour(fissure)), crack * 0.9)
    if moss:
        patch = smoothstep(-0.1, 0.2, tiled_fbm(context.pos, 0.9, 2, (0.0, 0.0, 0.0), seed + 9.0))
        low = smoothstep(moss_below, 0.0, context.pos[:, 2])
        rgb = mix(rgb, solid(count, colour(moss)), np.clip(low * (0.5 + patch), 0.0, 1.0) * 0.8 * (1.0 - crack * 0.6))
    return finish(saturate(rgb, WORLD_SATURATION), context, ao_strength=0.65, edge_light=0.3)
