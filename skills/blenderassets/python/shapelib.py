"""shapelib: mesh builders for detailed, paintable blendlib assets (headless Blender 4.1+).

Everything here is deterministic run to run (same face order, same vertex positions), which paintlib's bake cache
relies on. Most builders also author the PaintCoord UV layer (paintlib.COORD) so painters can place seams,
stitches and trims exactly on the modelled geometry.

Lofts (shapes along a spine):
    ring_loft(name, centre, levels, ring, steps, caps, uniform)   levels: (z, half_width, front, back, exponent)
        superellipse rings up a vertical axis; uniform=True spaces ring vertices by arc length, so every
        `per_channel` vertex columns can become one quilted channel. PaintCoord = (fraction round, height).
    quilt_puffs(obj, per_channel, depth)       raise channels between stitched grooves on a uniform ring_loft
    Loft(...).build() / catmull(points, steps) / bump / bumps / relax / displace

Cloth and gear:
    cloth_band(name, target, path, widths, thickness, lift, ...)   a sewn band laid over target along a smooth
        path: rolled hems, drifting folds, closed; underside flagged ink_skip. PaintCoord = (across, along) studs.
    hanging_tail(name, top, width, length, ...)                    a hanging cloth tail, swallowtail-cut end
    gathered_knot(name, at, radii, creases, depth)                 a ball of gathered cloth
    roll_ring(name, profile, sides, channels, depth)               a quilted roll round the vertical axis (collar)
    channel_dome(obj, centre, channels, depth)                     quilt an ellipsoid into radial channels
    ellipsoid(name, radii, at, segments, rings)                    a UV ellipsoid with a fixed face order
    rounded_box(name, size, at, radius, segments)                  a bevelled box with the bevel applied
    ribbon_on(name, target, path, width, thickness)                a flat strap laid over target
    mark_ink_skip(obj, keep_out)                                   flag faces the ink outline leaves out
    tree(obj) / nearest(found, point)                              BVH lookups for laying things on surfaces
"""

import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import blendlib as bl
from paintlib import COORD, COORD_OFFSET, apply_modifiers


def catmull(points, steps):
    points = [np.asarray(point, dtype=np.float64) for point in points]
    extended = [2 * points[0] - points[1]] + points + [2 * points[-1] - points[-2]]
    lengths = [np.linalg.norm(extended[index + 1] - extended[index]) ** 0.5 + 1e-9 for index in range(len(extended) - 1)]
    out = []
    for segment in range(1, len(extended) - 2):
        p0, p1, p2, p3 = extended[segment - 1:segment + 3]
        t0 = 0.0
        t1 = t0 + lengths[segment - 1]
        t2 = t1 + lengths[segment]
        t3 = t2 + lengths[segment + 1]
        count = steps if segment < len(extended) - 3 else steps + 1
        for step in range(count):
            # centripetal Catmull-Rom (Barry-Goldman pyramid) evaluated at t in [t1, t2]
            t = t1 + (t2 - t1) * step / steps
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            out.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
    return np.array(out)


def ring_point(angle, half_width, up, down, exponent, top_width=1.0):
    cosine, sine = math.cos(angle), math.sin(angle)
    # superellipse |x/a|^n + |y/b|^n = 1 sampled by angle: x = a sgn(c)|c|^(2/n), y = b sgn(s)|s|^(2/n)
    power = 2.0 / exponent
    width = half_width * (1.0 + (top_width - 1.0) * max(sine, 0.0))
    across = width * math.copysign(abs(cosine) ** power, cosine)
    height = (up if sine >= 0 else down) * math.copysign(abs(sine) ** power, sine)
    return across, height


def ring_angles(ring, seam, half_width, up, down, exponent, top_width=1.0, uniform=False):
    if not uniform:
        return [seam + 2 * math.pi * step / ring for step in range(ring)]
    # equal arc length between ring vertices, so quilting channels built from vertex columns stay even
    dense = 2048
    angles = seam + 2 * math.pi * np.arange(dense + 1) / dense
    points = np.array([ring_point(angle, half_width, up, down, exponent, top_width) for angle in angles])
    walked = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))])
    return list(np.interp(walked[-1] * np.arange(ring) / ring, walked, angles))


class Loft:
    def __init__(self, name, spine, sections, ring=24, steps=4, side=(1.0, 0.0, 0.0), seam=-math.pi / 2, caps=(True, True), up=(0.0, 0.0, 1.0), uniform=False):
        self.name = name
        self.ring = ring
        self.side = np.asarray(side, dtype=np.float64)
        self.up = np.asarray(up, dtype=np.float64)
        self.seam = seam
        self.caps = caps
        self.uniform = uniform
        keys = ("w", "up", "down", "n", "wt")
        table = np.array([[section.get(key, 1.0) for key in keys] for section in sections], dtype=np.float64)
        centres = catmull([section["c"] for section in sections], steps)
        values = catmull(list(table), steps)
        self.centres = centres
        self.values = values

    def build(self):
        centres, values, ring = self.centres, self.values, self.ring
        count = len(centres)
        builder = bmesh.new()
        uv_layer = builder.loops.layers.uv.new("UVMap")
        coord_layer = builder.loops.layers.uv.new(COORD)
        step_layer = builder.verts.layers.int.new("loft_step")
        level_layer = builder.verts.layers.int.new("loft_level")
        rings = []
        tangents = []
        for index in range(count):
            ahead = centres[min(index + 1, count - 1)]
            behind = centres[max(index - 1, 0)]
            tangent = ahead - behind
            tangent /= max(np.linalg.norm(tangent), 1e-9)
            tangents.append(tangent)
        along = [0.0]
        for index in range(1, count):
            along.append(along[-1] + float(np.linalg.norm(centres[index] - centres[index - 1])))
        perimeters = []
        for index in range(count):
            tangent = tangents[index]
            side = self.side - tangent * float(np.dot(self.side, tangent))
            side /= max(np.linalg.norm(side), 1e-9)
            upward = self.up - tangent * float(np.dot(self.up, tangent)) - side * float(np.dot(self.up, side))
            upward /= max(np.linalg.norm(upward), 1e-9)
            half_width, up, down, exponent, top_width = values[index]
            vertices = []
            for step, angle in enumerate(ring_angles(ring, self.seam, half_width, up, down, exponent, top_width, self.uniform)):
                across, height = ring_point(angle, half_width, up, down, exponent, top_width)
                position = centres[index] + side * across + upward * height
                vertex = builder.verts.new(tuple(position))
                vertex[step_layer] = step
                vertex[level_layer] = index
                vertices.append(vertex)
            rings.append(vertices)
            perimeters.append(sum((vertices[step].co - vertices[(step + 1) % ring].co).length for step in range(ring)))
        widest = max(perimeters)
        for index in range(count - 1):
            for step in range(ring):
                corners = (rings[index][step], rings[index][(step + 1) % ring], rings[index + 1][(step + 1) % ring], rings[index + 1][step])
                face = builder.faces.new(corners)
                for loop, (u_step, v_index) in zip(face.loops, ((step, index), (step + 1, index), (step + 1, index + 1), (step, index + 1))):
                    loop[uv_layer].uv = (u_step / ring * widest, along[v_index])
                    # paint coordinate: fraction around the ring (1.0 on the wrap, never back to 0) and height
                    loop[coord_layer].uv = (u_step / ring + COORD_OFFSET, float(centres[v_index][2]) + COORD_OFFSET)
        for end, cap in ((0, self.caps[0]), (count - 1, self.caps[1])):
            if not cap:
                continue
            centre = builder.verts.new(tuple(centres[end]))
            centre[step_layer] = -1
            centre[level_layer] = -1
            for step in range(ring):
                corners = (rings[end][step], rings[end][(step + 1) % ring], centre)
                if end == 0:
                    corners = tuple(reversed(corners))
                face = builder.faces.new(corners)
                for loop in face.loops:
                    position = loop.vert.co - Vector(tuple(centres[end]))
                    loop[uv_layer].uv = (widest * 1.1 + position.x * 0.6 + (0.0 if end == 0 else 1.2), along[end] + position.z * 0.6)
                    loop[coord_layer].uv = (-1.0 + COORD_OFFSET, float(centres[end][2]) + COORD_OFFSET)
        bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
        mesh = bpy.data.meshes.new(self.name)
        builder.to_mesh(mesh)
        builder.free()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def bump(obj, centre, radii, amount, falloff=2.0):
    mesh = obj.data
    count = len(mesh.vertices)
    positions = np.empty(count * 3)
    mesh.vertices.foreach_get("co", positions)
    positions = positions.reshape(-1, 3)
    normals = _vertex_normals(mesh)
    scaled = (positions - np.asarray(centre)) / np.asarray(radii)
    weight = np.exp(-np.power(np.sum(scaled * scaled, axis=1), falloff / 2.0))
    positions += normals * (amount * weight)[:, None]
    mesh.vertices.foreach_set("co", positions.ravel())
    mesh.update()
    return obj


def bumps(obj, entries, mirror=False):
    for centre, radii, amount in entries:
        bump(obj, centre, radii, amount)
        if mirror and abs(centre[0]) > 1e-6:
            bump(obj, (-centre[0], centre[1], centre[2]), radii, amount)
    return obj


def relax(obj, iterations=2, factor=0.5):
    modifier = obj.modifiers.new("Relax", "SMOOTH")
    modifier.iterations = iterations
    modifier.factor = factor
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def displace(obj, function):
    mesh = obj.data
    count = len(mesh.vertices)
    positions = np.empty(count * 3)
    mesh.vertices.foreach_get("co", positions)
    positions = positions.reshape(-1, 3)
    normals = _vertex_normals(mesh)
    steps = np.empty(count, dtype=np.int32)
    levels = np.empty(count, dtype=np.int32)
    mesh.attributes["loft_step"].data.foreach_get("value", steps)
    mesh.attributes["loft_level"].data.foreach_get("value", levels)
    offsets = function(positions, normals, steps, levels)
    positions += normals * offsets[:, None]
    mesh.vertices.foreach_set("co", positions.ravel())
    mesh.update()
    return obj


def ring_loft(name, centre, levels, ring=24, steps=1, caps=(True, True), seam=-math.pi / 2, axis_up=(0.0, -1.0, 0.0), uniform=False):
    sections = []
    for height, width, front, back, exponent in levels:
        sections.append({"c": (centre[0], centre[1], height), "w": width, "up": front, "down": back, "n": exponent})
    return Loft(name, None, sections, ring=ring, steps=steps, caps=caps, seam=seam, up=axis_up, uniform=uniform).build()


def quilt_puffs(obj, per_channel, depth, groove=-0.004):
    # Columns of loft vertices become channels: the column on a channel line is the stitched groove,
    # the ones between rise in a rounded puff. Cap centres (step -1) stay put.
    profile = np.array([groove] + [math.sin(math.pi * index / per_channel) ** 0.7 * depth for index in range(1, per_channel)])

    def offsets(positions, normals, steps, levels):
        return np.where(steps >= 0, profile[np.mod(steps, per_channel)], 0.0)

    return displace(obj, offsets)

def link(name, builder):
    mesh = bpy.data.meshes.new(name)
    builder.to_mesh(mesh)
    builder.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tree(obj):
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(obj, depsgraph), obj.matrix_world.copy()


def nearest(found, point):
    bvh, matrix = found
    inverse = matrix.inverted()
    location, normal, _, _ = bvh.find_nearest(inverse @ Vector(point))
    return matrix @ location, (matrix.to_3x3() @ normal).normalized()


def ribbon_on(name, target, path, width, thickness, lift=0.015, samples=6, widths=None):
    found = tree(target)
    points = [Vector(point) for point in path]
    dense = []
    for index in range(len(points) - 1):
        for step in range(samples):
            dense.append(points[index].lerp(points[index + 1], step / samples))
    dense.append(points[-1])
    surface = [nearest(found, point) for point in dense]
    builder = bmesh.new()
    rows = []
    for index, (location, normal) in enumerate(surface):
        ahead = surface[min(index + 1, len(surface) - 1)][0]
        behind = surface[max(index - 1, 0)][0]
        tangent = (ahead - behind).normalized()
        across = normal.cross(tangent).normalized()
        half = (widths[index] if widths else width) / 2
        base = location + normal * lift
        corners = (base - across * half, base + across * half, base + across * half + normal * thickness, base - across * half + normal * thickness)
        rows.append([builder.verts.new(corner) for corner in corners])
    for first, second in zip(rows[:-1], rows[1:]):
        for index in range(4):
            builder.faces.new((first[index], first[(index + 1) % 4], second[(index + 1) % 4], second[index]))
    builder.faces.new(list(reversed(rows[0])))
    builder.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    if builder.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(builder, faces=builder.faces)
    return link(name, builder)


def rounded_box(name, size, at=(0.0, 0.0, 0.0), radius=0.08, segments=3):
    obj = bl.box(name, size, at=at, bevel=radius, segments=segments)
    apply_modifiers(obj)
    return obj


def ellipsoid(name, radii, at=(0.0, 0.0, 0.0), segments=16, rings=8):
    # built by hand rather than bmesh's create_uvsphere, whose face order changes from run to run and so
    # broke the bake cache (cached UVs are stored per face corner)
    builder = bmesh.new()
    top = builder.verts.new((0.0, 0.0, radii[2]))
    bands = []
    for ring in range(1, rings):
        polar = math.pi * ring / rings
        band = []
        for segment in range(segments):
            azimuth = math.tau * segment / segments
            band.append(builder.verts.new((radii[0] * math.sin(polar) * math.cos(azimuth), radii[1] * math.sin(polar) * math.sin(azimuth), radii[2] * math.cos(polar))))
        bands.append(band)
    bottom = builder.verts.new((0.0, 0.0, -radii[2]))
    for segment in range(segments):
        following = (segment + 1) % segments
        builder.faces.new((top, bands[0][following], bands[0][segment]))
        for upper, lower in zip(bands[:-1], bands[1:]):
            builder.faces.new((upper[segment], upper[following], lower[following], lower[segment]))
        builder.faces.new((bottom, bands[-1][segment], bands[-1][following]))
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    obj = link(name, builder)
    obj.location = at
    bl.flat(obj)
    return obj


def _relax_normals(normals, passes=3):
    out = [Vector(normal) for normal in normals]
    for _ in range(passes):
        out = [(out[max(index - 1, 0)] + out[index] * 2 + out[min(index + 1, len(out) - 1)]).normalized() for index in range(len(out))]
    return out


def mark_ink_skip(obj, keep_out):
    """Flag faces the outline hull should leave out: keep_out(normal, centre) -> bool, in world space."""
    mesh = obj.data
    attribute = mesh.attributes.get("ink_skip") or mesh.attributes.new("ink_skip", "INT", "FACE")
    matrix = obj.matrix_world
    rotation = matrix.to_3x3()
    flags = [int(bool(keep_out((rotation @ polygon.normal).normalized(), matrix @ polygon.center))) for polygon in mesh.polygons]
    attribute.data.foreach_set("value", flags)
    return obj


def _close(builder, rows, coords, layer, skip_span=None):
    # rows: rings of verts with a matching coord per vert; quads between rings, fan caps on both ends.
    # skip_span (first, last): ring positions whose quads are flagged ink_skip
    count = len(rows[0])
    skip = builder.faces.layers.int.new("ink_skip") if skip_span else None
    for first, second, first_coords, second_coords in zip(rows[:-1], rows[1:], coords[:-1], coords[1:]):
        for index in range(count):
            following = (index + 1) % count
            face = builder.faces.new((first[index], first[following], second[following], second[index]))
            for loop, value in zip(face.loops, (first_coords[index], first_coords[following], second_coords[following], second_coords[index])):
                loop[layer].uv = (value[0] + COORD_OFFSET, value[1] + COORD_OFFSET)
            if skip is not None:
                face[skip] = int(skip_span[0] <= index < skip_span[1])
    # caps as fans round the centroid: the rippled, hemmed cross-section is not convex, so an n-gon cap
    # can triangulate into faces that point backwards
    for ring, ring_coords in ((rows[0], coords[0]), (rows[-1], coords[-1])):
        middle = builder.verts.new(sum((vert.co for vert in ring), Vector()) / len(ring))
        centre_coord = (sum(value[0] for value in ring_coords) / len(ring), sum(value[1] for value in ring_coords) / len(ring))
        for index in range(count):
            following = (index + 1) % count
            face = builder.faces.new((ring[index], ring[following], middle))
            for loop, value in zip(face.loops, (ring_coords[index], ring_coords[following], centre_coord)):
                loop[layer].uv = (value[0] + COORD_OFFSET, value[1] + COORD_OFFSET)
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    if builder.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(builder, faces=builder.faces)


def cloth_band(name, target, path, widths, thickness, lift=0.05, steps=5, across=7, hem=0.016, folds=0.012, fold_turns=1.4, seed=0.0):
    """A sewn cloth band laid over `target` along a smooth path: a rolled hem just inside each edge and soft
    folds that drift along its length. Closed and capped. PaintCoord is (across, signed studs; along, studs)."""
    found = tree(target)
    dense = catmull(path, steps)
    half_widths = catmull([(width / 2, 0.0, 0.0) for width in widths], steps)[:, 0]
    surface = [nearest(found, point) for point in dense]
    locations = [location for location, _ in surface]
    normals = _relax_normals([normal for _, normal in surface])
    along = [0.0]
    for index in range(1, len(locations)):
        along.append(along[-1] + (locations[index] - locations[index - 1]).length)
    builder = bmesh.new()
    layer = builder.loops.layers.uv.new(COORD)
    rows, coords = [], []
    for index, (location, normal) in enumerate(zip(locations, normals)):
        tangent = (locations[min(index + 1, len(locations) - 1)] - locations[max(index - 1, 0)]).normalized()
        side = normal.cross(tangent).normalized()
        normal = tangent.cross(side).normalized()
        half = float(half_widths[index])
        ring, ring_coords = [], []
        for column in range(across):
            spread = -1.0 + 2.0 * column / (across - 1)
            rise = thickness + hem * math.exp(-((abs(spread) - 0.84) / 0.1) ** 2)
            rise += folds * math.sin(math.pi * fold_turns * spread + along[index] * 2.6 + seed) * (1.0 - spread ** 4)
            ring.append(builder.verts.new(location + normal * (lift + rise) + side * (spread * half)))
            ring_coords.append((spread * half, along[index]))
        for column in reversed(range(across)):
            spread = -1.0 + 2.0 * column / (across - 1)
            inset = 0.97 if abs(spread) > 0.99 else 1.0
            ring.append(builder.verts.new(location + normal * lift + side * (spread * half * inset)))
            ring_coords.append((spread * half * inset, along[index]))
        rows.append(ring)
        coords.append(ring_coords)
    # the underside lies on the body; outlining it only shows where the band lifts off (over a shoulder)
    _close(builder, rows, coords, layer, skip_span=(across, 2 * across - 1))
    obj = link(name, builder)
    obj["band_length"] = along[-1]
    obj["band_half_widths"] = [float(value) for value in half_widths]
    obj["band_along"] = along
    return obj


def hanging_tail(name, top, width, length, thickness=0.035, sway=(0.0, 0.0), facing=(0.0, -1.0, 0.0), flare=1.25, notch=0.08, rows=9, across=5, folds=0.022, lift_off=0.05, seed=0.0):
    """A cloth tail hanging from `top`: folds across it, a slight sway, lifting off what it hangs over, and a
    swallowtail-cut end. PaintCoord is (across, signed studs; down from the top, studs)."""
    top = Vector(top)
    facing = Vector(facing).normalized()
    down = Vector((sway[0], sway[1], -1.0)).normalized()
    side = down.cross(facing).normalized()
    normal = side.cross(down).normalized()
    builder = bmesh.new()
    layer = builder.loops.layers.uv.new(COORD)
    rings, coords = [], []
    for row in range(rows):
        fraction = row / (rows - 1)
        ring, ring_coords = [], []
        offsets = []
        for column in range(across):
            spread = -1.0 + 2.0 * column / (across - 1)
            end = length - notch * (1.0 - abs(spread))
            travelled = fraction * end
            half = width / 2 * (1.0 + (flare - 1.0) * fraction)
            fold = folds * math.sin(math.pi * 1.3 * spread + seed + fraction * 1.7) * (0.35 + 0.65 * fraction)
            centre = top + down * travelled + normal * (lift_off * fraction * fraction + fold)
            offsets.append((centre + side * (spread * half), spread * half, travelled))
        for point, across_value, travelled in offsets:
            ring.append(builder.verts.new(point + normal * (thickness / 2)))
            ring_coords.append((across_value, travelled))
        for point, across_value, travelled in reversed(offsets):
            ring.append(builder.verts.new(point - normal * (thickness / 2)))
            ring_coords.append((across_value, travelled))
        rings.append(ring)
        coords.append(ring_coords)
    _close(builder, rings, coords, layer)
    return link(name, builder)


def _vertex_normals(mesh):
    # read through bmesh: a mesh just transformed can hand back stale vertex normals, which made the
    # displaced shapes differ from run to run
    builder = bmesh.new()
    builder.from_mesh(mesh)
    builder.normal_update()
    normals = np.array([vertex.normal[:] for vertex in builder.verts], dtype=np.float64)
    builder.free()
    return normals


def gathered_knot(name, at, radii, creases=7, depth=0.028, facing=(0.0, -1.0, 0.0), segments=24, rings=10):
    """A ball of gathered cloth: folds radiate from the front where the fabric is pinched."""
    knot = ellipsoid(name, radii, segments=segments, rings=rings)
    facing = np.asarray(facing, dtype=np.float64)
    facing /= np.linalg.norm(facing)
    helper = np.array((0.0, 0.0, 1.0)) if abs(facing[2]) < 0.9 else np.array((1.0, 0.0, 0.0))
    first = np.cross(facing, helper)
    first /= np.linalg.norm(first)
    second = np.cross(facing, first)
    mesh = knot.data
    count = len(mesh.vertices)
    positions = np.empty(count * 3)
    mesh.vertices.foreach_get("co", positions)
    positions = positions.reshape(-1, 3)
    normals = _vertex_normals(mesh)
    unit = positions / np.asarray(radii)
    azimuth = np.arctan2(unit @ second, unit @ first)
    latitude = np.clip(unit @ facing, -1.0, 1.0)
    crease = (np.abs(np.sin(azimuth * creases / 2)) ** 0.6 - 0.55) * depth * (1.0 - np.abs(latitude) ** 3)
    positions += normals * crease[:, None]
    mesh.vertices.foreach_set("co", positions.ravel())
    mesh.update()
    knot.data.transform(Matrix.Translation(Vector(at)))
    return knot


def _channel_profile(per_channel, depth, groove=-0.004):
    return np.array([groove] + [math.sin(math.pi * index / per_channel) ** 0.7 * depth for index in range(1, per_channel)])


def roll_ring(name, profile, sides=48, channels=16, depth=0.025, centre=(0.0, 0.0)):
    """A padded roll around the vertical axis (a quilted collar). `profile` is a closed loop of (radius, z);
    every sides/channels columns make one stitched channel. PaintCoord is (channel phase, loop fraction)."""
    per_channel = sides // channels
    puff = _channel_profile(per_channel, depth)
    builder = bmesh.new()
    layer = builder.loops.layers.uv.new(COORD)
    columns = []
    for step in range(sides):
        angle = math.tau * step / sides
        radial = Vector((math.cos(angle), math.sin(angle), 0.0))
        lift = float(puff[step % per_channel])
        columns.append([builder.verts.new((centre[0] + radial.x * (radius + lift), centre[1] + radial.y * (radius + lift), height)) for radius, height in profile])
    points = len(profile)
    for step in range(sides):
        following = (step + 1) % sides
        for index in range(points):
            upper = (index + 1) % points
            face = builder.faces.new((columns[step][index], columns[following][index], columns[following][upper], columns[step][upper]))
            for loop, (u_step, v_index) in zip(face.loops, ((step, index), (step + 1, index), (step + 1, index + 1), (step, index + 1))):
                loop[layer].uv = (u_step / per_channel + COORD_OFFSET, v_index / points + COORD_OFFSET)
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    if builder.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(builder, faces=builder.faces)
    return link(name, builder)


def channel_dome(obj, centre, channels=16, depth=0.03, axis=(0.0, 0.0, 1.0)):
    """Quilt an ellipsoid (a shoulder pad) into channels radiating around `axis`, puffs modelled and the
    channel phase written to PaintCoord (u, with the wrap kept continuous per face; v = height)."""
    mesh = obj.data
    count = len(mesh.vertices)
    positions = np.empty(count * 3)
    mesh.vertices.foreach_get("co", positions)
    positions = positions.reshape(-1, 3)
    normals = _vertex_normals(mesh)
    axis = np.asarray(axis, dtype=np.float64)
    helper = np.array((1.0, 0.0, 0.0))
    first = helper - axis * (helper @ axis)
    first /= np.linalg.norm(first)
    second = np.cross(axis, first)
    relative = positions - np.asarray(centre)
    phase = (np.arctan2(relative @ second, relative @ first) / math.tau % 1.0) * channels
    fraction = phase - np.floor(phase)
    puff = np.sin(math.pi * fraction) ** 0.7 * depth - 0.004
    pole = np.clip(np.abs(normals @ axis), 0.0, 1.0)
    positions += normals * (puff * (1.0 - pole ** 4))[:, None]
    mesh.vertices.foreach_set("co", positions.ravel())
    layer = mesh.uv_layers.get(COORD) or mesh.uv_layers.new(name=COORD)
    corner_vertices = np.empty(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", corner_vertices)
    values = np.stack([phase[corner_vertices], positions[corner_vertices, 2]], axis=1)
    for polygon in mesh.polygons:
        span = slice(polygon.loop_start, polygon.loop_start + polygon.loop_total)
        u = values[span, 0]
        if u.max() - u.min() > channels / 2:
            values[span, 0] = np.where(u < channels / 2, u + channels, u)
    layer.data.foreach_set("uv", (values + COORD_OFFSET).ravel())
    mesh.update()
    return obj


