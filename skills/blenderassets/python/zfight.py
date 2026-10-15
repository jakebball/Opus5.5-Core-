"""Z-fighting check, run by blendlib.finish() on every build (added 2026-10-16 from the GetAdopted Chef house).

Finds faces of different objects that lie in the same plane (within TOL studs), face the same way, have different
colours and overlap by more than MIN_AREA square studs, where the overlap can be seen: at least a third of the
samples over it, nudged 0.03 studs off the face, are outside every other solid. Those flicker in Roblox.

Not reported: back-to-back faces (one is always culled), same-colour overlaps (no visible flicker), overlaps buried
inside another solid, and downward faces resting on the asset's base or hovering within a stud of a solid below.
Every pair is written to <out>/zfight.txt; finish() prints the worst as warnings. Set BLENDLIB_ZFIGHT=0 to skip.
Fix by moving one face off the plane (0.03+ studs), shrinking a piece so its face ends inside the other, or
standing wall pieces 0.05 off the wall.
"""

import math
from collections import defaultdict

import bpy

TOL = 0.02
MIN_AREA = 0.02


def _faces():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    out = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        matrix = obj.matrix_world
        normal_matrix = matrix.to_3x3().inverted_safe().transposed()
        verts = [matrix @ v.co for v in mesh.vertices]
        attribute = mesh.color_attributes.get("Col") if hasattr(mesh, "color_attributes") else None
        fallback = None
        if obj.material_slots and obj.material_slots[0].material:
            fallback = tuple(round(c, 2) for c in obj.material_slots[0].material.diffuse_color[:3])
        for poly in mesh.polygons:
            if poly.area < 1e-4:
                continue
            normal = (normal_matrix @ poly.normal).normalized()
            points = [verts[i] for i in poly.vertices]
            colour = fallback
            if attribute is not None:
                index = poly.loop_start if attribute.domain == "CORNER" else poly.vertices[0]
                colour = tuple(round(c, 2) for c in attribute.data[index].color[:3])
            out.append((obj.name, normal, normal.dot(points[0]), points, colour))
        evaluated.to_mesh_clear()
    return out


def _project(points, normal):
    axis = max(range(3), key=lambda i: abs(normal[i]))
    keep = [i for i in range(3) if i != axis]
    flat = [(p[keep[0]], p[keep[1]]) for p in points]
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(flat, flat[1:] + flat[:1]))
    return flat if area > 0 else flat[::-1]


def _clip(subject, clip):
    """Sutherland-Hodgman: subject polygon clipped by a convex counter-clockwise polygon."""
    output = subject
    for a, b in zip(clip, clip[1:] + clip[:1]):
        if not output:
            break
        source, output = output, []
        inside = lambda p: (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9
        for p, q in zip(source, source[1:] + source[:1]):
            if inside(q):
                if not inside(p):
                    output.append(_cross(p, q, a, b))
                output.append(q)
            elif inside(p):
                output.append(_cross(p, q, a, b))
    return output


def _cross(p, q, a, b):
    dx, dy = q[0] - p[0], q[1] - p[1]
    ex, ey = b[0] - a[0], b[1] - a[1]
    denominator = dx * ey - dy * ex
    if abs(denominator) < 1e-12:
        return q
    t = ((a[0] - p[0]) * ey - (a[1] - p[1]) * ex) / denominator
    return (p[0] + t * dx, p[1] + t * dy)


def _area(poly):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))) / 2


def _part(name):
    obj = bpy.data.objects.get(name)
    return (obj.get("roblox_part") if obj else None) or name.rsplit("_", 1)[0]


def _unproject(flat_point, normal, d):
    axis = max(range(3), key=lambda i: abs(normal[i]))
    keep = [i for i in range(3) if i != axis]
    point = [0.0, 0.0, 0.0]
    point[keep[0]], point[keep[1]] = flat_point
    point[axis] = (d - normal[keep[0]] * point[keep[0]] - normal[keep[1]] * point[keep[1]]) / normal[axis]
    return point


class _Cover:
    """Answers "is this point inside some solid?" using each object's local bounding box (exact for the box
    primitives buildings are made of), bucketed in a coarse world grid."""

    CELL = 4.0

    def __init__(self):
        from mathutils import Vector
        self.Vector = Vector
        self.grid = defaultdict(list)
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH" or obj.hide_render:
                continue
            corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
            lo = [min(c[i] for c in corners) for i in range(3)]
            hi = [max(c[i] for c in corners) for i in range(3)]
            local = [tuple(c) for c in obj.bound_box]
            box_lo = [min(c[i] for c in local) for i in range(3)]
            box_hi = [max(c[i] for c in local) for i in range(3)]
            entry = (obj.matrix_world.inverted(), box_lo, box_hi)
            for gx in range(int(math.floor(lo[0] / self.CELL)), int(math.floor(hi[0] / self.CELL)) + 1):
                for gy in range(int(math.floor(lo[1] / self.CELL)), int(math.floor(hi[1] / self.CELL)) + 1):
                    for gz in range(int(math.floor(lo[2] / self.CELL)), int(math.floor(hi[2] / self.CELL)) + 1):
                        self.grid[(gx, gy, gz)].append(entry)

    def covered(self, point):
        cell = tuple(int(math.floor(c / self.CELL)) for c in point)
        world = self.Vector(point)
        for inverse, lo, hi in self.grid.get(cell, ()):
            p = inverse @ world
            if all(lo[i] + 1e-4 < p[i] < hi[i] - 1e-4 for i in range(3)):
                return True
        return False


def _visible(cover, clipped, normal, d, base):
    """True when at least a third of the samples over the overlap, nudged 0.03 studs off the face, are outside every
    other solid. A downward face hovering within 0.6 studs of a solid below it (a prop's underside on the floor)
    never shows and is skipped."""
    cx = sum(p[0] for p in clipped) / len(clipped)
    cy = sum(p[1] for p in clipped) / len(clipped)
    samples = [(cx, cy)] + [(cx + (p[0] - cx) * f, cy + (p[1] - cy) * f) for p in clipped for f in (0.4, 0.85)]
    clear = 0
    for flat in samples:
        point = _unproject(flat, normal, d)
        nudged = [point[i] + normal[i] * 0.03 for i in range(3)]
        if normal[2] < -0.9 and (point[2] <= base + 0.1 or any(cover.covered([point[0], point[1], point[2] - drop]) for drop in (0.3, 0.6, 1.0))):
            continue
        if not cover.covered(nudged):
            clear += 1
    return clear * 3 >= len(samples)


def find(hidden=False):
    """Coplanar same-facing overlaps between different objects. hidden=True also returns ones buried under
    another solid (which never show)."""
    groups = defaultdict(list)
    faces_all = _faces()
    base = min((p[2] for face in faces_all for p in face[3]), default=0.0)
    for name, normal, d, points, colour in faces_all:
        key = tuple(round(c, 2) for c in normal)
        groups[key].append((d, name, points, normal, colour))
    cover = None if hidden else _Cover()
    hits = {}
    for key, faces in groups.items():
        faces.sort(key=lambda f: f[0])
        start = 0
        for i, (d, name, points, normal, colour) in enumerate(faces):
            while faces[start][0] < d - TOL:
                start += 1
            flat = None
            for j in range(start, i):
                other = faces[j]
                if other[1] == name or (colour is not None and colour == other[4]):
                    continue
                if flat is None:
                    flat = _project(points, normal)
                    lo = (min(p[0] for p in flat), min(p[1] for p in flat))
                    hi = (max(p[0] for p in flat), max(p[1] for p in flat))
                oflat = _project(other[2], normal)
                if max(p[0] for p in oflat) <= lo[0] or min(p[0] for p in oflat) >= hi[0] or max(p[1] for p in oflat) <= lo[1] or min(p[1] for p in oflat) >= hi[1]:
                    continue
                clipped = _clip(flat, oflat) if len(oflat) >= 3 else []
                overlap = _area(clipped) if len(clipped) >= 3 else 0.0
                if overlap <= MIN_AREA:
                    continue
                if cover is not None and not _visible(cover, clipped, normal, d, base):
                    continue
                pair = tuple(sorted((_part(name), _part(other[1]))))
                cx = sum(p[0] for p in clipped) / len(clipped)
                cy = sum(p[1] for p in clipped) / len(clipped)
                centre = tuple(round(c, 1) for c in _unproject((cx, cy), normal, d))
                best = hits.get(pair)
                if best is None or overlap > best[0]:
                    hits[pair] = (overlap, centre, tuple(round(c, 2) for c in normal), abs(d - other[0]))
    return hits


def warnings(out_dir, limit=12):
    """Warning lines for blendlib.finish(): a summary plus the largest visible pairs; the full list goes to
    <out_dir>/zfight.txt."""
    import os
    hits = find()
    ranked = sorted(hits.items(), key=lambda item: -item[1][0])
    lines = [f"ZFIGHT  {a} | {b}  area {area:.2f}  at {centre}  normal {normal}  gap {gap:.3f}" for (a, b), (area, centre, normal, gap) in ranked]
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "zfight.txt"), "w", encoding="utf-8") as handle:
        handle.write("\n".join([f"{len(hits)} visible z-fighting pairs (tol {TOL}, min area {MIN_AREA})"] + lines) + "\n")
    if not hits:
        return []
    out = [f"z-fighting: {len(hits)} visible coplanar overlaps (all in zfight.txt); largest:"]
    for (a, b), (area, centre, normal, gap) in ranked[:limit]:
        out.append(f"  {a} | {b}: {area:.2f} sq studs at {centre}, facing {normal}")
    return out


def report(limit=200):
    """Print the pairs and write them to <out>/zfight.txt (blend.js does not echo Blender's stdout)."""
    import os
    import blendlib as bl
    hits = find()
    lines = [f"ZFIGHT {len(hits)} visible coplanar overlapping pairs (tol {TOL}, min area {MIN_AREA})"]
    for (a, b), (area, centre, normal, gap) in sorted(hits.items(), key=lambda item: -item[1][0])[:limit]:
        lines.append(f"ZFIGHT  {a} | {b}  area {area:.2f}  at {centre}  normal {normal}  gap {gap:.3f}")
    text = "\n".join(lines) + "\n"
    print(text)
    os.makedirs(bl.OUT, exist_ok=True)
    with open(os.path.join(bl.OUT, "zfight.txt"), "w", encoding="utf-8") as handle:
        handle.write(text)
    return hits
