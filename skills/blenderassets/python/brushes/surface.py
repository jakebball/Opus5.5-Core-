"""brushes.surface: helpers shared by the course-laid and tiling brushes (stone, roof, water, plant, fibre, and
the castle-scale cloth): a cell hash, surface coordinates for laying courses, noise that repeats exactly every
tile, a run frame for corner pieces, a seam-safe wall light, and object-space normals. No brushes live here.

Copied verbatim from Joust Tycoon's castle painters (blender-source/castle/castlepaint.py, paint_ground.py,
paint_wall.py, paint_props.py; Rebirth 0 castle, approved 2026-10-05), so the promoted brushes paint exactly what
the castle's own copies paint."""

import math

import numpy as np

from paintlib import GRADIENTS, PERMUTATION, Context, _fade


def _hash(first, second, seed=0.0):
    value = np.sin(first * 127.1 + second * 311.7 + seed * 74.7) * 43758.5453
    return value - np.floor(value)


def _fraction(value):
    return value - np.floor(value)


def _local_normal(context, rotation):
    if rotation is None:
        return context.normal
    # world -> object: n_local = R^T n, written for row vectors
    return context.normal @ np.asarray(rotation)


def _surface_uv(context, around=None):
    """Surface coordinates in studs for laying courses: arc length round a vertical axis when `around` = (x, y)
    is given (radial faces fall back to distance from the axis), else the dominant-axis projection. Tops and
    undersides get (x, y)."""
    pos, normal = context.pos, context.normal
    flat = np.abs(normal[:, 2]) > 0.75
    if around is not None:
        offset_x, offset_y = pos[:, 0] - around[0], pos[:, 1] - around[1]
        radius = np.maximum(np.hypot(offset_x, offset_y), 1e-3)
        radial = np.stack([offset_x / radius, offset_y / radius], axis=1)
        tangent_facing = np.abs(normal[:, 0] * -radial[:, 1] + normal[:, 1] * radial[:, 0]) > 0.7
        reference = around[2] if len(around) > 2 else 1.0
        # arc length measured at a fixed reference radius, so courses line up from the base batter to the parapet
        arc = np.arctan2(offset_y, offset_x) * reference
        u = np.where(tangent_facing, radius, arc)
    else:
        use_y = np.abs(normal[:, 0]) > np.abs(normal[:, 1])
        u = np.where(use_y, pos[:, 1], pos[:, 0])
    v = pos[:, 2]
    u = np.where(flat, pos[:, 0], u)
    v = np.where(flat, pos[:, 1], v)
    return u, v, flat


def _perlin(points, period):
    floor = np.floor(points)
    cell = floor.astype(np.int64)
    local = points - floor
    weights = _fade(local)

    def index(axis, step):
        value = cell[:, axis] + step
        if period[axis]:
            value = np.mod(value, period[axis])
        return value & 255

    corners = {}
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                hashed = PERMUTATION[PERMUTATION[PERMUTATION[index(0, dx)] + index(1, dy)] + index(2, dz)] % 12
                offset = local - np.array((dx, dy, dz), dtype=np.float64)
                corners[(dx, dy, dz)] = np.einsum("ij,ij->i", GRADIENTS[hashed], offset)
    wx, wy, wz = weights[:, 0], weights[:, 1], weights[:, 2]
    x00 = corners[(0, 0, 0)] * (1 - wx) + corners[(1, 0, 0)] * wx
    x10 = corners[(0, 1, 0)] * (1 - wx) + corners[(1, 1, 0)] * wx
    x01 = corners[(0, 0, 1)] * (1 - wx) + corners[(1, 0, 1)] * wx
    x11 = corners[(0, 1, 1)] * (1 - wx) + corners[(1, 1, 1)] * wx
    return (x00 * (1 - wy) + x10 * wy) * (1 - wz) + (x01 * (1 - wy) + x11 * wy) * wz


def tiled_fbm(points, scale=1.0, octaves=3, period=(0.0, 0.0, 0.0), seed=0.0):
    """paintlib.fbm that repeats every period[axis] studs (0 = free). The scale on a periodic axis is rounded so a
    whole number of noise cells fits the period."""
    points = np.asarray(points, dtype=np.float64)
    scales, cells = [], []
    for axis in range(3):
        if period[axis]:
            count = max(1, round(period[axis] * scale))
            scales.append(count / period[axis])
            cells.append(count)
        else:
            scales.append(scale)
            cells.append(0)
    scaled = points * np.array(scales)
    value = np.zeros(len(points))
    amplitude, total = 1.0, 0.0
    for octave in range(octaves):
        factor = 2 ** octave
        shift = seed * 17.0 + octave * 31.0
        value += amplitude * _perlin(scaled * factor + shift, [cell * factor for cell in cells])
        total += amplitude
        amplitude *= 0.5
    return value / total


def run_frame(pos, normal=None, swap=False, along=0.0):
    """Map corner-piece points into a straight run's frame for pattern lookups: swap turns a run along Y (offsets
    toward +X) into the run frame (x, y) -> (y, -x); along slides it along the run so the pattern continues from the
    run's end."""
    if swap:
        pos = np.stack((pos[:, 1], -pos[:, 0], pos[:, 2]), axis=1)
        if normal is not None:
            normal = np.stack((normal[:, 1], -normal[:, 0], normal[:, 2]), axis=1)
    pos = pos + np.array((along, 0.0, 0.0))
    return pos, normal


def wall_light(context, seam=None):
    """The context the finish sees on a wall that is turned to face every side: +Y normals mirrored to -Y (so the
    inner face is lit like the outer one), and edge light removed on the butt joints at |x| = seam (they are hidden
    by the next section)."""
    normal = context.normal.copy()
    normal[:, 1] = -np.abs(normal[:, 1])
    edge = context.edge
    if seam is not None:
        joint = (np.abs(np.abs(context.pos[:, 0]) - seam) < 0.22) & (np.abs(context.normal[:, 0]) < 0.6)
        edge = np.where(joint, 0.0, edge)
    return Context(context.pos, normal, context.ao, context.curvature, edge, context.local, context.coord)


def _ring(pos, period):
    # wrap X onto a circle whose circumference is the period, so 3D noise repeats every section; radius grows a
    # little with depth so the courtyard face does not copy the outer face's mottling
    theta = pos[:, 0] * (math.tau / period)
    radius = period / math.tau + pos[:, 1] * 0.15
    return np.stack([radius * np.cos(theta), radius * np.sin(theta), pos[:, 2]], axis=1)
