"""blendlib: author Roblox assets in headless Blender (4.1+).

Asset scripts run through `node blend.js build <asset.py>` and import this module:

    import blendlib as bl

    bl.reset()
    crate = bl.box("Crate", (1.6, 1.6, 1.0), at=(0, 0, 0.5), bevel=0.06, colour="9A6B3F")
    bl.roblox(crate, material="Wood")
    bl.finish("Crate", budget=500)

Frame: Blender's own. Z is up, the asset's front faces -Y (Blender's Front view), 1 unit = 1 stud, and the world
origin is the asset's pivot. The export turns this into Roblox's frame (Y up, front -Z) with a proper rotation, so
nothing is mirrored: Roblox (x, y, z) = Blender (-x, z, y).

Parts: every mesh object that renders becomes one MeshPart, named after the object. Objects given the same
roblox(obj, part="Name") merge into one MeshPart. finish() turns curves, text and surfaces into meshes first.
Objects with hide_render set are left out, so use that for guides and references.

Colour: the "Col" corner colour attribute, in sRGB hex. paint() and paint_faces() write it. finish() fills it from
the material base colours (or white) on any object without one, so the sheet shows exactly what Roblox gets.

API:
    reset()                                           empty scene, Standard view transform
    box(name, size, at, bevel, colour, segments)      size (x, y, z); bevel > 0 adds a Bevel modifier
    cylinder(name, radius, depth, sides, at, colour)  capped, along Z
    sphere(name, radius, segments, rings, at, colour)
    lathe(name, profile, sides, at, colour)           profile [(radius, z), ...] bottom to top; radius 0 closes an end
    tube(name, points, radius, sides, colour, caps)   a round tube along a smooth curve through points, capped
    paint(obj, colour) / paint_faces(obj, fn)         fn(polygon) -> hex or None, polygon in object space
    flat(obj) / smooth(obj, angle)                    shape helpers start flat
    roblox(obj, part, material, collision, collide, shadow, attributes)
                                                      Enum names as strings; defaults SmoothPlastic, Box, False, True;
                                                      attributes {name: value} become attributes on the MeshPart
    socket(name, at, part, up, front, attributes)     an Attachment on a part: a mount point for kit, trails, effects
    check(budget) -> report                           triangles per part, open edges, zero-area faces, size in studs
    render_sheet(path, size)                          four Workbench views on one PNG
    finish(name, budget)                              check, sheet, write <name>.json, print the BLENDLIB report

Painted textures (optional, see SKILL.md "Painted textures"): paintlib (Atlas, the bake/paint pipeline),
brushlib (painter recipes and the toon pass), shapelib (cloth, quilting and deterministic primitives), inklib (toon
outlines). An asset that makes a paintlib.Atlas gets it baked, painted and exported by finish(): the payload is
then blendlib-textured/1 and the sheet shows the real textures (team parts tinted PREVIEW_TINT).
"""

import json
import math
import os
import re
import sys
import tempfile

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

if bpy.app.version < (4, 1, 0):
    raise RuntimeError(f"blendlib needs Blender 4.1 or newer; this is {bpy.app.version_string}")

OUT = os.path.join(tempfile.gettempdir(), "blenderassets")
SOURCE = ""
TRIANGLE_LIMIT = 20000
QUANTUM = 1000
NORMAL_QUANTUM = 1000
COLOUR_ATTRIBUTE = "Col"
PREVIEW_TINT = "1E5BD8"
GEOMETRY_TYPES = {"CURVE", "SURFACE", "META", "FONT"}
VIEWS = (
    ("three-quarter", (-0.8, -1.0, 0.75), "PERSP"),
    ("front", (0.0, -1.0, 0.0), "ORTHO"),
    ("side", (1.0, 0.0, 0.0), "ORTHO"),
    ("top", (0.0, 0.0, 1.0), "ORTHO"),
)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    paintlib = sys.modules.get("paintlib")
    if paintlib is not None:
        paintlib.reset()


def srgb(colour):
    if isinstance(colour, str):
        value = colour.lstrip("#")
        return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4))
    return tuple(float(channel) for channel in colour[:3])


def _linear_to_srgb(value):
    value = min(max(value, 0.0), 1.0)
    return value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055


def _safe_name(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", str(name)) or "Mesh"


def _corner_layer(mesh):
    layer = mesh.color_attributes.get(COLOUR_ATTRIBUTE)
    if layer is not None and layer.domain == "CORNER":
        mesh.color_attributes.active_color_name = COLOUR_ATTRIBUTE
        return layer
    values = np.ones((len(mesh.loops), 4), dtype=np.float32)
    if layer is not None:
        point_colours = np.empty(len(layer.data) * 4, dtype=np.float32)
        layer.data.foreach_get("color_srgb", point_colours)
        vertex_indices = np.empty(len(mesh.loops), dtype=np.int32)
        mesh.loops.foreach_get("vertex_index", vertex_indices)
        values = point_colours.reshape(-1, 4)[vertex_indices]
        mesh.color_attributes.remove(layer)
    layer = mesh.color_attributes.new(COLOUR_ATTRIBUTE, "BYTE_COLOR", "CORNER")
    layer.data.foreach_set("color_srgb", values.ravel())
    mesh.color_attributes.active_color_name = COLOUR_ATTRIBUTE
    return layer


def paint(obj, colour):
    layer = _corner_layer(obj.data)
    rgba = np.array((*srgb(colour), 1.0), dtype=np.float32)
    layer.data.foreach_set("color_srgb", np.tile(rgba, len(layer.data)))
    return obj


def paint_faces(obj, fn):
    mesh = obj.data
    layer = _corner_layer(mesh)
    values = np.empty(len(layer.data) * 4, dtype=np.float32)
    layer.data.foreach_get("color_srgb", values)
    values = values.reshape(-1, 4)
    for polygon in mesh.polygons:
        colour = fn(polygon)
        if colour is not None:
            values[polygon.loop_start:polygon.loop_start + polygon.loop_total] = (*srgb(colour), 1.0)
    layer.data.foreach_set("color_srgb", values.ravel())
    return obj


def flat(obj):
    obj.data.polygons.foreach_set("use_smooth", np.zeros(len(obj.data.polygons), dtype=bool))
    return obj


def smooth(obj, angle=30.0):
    mesh = obj.data
    builder = bmesh.new()
    builder.from_mesh(mesh)
    limit = math.radians(angle)
    for face in builder.faces:
        face.smooth = True
    for edge in builder.edges:
        faces = edge.link_faces
        edge.smooth = not (len(faces) == 2 and faces[0].normal.angle(faces[1].normal, 0.0) > limit)
    builder.to_mesh(mesh)
    builder.free()
    return obj


def roblox(obj, part=None, material=None, collision=None, collide=None, shadow=None, attributes=None):
    if attributes:
        merged = json.loads(obj.get("roblox_attributes", "{}"))
        merged.update(attributes)
        obj["roblox_attributes"] = json.dumps(merged)
    for key, value in (
        ("roblox_part", part),
        ("roblox_material", material),
        ("roblox_collision", collision),
        ("roblox_collide", collide),
        ("roblox_shadow", shadow),
    ):
        if value is not None:
            obj[key] = value
    return obj


def socket(name, at, part, up=(0.0, 0.0, 1.0), front=(0.0, -1.0, 0.0), attributes=None):
    """A mount point: push makes an Attachment named `name` on MeshPart `part`, at `at` (Blender world space), with
    its up (Y) along `up` and its look (-Z) along `front`. Empties never render or export as geometry."""
    obj = bpy.data.objects.new(_safe_name(name), None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = at
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 0.25
    obj["roblox_socket"] = True
    obj["roblox_part"] = part
    obj["socket_up"] = list(up)
    obj["socket_front"] = list(front)
    if attributes:
        obj["roblox_attributes"] = json.dumps(attributes)
    return obj


def _to_roblox(vector):
    return [-vector[0], vector[2], vector[1]]


def sockets_payload():
    """Every socket in the scene, in Roblox axes (relative to the push origin, like the mesh vertices)."""
    entries = []
    for obj in bpy.context.scene.objects:
        if obj.type != "EMPTY" or not obj.get("roblox_socket"):
            continue
        rotation = obj.matrix_world.to_3x3()
        up = (rotation @ Vector(obj["socket_up"])).normalized()
        front = (rotation @ Vector(obj["socket_front"])).normalized()
        entries.append({
            "name": _safe_name(obj.name),
            "part": _safe_name(str(obj["roblox_part"])),
            "p": [round(value, 4) for value in _to_roblox(obj.matrix_world.translation)],
            "up": [round(value, 5) for value in _to_roblox(up)],
            "front": [round(value, 5) for value in _to_roblox(front)],
            "attributes": json.loads(obj.get("roblox_attributes", "{}")),
        })
    return entries


def part_attributes(objects):
    merged = {}
    for obj in objects:
        merged.update(json.loads(obj.get("roblox_attributes", "{}")))
    return merged


def _link(name, builder, at, colour):
    mesh = bpy.data.meshes.new(name)
    builder.to_mesh(mesh)
    builder.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = at
    flat(obj)
    if colour is not None:
        paint(obj, colour)
    return obj


def box(name, size, at=(0, 0, 0), bevel=0.0, colour=None, segments=1):
    builder = bmesh.new()
    bmesh.ops.create_cube(builder, size=1.0)
    bmesh.ops.scale(builder, vec=Vector(size), verts=builder.verts)
    obj = _link(name, builder, at, colour)
    if bevel > 0:
        modifier = obj.modifiers.new("Bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = segments
        modifier.limit_method = "ANGLE"
    return obj


def cylinder(name, radius, depth, sides=12, at=(0, 0, 0), colour=None):
    builder = bmesh.new()
    bmesh.ops.create_cone(builder, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius, depth=depth)
    return _link(name, builder, at, colour)


def sphere(name, radius, segments=12, rings=8, at=(0, 0, 0), colour=None):
    # built by hand: bmesh's create_uvsphere orders its faces differently run to run
    builder = bmesh.new()
    top = builder.verts.new((0.0, 0.0, radius))
    bands = []
    for ring in range(1, rings):
        polar = math.pi * ring / rings
        bands.append([
            builder.verts.new((radius * math.sin(polar) * math.cos(math.tau * segment / segments), radius * math.sin(polar) * math.sin(math.tau * segment / segments), radius * math.cos(polar)))
            for segment in range(segments)
        ])
    bottom = builder.verts.new((0.0, 0.0, -radius))
    for segment in range(segments):
        following = (segment + 1) % segments
        builder.faces.new((top, bands[0][following], bands[0][segment]))
        for upper, lower in zip(bands[:-1], bands[1:]):
            builder.faces.new((upper[segment], upper[following], lower[following], lower[segment]))
        builder.faces.new((bottom, bands[-1][segment], bands[-1][following]))
    bmesh.ops.recalc_face_normals(builder, faces=builder.faces)
    return _link(name, builder, at, colour)


def lathe(name, profile, sides=12, at=(0, 0, 0), colour=None):
    builder = bmesh.new()
    rings = []
    for radius, height in profile:
        if radius < 1e-6:
            rings.append([builder.verts.new((0.0, 0.0, height))])
            continue
        rings.append([
            builder.verts.new((radius * math.cos(2 * math.pi * step / sides), radius * math.sin(2 * math.pi * step / sides), height))
            for step in range(sides)
        ])
    for lower, upper in zip(rings, rings[1:]):
        for step in range(sides):
            corners = (
                lower[step % len(lower)],
                lower[(step + 1) % len(lower)],
                upper[(step + 1) % len(upper)],
                upper[step % len(upper)],
            )
            unique = list(dict.fromkeys(corners))
            if len(unique) >= 3:
                builder.faces.new(unique)
    return _link(name, builder, at, colour)


def tube(name, points, radius, sides=8, colour=None, caps=True, resolution=6):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = max(0, (sides - 4) // 2)
    curve.use_fill_caps = caps
    curve.resolution_u = resolution
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for control, point in zip(spline.bezier_points, points):
        control.co = point
        control.handle_left_type = "AUTO"
        control.handle_right_type = "AUTO"
    holder = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(holder)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(holder.evaluated_get(depsgraph))
    bpy.data.objects.remove(holder)
    bpy.data.curves.remove(curve)
    welder = bmesh.new()
    welder.from_mesh(mesh)
    bmesh.ops.remove_doubles(welder, verts=welder.verts, dist=1e-5)
    welder.to_mesh(mesh)
    welder.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    flat(obj)
    if colour is not None:
        paint(obj, colour)
    return obj


def _asset_objects():
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and not obj.hide_render]


def _material_srgb(material):
    if material is None:
        return (1.0, 1.0, 1.0)
    colour = material.diffuse_color[:3]
    if material.use_nodes and material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                colour = node.inputs["Base Color"].default_value[:3]
                break
    return tuple(_linear_to_srgb(channel) for channel in colour)


def _paint_from_materials(obj):
    mesh = obj.data
    colours = [_material_srgb(slot.material) for slot in obj.material_slots] or [(1.0, 1.0, 1.0)]
    layer = _corner_layer(mesh)
    values = np.ones((len(layer.data), 4), dtype=np.float32)
    for polygon in mesh.polygons:
        colour = colours[min(polygon.material_index, len(colours) - 1)]
        values[polygon.loop_start:polygon.loop_start + polygon.loop_total] = (*colour, 1.0)
    layer.data.foreach_set("color_srgb", values.ravel())
    return bool(obj.material_slots)


def _bake_geometry():
    notes = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in list(bpy.context.scene.objects):
        if obj.type not in GEOMETRY_TYPES or obj.hide_render:
            continue
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        name, matrix = obj.name, obj.matrix_world.copy()
        properties = {key: obj[key] for key in obj.keys() if key.startswith("roblox_")}
        collections = list(obj.users_collection)
        bpy.data.objects.remove(obj)
        baked = bpy.data.objects.new(name, mesh)
        baked.matrix_world = matrix
        for key, value in properties.items():
            baked[key] = value
        for collection in collections:
            collection.objects.link(baked)
    for obj in _asset_objects():
        if obj.data.color_attributes.get(COLOUR_ATTRIBUTE) is None:
            if not _paint_from_materials(obj):
                notes.append(f"{obj.name}: no colour attribute or material, painted white")
    return notes


def _to_world(points, matrix):
    transform = np.array(matrix)
    return points @ transform[:3, :3].T + transform[:3, 3]


def _roblox_size(low, high):
    extent = high - low
    return [round(float(extent[0]), 3), round(float(extent[2]), 3), round(float(extent[1]), 3)]


def check(budget=None):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    objects, parts, part_materials, warnings, errors = [], {}, {}, [], []
    low, high = np.full(3, np.inf), np.full(3, -np.inf)
    for obj in _asset_objects():
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        builder = bmesh.new()
        builder.from_mesh(mesh)
        open_edges = sum(1 for edge in builder.edges if not edge.is_manifold)
        loose = sum(1 for vertex in builder.verts if not vertex.link_faces)
        builder.free()
        areas = np.empty(triangles, dtype=np.float32)
        mesh.loop_triangles.foreach_get("area", areas)
        degenerate = int((areas < 1e-8).sum())
        points = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", points)
        corner_vertices = np.empty(triangles * 3, dtype=np.int32)
        mesh.loop_triangles.foreach_get("vertices", corner_vertices)
        local = points.reshape(-1, 3).astype(np.float64)
        if len(local):
            world = _to_world(local, obj.matrix_world)
            low, high = np.minimum(low, world.min(0)), np.maximum(high, world.max(0))
        corners = local[corner_vertices.reshape(-1, 3)]
        volume = float(np.einsum("ij,ij->i", corners[:, 0], np.cross(corners[:, 1], corners[:, 2])).sum() / 6) if triangles else 0.0
        evaluated.to_mesh_clear()
        part = _safe_name(obj.get("roblox_part", obj.name))
        material = obj.get("roblox_material", "SmoothPlastic")
        if part in part_materials and part_materials[part] != material:
            warnings.append(f"{obj.name}: roblox_material {material} differs from part {part}'s {part_materials[part]}; the first wins")
        part_materials.setdefault(part, material)
        parts[part] = parts.get(part, 0) + triangles
        objects.append({"name": obj.name, "part": part, "triangles": triangles, "openEdges": open_edges, "zeroArea": degenerate, "loose": loose})
        if triangles == 0:
            warnings.append(f"{obj.name}: no faces")
        if open_edges:
            warnings.append(f"{obj.name}: {open_edges} open edges (a hole, or an intentionally open surface)")
        elif volume < 0 and not obj.get("ink"):
            warnings.append(f"{obj.name}: closed but inside out (faces point inward); flip it with bmesh.ops.reverse_faces")
        if degenerate:
            warnings.append(f"{obj.name}: {degenerate} zero-area triangles, dropped on export")
        if loose:
            warnings.append(f"{obj.name}: {loose} loose vertices")
    for part, triangles in parts.items():
        if triangles > TRIANGLE_LIMIT:
            errors.append(f"part {part}: {triangles} triangles, over EditableMesh's {TRIANGLE_LIMIT}; split it with roblox(part=...)")
    total = sum(parts.values())
    if budget is not None and total > budget:
        warnings.append(f"{total} triangles, over the {budget} budget")
    if not objects:
        errors.append("no mesh objects to export")
    return {
        "triangles": total,
        "parts": parts,
        "objects": objects,
        "size": _roblox_size(low, high) if objects else [0, 0, 0],
        "warnings": warnings,
        "errors": errors,
    }


def _aim(camera, centre, radius, direction, kind, corners):
    direction = Vector(direction).normalized()
    if abs(direction.z) > 0.999:
        rotation = Matrix.Identity(3) if direction.z > 0 else Matrix.Rotation(math.pi, 3, "X")
    else:
        rotation = direction.to_track_quat("Z", "Y").to_matrix()
    camera.rotation_euler = rotation.to_euler()
    camera.data.type = kind
    if kind == "ORTHO":
        right, up = rotation.col[0], rotation.col[1]
        across = [corner.dot(right) for corner in corners]
        along = [corner.dot(up) for corner in corners]
        camera.data.ortho_scale = max(max(across) - min(across), max(along) - min(along), 0.01) * 1.12
        distance = radius * 3 + 1
    else:
        distance = radius / math.sin(camera.data.angle / 2) * 1.05
    camera.location = centre + direction * distance
    camera.data.clip_start = 0.01
    camera.data.clip_end = distance + radius * 4 + 10


def _load_pixels(path):
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(height, width, 4)


def _preview_materials(tint):
    """Workbench TEXTURE shading shows each object's image node, else its material colour: give painted pieces
    their texture (pre-tinted by alpha where the part takes team colour) and everything else its own colour."""
    images = {}
    tint_rgb = np.array(srgb(tint), dtype=np.float32)
    for obj in _asset_objects():
        obj.data.materials.clear()
        material = bpy.data.materials.new(f"Preview_{obj.name}")
        image_path = obj.get("paint_image")
        if image_path:
            key = (image_path, bool(obj.get("team")))
            if key not in images:
                image = bpy.data.images.load(image_path)
                if obj.get("team"):
                    width, height = image.size
                    pixels = np.empty(width * height * 4, dtype=np.float32)
                    image.pixels.foreach_get(pixels)
                    pixels = pixels.reshape(-1, 4)
                    tinted = pixels[:, :3] * (1 - pixels[:, 3:4] + pixels[:, 3:4] * tint_rgb)
                    copy = bpy.data.images.new(f"{image.name}_tinted", width, height, alpha=True)
                    copy.pixels.foreach_set(np.concatenate([tinted, np.ones((len(tinted), 1), dtype=np.float32)], axis=1).ravel())
                    image = copy
                image.alpha_mode = "NONE"
                images[key] = image
            material.use_nodes = True
            texture = material.node_tree.nodes.new("ShaderNodeTexImage")
            texture.image = images[key]
            material.node_tree.nodes.active = texture
        else:
            layer = obj.data.color_attributes.get(COLOUR_ATTRIBUTE)
            colour = (1.0, 1.0, 1.0)
            if obj.get("solid_colour"):
                colour = srgb(str(obj["solid_colour"]))
            elif layer is not None and len(layer.data):
                values = np.empty(len(layer.data) * 4, dtype=np.float32)
                layer.data.foreach_get("color_srgb", values)
                colour = tuple(float(value) for value in values.reshape(-1, 4)[:, :3].mean(axis=0))
            material.diffuse_color = (*(_srgb_to_linear(channel) for channel in colour), 1.0)
        obj.data.materials.append(material)


def _srgb_to_linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def render_sheet(path, size=512, textured=False):
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    corners = []
    for obj in _asset_objects():
        evaluated = obj.evaluated_get(depsgraph)
        corners += [evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box]
    if not corners:
        raise RuntimeError("render_sheet: nothing to render")
    low = Vector([min(corner[axis] for corner in corners) for axis in range(3)])
    high = Vector([max(corner[axis] for corner in corners) for axis in range(3)])
    centre = (low + high) / 2
    radius = max((high - low).length / 2, 0.01)

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.16, 0.17, 0.19)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.display.render_aa = "8"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    shading.show_object_outline = True
    shading.show_shadows = True
    shading.show_backface_culling = True
    if textured:
        _preview_materials(PREVIEW_TINT)
        shading.color_type = "TEXTURE"

    camera_data = bpy.data.cameras.new("SheetCamera")
    camera = bpy.data.objects.new("SheetCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    tiles = []
    folder = os.path.dirname(os.path.abspath(path))
    os.makedirs(folder, exist_ok=True)
    for index, (_, direction, kind) in enumerate(VIEWS):
        _aim(camera, centre, radius, direction, kind, corners)
        tile_path = os.path.join(folder, f".sheet_tile_{index}.png")
        scene.render.filepath = tile_path
        bpy.ops.render.render(write_still=True)
        tiles.append(_load_pixels(tile_path))
        os.remove(tile_path)
    bpy.data.objects.remove(camera)
    bpy.data.cameras.remove(camera_data)

    sheet = np.zeros((size * 2, size * 2, 4), dtype=np.float32)
    sheet[size:, :size] = tiles[0]
    sheet[size:, size:] = tiles[1]
    sheet[:size, :size] = tiles[2]
    sheet[:size, size:] = tiles[3]
    image = bpy.data.images.new("ContactSheet", size * 2, size * 2, alpha=True)
    image.pixels.foreach_set(sheet.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    return path


def _export_part(name, objects, depsgraph):
    positions, triangles, normals, colours = [], [], [], []
    offset = 0
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        count = len(mesh.loop_triangles)
        if count == 0:
            evaluated.to_mesh_clear()
            continue
        corner_vertices = np.empty(count * 3, dtype=np.int32)
        mesh.loop_triangles.foreach_get("vertices", corner_vertices)
        corner_loops = np.empty(count * 3, dtype=np.int32)
        mesh.loop_triangles.foreach_get("loops", corner_loops)
        points = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", points)
        loop_normals = np.empty(len(mesh.loops) * 3, dtype=np.float32)
        mesh.corner_normals.foreach_get("vector", loop_normals)
        layer = mesh.color_attributes.get(COLOUR_ATTRIBUTE)
        if layer is not None:
            raw = np.empty(len(layer.data) * 4, dtype=np.float32)
            layer.data.foreach_get("color_srgb", raw)
            raw = raw.reshape(-1, 4)
            corner_colours = raw[corner_loops] if layer.domain == "CORNER" else raw[corner_vertices]
        else:
            corner_colours = np.ones((count * 3, 4), dtype=np.float32)
        evaluated.to_mesh_clear()

        transform = np.array(obj.matrix_world)
        linear = transform[:3, :3]
        world_points = points.reshape(-1, 3).astype(np.float64) @ linear.T + transform[:3, 3]
        world_normals = loop_normals.reshape(-1, 3)[corner_loops].astype(np.float64) @ np.linalg.pinv(linear)
        world_normals /= np.maximum(np.linalg.norm(world_normals, axis=1, keepdims=True), 1e-12)
        faces = corner_vertices.reshape(-1, 3)
        face_normals = world_normals.reshape(-1, 3, 3)
        face_colours = corner_colours.reshape(-1, 3, 4)
        if np.linalg.det(linear) < 0:
            faces, face_normals, face_colours = faces[:, [0, 2, 1]], face_normals[:, [0, 2, 1]], face_colours[:, [0, 2, 1]]
        first, second, third = world_points[faces[:, 0]], world_points[faces[:, 1]], world_points[faces[:, 2]]
        keep = np.linalg.norm(np.cross(second - first, third - first), axis=1) > 2e-9
        positions.append(world_points)
        triangles.append(faces[keep] + offset)
        normals.append(face_normals[keep])
        colours.append(face_colours[keep])
        offset += len(world_points)
    if not triangles or not sum(len(block) for block in triangles):
        return None

    all_points = np.concatenate(positions)
    all_faces = np.concatenate(triangles)
    all_normals = np.concatenate(normals).reshape(-1, 3)
    all_colours = np.concatenate(colours).reshape(-1, 4)
    roblox_points = np.stack([-all_points[:, 0], all_points[:, 2], all_points[:, 1]], axis=1)
    roblox_normals = np.stack([-all_normals[:, 0], all_normals[:, 2], all_normals[:, 1]], axis=1)

    count = len(all_faces)
    used, vertex_index = np.unique(all_faces.ravel(), return_inverse=True)
    vertex_index = vertex_index.reshape(count, 3)
    unique_normals, normal_index = np.unique(np.rint(roblox_normals * NORMAL_QUANTUM).astype(np.int64), axis=0, return_inverse=True)
    colour_bytes = np.rint(np.clip(all_colours[:, :3], 0.0, 1.0) * 255).astype(np.int64)
    unique_colours, colour_index = np.unique(colour_bytes, axis=0, return_inverse=True)

    corners = roblox_points[all_faces]
    winding = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    inverted = int((np.einsum("ij,ij->i", winding, roblox_normals.reshape(count, 3, 3).sum(axis=1)) < 0).sum())

    table = np.concatenate([vertex_index, normal_index.reshape(count, 3), colour_index.reshape(count, 3)], axis=1) + 1
    first = objects[0]
    return {
        "name": name,
        "material": str(first.get("roblox_material", "SmoothPlastic")),
        "collision": str(first.get("roblox_collision", "Box")),
        "collide": bool(first.get("roblox_collide", False)),
        "shadow": bool(first.get("roblox_shadow", True)),
        "attributes": part_attributes(objects),
        "triangles": count,
        "inverted": inverted,
        "v": np.rint(roblox_points[used] * QUANTUM).astype(np.int64).ravel().tolist(),
        "n": unique_normals.ravel().tolist(),
        "c": ["%02X%02X%02X" % tuple(int(channel) for channel in colour) for colour in unique_colours],
        "t": table.ravel().tolist(),
    }


def export(path, name, report=None):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    groups = {}
    for obj in _asset_objects():
        groups.setdefault(_safe_name(obj.get("roblox_part", obj.name)), []).append(obj)
    meshes = []
    for part, objects in groups.items():
        entry = _export_part(part, objects, depsgraph)
        if entry is not None:
            meshes.append(entry)
    payload = {
        "format": "blendlib/1",
        "name": name,
        "source": os.path.basename(SOURCE),
        "blender": bpy.app.version_string,
        "quantum": QUANTUM,
        "size": report["size"] if report else None,
        "triangles": sum(entry["triangles"] for entry in meshes),
        "meshes": meshes,
        "sockets": sockets_payload(),
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    return path, [f"part {entry['name']}: {entry['inverted']} triangles face against their normals" for entry in meshes if entry["inverted"]]


def finish(name, budget=None, sheet=True):
    name = _safe_name(name)
    os.makedirs(OUT, exist_ok=True)
    paintlib = sys.modules.get("paintlib")
    atlases = paintlib.build_all(OUT) if paintlib is not None else []
    notes = _bake_geometry()
    report = check(budget)
    report["warnings"] = notes + report["warnings"]
    report["name"] = name
    report["blender"] = bpy.app.version_string
    if atlases:
        report["textures"] = [{"name": atlas.name, "size": atlas.size, "cached": bool(atlas.timings.get("cached")), "seconds": round(sum(atlas.timings.get(key, 0.0) for key in ("unwrap", "bake", "paint", "save")), 1)} for atlas in atlases]
    if sheet and report["objects"]:
        report["sheet"] = render_sheet(os.path.join(OUT, f"{name}_sheet.png"), textured=bool(atlases))
    sockets = sockets_payload()
    if sockets:
        parts = {_safe_name(obj.get("roblox_part", obj.name)) for obj in _asset_objects()}
        report["sockets"] = len(sockets)
        report["errors"] += [f"socket {entry['name']}: no part named {entry['part']}" for entry in sockets if entry["part"] not in parts]
        names = [entry["name"] for entry in sockets]
        report["errors"] += [f"socket name {name} is used twice" for name in sorted(set(names)) if names.count(name) > 1]
    if not report["errors"] and atlases:
        report["payload"], problems = paintlib.export_textured(os.path.join(OUT, f"{name}.json"), name, atlases, report)
        report["errors"] += problems
    elif not report["errors"]:
        report["payload"], inverted = export(os.path.join(OUT, f"{name}.json"), name, report)
        report["warnings"] += inverted
    print("BLENDLIB " + json.dumps(report))
    if report["errors"]:
        raise RuntimeError("; ".join(report["errors"]))
    return report
