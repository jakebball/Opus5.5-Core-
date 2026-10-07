"""paintlib: painted textures for blendlib assets (headless Blender 4.1+).

An asset that wants painted detail instead of (or beside) vertex colour puts pieces on an Atlas, one texture per
MeshPart, with a painter that colours every texel from baked surface data:

    import blendlib as bl
    import paintlib as pl
    import brushlib as pt

    bl.reset()
    atlas = pl.Atlas("Crate", size=512)                  # registers itself; bl.finish() bakes and paints it
    box = bl.box("Crate", (2, 2, 2), at=(0, 0, 1), bevel=0.08, segments=2)
    atlas.add(box, pt.wood(), tint=False)                # painter(context) -> RGB or RGBA per texel
    bl.finish("Crate", budget=2000)                      # sheet + <Name>.json (blendlib-textured/1 when atlases exist)

A painter is any function(context) -> (N, 3) RGB or (N, 4) RGBA array in 0..1. context carries, per covered texel:
pos (world), normal (world), ao (0 occluded .. 1 open), curvature (Cycles pointiness, 0.5 flat), edge (0 flat .. 1
on a convex edge), local (object space), coord (the PaintCoord layer, see below) and count. On a tinted part
(tint=True, Roblox SurfaceAppearance AlphaMode TintMask) alpha is the amount of castle/team tint: paint the tintable
cloth near-white with alpha 1 and anything that must keep its own colour (gold trim) with alpha 0.

Rules the pipeline keeps for you:
  - one texture per MeshPart: every piece of a part goes on the same atlas; a texture is at most 1024 square
    (EditableImage's cap) - give big assets several atlases, one per part (or per pair of mirrored parts);
  - bakes run on the GPU as ONE merged copy of the atlas's pieces per pass (a bake setup per piece was nearly
    all the time); ink outline hulls (obj["ink"]) are hidden while baking or they shade the paint;
  - the unwrap and the six bake passes are cached per atlas in OUT/<atlas>.bake.npz, keyed on the geometry of
    the atlas's pieces and of anything within ao_distance of them, so a paint-only change skips both; geometry
    must therefore be deterministic run to run (use shapelib.ellipsoid / bl.sphere, never bmesh's create_uvsphere,
    and read vertex normals through bmesh);
  - empty texture space is filled by push-pull padding so far mip levels never blend black into the islands;
  - timings per atlas land in OUT/<atlas>.timing.json.

PaintCoord: a second UV layer (COORD) an asset can author to give painters exact surface coordinates (around and
along a loft, across and along a cloth band), stored +COORD_OFFSET so it bakes as a positive colour. shapelib.py's
builders write it; context.coord is (-COORD_OFFSET, -COORD_OFFSET) where a piece has none.

UV packing (BLENDLIB_PACK_SHAPE): AUTO (default) packs island boxes and falls back to the concave packer only
for irregular islands; CONCAVE always packs tight (slow); AABB always packs boxes (instant, can waste texels).
"""

import hashlib
import json
import math
import os
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector

import blendlib as bl

COORD = "PaintCoord"
COORD_OFFSET = 8.0
# bump when the bake passes change, so cached bakes (<atlas>.bake.npz beside the textures) are not reused
BAKE_VERSION = 3
# AUTO: pack island bounding boxes (instant); re-pack with Blender's concave packer (tight, but 8-70 s per atlas)
# only when the islands are irregular AND box packing left the texture under half used. Measured on the Joust
# Tycoon armour set: that keeps the concave packer's real gains (+49% texture use on a sash) and skips the
# near-zero ones (+1% on sleeves for 17 s).
PACK_SHAPE = os.environ.get("BLENDLIB_PACK_SHAPE", "AUTO")
RECTANGULAR_ENOUGH = 0.8
COVERED_ENOUGH = 0.5
ATLASES = []
PERMUTATION = np.random.RandomState(1337).permutation(256)
PERMUTATION = np.concatenate([PERMUTATION, PERMUTATION]).astype(np.int64)
GRADIENTS = np.array([
    (1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0), (1, 0, 1), (-1, 0, 1),
    (1, 0, -1), (-1, 0, -1), (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1),
], dtype=np.float64)


def _fade(value):
    return value * value * value * (value * (value * 6 - 15) + 10)


def perlin(points):
    floor = np.floor(points)
    cell = floor.astype(np.int64) & 255
    local = points - floor
    weights = _fade(local)
    total = 0.0
    corner_values = {}
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                hashed = PERMUTATION[PERMUTATION[PERMUTATION[(cell[:, 0] + dx) & 255] + ((cell[:, 1] + dy) & 255)] + ((cell[:, 2] + dz) & 255)] % 12
                gradient = GRADIENTS[hashed]
                offset = local - np.array((dx, dy, dz), dtype=np.float64)
                corner_values[(dx, dy, dz)] = np.einsum("ij,ij->i", gradient, offset)
    wx, wy, wz = weights[:, 0], weights[:, 1], weights[:, 2]
    x00 = corner_values[(0, 0, 0)] * (1 - wx) + corner_values[(1, 0, 0)] * wx
    x10 = corner_values[(0, 1, 0)] * (1 - wx) + corner_values[(1, 1, 0)] * wx
    x01 = corner_values[(0, 0, 1)] * (1 - wx) + corner_values[(1, 0, 1)] * wx
    x11 = corner_values[(0, 1, 1)] * (1 - wx) + corner_values[(1, 1, 1)] * wx
    y0 = x00 * (1 - wy) + x10 * wy
    y1 = x01 * (1 - wy) + x11 * wy
    total = y0 * (1 - wz) + y1 * wz
    return total


def fbm(points, scale=1.0, octaves=4, stretch=(1.0, 1.0, 1.0), seed=0.0):
    points = np.asarray(points, dtype=np.float64) * np.asarray(stretch) * scale + seed * 17.13
    value = np.zeros(len(points))
    amplitude, total = 1.0, 0.0
    for octave in range(octaves):
        value += amplitude * perlin(points * (2.0 ** octave) + octave * 31.7)
        total += amplitude
        amplitude *= 0.5
    return value / total


def hex_rgb(colour):
    value = colour.lstrip("#")
    return np.array([int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)], dtype=np.float64)


def solid(count, colour):
    return np.tile(hex_rgb(colour), (count, 1))


def mix(first, second, amount):
    amount = np.clip(np.asarray(amount, dtype=np.float64), 0.0, 1.0)
    if amount.ndim == 1:
        amount = amount[:, None]
    return first * (1 - amount) + second * amount


def smoothstep(low, high, value):
    t = np.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ramp(value, stops):
    positions = np.array([position for position, _ in stops])
    colours = np.array([hex_rgb(colour) for _, colour in stops])
    out = np.empty((len(value), 3))
    for channel in range(3):
        out[:, channel] = np.interp(value, positions, colours[:, channel])
    return out


def shade(rgb, amount):
    amount = np.asarray(amount, dtype=np.float64)
    if amount.ndim == 1:
        amount = amount[:, None]
    return np.clip(rgb * amount, 0.0, 1.0)


def lift(rgb, amount, toward="FFF4DE"):
    return mix(rgb, np.tile(hex_rgb(toward), (len(rgb), 1)), amount)


def segment_distance(points, start, end):
    start, end = np.asarray(start, dtype=np.float64), np.asarray(end, dtype=np.float64)
    direction = end - start
    length_squared = max(float(direction @ direction), 1e-12)
    along = np.clip((points - start) @ direction / length_squared, 0.0, 1.0)
    nearest = start + along[:, None] * direction
    return np.linalg.norm(points - nearest, axis=1), along


def polyline_distance(points, polyline):
    best = np.full(len(points), np.inf)
    travelled = np.zeros(len(points))
    walked = 0.0
    for start, end in zip(polyline[:-1], polyline[1:]):
        distance, along = segment_distance(points, start, end)
        length = float(np.linalg.norm(np.asarray(end) - np.asarray(start)))
        closer = distance < best
        best = np.where(closer, distance, best)
        travelled = np.where(closer, walked + along * length, travelled)
        walked += length
    return best, travelled


def dots(points, centres, radius):
    best = np.full(len(points), np.inf)
    for centre in centres:
        best = np.minimum(best, np.linalg.norm(points - np.asarray(centre), axis=1))
    return best / radius


def painted_light(normal, key=(-0.35, -0.45, 0.82), strength=0.16, floor=0.86):
    key = np.asarray(key, dtype=np.float64)
    key /= np.linalg.norm(key)
    facing = normal @ key
    return floor + strength * np.clip(facing, -1.0, 1.0) + 0.06 * normal[:, 2]


class Context:
    def __init__(self, pos, normal, ao, curvature, edge, local, coord=None):
        self.pos = pos
        self.normal = normal
        self.ao = ao
        self.curvature = curvature
        self.edge = edge
        self.local = local
        self.coord = coord if coord is not None else np.full((len(pos), 2), -COORD_OFFSET)
        self.count = len(pos)


def _image(name, size, float_buffer=True):
    existing = bpy.data.images.get(name)
    if existing:
        bpy.data.images.remove(existing)
    image = bpy.data.images.new(name, size, size, alpha=True, float_buffer=float_buffer)
    image.generated_color = (0.0, 0.0, 0.0, 0.0)
    if float_buffer:
        image.colorspace_settings.name = "Non-Color"
    return image


def _pixels(image):
    width, height = image.size
    buffer = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(buffer)
    return buffer.reshape(height, width, 4)


def _push_pull(rgb, known):
    # Push-pull padding: average the known texels down a mip pyramid (2x2 box sums of colour and weight),
    # then fill each unknown texel from the finest coarser level that holds colour above it, so the
    # texture's own far mip levels never blend black into the islands.
    colours = [rgb * known[..., None]]
    weights = [known.astype(np.float64)]
    while colours[-1].shape[0] > 1:
        half = colours[-1].shape[0] // 2
        colours.append(colours[-1].reshape(half, 2, half, 2, 3).sum(axis=(1, 3)))
        weights.append(weights[-1].reshape(half, 2, half, 2).sum(axis=(1, 3)))
    filled = colours[-1] / np.maximum(weights[-1][..., None], 1e-9)
    for colour, weight in zip(reversed(colours[:-1]), reversed(weights[:-1])):
        coarse = filled.repeat(2, axis=0).repeat(2, axis=1)
        filled = np.where(weight[..., None] > 0, colour / np.maximum(weight[..., None], 1e-9), coarse)
    return filled


def reset():
    ATLASES.clear()


def use_gpu(scene):
    preferences = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
        try:
            preferences.compute_device_type = kind
        except TypeError:
            continue
        preferences.refresh_devices()
        devices = [device for device in preferences.devices if device.type == kind]
        if devices:
            for device in preferences.devices:
                device.use = device.type == kind
            scene.cycles.device = "GPU"
            return kind
    scene.cycles.device = "CPU"
    return "CPU"


def apply_modifiers(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return obj


def is_ink(obj):
    return bool(obj.get("ink")) or obj.get("stage_material") == "Ink"


def _select(objects):
    for other in list(bpy.context.selected_objects):
        other.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


class Atlas:
    def __init__(self, name, size=1024, margin=0.006, samples=48, ao_distance=0.9):
        self.name = name
        self.size = size
        self.margin = margin
        self.samples = samples
        self.ao_distance = ao_distance
        self.entries = []
        self.timings = {}
        ATLASES.append(self)

    def add(self, obj, painter, tint=False, density=1.0, team=None):
        """Put a mesh object on this atlas. tint: its part takes SurfaceAppearance TintMask (team colour).
        density scales the piece's texel density relative to the others (2.0 = twice as sharp)."""
        apply_modifiers(obj)
        obj["paint_atlas"] = self.name
        obj["team"] = bool(tint if team is None else team)
        self.entries.append((obj, painter, density))
        return obj

    def objects(self):
        return [entry[0] for entry in self.entries]

    def unwrap(self):
        objects = self.objects()
        for obj in objects:
            for layer in list(obj.data.uv_layers):
                if layer.name != COORD:
                    obj.data.uv_layers.remove(layer)
            atlas_layer = obj.data.uv_layers.new(name="UVMap")
            obj.data.uv_layers.active = atlas_layer
            atlas_layer.active_render = True
        unwrap_started = time.perf_counter()
        _select(objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=0.002, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
        projected = time.perf_counter()
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.average_islands_scale()
        bpy.ops.object.mode_set(mode="OBJECT")
        averaged = time.perf_counter()
        for obj, _, density in self.entries:
            if density != 1.0:
                layer = obj.data.uv_layers["UVMap"]
                uvs = np.empty(len(layer.data) * 2)
                layer.data.foreach_get("uv", uvs)
                layer.data.foreach_set("uv", uvs * density)
        self._pack(objects, "AABB" if PACK_SHAPE == "AUTO" else PACK_SHAPE)
        if PACK_SHAPE == "AUTO":
            fill, used = self._island_fill(objects)
            self.timings["unwrap island fill"] = fill
            self.timings["unwrap texture used"] = used
            if fill < RECTANGULAR_ENOUGH and used < COVERED_ENOUGH:
                self._pack(objects, "CONCAVE")
                self.timings["unwrap texture used"] = self._island_fill(objects)[1]
        self.timings.update({"unwrap project": projected - unwrap_started, "unwrap average": averaged - projected, "unwrap pack": time.perf_counter() - averaged})
        uvs = []
        for obj in objects:
            layer = obj.data.uv_layers["UVMap"]
            values = np.empty(len(layer.data) * 2)
            layer.data.foreach_get("uv", values)
            uvs.append(values.reshape(-1, 2))
        merged = np.concatenate(uvs)
        if np.isnan(merged).any() or merged.min() < -0.01 or merged.max() > 1.01 or (merged.max(axis=0) - merged.min(axis=0)).min() < 0.5:
            raise RuntimeError(f"atlas {self.name}: UV packing failed, bbox {merged.min(axis=0)} {merged.max(axis=0)}")

    def _pack(self, objects, shape):
        _select(objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, rotate_method="AXIS_ALIGNED", scale=True, margin_method="FRACTION", margin=self.margin, shape_method=shape)
        bpy.ops.object.mode_set(mode="OBJECT")

    def _island_fill(self, objects):
        # (island area / island bounding-box area, island area / texture): the first is near 1 for rectangular
        # islands, where box packing is already as tight as the concave packer; the second is the texture used
        from bpy_extras.bmesh_utils import bmesh_linked_uv_islands
        filled = boxed = 0.0
        for obj in objects:
            builder = bmesh.new()
            builder.from_mesh(obj.data)
            layer = builder.loops.layers.uv["UVMap"]
            for island in bmesh_linked_uv_islands(builder, layer):
                corners = []
                for face in island:
                    points = np.array([loop[layer].uv[:] for loop in face.loops])
                    corners.append(points)
                    filled += 0.5 * abs(np.dot(points[:, 0], np.roll(points[:, 1], 1)) - np.dot(points[:, 1], np.roll(points[:, 0], 1)))
                points = np.concatenate(corners)
                boxed += float(np.prod(points.max(axis=0) - points.min(axis=0)))
            builder.free()
        return filled / max(boxed, 1e-12), filled

    def _bake_material(self, image, kind, low, high):
        material = bpy.data.materials.new(f"Bake{kind}")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        target = nodes.new("ShaderNodeTexImage")
        target.image = image
        nodes.active = target
        emission = nodes.new("ShaderNodeEmission")
        geometry = nodes.new("ShaderNodeNewGeometry")
        if kind == "POS":
            shift = nodes.new("ShaderNodeVectorMath")
            shift.operation = "SUBTRACT"
            links.new(geometry.outputs["Position"], shift.inputs[0])
            shift.inputs[1].default_value = tuple(low)
            scale = nodes.new("ShaderNodeVectorMath")
            scale.operation = "DIVIDE"
            links.new(shift.outputs[0], scale.inputs[0])
            scale.inputs[1].default_value = tuple(high - low)
            links.new(scale.outputs[0], emission.inputs["Color"])
        elif kind == "NRM":
            half = nodes.new("ShaderNodeVectorMath")
            half.operation = "MULTIPLY_ADD"
            links.new(geometry.outputs["Normal"], half.inputs[0])
            half.inputs[1].default_value = (0.5, 0.5, 0.5)
            half.inputs[2].default_value = (0.5, 0.5, 0.5)
            links.new(half.outputs[0], emission.inputs["Color"])
        elif kind == "COORD":
            coord = nodes.new("ShaderNodeUVMap")
            coord.uv_map = COORD
            links.new(coord.outputs["UV"], emission.inputs["Color"])
        elif kind == "ID":
            info = nodes.new("ShaderNodeAttribute")
            info.attribute_type = "GEOMETRY"
            info.attribute_name = "atlas_id"
            divide = nodes.new("ShaderNodeMath")
            divide.operation = "DIVIDE"
            links.new(info.outputs["Fac"], divide.inputs[0])
            divide.inputs[1].default_value = 1000.0
            links.new(divide.outputs[0], emission.inputs["Color"])
        elif kind == "CURV":
            combine = nodes.new("ShaderNodeCombineXYZ")
            links.new(geometry.outputs["Pointiness"], combine.inputs[1])
            bevel = nodes.new("ShaderNodeBevel")
            bevel.samples = 8
            bevel.inputs["Radius"].default_value = 0.035
            dot = nodes.new("ShaderNodeVectorMath")
            dot.operation = "DOT_PRODUCT"
            links.new(bevel.outputs["Normal"], dot.inputs[0])
            links.new(geometry.outputs["Normal"], dot.inputs[1])
            links.new(dot.outputs["Value"], combine.inputs[2])
            links.new(combine.outputs[0], emission.inputs["Color"])
        links.new(emission.outputs[0], output.inputs["Surface"])
        return material

    def _merged(self):
        # every piece in world space in one mesh, with its entry number (1-based) on each face for the ID pass
        builder = bmesh.new()
        for index, obj in enumerate(self.objects()):
            mesh = obj.data.copy()
            mesh.transform(obj.matrix_world)
            if obj.matrix_world.determinant() < 0:
                mesh.flip_normals()
            identity = mesh.attributes.get("atlas_id") or mesh.attributes.new("atlas_id", "FLOAT", "FACE")
            identity.data.foreach_set("value", [float(index + 1)] * len(mesh.polygons))
            builder.from_mesh(mesh)
            bpy.data.meshes.remove(mesh)
        mesh = bpy.data.meshes.new(f"{self.name}_Bake")
        builder.to_mesh(mesh)
        builder.free()
        mesh.uv_layers.active = mesh.uv_layers["UVMap"]
        merged = bpy.data.objects.new(f"{self.name}_Bake", mesh)
        bpy.context.scene.collection.objects.link(merged)
        return merged

    def bake(self):
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        use_gpu(scene)
        scene.cycles.samples = 1
        scene.render.bake.margin = 6
        scene.render.bake.margin_type = "EXTEND"
        scene.render.bake.use_clear = True
        objects = self.objects()
        bpy.context.view_layer.update()
        corners = []
        for obj in objects:
            corners += [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        low = np.array([min(corner[axis] for corner in corners) for axis in range(3)]) - 0.01
        high = np.array([max(corner[axis] for corner in corners) for axis in range(3)]) + 0.01
        # Ink hulls wrap every piece a few hundredths out; left in, they occlude the AO bake and darken the paint.
        # The pieces themselves bake as one merged copy (one bake setup per pass instead of one per piece,
        # which was nearly all the bake time), so the originals are hidden while the copy stands in for them.
        hidden = [obj for obj in scene.objects if (is_ink(obj) or obj in objects) and not obj.hide_render]
        for obj in hidden:
            obj.hide_render = True
        merged = self._merged()
        buffers = {}
        world = scene.world or bpy.data.worlds.new("BakeWorld")
        scene.world = world
        world.light_settings.distance = self.ao_distance
        for kind in ("POS", "NRM", "ID", "CURV", "COORD", "AO"):
            pass_started = time.perf_counter()
            image = _image(f"{self.name}_{kind}", self.size)
            material = self._bake_material(image, kind if kind != "AO" else "NRM", low, high)
            merged.data.materials.clear()
            merged.data.materials.append(material)
            _select([merged])
            if kind == "AO":
                scene.cycles.samples = self.samples
                bpy.ops.object.bake(type="AO")
                scene.cycles.samples = 1
            else:
                scene.cycles.samples = 12 if kind == "CURV" else 1
                bpy.ops.object.bake(type="EMIT")
            buffers[kind] = _pixels(image)
            bpy.data.materials.remove(material)
            self.timings[f"bake {kind}"] = time.perf_counter() - pass_started
        bake_mesh = merged.data
        bpy.data.objects.remove(merged)
        bpy.data.meshes.remove(bake_mesh)
        for obj in hidden:
            obj.hide_render = False
        self.low, self.high = low, high
        self.buffers = buffers
        if os.environ.get("PAINT_DUMP"):
            for kind, data in buffers.items():
                dump = bpy.data.images.new(f"dump_{kind}", self.size, self.size, alpha=True)
                values = data.copy()
                values[..., 3] = 1.0
                dump.pixels.foreach_set(values.ravel())
                dump.filepath_raw = os.path.join(os.environ["PAINT_DUMP"], f"{self.name}_{kind}.png")
                dump.file_format = "PNG"
                dump.save()
                bpy.data.images.remove(dump)
        return buffers

    def paint(self):
        buffers = self.buffers
        size = self.size
        ids = np.rint(buffers["ID"][..., 0] * 1000.0).astype(np.int64)
        # a texel is on a piece where the ID pass wrote one (IDs start at 1); bake alpha is not reliable
        covered = buffers["ID"][..., 0] > 0.0005
        rgba = np.zeros((size, size, 4), dtype=np.float64)
        rgba[..., 3] = 1.0
        position = buffers["POS"][..., :3].astype(np.float64) * (self.high - self.low) + self.low
        normal = buffers["NRM"][..., :3].astype(np.float64) * 2.0 - 1.0
        normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)
        ao = buffers["AO"][..., 0].astype(np.float64)
        curvature = buffers["CURV"][..., 1].astype(np.float64)
        edge = 1.0 - np.clip(buffers["CURV"][..., 2].astype(np.float64), 0.0, 1.0)
        coord = buffers["COORD"][..., :2].astype(np.float64) - COORD_OFFSET
        for index, (obj, painter, _) in enumerate(self.entries):
            mask = covered & (ids == index + 1)
            if not mask.any():
                continue
            inverse = np.array(obj.matrix_world.inverted())
            pos = position[mask]
            local = pos @ inverse[:3, :3].T + inverse[:3, 3]
            context = Context(pos, normal[mask], ao[mask], curvature[mask], edge[mask], local, coord[mask])
            painter_started = time.perf_counter()
            if os.environ.get("PAINT_STATS"):
                print("PAINTSTATS", obj.name, "curv", np.percentile(context.curvature, [5, 50, 95]).round(3), "edge", np.percentile(context.edge, [5, 50, 95]).round(3), "ao", np.percentile(context.ao, [5, 50, 95]).round(3))
            painted = np.clip(painter(context), 0.0, 1.0)
            self.timings[f"paint {obj.name}"] = time.perf_counter() - painter_started
            # a painter may return RGBA: alpha is the TintMask amount on team parts (0 keeps the paint untinted)
            if painted.shape[1] == 4:
                rgba[mask] = painted
            else:
                rgba[mask, :3] = painted
            if os.environ.get("PAINT_STATS"):
                painted_values = rgba[mask, :3]
                print("PAINTRGB", obj.name, "texels", int(mask.sum()), "mean", painted_values.mean(axis=0).round(3), "p5", np.percentile(painted_values.mean(axis=1), 5).round(3), "p95", np.percentile(painted_values.mean(axis=1), 95).round(3))
        filled = covered.copy()
        for _ in range(12):
            if filled.all():
                break
            grown = rgba.copy()
            count = np.zeros((size, size))
            total = np.zeros((size, size, 3))
            for shift_y, shift_x in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                moved = np.roll(np.roll(filled, shift_y, 0), shift_x, 1)
                colours = np.roll(np.roll(rgba[..., :3], shift_y, 0), shift_x, 1)
                total += colours * moved[..., None]
                count += moved
            frontier = (~filled) & (count > 0)
            grown[frontier, :3] = total[frontier] / count[frontier, None]
            rgba = grown
            filled = filled | frontier
        if not filled.all():
            rgba[~filled, :3] = _push_pull(rgba[..., :3], filled)[~filled]
        self.rgba = rgba
        return rgba

    def save(self, folder):
        os.makedirs(folder, exist_ok=True)
        size = self.size
        image = bpy.data.images.new(f"{self.name}_Paint", size, size, alpha=True)
        image.pixels.foreach_set(self.rgba.astype(np.float32).ravel())
        path = os.path.join(folder, f"{self.name}.png")
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        bpy.data.images.remove(image)
        raw = (np.clip(self.rgba[::-1], 0.0, 1.0) * 255 + 0.5).astype(np.uint8)
        raw_path = os.path.join(folder, f"{self.name}.rgba")
        raw.tofile(raw_path)
        self.path = path
        self.raw_path = raw_path
        for obj, _, _ in self.entries:
            obj["paint_image"] = path
        self._vertex_colours()
        return path

    def _vertex_colours(self):
        size = self.size
        for obj, _, _ in self.entries:
            mesh = obj.data
            layer = mesh.uv_layers["UVMap"]
            uvs = np.empty(len(layer.data) * 2)
            layer.data.foreach_get("uv", uvs)
            uvs = uvs.reshape(-1, 2)
            columns = np.clip((uvs[:, 0] * size).astype(np.int64), 0, size - 1)
            rows = np.clip((uvs[:, 1] * size).astype(np.int64), 0, size - 1)
            sampled = self.rgba[rows, columns, :3]
            colours = np.ones((len(sampled), 4), dtype=np.float32)
            for polygon in mesh.polygons:
                start, count = polygon.loop_start, polygon.loop_total
                colours[start:start + count, :3] = sampled[start:start + count].mean(axis=0)
            colour_layer = mesh.color_attributes.get(bl.COLOUR_ATTRIBUTE)
            if colour_layer is None or colour_layer.domain != "CORNER":
                if colour_layer is not None:
                    mesh.color_attributes.remove(colour_layer)
                colour_layer = mesh.color_attributes.new(bl.COLOUR_ATTRIBUTE, "BYTE_COLOR", "CORNER")
            colour_layer.data.foreach_set("color_srgb", colours.ravel())

    def _bake_key(self):
        # everything a bake reads: this atlas's settings, its pieces (order is the ID pass) with their
        # geometry and UVs, and every other mesh that can occlude it in the AO pass
        digest = hashlib.sha1(repr((BAKE_VERSION, PACK_SHAPE, self.name, self.size, self.margin, self.samples, self.ao_distance)).encode())
        mine = self.objects()
        names = {obj.name for obj in mine}

        def bounds(obj):
            corners = np.array([tuple(obj.matrix_world @ Vector(corner)) for corner in obj.bound_box])
            return corners.min(axis=0), corners.max(axis=0)

        # AO rays stop at ao_distance, so only meshes within that reach of this atlas can change its bake
        spans = [bounds(obj) for obj in mine]
        low = np.min([span[0] for span in spans], axis=0) - self.ao_distance
        high = np.max([span[1] for span in spans], axis=0) + self.ao_distance

        def near(obj):
            other_low, other_high = bounds(obj)
            return bool(np.all(other_low <= high) and np.all(other_high >= low))

        others = sorted((obj for obj in bpy.context.scene.objects if obj.type == "MESH" and not obj.hide_render and not is_ink(obj) and obj.name not in names and near(obj)), key=lambda item: item.name)
        for obj in mine + others:
            mesh = obj.data
            digest.update(obj.name.encode())
            digest.update(np.array(obj.matrix_world, dtype=np.float64).tobytes())
            points = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
            mesh.vertices.foreach_get("co", points)
            digest.update(points.tobytes())
            if obj.name in names:
                corners = np.empty(len(mesh.loops), dtype=np.int32)
                mesh.loops.foreach_get("vertex_index", corners)
                digest.update(corners.tobytes())
                layer = mesh.uv_layers.get(COORD)
                if layer is not None:
                    values = np.empty(len(layer.data) * 2, dtype=np.float32)
                    layer.data.foreach_get("uv", values)
                    digest.update(values.tobytes())
        return digest.hexdigest()

    def _save_bake(self, path, key):
        buffers = self.buffers
        uvs = {}
        for index, obj in enumerate(self.objects()):
            layer = obj.data.uv_layers["UVMap"]
            values = np.empty(len(layer.data) * 2, dtype=np.float32)
            layer.data.foreach_get("uv", values)
            uvs[f"uv{index}"] = values
        np.savez(path, key=np.array(key), low=self.low, high=self.high, **uvs, POS=buffers["POS"],
                 NRM=buffers["NRM"][..., :3].astype(np.float16), ID=buffers["ID"][..., 0],
                 CURV=buffers["CURV"][..., 1:3].astype(np.float16), COORD=buffers["COORD"][..., :2],
                 AO=buffers["AO"][..., 0].astype(np.float16))

    def _load_bake(self, path, key):
        if not os.path.exists(path):
            return False
        with np.load(path) as stored:
            if str(stored["key"]) != key:
                return False
            for index, obj in enumerate(self.objects()):
                values = stored[f"uv{index}"]
                mesh = obj.data
                for layer in list(mesh.uv_layers):
                    if layer.name != COORD:
                        mesh.uv_layers.remove(layer)
                layer = mesh.uv_layers.new(name="UVMap")
                mesh.uv_layers.active = layer
                layer.active_render = True
                if len(layer.data) * 2 != values.size:
                    return False
                layer.data.foreach_set("uv", values)

            def expand(values, first):
                values = values.astype(np.float32)
                if values.ndim == 2:
                    values = values[..., None]
                out = np.zeros((self.size, self.size, 4), dtype=np.float32)
                out[..., first:first + values.shape[-1]] = values
                return out

            self.buffers = {
                "POS": stored["POS"].astype(np.float32), "NRM": expand(stored["NRM"], 0), "ID": expand(stored["ID"], 0),
                "CURV": expand(stored["CURV"], 1), "COORD": expand(stored["COORD"], 0), "AO": expand(stored["AO"], 0),
            }
            self.low, self.high = np.array(stored["low"]), np.array(stored["high"])
        return True

    def build(self, folder):
        started = time.perf_counter()
        cache = os.path.join(folder, f"{self.name}.bake.npz")
        key = self._bake_key()
        hit = self._load_bake(cache, key)
        unwrapped = baked = time.perf_counter()
        if not hit:
            self.unwrap()
            unwrapped = time.perf_counter()
            self.bake()
            self._save_bake(cache, key)
            # paint from the cached precision (float16 normals, AO, curvature) so a first build and every
            # cached rebuild of an asset paint byte for byte the same
            self._load_bake(cache, key)
            baked = time.perf_counter()
        self.paint()
        painted = time.perf_counter()
        path = self.save(folder)
        self.timings.update({"unwrap": unwrapped - started, "bake": baked - unwrapped, "cached": hit, "paint": painted - baked, "save": time.perf_counter() - painted})
        with open(os.path.join(folder, f"{self.name}.timing.json"), "w", encoding="utf-8") as handle:
            json.dump(self.timings, handle, indent=1)
        return path


def build_all(folder):
    """Bake (or load from cache) and paint every atlas made since reset. Returns the atlases built."""
    built = []
    for atlas in ATLASES:
        atlas.entries = [entry for entry in atlas.entries if entry[0].name in bpy.data.objects]
        if atlas.entries:
            atlas.build(folder)
            built.append(atlas)
    return built


def _solid_colour(obj):
    if obj.get("solid_colour"):
        return str(obj["solid_colour"])
    layer = obj.data.color_attributes.get(bl.COLOUR_ATTRIBUTE)
    if layer is not None and len(layer.data):
        values = np.empty(len(layer.data) * 4, dtype=np.float32)
        layer.data.foreach_get("color_srgb", values)
        mean = values.reshape(-1, 4)[:, :3].mean(axis=0)
        return "%02X%02X%02X" % tuple(int(round(channel * 255)) for channel in np.clip(mean, 0.0, 1.0))
    return "FFFFFF"


def export_textured(path, name, atlases, report=None):
    """Write the blendlib-textured/1 payload: textured parts carry UVs and a texture key, the rest a solid colour."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    groups = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render or obj.get("stage_only"):
            continue
        groups.setdefault(bl._safe_name(obj.get("roblox_part", obj.name)), []).append(obj)
    meshes = []
    textures = {}
    for atlas in atlases:
        textures[atlas.name] = {"file": os.path.abspath(atlas.raw_path), "png": os.path.abspath(atlas.path), "width": atlas.size, "height": atlas.size}
    problems = []
    for part, objects in groups.items():
        positions, normals, uvs, faces = [], [], [], []
        offset = 0
        texture = None
        tint = False
        for obj in objects:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            mesh.calc_loop_triangles()
            count = len(mesh.loop_triangles)
            if count == 0:
                evaluated.to_mesh_clear()
                continue
            atlas_name = obj.get("paint_atlas")
            if atlas_name and texture and atlas_name != texture:
                problems.append(f"part {part}: pieces on two atlases ({texture}, {atlas_name}); a MeshPart holds one texture")
            texture = atlas_name or texture
            tint = tint or bool(obj.get("team"))
            corner_vertices = np.empty(count * 3, dtype=np.int64)
            mesh.loop_triangles.foreach_get("vertices", corner_vertices)
            corner_loops = np.empty(count * 3, dtype=np.int64)
            mesh.loop_triangles.foreach_get("loops", corner_loops)
            points = np.empty(len(mesh.vertices) * 3)
            mesh.vertices.foreach_get("co", points)
            loop_normals = np.empty(len(mesh.loops) * 3)
            mesh.corner_normals.foreach_get("vector", loop_normals)
            layer = mesh.uv_layers.get("UVMap")
            loop_uvs = np.zeros(len(mesh.loops) * 2)
            if layer is not None:
                layer.data.foreach_get("uv", loop_uvs)
            evaluated.to_mesh_clear()
            transform = np.array(obj.matrix_world)
            linear = transform[:3, :3]
            world = points.reshape(-1, 3) @ linear.T + transform[:3, 3]
            corner_normals = loop_normals.reshape(-1, 3)[corner_loops] @ np.linalg.pinv(linear)
            corner_normals /= np.maximum(np.linalg.norm(corner_normals, axis=1, keepdims=True), 1e-12)
            corner_uvs = loop_uvs.reshape(-1, 2)[corner_loops]
            triangle_vertices = corner_vertices.reshape(-1, 3)
            if np.linalg.det(linear) < 0:
                order = [0, 2, 1]
                triangle_vertices = triangle_vertices[:, order]
                corner_normals = corner_normals.reshape(-1, 3, 3)[:, order].reshape(-1, 3)
                corner_uvs = corner_uvs.reshape(-1, 3, 2)[:, order].reshape(-1, 2)
            first, second, third = world[triangle_vertices[:, 0]], world[triangle_vertices[:, 1]], world[triangle_vertices[:, 2]]
            keep = np.linalg.norm(np.cross(second - first, third - first), axis=1) > 2e-9
            positions.append(world)
            faces.append(triangle_vertices[keep] + offset)
            normals.append(corner_normals.reshape(-1, 3, 3)[keep].reshape(-1, 3))
            uvs.append(corner_uvs.reshape(-1, 3, 2)[keep].reshape(-1, 2))
            offset += len(world)
        if not faces:
            continue
        all_points = np.concatenate(positions)
        all_faces = np.concatenate(faces)
        all_normals = np.concatenate(normals)
        all_uvs = np.concatenate(uvs)
        roblox_points = np.stack([-all_points[:, 0], all_points[:, 2], all_points[:, 1]], axis=1)
        roblox_normals = np.stack([-all_normals[:, 0], all_normals[:, 2], all_normals[:, 1]], axis=1)
        roblox_uvs = np.stack([all_uvs[:, 0], 1.0 - all_uvs[:, 1]], axis=1)
        count = len(all_faces)
        used, vertex_index = np.unique(all_faces.ravel(), return_inverse=True)
        vertex_index = vertex_index.reshape(count, 3)
        unique_normals, normal_index = np.unique(np.rint(roblox_normals * 1000).astype(np.int64), axis=0, return_inverse=True)
        unique_uvs, uv_index = np.unique(np.rint(roblox_uvs * 10000).astype(np.int64), axis=0, return_inverse=True)
        table = np.concatenate([vertex_index, normal_index.reshape(count, 3), uv_index.reshape(count, 3)], axis=1) + 1
        first = objects[0]
        meshes.append({
            "name": part,
            "material": str(first.get("roblox_material", "SmoothPlastic")),
            "collision": str(first.get("roblox_collision", "Box")),
            "collide": bool(first.get("roblox_collide", False)),
            "shadow": bool(first.get("roblox_shadow", True)),
            "attributes": bl.part_attributes(objects),
            "triangles": count,
            "texture": texture,
            "colour": None if texture else _solid_colour(first),
            "tint": tint,
            "v": np.rint(roblox_points[used] * 1000).astype(np.int64).ravel().tolist(),
            "n": unique_normals.ravel().tolist(),
            "u": unique_uvs.ravel().tolist(),
            "t": table.ravel().tolist(),
        })
    payload = {
        "format": "blendlib-textured/1",
        "name": name,
        "source": os.path.basename(bl.SOURCE),
        "blender": bpy.app.version_string,
        "quantum": 1000,
        "uvQuantum": 10000,
        "size": report["size"] if report else None,
        "textures": textures,
        "meshes": meshes,
        "sockets": bl.sockets_payload(),
        "triangles": sum(mesh["triangles"] for mesh in meshes),
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    return path, problems


