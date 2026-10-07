"""brushes.wood: wood brushes. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import math

import numpy as np

import paintlib as paint
from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

from .core import _dashes, _gold, _streaks, colour, finish, posterize, stitch_lines
from .registry import brush
from .surface import _hash, _local_normal, tiled_fbm



@brush("wood.ash_grain", version=1, material="wood", fixture="cylinder", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Ash-like wood: grain streaks round an axis (axis=0/1/2), posterised patches, knots, optional grime')
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


@brush("wood.firewood", version=1, material="wood", fixture="log", tint=False, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (woodpile)", summary="Split firewood along object `axis` with the pith on it: dark fissured bark (mossy) on the round faces, pale fibrous split faces, end grain with growth rings and checks on the cut ends")
def firewood(context, rotation=None, axis=0, radius=0.35, seed=0.0):
    """Split firewood whose length runs along object `axis` with the pith on that axis: dark fissured bark on the
    round faces, pale fibrous split faces, end grain with growth rings and checks on the cut ends."""
    count = context.count
    local = context.local
    normal = _local_normal(context, rotation)
    first, second = (axis + 1) % 3, (axis + 2) % 3
    along = local[:, axis]
    offset = np.stack([local[:, first], local[:, second]], axis=1)
    rho = np.maximum(np.linalg.norm(offset, axis=1), 1e-4)
    radial = offset / rho[:, None]
    facing_out = normal[:, first] * radial[:, 0] + normal[:, second] * radial[:, 1]
    end = smoothstep(0.65, 0.8, np.abs(normal[:, axis]))
    bark = smoothstep(0.75, 0.9, facing_out) * smoothstep(radius * 0.7, radius * 0.85, rho) * (1 - end)
    angle = np.arctan2(offset[:, 1], offset[:, 0])

    wobble = fbm(local, scale=1.4, octaves=2, seed=seed + 5.0)
    fissure = np.abs(np.sin(angle * 7.0 + wobble * 4.0 + along * 0.6))
    bark_rgb = ramp(posterize(np.clip(fissure, 0, 1), 3), [(0.0, colour("CastleBarkDark")), (0.5, colour("CastleBark")), (1.0, colour("CastleBarkLight"))])
    bark_rgb = mix(bark_rgb, solid(count, colour("CastleBarkDark")), (1 - smoothstep(0.05, 0.2, fissure)) * 0.8)
    moss = smoothstep(0.3, 0.45, fbm(local, scale=1.2, octaves=2, seed=seed + 9.0))
    bark_rgb = mix(bark_rgb, solid(count, colour("CastleMossDark")), moss * 0.45)

    fibres = _streaks(local, [1.0 if index == axis else 0.0 for index in range(3)], along=0.15, across=10.0, seed=seed + 13.0, octaves=2)
    split_rgb = ramp(posterize(np.clip(0.5 + fibres * 2.4, 0, 1), 4), [(0.0, colour("CastleSplitDark")), (0.5, colour("CastleSplit")), (1.0, colour("CastleEndGrain"))])
    split_rgb = mix(split_rgb, shade(split_rgb, 0.6), (1 - smoothstep(0.0, 0.1, np.abs(np.sin(fibres * 36.0)))) * 0.5)

    rings = np.abs(np.sin((rho + wobble * 0.03) / 0.055 * math.pi))
    end_rgb = mix(solid(count, colour("CastleEndGrain")), solid(count, colour("CastleSplit")), smoothstep(0.0, radius, rho) * 0.6)
    end_rgb = mix(end_rgb, solid(count, colour("CastleEndRing")), (1 - smoothstep(0.08, 0.25, rings)) * 0.75)
    check = (1 - smoothstep(0.0, 0.05, np.abs(np.sin(angle * 2.0 + seed * 3.0)))) * smoothstep(radius * 0.25, radius * 0.6, rho)
    end_rgb = mix(end_rgb, solid(count, colour("CastleTimberGrain")), check * 0.8)
    end_rgb = mix(end_rgb, solid(count, colour("CastleBarkDark")), smoothstep(radius * 0.86, radius * 0.95, rho))
    end_rgb = mix(end_rgb, solid(count, colour("CastleEndRing")), 1 - smoothstep(0.02, 0.05, rho))

    rgb = mix(split_rgb, bark_rgb, bark)
    rgb = mix(rgb, end_rgb, end)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("wood.chopping_block", version=1, material="wood", fixture="stump", tint=False, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (woodpile)", summary="A chopping block standing on object Z from 0 to `top`: wood.firewood bark round the side, end grain on top scored by axe cuts (list of ((x, y), angle))")
def stump(context, wood_bark_radius=0.7, top=1.2, cuts=()):
    """A chopping block on object Z: bark round the side, end grain on top scored by axe cuts (list of
    ((x, y), angle) in object space)."""
    count = context.count
    local = context.local
    rgb = firewood(context, axis=2, radius=wood_bark_radius, seed=4.0)
    top_face = smoothstep(0.75, 0.85, context.normal[:, 2]) * (local[:, 2] > top * 0.8)
    scars = np.zeros(count)
    for (x, y), angle in cuts:
        direction = np.array((math.cos(angle), math.sin(angle)))
        dx, dy = local[:, 0] - x, local[:, 1] - y
        along = dx * direction[0] + dy * direction[1]
        across = -dx * direction[1] + dy * direction[0]
        scars = np.maximum(scars, (1 - smoothstep(0.015, 0.04, np.abs(across))) * (1 - smoothstep(0.22, 0.3, np.abs(along))))
    return mix(rgb, shade(solid(count, colour("CastleTimberGrain")), 1.0), scars * top_face * 0.85)


# ---- Greenmeadow timber and painted boards (Joust Tycoon, approved 2026-10-05). Copied verbatim from the project's
# farmpaint.py and hubpaint.py, so these paint exactly what the project's copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("wood.weatherboard", version=1, material="wood", fixture="drum", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowWindmill tower)", summary="Lapped weatherboarding round a vertical axis through `centre`: boards boards[1] tall counted from z = boards[0], grain running round, a dark lap shadow under each board, staggered butt joints, weathered patches; measured round at `radius` with noise that repeats once round (no seam)")
def weatherboard(context, centre=(0.0, 0.0), radius=4.6, boards=(18.0, 0.55), seed=3.0):
    """Lapped weatherboarding round a vertical axis through `centre`: boards `boards[1]` tall from z = boards[0]
    downward and upward, grain running round the tower, a dark lap shadow under each board's lower edge, butt joints
    staggered from board to board. Measured round at a fixed `radius` with noise that repeats once round."""
    count = context.count
    pos = context.pos
    around = np.arctan2(pos[:, 1] - centre[1], pos[:, 0] - centre[0]) * radius
    period = (math.tau * radius, 0.0, 0.0)
    flat = np.stack([around, pos[:, 2], np.zeros(count)], axis=1)
    row = np.floor((pos[:, 2] - boards[0]) / boards[1])
    within = (pos[:, 2] - boards[0]) / boards[1] - row
    grain = tiled_fbm(np.stack([around * 0.08, pos[:, 2] * 3.0 + row * 7.0, np.zeros(count)], axis=1), 6.0, 3, (period[0] * 0.08, 0.0, 0.0), seed)
    tone = posterize(np.clip(0.5 + grain * 1.5 + (_hash(row, 1.0, seed) - 0.5) * 0.5, 0, 1), 4)
    rgb = ramp(tone, [(0.0, colour("MeadowFarmTimberDark")), (0.5, colour("MeadowFarmTimber")), (1.0, colour("MeadowFarmTimberLight"))])
    streak = np.abs(np.sin(grain * 30.0))
    rgb = mix(rgb, solid(count, colour("MeadowFarmTimberGrain")), (1 - smoothstep(0.0, 0.2, streak)) * 0.35)
    rgb = mix(rgb, solid(count, colour("MeadowFarmTimberGrain")), smoothstep(0.16, 0.0, within) * 0.75)
    rgb = lift(rgb, smoothstep(0.75, 0.98, within) * 0.15, toward=colour("MeadowFarmTimberLight"))
    joints = np.mod(around / 3.1 + _hash(row, 4.0, seed), 1.0)
    rgb = mix(rgb, solid(count, colour("MeadowFarmTimberGrain")), smoothstep(0.012, 0.0, np.minimum(joints, 1 - joints)) * 0.8)
    weather = smoothstep(0.15, 0.45, tiled_fbm(flat, 0.4, 2, period, seed + 9.0))
    rgb = mix(rgb, solid(count, colour("MeadowFarmRail")), weather * 0.35)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.2)


def _face_paint(count, pos2, seed, base="MeadowFarmShield", dark="MeadowFarmShieldDark"):
    """Flat sign paint: two greens in broad brush strokes running across, a little lighter where the brush lifted."""
    strokes = fbm(np.stack([pos2[:, 0] * 0.35, pos2[:, 1] * 2.6, np.full(count, seed)], axis=1), scale=1.6, octaves=3, seed=seed)
    tone = posterize(np.clip(0.5 + strokes * 1.6, 0, 1), 3)
    return ramp(tone, [(0.0, colour(dark)), (0.55, colour(base)), (1.0, colour(base))])


@brush("wood.sign_panel", version=1, material="painted wood", fixture="board", tint=False, styles=("painted-toon",), source=MEADOW + " (MeadowSignpost name board)", summary="The painted face of a sign board (object X across, Z up, facing -Y; half_width x half_height about centre_z): flat paint in broad brush strokes, a thin gold line `border` in from the edge, weathered chips showing timber near the rim, plain timber on the edges; the middle stays quiet so lettering laid over it reads")
def sign_panel(context, half_width, half_height, centre_z, border=0.12):
    """The painted face of a sign board (object space: X across, Z up, faces toward -Y): flat hedge-green paint in
    brush strokes, a thin gold line `border` in from the edge, weathered chips showing the timber near the rim. The
    middle stays plain and quiet, so lettering laid over it reads."""
    count = context.count
    local = context.local
    pos2 = np.stack([local[:, 0], local[:, 2] - centre_z], axis=1)
    rgb = _face_paint(count, pos2, 3.0)
    from_edge = np.minimum(half_width - np.abs(pos2[:, 0]), half_height - np.abs(pos2[:, 1]))
    line = smoothstep(0.035, 0.015, np.abs(from_edge - border))
    gold = ramp(posterize(np.clip(0.5 + fbm(local, scale=4.0, octaves=2, seed=5.0), 0, 1), 3), [(0.0, colour("MeadowFarmShieldRim")), (1.0, colour("MeadowStraw"))])
    rgb = mix(rgb, gold, line)
    chips = smoothstep(0.32, 0.4, fbm(local, scale=3.2, octaves=2, seed=9.0)) * smoothstep(0.2, 0.02, from_edge)
    rgb = mix(rgb, solid(count, colour("MeadowFarmTimberLight")), chips * 0.9)
    side = np.abs(context.normal[:, 1]) < 0.6
    rgb = np.where(side[:, None], solid(count, colour("MeadowFarmTimber")), rgb)
    return finish(rgb, context, ao_strength=0.6, edge_light=0.2)


@brush("wood.chalk_board", version=1, material="painted wood", fixture="board", tint=False, styles=("painted-toon",), source=MEADOW + " (hub quartermaster's price board)", summary="A shop's chalk price board (object X across, Z up; `half` = (x, z) of its face): dark slate-green board in a pine frame `frame` wide, chalked with `rows` rows of illegible scribbled prices, a loaf and coin doodled at the head, chalk smears")
def chalk_board(context, half, frame=0.18, rows=5, seed=0.0):
    """The quartermaster's price board: a dark slate-green board in a pine frame, chalked with rows of scribbled
    marks (prices with no legible text) and a little loaf and coin doodled at the head. half = (x, z) of the board's
    face in object space."""
    count = context.count
    x, z = context.local[:, 0], context.local[:, 2]
    rgb = ramp(posterize(np.clip(0.5 + fbm(context.pos, scale=1.5, octaves=2, seed=seed + 41.0) * 1.2, 0, 1), 3), [(0.0, colour("MeadowHubBoard")), (1.0, colour("MeadowHubBoardLight"))])
    smear = smoothstep(0.15, 0.45, fbm(context.pos * np.array((1.0, 1.0, 3.0)), scale=1.2, octaves=2, seed=seed + 43.0)) * 0.2
    rgb = mix(rgb, solid(count, colour("MeadowHubChalk")), smear * 0.5)
    inner_x, inner_z = half[0] - frame, half[1] - frame
    top = inner_z - 0.55
    pitch = (top + inner_z * 0.9) / rows
    row = np.floor((top - z) / pitch)
    within = (top - z) / pitch - row
    line = (1 - smoothstep(0.06, 0.12, np.abs(within - 0.5))) * (row >= 0) * (row < rows)
    jitter = fbm(np.stack([x * 6.0, row * 3.1, np.zeros(count)], axis=1), scale=1.0, octaves=1, seed=seed + 47.0)
    scribble = np.abs(np.sin(x * 26.0 + jitter * 6.0)) > 0.35
    word = (np.mod(x * 1.6 + row * 0.37, 1.0) < 0.72) & (x < inner_x * 0.15) & (x > -inner_x * 0.85)
    price = (x > inner_x * 0.45) & (x < inner_x * 0.85)
    chalk = line * scribble * (word | price)
    head = np.hypot((x + inner_x * 0.45) / 0.5, (z - (inner_z - 0.3)) / 0.22)
    loaf = (1 - smoothstep(0.9, 1.0, head)) * smoothstep(0.62, 0.72, head)
    coin = np.hypot(x - inner_x * 0.45, z - (inner_z - 0.3))
    coin_ring = (1 - smoothstep(0.17, 0.2, coin)) * smoothstep(0.1, 0.13, coin)
    chalk = np.clip(chalk + loaf + coin_ring, 0, 1)
    rgb = mix(rgb, solid(count, colour("MeadowHubChalk")), chalk * 0.85)
    margin = np.minimum(half[0] - np.abs(x), half[1] - np.abs(z))
    rim = 1 - smoothstep(frame - 0.02, frame, margin)
    wood = ramp(posterize(np.clip(0.5 + fbm(context.local, scale=2.0, octaves=2, seed=seed + 53.0) * 1.5, 0, 1), 3), [(0.0, colour("MeadowFairTimberDark")), (0.5, colour("MeadowFairTimber")), (1.0, colour("MeadowFairTimberLight"))])
    rgb = mix(rgb, wood, rim)
    return finish(rgb, context, ao_strength=0.5, edge_light=0.25)
