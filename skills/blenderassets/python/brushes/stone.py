"""brushes.stone: masonry and field-stone brushes (ashlar, tiling ashlar, flagstone paving, the dark of a slit,
boulders, dry-stone walling and its coping). Each is painter(context, **options) -> RGB; see brushes/README.md.
Block, flag and stone sizes are real studs, so courses match across every piece that shares them."""

import math

import numpy as np

from paintlib import Context, fbm, lift, mix, ramp, shade, smoothstep, solid

from .core import colour, finish, posterize
from .registry import brush
from .surface import _hash, _surface_uv, run_frame, tiled_fbm

SOURCE = "Joust Tycoon castle (Rebirth 0), 2026-10-05"


@brush("stone.ashlar", version=1, material="stone", fixture="drum", tint=False, styles=("painted-toon",), source=SOURCE, summary="Ashlar in running bond: per-block tones with warm/cool strays, painted bevel (lit lip, shaded foot), chips, cracks, moss from the ground and in crevices; around=(x, y, radius) lays courses round a drum, tops are square flags")
def stone(context, around=None, block=(2.6, 1.3), mortar=0.13, moss_below=2.5, moss=0.4, grime=0.08,
          base="CastleStone", light="CastleStoneLight", dark="CastleStoneDark", warm="CastleStoneWarm",
          cool="CastleStoneCool", joint="CastleMortar", moss_colour="CastleMoss", moss_dark="CastleMossDark"):
    """Ashlar in running bond: per-block tone, a painted bevel (lit top lip, shaded foot), chips, hairline cracks,
    moss creeping up from the ground and into crevices. Tops are laid as square flags."""
    count = context.count
    u, v, flat = _surface_uv(context, around)
    width = np.where(flat, block[0] * 0.8, block[0])
    height = np.where(flat, block[0] * 0.8, block[1])
    row = np.floor(v / height)
    shifted = u / width + 0.5 * np.mod(row, 2.0) + (_hash(row, 3.0) - 0.5) * 0.3
    column = np.floor(shifted)
    across = shifted - column
    up = v / height - row
    edge = np.minimum(np.minimum(across, 1 - across) * width, np.minimum(up, 1 - up) * height)
    joint_mask = 1 - smoothstep(mortar * 0.55, mortar, edge)

    tone = _hash(row, column)
    rgb = ramp(posterize(tone, 4), [(0.0, colour(dark)), (0.35, colour(base)), (0.75, colour(base)), (1.0, colour(light))])
    stray = _hash(column, row, 5.0)
    rgb = mix(rgb, solid(count, colour(warm)), (stray > 0.86) * 0.7)
    rgb = mix(rgb, solid(count, colour(cool)), (stray < 0.1) * 0.6)
    mottle = fbm(context.pos, scale=0.9, octaves=3, seed=11.0)
    rgb = shade(rgb, 0.93 + mottle * 0.18)

    lip = smoothstep(1 - 0.24, 1 - 0.08, up) * (1 - flat)
    foot = smoothstep(0.24, 0.06, up) * (1 - flat)
    rgb = lift(rgb, lip * 0.22, toward=colour(light))
    rgb = shade(rgb, 1 - foot * 0.16)
    chips = smoothstep(0.42, 0.5, fbm(context.pos, scale=2.6, octaves=2, seed=13.0))
    rgb = shade(rgb, 1 - chips * 0.22)
    crack_field = fbm(context.pos, scale=1.4, octaves=3, seed=17.0)
    crack = (1 - smoothstep(0.004, 0.018, np.abs(crack_field))) * (_hash(column, row, 9.0) > 0.7)
    rgb = mix(rgb, solid(count, colour(joint)), crack * 0.7)
    rgb = mix(rgb, solid(count, colour(joint)), joint_mask * 0.92)

    if moss > 0:
        patch = smoothstep(-0.05, 0.25, fbm(context.pos, scale=0.7, octaves=3, seed=19.0))
        low = smoothstep(moss_below, 0.0, context.pos[:, 2])
        crevice = smoothstep(0.4, 0.15, np.clip(context.ao, 0, 1)) * 0.35
        amount = np.clip((low + crevice) * patch, 0, 1) * moss
        moss_rgb = mix(solid(count, colour(moss_colour)), solid(count, colour(moss_dark)), smoothstep(0.1, 0.5, fbm(context.pos, scale=3.0, octaves=2, seed=23.0)))
        rgb = mix(rgb, moss_rgb, amount * np.maximum(joint_mask, 0.55))
    if grime > 0:
        streak = smoothstep(0.1, 0.45, fbm(context.pos * np.array((3.0, 3.0, 0.25)), scale=1.0, octaves=2, seed=29.0))
        rgb = shade(rgb, 1 - streak * grime * 0.35)
    return finish(rgb, context, ao_strength=0.65, edge_light=0.28)


@brush("stone.ashlar_tiled", version=1, material="stone", fixture="wall", tint=False, styles=("painted-toon",), source=SOURCE + " (moat retaining walls and coping)", summary="stone.ashlar for straight runs that tile along X: block columns and every noise repeat each period[0] studs (block widths must divide it); shift moves the coursing, swap/along place a corner arm in its run's frame; moss below moss_below (a waterline)")
def stone_tiled(context, period=(21.0, 0.0, 0.0), block=(2.5, 0.65), flat_block=(2.0, 2.0), shift=(0.0, 0.0), mortar=0.12,
                moss_below=-0.2, moss=0.45, grime=0.08, base="CastleStone", light="CastleStoneLight", dark="CastleStoneDark",
                warm="CastleStoneWarm", cool="CastleStoneCool", joint="CastleMortar", moss_colour="CastleMoss",
                moss_dark="CastleMossDark", swap=False, along=0.0):
    """stone.ashlar for straight runs that tile along X: the same running-bond ashlar, but block columns and
    every noise repeat each period[0] studs, so courses and tones meet across the joint. Block widths must divide
    the period. shift moves the coursing (u, v) so a course line can sit off an edge; swap and along place a corner
    arm in its run's frame (surface.run_frame)."""
    count = context.count
    pos, normal = run_frame(context.pos, context.normal, swap, along)
    flat = np.abs(normal[:, 2]) > 0.75
    use_y = np.abs(normal[:, 0]) > np.abs(normal[:, 1])
    u = np.where(flat | ~use_y, pos[:, 0], pos[:, 1]) + shift[0]
    v = np.where(flat, pos[:, 1], pos[:, 2]) + shift[1]
    width = np.where(flat, flat_block[0], block[0])
    height = np.where(flat, flat_block[1], block[1])
    columns = np.where(flat, round(period[0] / flat_block[0]), round(period[0] / block[0])) if period[0] else None
    row = np.floor(v / height)
    shifted = u / width + 0.5 * np.mod(row, 2.0) + (_hash(row, 3.0) - 0.5) * 0.3
    column = np.floor(shifted)
    if columns is not None:
        column = np.mod(column, columns)
    across = shifted - np.floor(shifted)
    up = v / height - row
    edge = np.minimum(np.minimum(across, 1 - across) * width, np.minimum(up, 1 - up) * height)
    joint_mask = 1 - smoothstep(mortar * 0.55, mortar, edge)

    noise = lambda scale, octaves, seed, stretch=(1.0, 1.0, 1.0): tiled_fbm(pos * np.array(stretch), scale, octaves, period, seed)
    tone = _hash(row, column)
    rgb = ramp(posterize(tone, 4), [(0.0, colour(dark)), (0.35, colour(base)), (0.75, colour(base)), (1.0, colour(light))])
    stray = _hash(column, row, 5.0)
    rgb = mix(rgb, solid(count, colour(warm)), (stray > 0.86) * 0.7)
    rgb = mix(rgb, solid(count, colour(cool)), (stray < 0.1) * 0.6)
    rgb = shade(rgb, 0.93 + noise(0.9, 3, 11.0) * 0.18)
    lip = smoothstep(1 - 0.24, 1 - 0.08, up) * (1 - flat)
    foot = smoothstep(0.24, 0.06, up) * (1 - flat)
    rgb = lift(rgb, lip * 0.22, toward=colour(light))
    rgb = shade(rgb, 1 - foot * 0.16)
    chips = smoothstep(0.42, 0.5, noise(2.6, 2, 13.0))
    rgb = shade(rgb, 1 - chips * 0.22)
    crack = (1 - smoothstep(0.004, 0.018, np.abs(noise(1.4, 3, 17.0)))) * (_hash(column, row, 9.0) > 0.7)
    rgb = mix(rgb, solid(count, colour(joint)), crack * 0.7)
    rgb = mix(rgb, solid(count, colour(joint)), joint_mask * 0.92)
    if moss > 0:
        patch = smoothstep(-0.05, 0.25, noise(0.7, 3, 19.0))
        low = smoothstep(moss_below, moss_below - 1.4, pos[:, 2])
        crevice = smoothstep(0.4, 0.15, np.clip(context.ao, 0, 1)) * 0.35
        amount = np.clip((low + crevice) * patch, 0, 1) * moss
        moss_rgb = mix(solid(count, colour(moss_colour)), solid(count, colour(moss_dark)), smoothstep(0.1, 0.5, noise(3.0, 2, 23.0)))
        rgb = mix(rgb, moss_rgb, amount * np.maximum(joint_mask, 0.55))
    if grime > 0:
        streak = smoothstep(0.1, 0.45, noise(1.0, 2, 29.0, stretch=(3.0, 3.0, 0.25)))
        rgb = shade(rgb, 1 - streak * grime * 0.35)
    return finish(rgb, context, ao_strength=0.65, edge_light=0.28)


@brush("stone.slit", version=1, material="stone", fixture="box", tint=False, styles=("painted-toon",), source=SOURCE, summary="The flat dark of an arrow slit or window recess (no light, almost no edge)")
def slit(context):
    """The dark of an arrow slit or window recess."""
    rgb = solid(context.count, colour("CastleSlit"))
    return finish(rgb, context, ao_strength=0.2, edge_light=0.05)


def _courses(tile, rows, seed, shortest=1.9, longest=3.9):
    """Per course, the stone boundaries across one tile: random lengths that add up to exactly the tile, so the
    tile edge is a joint in every course."""
    random = np.random.RandomState(seed)
    courses = []
    for _ in range(rows):
        lengths = []
        while sum(lengths) < tile - longest:
            lengths.append(random.uniform(shortest, longest))
        remainder = tile - sum(lengths)
        if remainder < shortest:
            lengths[-1] += remainder
        elif remainder > longest:
            lengths += [remainder / 2, remainder / 2]
        else:
            lengths.append(remainder)
        random.shuffle(lengths)
        courses.append(np.concatenate([[0.0], np.cumsum(lengths)]))
    return courses


@brush("stone.paving", version=1, material="stone", fixture="plane", tint=False, styles=("painted-toon",), source=SOURCE + " (courtyard paving, gatehouse threshold)", summary="Flagstones for a square tile centred on the origin: courses along X of random-length real-sized flags (1.9-3.9 studs) closing on the tile edge, per-flag tone, painted raised edge, wear, chips, moss in the joints; repeats each tile in X and Y")
def paving(context, tile=18.9, rows=8, mortar=0.11, seed=5, moss=0.4):
    """Courtyard flagstones for a square tile centred on the origin: courses running along X of random-length
    flags, each its own tone with a painted raised edge (lit toward the key light, shaded away), chips, wear and
    moss in the joints. Courses and noise repeat each tile in X and Y."""
    count = context.count
    pos = context.pos
    period = (tile, tile, 0.0)
    across = np.mod(pos[:, 0] + tile / 2, tile)
    along = np.mod(pos[:, 1] + tile / 2, tile)
    course_depth = tile / rows
    row = np.clip(np.floor(along / course_depth), 0, rows - 1)
    up = along / course_depth - row
    courses = _courses(tile, rows, seed)
    left = np.zeros(count)
    right = np.zeros(count)
    stone_index = np.zeros(count)
    for index, bounds in enumerate(courses):
        mask = row == index
        if not mask.any():
            continue
        slot = np.clip(np.searchsorted(bounds, across[mask], side="right") - 1, 0, len(bounds) - 2)
        stone_index[mask] = slot
        left[mask] = across[mask] - bounds[slot]
        right[mask] = bounds[slot + 1] - across[mask]
    front, back = up * course_depth, (1 - up) * course_depth
    edge = np.minimum(np.minimum(left, right), np.minimum(front, back))
    joint_mask = 1 - smoothstep(mortar * 0.5, mortar, edge)

    noise = lambda scale, octaves, seed_value: tiled_fbm(pos, scale, octaves, period, seed_value)
    tone = _hash(row, stone_index, 2.0)
    rgb = ramp(posterize(tone, 3), [(0.0, colour("CastlePaveDark")), (0.25, colour("CastlePave")), (0.8, colour("CastlePave")), (1.0, colour("CastlePaveLight"))])
    rgb = mix(rgb, solid(count, colour("CastlePave")), 0.3)
    stray = _hash(stone_index, row, 6.0)
    rgb = mix(rgb, solid(count, colour("CastlePaveWarm")), (stray > 0.88) * 0.55)
    rgb = mix(rgb, solid(count, colour("CastlePaveCool")), (stray < 0.08) * 0.5)
    rgb = shade(rgb, 0.94 + noise(0.8, 3, 41.0) * 0.16)
    # a flag's raised edge: lit on the sides facing the key light (-X, -Y), shaded on the far sides
    band = 0.28
    rgb = lift(rgb, smoothstep(band, mortar, np.minimum(left, front)) * 0.2, toward=colour("CastlePaveLight"))
    rgb = shade(rgb, 1 - smoothstep(band, mortar, np.minimum(right, back)) * 0.18)
    wear = smoothstep(0.15, 0.45, noise(0.35, 2, 43.0))
    rgb = lift(rgb, wear * 0.1, toward=colour("CastlePaveLight"))
    chips = smoothstep(0.42, 0.5, noise(2.4, 2, 47.0))
    rgb = shade(rgb, 1 - chips * 0.18)
    crack = (1 - smoothstep(0.004, 0.014, np.abs(noise(0.9, 2, 53.0)))) * (_hash(row, stone_index, 11.0) > 0.86)
    rgb = mix(rgb, solid(count, colour("CastleMortar")), crack * 0.7)
    rgb = mix(rgb, solid(count, colour("CastleMortar")), joint_mask * 0.92)
    if moss > 0:
        patch = smoothstep(0.12, 0.35, noise(0.4, 3, 59.0))
        near_joint = 1 - smoothstep(mortar, mortar * 2.5, edge)
        moss_rgb = mix(solid(count, colour("CastleMoss")), solid(count, colour("CastleMossDark")), smoothstep(0.1, 0.5, noise(3.0, 2, 61.0)))
        rgb = mix(rgb, moss_rgb, patch * near_joint * moss)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.25)


# ---- Greenmeadow field stone (Joust Tycoon, approved 2026-10-05): boulders and dry-stone field walls. Copied
# verbatim from the project's coverpaint.py and farmpaint.py, so these paint exactly what the project's copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("stone.boulder", version=1, material="stone", fixture="rock", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowGroundCover boulders and stones)", summary="Field stone in its own frame: posterised tone patches with warm/cool strays, speckle, hairline cracks on the sides, ragged moss cushions on the tops, lee side and cracks, yellow and pale lichen rosettes on the flanks, earthy grime at the ground (z 0); scale shrinks the patterns for a small stone")
def boulder(context, seed=0.0, moss=0.7, lichen=0.6, cracks=0.8, scale=1.0):
    """Field stone on its own frame: posterised tone patches with warm and cool strays, a speckle, hairline cracks
    on the sides, cushions of moss on the tops and in from the ground, yellow and pale lichen rosettes on the
    flanks, and earthy grime where it meets the ground. scale shrinks the patterns for a small stone."""
    count = context.count
    local = context.local / scale
    up = context.normal[:, 2]
    patches = fbm(local, scale=0.32, octaves=3, seed=seed)
    rgb = ramp(posterize(np.clip(0.5 + patches * 1.5, 0, 1), 4), [(0.0, colour("MeadowStoneDark")), (0.35, colour("MeadowStone")), (0.75, colour("MeadowStone")), (1.0, colour("MeadowStoneLight"))])
    stray = fbm(local, scale=0.55, octaves=2, seed=seed + 2.0)
    rgb = mix(rgb, solid(count, colour("MeadowRockWarm")), smoothstep(0.22, 0.3, stray) * 0.7)
    rgb = mix(rgb, solid(count, colour("MeadowRockCool")), smoothstep(-0.22, -0.3, stray) * 0.6)
    speckle = fbm(local * 9.0, scale=1.0, octaves=1, seed=seed + 4.0)
    rgb = shade(rgb, 0.95 + 0.1 * (speckle > 0.25) - 0.06 * (speckle < -0.3))
    if cracks:
        crack = (1 - smoothstep(0.006, 0.022, np.abs(fbm(local, scale=0.7, octaves=3, seed=seed + 6.0))))
        crack *= smoothstep(0.0, 0.2, fbm(local, scale=0.4, octaves=2, seed=seed + 7.0)) * smoothstep(0.8, 0.5, up)
        rgb = mix(rgb, solid(count, colour("MeadowRockCrack")), crack * cracks)
    if lichen:
        rosette = fbm(local * 2.4, scale=1.0, octaves=2, seed=seed + 8.0)
        flank = smoothstep(-0.3, 0.1, up) * smoothstep(0.85, 0.55, up)
        rgb = mix(rgb, solid(count, colour("MeadowRockLichen")), smoothstep(0.3, 0.34, rosette) * flank * lichen)
        pale = fbm(local * 3.1, scale=1.0, octaves=2, seed=seed + 9.0)
        rgb = mix(rgb, solid(count, colour("MeadowRockLichenPale")), smoothstep(0.33, 0.37, pale) * flank * lichen * 0.8)
    if moss:
        # moss grows in broken patches on the tops, creeps down the lee side (away from the key light) and along the
        # cracks; a ragged high-frequency edge breaks the outline, and bare stone is left between the patches
        clump = fbm(local, scale=0.9, octaves=3, seed=seed + 10.0)
        ragged = fbm(local * 6.0, scale=1.0, octaves=2, seed=seed + 11.0)
        lee = np.clip(context.normal @ np.array((0.35, 0.45, 0.0)), 0, 1)
        seam = 1 - smoothstep(0.02, 0.07, np.abs(fbm(local, scale=0.7, octaves=3, seed=seed + 6.0)))
        cover = smoothstep(0.25, 0.75, up) * 0.65 + lee * 0.35 + seam * smoothstep(-0.2, 0.3, up) * 0.45
        ground = smoothstep(0.35 * scale, 0.05, context.pos[:, 2]) * 0.4
        amount = (cover + ground) * moss + clump * 0.9 + ragged * 0.35
        tufts = fbm(local * 1.6, scale=1.0, octaves=2, seed=seed + 12.0)
        cushion = np.clip(0.45 + tufts * 1.1 + (up - 0.5) * 0.35, 0, 1)
        moss_rgb = ramp(posterize(cushion, 3), [(0.0, colour("MeadowGrassDark")), (0.65, colour("MeadowMoss")), (1.0, colour("MeadowMoss"))])
        moss_rgb = mix(moss_rgb, solid(count, colour("MeadowStoneDark")), 0.25)
        # the hard cool band where a patch rolls over the edge and hangs
        moss_rgb = mix(moss_rgb, solid(count, colour("MeadowGrassCool")), smoothstep(0.35, 0.15, up) * 0.7)
        rgb = mix(rgb, moss_rgb, smoothstep(0.48, 0.54, amount))
    grime = smoothstep(0.5 * scale, 0.0, context.pos[:, 2])
    rgb = mix(rgb, solid(count, colour("MeadowEarthDark")), grime * 0.45)
    return finish(rgb, context, ao_strength=0.65, edge_light=0.3)


def _wall_courses(length, rows, seed, shortest, longest):
    """Per course, stone boundaries across a run of `length`: random lengths that add up to exactly the run, so
    both ends are a joint in every course (the paving brush's method)."""
    random = np.random.RandomState(seed)
    courses = []
    for _ in range(rows):
        lengths = []
        while sum(lengths) < length - longest:
            lengths.append(random.uniform(shortest, longest))
        remainder = length - sum(lengths)
        if remainder < shortest:
            lengths[-1] += remainder
        elif remainder > longest:
            lengths += [remainder / 2, remainder / 2]
        else:
            lengths.append(remainder)
        random.shuffle(lengths)
        courses.append(np.concatenate([[0.0], np.cumsum(lengths)]))
    return courses


def field_light(context, seams=()):
    """The context the finish sees on a field wall or fence seen from both sides: +Y normals mirrored to -Y so both
    faces take the front-left key alike, and no edge light on butt joints at x in `seams` (hidden by the next
    piece)."""
    normal = context.normal.copy()
    normal[:, 1] = -np.abs(normal[:, 1])
    edge = context.edge
    for seam in seams:
        joint = (np.abs(context.pos[:, 0] - seam) < 0.2) & (np.abs(context.normal[:, 0]) < 0.6)
        edge = np.where(joint, 0.0, edge)
    return Context(context.pos, normal, context.ao, context.curvature, edge, context.local, context.coord)


def _field_stone_tone(count, key_a, key_b):
    tone = _hash(key_a, key_b, 2.0)
    rgb = ramp(posterize(tone, 4), [(0.0, colour("MeadowStoneDark")), (0.3, colour("MeadowStone")), (0.78, colour("MeadowStone")), (1.0, colour("MeadowStoneLight"))])
    stray = _hash(key_b, key_a, 6.0)
    rgb = mix(rgb, solid(count, colour("MeadowFarmStoneWarm")), (stray > 0.84) * 0.7)
    rgb = mix(rgb, solid(count, colour("MeadowFarmStoneCool")), (stray < 0.12) * 0.6)
    return rgb


def _field_moss(count, pos, period, seed):
    deep = smoothstep(0.05, 0.45, tiled_fbm(pos, 2.6, 2, period, seed + 3.0))
    rgb = mix(solid(count, colour("MeadowMoss")), solid(count, colour("MeadowFarmMossDark")), deep)
    tufts = smoothstep(0.25, 0.4, tiled_fbm(pos, 5.0, 1, period, seed + 5.0))
    return mix(rgb, solid(count, colour("MeadowGrassLight")), tufts * 0.45)


@brush("stone.dry_stone", version=1, material="stone", fixture="drywall", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowStoneWall segment and end)", summary="Dry-stone walling along X from origin_x to origin_x + length: rough courses (`courses` tall from `foot`) of real-sized stones (0.6-1.8 long) with dark voids and no mortar, per-stone tone, pillowed faces, lichen, moss creeping from the top (`top`) and ground; courses close on both ends and noise repeats every `period`, so pieces tile; end faces lay stones across Y; lit the same from both sides (seams: hidden butt joints)")
def dry_stone(context, origin_x=-6.0, length=12.0, courses=(0.72, 0.62, 0.55, 0.5, 0.45), foot=-0.3, top=2.35,
              seed=3, period=12.0, seams=(-6.0, 6.0), cheek_x=None):
    """Dry-stone walling along X from origin_x to origin_x + length. Faces carry rough courses of real-sized stones
    (0.9-1.9 long, `courses` tall from `foot`) with dark voids between them, per-stone tone, pillowed faces (lit top
    lip, shaded foot), lichen and moss in the voids near the top; tops are moss over stone. End faces (normal
    along X) lay their stones across Y; cheek_x marks a finished end whose big tie stones run the full depth."""
    count = context.count
    pos, normal = context.pos, context.normal
    noise_period = (period, 0.0, 0.0)
    noise = lambda scale, octaves, seed_value: tiled_fbm(pos, scale, octaves, noise_period, seed_value)
    end_face = np.abs(normal[:, 0]) > 0.7
    top_face = normal[:, 2] > 0.6
    u = np.where(end_face, pos[:, 1] + 1.5, pos[:, 0] - origin_x)
    run = np.where(end_face, 3.0, length)
    heights = np.concatenate([[foot], foot + np.cumsum(courses)])
    wave = 0.05 * np.sin(u * math.tau / length * 3.0 + 1.3) + 0.04 * noise(1.3, 1, seed + 1.0)
    v = pos[:, 2] + wave
    row = np.clip(np.searchsorted(heights, v, side="right") - 1, 0, len(courses) - 1)
    course_low = heights[row]
    course_high = heights[np.minimum(row + 1, len(courses))]
    rows = _wall_courses(length, len(courses), seed, 0.6, 1.8)
    ends = _wall_courses(3.0, len(courses), seed + 7, 0.7, 1.5)
    wobble = 0.1 * noise(1.1, 2, seed + 2.0) * smoothstep(0.0, 0.3, np.minimum(u, run - u))
    shifted = u + wobble
    left = np.zeros(count)
    right = np.zeros(count)
    index = np.zeros(count)
    for course in range(len(courses)):
        for layout, mask in ((rows[course], (row == course) & ~end_face), (ends[course], (row == course) & end_face)):
            if not mask.any():
                continue
            slot = np.clip(np.searchsorted(layout, shifted[mask], side="right") - 1, 0, len(layout) - 2)
            index[mask] = slot + end_face[mask] * 50
            left[mask] = shifted[mask] - layout[slot]
            right[mask] = layout[slot + 1] - shifted[mask]
    centre_u = shifted + (right - left) / 2
    half_w = (left + right) / 2
    centre_v = (course_low + course_high) / 2
    half_h = (course_high - course_low) / 2
    du = shifted - centre_u
    dv = v - centre_v
    # each stone is a rounded rectangle turned a few degrees about its own centre (signed distance d < 0 inside)
    angle = (_hash(row, index, 3.0) - 0.5) * 0.18
    ru = du * np.cos(angle) + dv * np.sin(angle)
    rv = -du * np.sin(angle) + dv * np.cos(angle)
    inset = 0.025 + _hash(index, row, 4.0) * 0.05
    radius = 0.07 + _hash(row, index, 8.0) * 0.13
    qx = np.abs(ru) - np.maximum(half_w - inset - radius, 0.02)
    qy = np.abs(rv) - np.maximum(half_h - inset - radius, 0.02)
    distance = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius
    void = smoothstep(-0.012, 0.012, distance)
    inside = np.maximum(-distance, 0)

    rgb = _field_stone_tone(count, row + 0.0, index)
    rgb = shade(rgb, 0.93 + noise(0.9, 3, seed + 11.0) * 0.16)
    lip = smoothstep(0.2, 0.05, inside) * (rv > 0)
    sole = smoothstep(0.2, 0.04, inside) * (rv <= 0)
    rgb = lift(rgb, lip * 0.26, toward=colour("MeadowStoneLight"))
    rgb = shade(rgb, 1 - sole * 0.24)
    chips = smoothstep(0.42, 0.5, noise(2.8, 2, seed + 13.0))
    rgb = shade(rgb, 1 - chips * 0.2)
    lichen = smoothstep(0.38, 0.46, noise(3.4, 2, seed + 17.0)) * (_hash(row, index, 9.0) > 0.5)
    rgb = mix(rgb, solid(count, colour("MeadowFarmLichen")), lichen * 0.55)
    rgb = mix(rgb, solid(count, colour("MeadowFarmStoneVoid")), void * 0.95)

    moss_rgb = _field_moss(count, pos, noise_period, seed)
    patch = smoothstep(-0.1, 0.2, noise(0.8, 3, seed + 19.0))
    creeping = smoothstep(top - 0.9, top, pos[:, 2]) * patch * np.maximum(void, 0.35)
    ground = smoothstep(0.5, -0.1, pos[:, 2]) * smoothstep(0.0, 0.3, noise(1.2, 2, seed + 23.0)) * 0.6
    on_top = top_face * smoothstep(-0.25, 0.1, noise(0.9, 2, seed + 29.0))
    rgb = mix(rgb, moss_rgb, np.clip(creeping + ground + on_top, 0, 1))
    return finish(rgb, field_light(context, seams), ao_strength=0.7, edge_light=0.28)


@brush("stone.coping_stone", version=1, material="stone", fixture="box", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowStoneWall combers)", summary="One upright coping stone (a comber) on a dry-stone wall's top: its own tone per `key`, chips, lichen, moss over its top; noise repeats every `period` along X like stone.dry_stone")
def coping_stone(context, key=0, period=12.0, seed=3, seams=()):
    """One upright coping stone set on edge along a dry-stone wall's top: its own tone, pillowed edges from AO and
    edge, lichen, and moss over its top."""
    count = context.count
    pos = context.pos
    noise_period = (period, 0.0, 0.0)
    rgb = _field_stone_tone(count, np.full(count, 7.0 + key), np.full(count, float(key)))
    rgb = shade(rgb, 0.92 + tiled_fbm(pos, 1.6, 3, noise_period, seed + 31.0) * 0.18)
    chips = smoothstep(0.4, 0.5, tiled_fbm(pos, 3.0, 2, noise_period, seed + 37.0))
    rgb = shade(rgb, 1 - chips * 0.2)
    lichen = smoothstep(0.36, 0.45, tiled_fbm(pos, 3.6, 2, noise_period, seed + 41.0))
    rgb = mix(rgb, solid(count, colour("MeadowFarmLichen")), lichen * 0.5)
    up = smoothstep(0.35, 0.75, context.normal[:, 2])
    patch = smoothstep(-0.2, 0.15, tiled_fbm(pos, 1.0, 2, noise_period, seed + 43.0))
    rgb = mix(rgb, _field_moss(count, pos, noise_period, seed + 50), np.clip(up * patch * 1.2, 0, 1))
    return finish(rgb, field_light(context, seams), ao_strength=0.75, edge_light=0.3)
