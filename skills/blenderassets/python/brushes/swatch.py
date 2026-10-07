"""Renders the brush library's swatches and catalog. Run through blend.js (it needs Blender):

    node <skill>/blend.js brushes [--style NAME] [--role ROLE]      (passed on as BRUSH_STYLE / BRUSH_ROLE)

For every style in brushes/styles/, each role's brush is painted on its fixture (a test shape that gives the brush
the geometry it needs) under that style's finish, rendered to brushes/swatches/tiles/<style>/<role>.png and
composed into brushes/swatches/<style>.png. Then brushes/catalog.json and brushes/CATALOG.md are rewritten from
the registry and the style files, so any session can read the library without running Blender.
"""

import json
import math
import os
import sys
import tempfile

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import blendlib as bl
import brushes
import paintlib
import shapelib
from brushes import sheet

HERE = os.path.dirname(os.path.abspath(__file__))
SWATCHES = os.path.join(HERE, "swatches")
CACHE = os.path.join(tempfile.gettempdir(), "blenderassets-brush-swatches")
TILE = 320
HOST_COLOUR = "8C919C"


def _perimeter(half_width, front, back, exponent):
    angles = np.linspace(0.0, math.tau, 721)
    points = np.array([shapelib.ring_point(angle, half_width, front, back, exponent) for angle in angles])
    return float(np.linalg.norm(np.diff(points, axis=0), axis=1).sum())


def _host(obj):
    obj["solid_colour"] = HOST_COLOUR
    bl.paint(obj, HOST_COLOUR)
    return obj


def fixture_box():
    piece = bl.smooth(shapelib.rounded_box("Swatch", (1.2, 1.2, 1.2), at=(0.0, 0.0, 0.6), radius=0.06, segments=2), 40)
    return [piece], {}, []


def fixture_cylinder():
    piece = bl.smooth(bl.cylinder("Swatch", 0.32, 1.8, sides=24, at=(0.0, 0.0, 0.9)), 50)
    return [piece], {"axis": 2}, []


def fixture_points():
    piece = bl.smooth(shapelib.rounded_box("Swatch", (1.2, 1.2, 1.2), at=(0.0, 0.0, 0.6), radius=0.06, segments=2), 40)
    centres = [(x, -0.6, z) for x in (-0.35, 0.0, 0.35) for z in (0.3, 0.9)]
    return [piece], {"centres": centres, "radius": 0.07, "studs": centres}, []


def fixture_ring():
    levels = [(0.0, 0.6, 0.6, 0.6, 2.0), (0.03, 0.64, 0.64, 0.64, 2.0), (0.37, 0.64, 0.64, 0.64, 2.0), (0.4, 0.6, 0.6, 0.6, 2.0)]
    piece = bl.smooth(shapelib.ring_loft("Swatch", (0.0, 0.0), levels, ring=64, steps=1, uniform=True), 50)
    perimeter = _perimeter(0.64, 0.64, 0.64, 2.0)
    return [piece], {"rows": (0.07, 0.33), "centre": 0.2, "pitch": perimeter, "studs": 0.2, "count_around": 14, "perimeter": perimeter}, []


def fixture_sleeve():
    levels = [(2.6, 0.6, 0.6, 0.6, 4.2), (2.82, 0.64, 0.64, 0.64, 4.2), (3.0, 0.615, 0.615, 0.615, 4.2), (3.18, 0.645, 0.645, 0.645, 4.2), (3.36, 0.62, 0.62, 0.62, 4.2), (3.56, 0.65, 0.65, 0.65, 4.2), (3.78, 0.625, 0.625, 0.625, 4.2)]
    piece = bl.smooth(shapelib.ring_loft("Swatch", (1.5, 0.0), levels, ring=24, steps=1, uniform=True), 70)
    return [piece], {"pitch": 0.33, "origin": 2.45}, []


def fixture_channels():
    channels = 24
    levels = [(0.0, 0.62, 0.5, 0.5, 4.0), (0.6, 0.66, 0.54, 0.54, 4.0), (1.2, 0.62, 0.5, 0.5, 4.0)]
    piece = shapelib.ring_loft("Swatch", (0.0, 0.0), levels, ring=channels * 4, steps=2, uniform=True)
    shapelib.quilt_puffs(piece, 4, depth=0.04)
    bl.smooth(piece, 50)
    perimeter = _perimeter(0.66, 0.54, 0.54, 4.0)
    return [piece], {"scale": channels, "pitch": perimeter / channels, "rows": 0.3, "row_offset": 0.0}, []


def fixture_band():
    host = _host(bl.smooth(shapelib.rounded_box("Host", (1.4, 1.0, 1.0), at=(0.0, 0.0, 0.5), radius=0.05, segments=2), 40))
    path = [(0.0, -0.62, 0.08), (0.0, -0.62, 0.7), (0.0, -0.35, 1.06), (0.0, 0.35, 1.06), (0.0, 0.62, 0.7), (0.0, 0.62, 0.08)]
    piece = bl.smooth(shapelib.cloth_band("Swatch", host, path, [0.42] * len(path), thickness=0.03, lift=0.035, steps=5, across=7), 40)
    options = {"along_samples": list(piece["band_along"]), "half_samples": list(piece["band_half_widths"]), "half": 0.21, "length": float(piece["band_length"]), "cloth": "PatchRed"}
    return [piece], options, [host]


def fixture_tail():
    piece = bl.smooth(shapelib.hanging_tail("Swatch", (0.0, 0.0, 1.4), 0.32, 1.2, thickness=0.04, flare=1.3, notch=0.12, folds=0.03), 50)
    return [piece], {"length": 1.2, "notch": 0.12, "half_top": 0.16, "half_end": 0.208}, []


def fixture_knot():
    piece = bl.smooth(shapelib.gathered_knot("Swatch", (0.0, 0.0, 0.4), (0.42, 0.28, 0.34), creases=7, depth=0.05), 60)
    return [piece], {}, []


def fixture_dome():
    piece = bl.smooth(shapelib.ellipsoid("Swatch", (0.9, 0.6, 0.55), at=(0.0, 0.0, 0.55), segments=32, rings=16), 80)
    return [piece], {"flow": (0.0, 1.0, -0.35)}, []


# ---- castle-scale fixtures (Joust Tycoon castle, 2026-10-05): real stud sizes, so masonry, tiles and flags show
# at the size they paint in a game

def _mesh(name, verts, faces, recalc=True):
    """A mesh object from vertex and face lists; recalc makes a closed mesh's normals point outward (open sheets
    keep their authored winding)."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(vert) for vert in verts], [], [tuple(face) for face in faces])
    if recalc:
        builder = bmesh.new()
        builder.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
        builder.to_mesh(mesh)
        builder.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return bl.flat(obj)


def _outward(obj):
    builder = bmesh.new()
    builder.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    builder.to_mesh(obj.data)
    builder.free()
    return obj


def fixture_drum():
    piece = bl.smooth(bl.cylinder("Swatch", 3.0, 4.0, sides=40, at=(0.0, 0.0, 2.0)), 50)
    return [piece], {"around": (0.0, 0.0, 3.0), "centre": (0.0, 0.0), "radius": 3.0}, []


def fixture_wall():
    piece = bl.smooth(shapelib.rounded_box("Swatch", (10.0, 1.6, 3.0), at=(0.0, 0.0, 0.0), radius=0.06, segments=2), 40)
    return [piece], {"period": (10.0, 0.0, 0.0)}, []


def fixture_cone():
    piece = bl.smooth(_outward(bl.lathe("Swatch", [(0.0, 0.0), (3.2, 0.0), (0.0, 4.4)], sides=40)), 60)
    return [piece], {"around": (0.0, 0.0, 3.2)}, []


def fixture_banner():
    piece = bl.smooth(shapelib.hanging_tail("Swatch", (0.0, 0.0, 7.2), 2.8, 7.0, thickness=0.12, flare=1.05, notch=0.85, rows=12, across=7, folds=0.18, lift_off=0.0), 50)
    return [piece], {"length": 7.0, "half_top": 1.4, "half_end": 1.47, "notch": 0.85}, []


def fixture_valance():
    top, notch, point, pitch, dags = 1.3, 0.42, 0.95, 2.5, 3
    verts, faces = [], []
    for dag in range(dags):
        left = -pitch * dags / 2 + dag * pitch
        start = len(verts)
        for index, tip in enumerate((0, 1, 0)):
            x = left + index * pitch / 2
            verts += [(x, 0.0, top), (x, -0.07 * tip, top - (point if tip else notch))]
        faces += [(start, start + 1, start + 3, start + 2), (start + 2, start + 3, start + 5, start + 4)]
    piece = _mesh("Swatch", verts, faces, recalc=False)
    solidify = piece.modifiers.new("Solidify", "SOLIDIFY")
    solidify.thickness = 0.06
    solidify.offset = 1.0
    host = _host(bl.smooth(shapelib.rounded_box("Host", (pitch * dags, 1.0, 2.2), at=(0.0, 0.6, 0.4), radius=0.05, segments=2), 40))
    return [piece], {"top": top, "pitch": pitch, "notch": notch, "point": point, "period": pitch * dags}, [host]


def fixture_plane():
    piece = bl.smooth(shapelib.rounded_box("Swatch", (9.45, 9.45, 0.3), at=(0.0, 0.0, -0.15), radius=0.03, segments=1), 40)
    return [piece], {"tile": 9.45, "rows": 4}, []


def fixture_pool():
    piece = bl.box("Swatch", (10.0, 10.0, 0.2), at=(0.0, 0.0, -0.1))
    post = _host(bl.smooth(bl.cylinder("Post", 0.9, 3.0, sides=16, at=(1.4, 1.2, 0.5)), 50))
    return [piece], {}, [post]


def fixture_bank():
    piece = bl.smooth(shapelib.rounded_box("Swatch", (4.0, 3.0, 1.2), at=(0.0, 0.0, 0.6), radius=0.35, segments=3), 40)
    return [piece], {}, []


def fixture_blades():
    verts, faces = [], []
    for blade in range(7):
        angle = blade * 2.39996
        spread = 0.18 + 0.12 * (blade % 3)
        bx, by = math.cos(angle) * spread, math.sin(angle) * spread * 0.6
        height = 1.1 + 0.9 * ((blade * 37) % 7) / 6
        lean = 0.25 + 0.15 * (blade % 2)
        start = len(verts)
        verts += [(bx - 0.075 * math.sin(angle), by + 0.075 * math.cos(angle), -0.15),
                  (bx + 0.075 * math.sin(angle), by - 0.075 * math.cos(angle), -0.15),
                  (bx - 0.03 * math.cos(angle), by - 0.03 * math.sin(angle) - 0.05, -0.15),
                  (bx + math.cos(angle) * lean, by + math.sin(angle) * lean * 0.5 + 0.1, height)]
        faces += [(start + a, start + b, start + c) for a, b, c in ((0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3))]
    return [_mesh("Swatch", verts, faces)], {"base_z": 0.0, "height": 2.0, "top": 2.0}, []


def fixture_pad():
    radius, rim = 0.9, []
    for step in range(11):
        angle = 0.35 + step / 10 * (math.tau - 0.7)
        rim.append((math.cos(angle) * radius, math.sin(angle) * radius))
    verts = [(0.0, 0.0, 0.03)] + [(x, y, 0.03) for x, y in rim] + [(x * 0.97, y * 0.97, -0.1) for x, y in rim] + [(0.0, 0.0, -0.1)]
    faces = [(0, step + 1, step + 2) for step in range(10)]
    faces += [(step + 1, step + 12, step + 13, step + 2) for step in range(10)]
    faces += [(0, 23, 12, 1), (0, 11, 22, 23)]
    return [_mesh("Swatch", verts, faces, recalc=False)], {"radius": radius}, []


def fixture_heap():
    piece = bl.smooth(shapelib.ellipsoid("Swatch", (1.1, 0.9, 0.6), at=(0.0, 0.0, 0.15), segments=32, rings=16), 80)
    return [piece], {}, []


def fixture_coil():
    major, minor, height, segments, sides = 0.55, 0.24, 0.36, 24, 10
    verts, faces = [], []
    for index in range(segments):
        angle = math.tau * index / segments
        for side in range(sides):
            tube = math.tau * side / sides
            reach = major + minor * math.cos(tube)
            verts.append((reach * math.cos(angle), reach * math.sin(angle), height * math.sin(tube)))
    for index in range(segments):
        following = (index + 1) % segments
        for side in range(sides):
            after = (side + 1) % sides
            faces.append((index * sides + side, following * sides + side, following * sides + after, index * sides + after))
    piece = bl.smooth(_mesh("Swatch", verts, faces), 70)
    return [piece], {"base": -height, "rope": minor, "major": major}, []


def fixture_log():
    # a split wedge of a log along X, pith on the axis: bark round most of it, two split faces toward the camera, cut ends
    radius, half, steps = 0.35, 0.8, 18
    profile = [(0.0, 0.0)] + [(radius * math.cos(angle), radius * math.sin(angle)) for angle in np.linspace(math.radians(160), math.radians(420), steps)]
    count = len(profile)
    verts = [(x, y, z) for x in (-half, half) for y, z in profile]
    faces = [tuple(range(count)), tuple(range(count, 2 * count))]
    faces += [(index, (index + 1) % count, count + (index + 1) % count, count + index) for index in range(count)]
    piece = bl.smooth(_mesh("Swatch", verts, faces), 40)
    piece.location = (0.0, 0.0, radius)
    return [piece], {"axis": 0, "radius": radius}, []


def fixture_stump():
    piece = bl.smooth(_outward(bl.lathe("Swatch", [(0.0, 0.0), (0.7, 0.0), (0.7, 1.2), (0.0, 1.2)], sides=28)), 50)
    cuts = [((0.15, -0.2), 0.6), ((-0.25, 0.1), 2.0), ((0.1, 0.3), 1.2)]
    return [piece], {"wood_bark_radius": 0.7, "top": 1.2, "cuts": cuts}, []


# ---- Greenmeadow fixtures (Joust Tycoon, 2026-10-05): leaf masses, limbs, wildflowers, crops, field walls, fair
# goods, roofs in their own plane, garments. Real stud sizes, like the castle's.

def _turned(name, profile, sides=32, smooth=60):
    """A closed lathe round object Z with outward normals (profile: (radius, z) from the bottom centre up)."""
    return bl.smooth(_outward(bl.lathe(name, profile, sides=sides)), smooth)


def _coord_mesh(name, verts, faces, coords, recalc=True, smooth=None):
    """A mesh from vertex and face lists whose face corners carry PaintCoord (coords: per face, one (u, v) per
    corner), so PaintCoord brushes paint it as they would the game's builders."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(vert) for vert in verts], [], [tuple(face) for face in faces])
    layer = mesh.uv_layers.new(name=paintlib.COORD)
    for polygon, corners in zip(mesh.polygons, coords):
        for loop_index, (u, v) in zip(polygon.loop_indices, corners):
            layer.data[loop_index].uv = (u + paintlib.COORD_OFFSET, v + paintlib.COORD_OFFSET)
    if recalc:
        builder = bmesh.new()
        builder.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
        builder.to_mesh(mesh)
        builder.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return bl.smooth(obj, smooth) if smooth else bl.flat(obj)


def _slab(name, low, high):
    """An axis-aligned box from corner `low` to `high` with its origin at the world origin (so object space is world
    space, as the brushes that read object positions expect)."""
    (x0, y0, z0), (x1, y1, z1) = low, high
    verts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return _mesh(name, verts, faces)


def fixture_crown():
    radii = (2.6, 2.6, 2.2)
    piece = bl.smooth(shapelib.ellipsoid("Swatch", radii, at=(0.0, 0.0, 2.2), segments=40, rings=20), 80)
    return [piece], {"radii": radii}, []


def fixture_limb():
    # a tapering trunk with a root flare; ring_loft writes PaintCoord (fraction round, height in studs)
    levels = [(0.0, 0.85, 0.85, 0.85, 2.0), (0.35, 0.62, 0.62, 0.62, 2.0), (2.0, 0.52, 0.52, 0.52, 2.0), (4.0, 0.42, 0.42, 0.42, 2.0)]
    piece = bl.smooth(shapelib.ring_loft("Swatch", (0.0, 0.0), levels, ring=24, steps=4), 60)
    return [piece], {}, []


def fixture_cord():
    # a rope sagging between two posts, PaintCoord (fraction round, studs along) like a game's rope tube
    sides, steps, radius, span, sag = 8, 24, 0.09, 3.0, 0.5
    points = [(-span / 2 + span * step / steps, 0.0, 1.2 - sag * (1 - (2 * step / steps - 1) ** 2)) for step in range(steps + 1)]
    verts, faces, coords, along = [], [], [], [0.0]
    for index in range(1, len(points)):
        along.append(along[-1] + math.dist(points[index], points[index - 1]))
    for index, (x, y, z) in enumerate(points):
        ahead, behind = points[min(index + 1, steps)], points[max(index - 1, 0)]
        tangent = np.subtract(ahead, behind)
        tangent /= np.linalg.norm(tangent)
        side = np.array((0.0, 1.0, 0.0))
        up = np.cross(tangent, side)
        for step in range(sides):
            angle = math.tau * step / sides
            verts.append(tuple(np.array((x, y, z)) + (side * math.cos(angle) + up * math.sin(angle)) * radius))
    for index in range(steps):
        for step in range(sides):
            following = (step + 1) % sides
            faces.append((index * sides + step, (index + 1) * sides + step, (index + 1) * sides + following, index * sides + following))
            coords.append(((step / sides, along[index]), (step / sides, along[index + 1]), ((step + 1) / sides, along[index + 1]), ((step + 1) / sides, along[index])))
    return [_coord_mesh("Swatch", verts, faces, coords, smooth=50)], {}, []


def fixture_flower():
    # a five-petal star head in its own frame (covershapes.star_head): petal tips and notches, cupped, a raised eye
    petal_count, per_petal, radius, notch, cup, eye_rise, under = 5, 6, 0.5, 0.45, 0.12, 0.06, 0.12
    verts, faces = [(0.0, 0.0, eye_rise)], []
    for petal in range(petal_count):
        for step in range(per_petal):
            fraction = step / per_petal
            angle = (petal + fraction) * math.tau / petal_count
            reach = radius * (notch + (1 - notch) * math.sin(math.pi * fraction) ** 0.6)
            verts.append((math.cos(angle) * reach, math.sin(angle) * reach, cup * (reach / radius) ** 2))
    verts.append((0.0, 0.0, -under))
    ring = len(verts) - 2
    for index in range(ring):
        following = (index + 1) % ring
        faces += [(0, index + 1, following + 1), (ring + 1, following + 1, index + 1)]
    piece = bl.smooth(_mesh("Swatch", verts, faces), 70)
    piece.location = (0.0, 0.0, 0.3)
    return [piece], {"radius": radius, "petal_count": petal_count}, []


def fixture_leaf():
    # a lance leaf along +X from the origin, diamond section, arching up then drooping (covershapes.leaf)
    length, width, rings = 1.4, 0.36, 8
    verts, faces = [(0.0, 0.0, 0.0)], []
    for ring in range(1, rings):
        fraction = ring / rings
        x = length * fraction
        lift = 0.18 * math.sin(math.pi * fraction * 0.85) - 0.12 * fraction ** 2
        half = width / 2 * math.sin(math.pi * fraction) ** 0.7
        verts += [(x, -half, lift), (x, 0.0, lift + 0.03), (x, half, lift), (x, 0.0, lift - 0.02)]
    verts.append((length, 0.0, 0.18 * math.sin(math.pi * 0.85) - 0.12))
    tip = len(verts) - 1
    for corner in range(4):
        faces.append((0, 1 + corner, 1 + (corner + 1) % 4))
    for ring in range(rings - 2):
        base = 1 + ring * 4
        for corner in range(4):
            following = (corner + 1) % 4
            faces.append((base + corner, base + 4 + corner, base + 4 + following, base + following))
    last = 1 + (rings - 2) * 4
    for corner in range(4):
        faces.append((last + corner, tip, last + (corner + 1) % 4))
    piece = bl.smooth(_mesh("Swatch", verts, faces), 70)
    return [piece], {"length": length}, []


def fixture_spindle():
    # a slim turned head on object Z from 0: a bulrush, an ear of wheat, a seed head, a toadstool stalk
    length = 1.4
    piece = _turned("Swatch", [(0.0, 0.0), (0.12, 0.08), (0.17, 0.5), (0.15, 1.0), (0.09, 1.3), (0.0, length)], sides=20)
    return [piece], {"length": length, "height": length}, []


def fixture_toadstool():
    # a domed cap in its own frame, gills underneath; spots laid on the dome like the game's
    radius, height = 0.8, 0.6
    profile = [(0.0, 0.1), (radius * 0.35, 0.06), (radius, 0.0), (radius * 0.97, 0.12)]
    profile += [(radius * math.cos(angle), 0.12 + (height - 0.12) * math.sin(angle)) for angle in np.linspace(0.25, math.pi / 2 - 0.05, 7)]
    profile.append((0.0, height))
    piece = _turned("Swatch", profile, sides=40)
    piece.location = (0.0, 0.0, 0.4)
    spots = []
    for spot in range(9):
        angle = spot * 2.39996
        reach = radius * (0.15 + 0.6 * math.sqrt((spot + 0.5) / 9))
        spots.append((math.cos(angle) * reach, math.sin(angle) * reach, height * (0.95 - 0.55 * (reach / radius) ** 2)))
    return [piece], {"radius": radius, "spots": spots, "spot_size": radius * 0.17}, []


def fixture_rock():
    piece = shapelib.ellipsoid("Swatch", (1.5, 1.15, 0.95), at=(0.0, 0.0, 0.6), segments=36, rings=18)
    # lumpy: push each vertex out or in along its direction from the centre
    count = len(piece.data.vertices)
    co = np.empty(count * 3)
    piece.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    co *= (1.0 + 0.08 * np.sin(co[:, 0] * 3.1 + co[:, 1] * 1.7) + 0.06 * np.sin(co[:, 2] * 4.3 - co[:, 0] * 2.2))[:, None]
    piece.data.vertices.foreach_set("co", co.ravel())
    piece.data.update()
    return [bl.smooth(piece, 60)], {}, []


def fixture_drywall():
    # a 12-stud dry-stone wall segment, battered, from foot -0.3 to top 2.35 (MeadowStoneWall's size)
    piece = _slab("Swatch", (-6.0, -1.0, -0.3), (6.0, 1.0, 2.35))
    return [piece], {"origin_x": -6.0, "length": 12.0, "period": 12.0, "seams": (-6.0, 6.0), "foot": -0.3, "top": 2.35}, []


def fixture_rick():
    profile = [(0.0, 0.0), (2.5, 0.0), (2.9, 1.2), (3.1, 2.6), (3.0, 3.75), (2.4, 4.6), (1.4, 5.5), (0.5, 6.1), (0.0, 6.25)]
    return [_turned("Swatch", profile, sides=48)], {"centre": (0.0, 0.0), "radius": 3.0, "eave": 3.75}, []


def fixture_sheaf():
    profile = [(0.0, 0.0), (0.42, 0.0), (0.36, 0.6), (0.24, 1.2), (0.34, 1.8), (0.5, 2.3), (0.44, 2.75), (0.0, 3.0)]
    return [_turned("Swatch", profile, sides=24)], {"waist": 1.2, "ear_line": 2.25}, []


def fixture_field():
    # a 16 x 16 wheat tile standing from foot -0.4 to crest 2.2, its cut edges showing the stalks
    piece = _slab("Swatch", (-8.0, -8.0, -0.4), (8.0, 8.0, 2.2))
    return [piece], {"period": 16.0, "foot": -0.4, "crest": 2.2}, []


def fixture_board():
    # a sign board: X across, Z up, its face toward -Y, centred on the origin
    piece = _slab("Swatch", (-1.5, -0.08, -0.8), (1.5, 0.08, 0.8))
    return [piece], {"half_width": 1.5, "half_height": 0.8, "centre_z": 0.0, "half": (1.5, 0.8)}, []


def fixture_sail():
    # sailcloth from the whip (object x 0) across 3 studs, out along Z to 12
    piece = _slab("Swatch", (0.0, -0.04, 0.0), (3.0, 0.04, 12.0))
    return [piece], {"length": 12.0, "width": 3.0}, []


def fixture_sheet():
    # three stripe gores of an awning sloping down toward -Y, each with PaintCoord (fraction across, studs along)
    gores, gore_width, cols, rows, length = 3, 1.2, 6, 8, 3.0
    verts, faces, coords = [], [], []
    for gore in range(gores):
        start = len(verts)
        for row in range(rows + 1):
            along = length * row / rows
            for col in range(cols + 1):
                across = col / cols
                x = -gores * gore_width / 2 + (gore + across) * gore_width
                verts.append((x, -along * 0.8, 3.0 - along * 0.6 - 0.08 * math.sin(math.pi * across)))
        for row in range(rows):
            for col in range(cols):
                corner = start + row * (cols + 1) + col
                faces.append((corner, corner + 1, corner + cols + 2, corner + cols + 1))
                coords.append(((col / cols, length * row / rows), ((col + 1) / cols, length * row / rows), ((col + 1) / cols, length * (row + 1) / rows), (col / cols, length * (row + 1) / rows)))
    piece = _coord_mesh("Swatch", verts, faces, coords, recalc=False)
    solidify = piece.modifiers.new("Solidify", "SOLIDIFY")
    solidify.thickness = 0.06
    solidify.use_rim = True
    return [piece], {}, []


def fixture_bunting():
    # five pennants hanging edge-on from a line along X, PaintCoord (index x stride + across, drop)
    count, width, length, gap, stride, thickness = 5, 0.55, 0.75, 0.25, 10.0, 0.04
    verts, faces, coords = [], [], []
    for index in range(count):
        centre = (index - (count - 1) / 2) * (width + gap)
        swing = 0.16 * math.sin(index * 2.399 + 1.0)
        for side in (-1, 1):
            start = len(verts)
            corners = [(-width / 2, 0.0), (0.0, 0.0), (width / 2, 0.0), (0.0, length)]
            for across, drop in corners:
                verts.append((centre + across, side * thickness / 2 + math.sin(swing) * drop, 1.5 - math.cos(swing) * drop))
            if side < 0:
                faces += [(start, start + 1, start + 3), (start + 1, start + 2, start + 3)]
            else:
                faces += [(start, start + 3, start + 1), (start + 1, start + 3, start + 2)]
            uv = [(index * stride + across, drop) for across, drop in corners]
            coords += [(uv[0], uv[1], uv[3]), (uv[1], uv[2], uv[3])] if side < 0 else [(uv[0], uv[3], uv[1]), (uv[1], uv[3], uv[2])]
    return [_coord_mesh("Swatch", verts, faces, coords, recalc=False)], {"width": width, "length": length, "stride": stride}, []


def fixture_basket():
    height = 0.8
    profile = [(0.0, 0.0), (0.5, 0.0), (0.58, 0.3), (0.64, 0.7), (0.68, height), (0.0, height)]
    return [_turned("Swatch", profile, sides=36)], {"height": height, "base": 0.0}, []


def fixture_fruit():
    # a mound with round fruit sitting on it; centres in object space
    piece = bl.smooth(shapelib.ellipsoid("Swatch", (1.0, 1.0, 0.45), at=(0.0, 0.0, 0.0), segments=36, rings=18), 70)
    radius, centres = 0.26, []
    for ring, (reach, count) in enumerate(((0.0, 1), (0.45, 6), (0.82, 11))):
        for step in range(count):
            angle = step / count * math.tau + ring * 0.4
            x, y = math.cos(angle) * reach, math.sin(angle) * reach
            z = 0.45 * math.sqrt(max(0.0, 1 - (x * x + y * y))) + radius * 0.4
            centres.append((x, y, z))
    return [piece], {"centres": centres, "radius": radius}, []


def fixture_hearth():
    piece = bl.smooth(shapelib.ellipsoid("Swatch", (1.2, 1.2, 0.3), at=(0.0, 0.0, 0.1), segments=36, rings=14), 70)
    return [piece], {"centre": (0.0, 0.0, 0.1), "radius": 1.2}, []


def fixture_bolt():
    # a bolt of cloth wound round object X
    radius, half = 0.35, 0.8
    piece = bl.cylinder("Swatch", radius, half * 2, sides=32)
    piece.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))
    piece.location = (0.0, 0.0, radius)
    return [bl.smooth(piece, 40)], {"radius": radius}, []


def fixture_basin():
    piece = bl.cylinder("Swatch", 1.0, 0.1, sides=40, at=(0.0, 0.0, 0.05))
    rim = _host(bl.smooth(_outward(bl.lathe("Rim", [(1.0, -0.2), (1.12, -0.2), (1.12, 0.35), (1.0, 0.35)], sides=40)), 40))
    return [piece], {}, [rim]


def fixture_roof():
    # a roof plane: object X along the eave, object Y up the slope, turned 35 degrees about X so it pitches up and
    # faces -Y (toward the camera)
    piece = _slab("Swatch", (-3.0, 0.0, -0.15), (3.0, 4.5, 0.0))
    piece.rotation_euler = (math.radians(35.0), 0.0, 0.0)
    bpy.context.view_layer.update()
    return [piece], {}, []


def fixture_tunic():
    # a hip tunic round object Z; ring_loft writes PaintCoord (fraction round, height)
    levels = [(0.0, 0.95, 0.62, 0.62, 2.4), (0.6, 0.88, 0.58, 0.58, 2.4), (1.5, 0.82, 0.55, 0.55, 2.4), (2.2, 0.9, 0.56, 0.56, 2.4), (2.5, 0.6, 0.42, 0.42, 2.4)]
    piece = bl.smooth(shapelib.ring_loft("Swatch", (0.0, 0.0), levels, ring=40, steps=3), 60)
    return [piece], {}, []


def fixture_hat():
    profile = [(0.0, 0.55), (0.34, 0.52), (0.4, 0.2), (0.95, 0.12), (1.0, 0.07), (0.95, 0.04), (0.42, 0.1), (0.0, 0.1)]
    piece = _turned("Swatch", list(reversed(profile)), sides=40)
    return [piece], {"centre": (0.0, 0.0)}, []


FIXTURES = {
    "box": fixture_box, "cylinder": fixture_cylinder, "points": fixture_points, "ring": fixture_ring,
    "sleeve": fixture_sleeve, "channels": fixture_channels, "band": fixture_band, "tail": fixture_tail,
    "knot": fixture_knot, "dome": fixture_dome,
    "drum": fixture_drum, "wall": fixture_wall, "cone": fixture_cone, "banner": fixture_banner,
    "valance": fixture_valance, "plane": fixture_plane, "pool": fixture_pool, "bank": fixture_bank,
    "blades": fixture_blades, "pad": fixture_pad, "heap": fixture_heap, "coil": fixture_coil, "log": fixture_log,
    "stump": fixture_stump,
    "crown": fixture_crown, "limb": fixture_limb, "cord": fixture_cord, "flower": fixture_flower, "leaf": fixture_leaf,
    "spindle": fixture_spindle, "toadstool": fixture_toadstool, "rock": fixture_rock, "drywall": fixture_drywall,
    "rick": fixture_rick, "sheaf": fixture_sheaf, "field": fixture_field, "board": fixture_board, "sail": fixture_sail,
    "sheet": fixture_sheet, "bunting": fixture_bunting, "basket": fixture_basket, "fruit": fixture_fruit,
    "hearth": fixture_hearth, "bolt": fixture_bolt, "basin": fixture_basin, "roof": fixture_roof, "tunic": fixture_tunic,
    "hat": fixture_hat,
}
# tile brushes (brushes.terrain) paint a flat texture: studs per tile for the swatch, 16 unless named here
TILE_PERIODS = {"terrain.ground": 12.0}


def render_tile(path):
    scene = bpy.context.scene
    objects = [obj for obj in scene.objects if obj.type == "MESH" and not obj.hide_render]
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector([min(corner[axis] for corner in corners) for axis in range(3)])
    high = Vector([max(corner[axis] for corner in corners) for axis in range(3)])
    centre, radius = (low + high) / 2, max((high - low).length / 2, 0.01) * 1.2
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.16, 0.17, 0.19)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = scene.render.resolution_y = TILE
    scene.render.resolution_percentage = 100
    scene.display.render_aa = "8"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.show_shadows = True
    shading.show_backface_culling = True
    bl._preview_materials(bl.PREVIEW_TINT)
    shading.color_type = "TEXTURE"
    camera = bpy.data.objects.new("SwatchCamera", bpy.data.cameras.new("SwatchCamera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    bl._aim(camera, centre, radius, (-0.8, -1.0, 0.75), "PERSP", corners)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def tile_swatch(style, role, folder):
    """A tile brush's swatch: the texture painted at full size, tiled 2 x 2 (so a seam would show as a cross through
    the middle) and shrunk to the swatch tile."""
    from brushes import terrain
    brush = style.brush(role)
    tile = terrain.Tile(TILE_PERIODS.get(brush.id, 16.0))
    rgb = np.clip(style.painter(role)(tile)[:, :3], 0.0, 1.0).reshape(tile.size, tile.size, 3)
    tiled = np.tile(rgb, (2, 2, 1))
    box = tiled.reshape(tiled.shape[0] // 4, 4, tiled.shape[1] // 4, 4, 3).mean(axis=(1, 3))
    picks = (np.arange(TILE) * box.shape[0] / TILE).astype(np.int64)
    small = box[picks][:, picks]
    tile_path = os.path.join(folder, "".join(char if char.isalnum() else "_" for char in role) + ".png")
    sheet.write_png(tile_path, np.concatenate([small, np.ones((TILE, TILE, 1))], axis=2).astype(np.float32))
    return tile_path


def swatch(style, role, folder):
    brush = style.brush(role)
    if brush.fixture == "tile":
        return tile_swatch(style, role, folder)
    builder = FIXTURES.get(brush.fixture, fixture_box)
    bl.reset()
    pieces, geometry, hosts = builder()
    fixed = style.entry(role).get("options", {})
    options = {name: value for name, value in geometry.items() if name in brush.options and name not in fixed}
    atlas = paintlib.Atlas("Swatch_" + "".join(char if char.isalnum() else "_" for char in role), size=256, ao_distance=0.4, samples=16)
    painter = style.painter(role, **options)
    for piece in pieces:
        atlas.add(piece, painter, tint=brush.tint)
    os.makedirs(CACHE, exist_ok=True)
    atlas.build(CACHE)
    tile = os.path.join(folder, "".join(char if char.isalnum() else "_" for char in role) + ".png")
    render_tile(tile)
    return tile


def write_catalog():
    entries = brushes.catalog()
    with open(os.path.join(HERE, "catalog.json"), "w", encoding="utf-8") as handle:
        json.dump({"brushes": entries, "styles": {name: brushes.load(name) for name in brushes.styles()}}, handle, indent=1)
    lines = [
        "# Brush catalog",
        "",
        "Generated by `node blend.js brushes` from the registry and `styles/`. Do not edit by hand; see `README.md`.",
        "",
        "## Styles",
        "",
    ]
    for name in brushes.styles():
        data = brushes.load(name)
        lines += [f"### {name}: {data.get('title', name)}", "", data.get("summary", ""), "",
                  f"- From: {data.get('from', '?')}", f"- Status: {data.get('status', '?')}",
                  f"- Finish: `{json.dumps(data.get('finish', {}))}`", f"- Ink: `{json.dumps(data.get('ink'))}`",
                  f"- Swatches: `swatches/{name}.png`", "", "| Role | Brush | Options |", "| --- | --- | --- |"]
        for role, entry in sorted(data.get("painters", {}).items()):
            lines.append(f"| {role} | `{entry['brush']}` | {json.dumps(entry.get('options', {})) if entry.get('options') else ''} |")
        lines.append("")
    lines += ["## Brushes", "", "| Brush | Material | Fixture | Tint | Styles | Status | What it paints |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for entry in entries:
        lines.append(f"| `{entry['key']}` | {entry['material']} | {entry['fixture']} | {'yes' if entry['tint'] else ''} | {', '.join(entry['styles'])} | {entry['status']} | {entry['summary']} |")
    lines += ["", "### Options", ""]
    for entry in entries:
        options = ", ".join(f"{name}={json.dumps(value)}" for name, value in entry["options"].items())
        lines.append(f"- `{entry['key']}` ({entry['source']}): {options}")
    with open(os.path.join(HERE, "CATALOG.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    only_style = os.environ.get("BRUSH_STYLE") or None
    only_role = os.environ.get("BRUSH_ROLE") or None
    for name in brushes.styles():
        if only_style and name != only_style:
            continue
        folder = os.path.join(SWATCHES, "tiles", name)
        os.makedirs(folder, exist_ok=True)
        style = brushes.use_style(name)
        tiles, labels = [], []
        for role in style.roles:
            if only_role and role != only_role:
                continue
            try:
                tiles.append(swatch(style, role, folder))
                labels.append(role)
                print(f"SWATCH {name} {role}")
            except Exception as error:
                print(f"SWATCH FAILED {name} {role}: {error}")
        if tiles and not only_role:
            sheet.compose(tiles, 5, os.path.join(SWATCHES, f"{name}.png"), labels=[label.upper() for label in labels])
    write_catalog()
    print("BRUSHES done")


main()
