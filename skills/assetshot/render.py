import json
import math
import os
import re
import sys
import time
import traceback

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

POSITION_SCALE = 10000.0
NORMAL_SCALE = 1000.0
UV_SCALE = 10000.0
CAMERA_WIDTH = 960
VIEW_TILE = (640, 480)
SHEET_WIDTH = 1920
VIEW_FOV = 30.0
FOCUS_FOV = 30.0
DEFAULT_VIEWS = ["persp", "front", "left", "right", "back", "top"]
BACKDROP = (0.42, 0.46, 0.53)
SHEET_BACKGROUND = (0.10, 0.11, 0.13)
SKY_ZENITH = (0.47, 0.69, 0.87)
SKY_HORIZON = (0.86, 0.90, 0.94)
SKY_GROUND = (0.33, 0.35, 0.39)
SKY_HAZE = (0.78, 0.82, 0.87)
SUN_ENERGY = 3.4
SKY_STRENGTH = 1.7
NEON_STRENGTH = 2.2
STUD_HALF_WIDTH = 0.275
STUD_EDGE = 0.02
STUD_HEIGHT = 0.2
STUD_ROUNDNESS = 6.0
LABEL_SCALE = 2
LABEL_PAD = 6

ROUGHNESS = {
    "Plastic": 0.55,
    "SmoothPlastic": 0.32,
    "Glass": 0.05,
    "Ice": 0.12,
    "Marble": 0.3,
    "Metal": 0.35,
    "DiamondPlate": 0.4,
    "Foil": 0.22,
    "CorrodedMetal": 0.65,
    "ForceField": 0.3,
}
METALLIC = {"Metal": 0.85, "DiamondPlate": 0.8, "Foil": 1.0, "CorrodedMetal": 0.5}

FACES = {
    "Front": ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    "Back": ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    "Right": ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    "Left": ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
    "Top": ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
    "Bottom": ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
}

FORWARDS = {"-z": (0, 0, -1), "+z": (0, 0, 1), "-x": (-1, 0, 0), "+x": (1, 0, 0)}

GLYPHS = {
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11111 00010 00100 00010 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 01100",
    "-": "00000 00000 00000 11111 00000 00000 00000",
    "+": "00000 00100 00100 11111 00100 00100 00000",
    ".": "00000 00000 00000 00000 00000 01100 01100",
    ",": "00000 00000 00000 00000 01100 00100 01000",
    "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000",
    "/": "00001 00001 00010 00100 01000 10000 10000",
    ":": "00000 01100 01100 00000 01100 01100 00000",
    "_": "00000 00000 00000 00000 00000 00000 11111",
    "%": "11000 11001 00010 00100 01000 10011 00011",
    "=": "00000 00000 11111 00000 11111 00000 00000",
    "?": "01110 10001 00001 00010 00100 00000 00100",
    "'": "00100 00100 01000 00000 00000 00000 00000",
}


def srgb_to_linear(value):
    value = min(max(float(value), 0.0), 1.0)
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def linear_array(values):
    values = np.clip(values, 0.0, 1.0)
    return np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)


def matrix_from(components):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0.0, 0.0, 0.0, 1.0)))


def look_matrix(location, back, up):
    axis_z = Vector(back).normalized()
    axis_x = Vector(up).cross(axis_z)
    if axis_x.length < 1e-6:
        axis_x = Vector((1.0, 0.0, 0.0)).cross(axis_z)
        if axis_x.length < 1e-6:
            axis_x = Vector((0.0, 0.0, 1.0)).cross(axis_z)
    axis_x.normalize()
    axis_y = axis_z.cross(axis_x)
    matrix = Matrix((axis_x, axis_y, axis_z)).transposed().to_4x4()
    matrix.translation = Vector(location)
    return matrix


def axis_name(vector):
    names = ("X", "Y", "Z")
    index = max(range(3), key=lambda axis: abs(vector[axis]))
    return ("+" if vector[index] > 0 else "-") + names[index]


def slug(text):
    return re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_")[:48] or "tile"


def use_gpu(scene):
    try:
        preferences = bpy.context.preferences.addons["cycles"].preferences
    except KeyError:
        scene.cycles.device = "CPU"
        return "CPU"
    for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
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
            return f"{kind} {devices[0].name}"
    scene.cycles.device = "CPU"
    return "CPU"


def socket_math(nodes, links, operation, first, second=None):
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    for index, value in enumerate((first, second)):
        if value is None:
            continue
        if isinstance(value, (int, float)):
            node.inputs[index].default_value = value
        else:
            links.new(value, node.inputs[index])
    return node.outputs[0]


def separate(nodes, links, vector):
    node = nodes.new("ShaderNodeSeparateXYZ")
    links.new(vector, node.inputs[0])
    return node.outputs["X"], node.outputs["Y"], node.outputs["Z"]


def one_sided(nodes, links, surface):
    geometry = nodes.new("ShaderNodeNewGeometry")
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    cull = nodes.new("ShaderNodeMixShader")
    links.new(geometry.outputs["Backfacing"], cull.inputs[0])
    links.new(surface, cull.inputs[1])
    links.new(transparent.outputs[0], cull.inputs[2])
    return cull.outputs[0]


class Renderer:
    def __init__(self, data, out_dir):
        self.data = data
        self.out_dir = out_dir
        self.parts = data["parts"]
        self.meshes = data.get("meshes", {})
        self.images = data.get("images", {})
        self.options = data.get("options", {})
        self.arrays = {}
        self.mesh_cache = {}
        self.triangle_cache = {}
        self.material_cache = {}
        self.image_cache = {}
        self.warnings = []
        self.object_count = 0
        self.triangle_count = 0
        self.scene = bpy.context.scene
        for leftover in list(bpy.data.objects):
            bpy.data.objects.remove(leftover, do_unlink=True)
        self.device = self.setup_scene()
        self.flat_switch = self.setup_world()
        self.setup_sun()
        camera_data = bpy.data.cameras.new("ShotCamera")
        self.camera = bpy.data.objects.new("ShotCamera", camera_data)
        self.scene.collection.objects.link(self.camera)
        self.scene.camera = self.camera

    def setup_scene(self):
        scene = self.scene
        scene.render.engine = "CYCLES"
        device = use_gpu(scene)
        cycles = scene.cycles
        cycles.samples = int(self.options.get("samples", 24))
        cycles.use_adaptive_sampling = True
        cycles.adaptive_threshold = 0.03
        cycles.use_denoising = True
        cycles.denoiser = "OPTIX" if device.startswith("OPTIX") else "OPENIMAGEDENOISE"
        cycles.max_bounces = 4
        cycles.diffuse_bounces = 2
        cycles.glossy_bounces = 2
        cycles.transmission_bounces = 4
        cycles.transparent_max_bounces = 24
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
        scene.render.image_settings.file_format = "PNG"
        icon = self.options.get("icon")
        scene.render.image_settings.color_mode = "RGBA" if icon else "RGB"
        scene.render.resolution_percentage = 100
        scene.render.film_transparent = bool(icon)
        return device

    def setup_world(self):
        world = bpy.data.worlds.new("ShotSky")
        self.scene.world = world
        world.use_nodes = True
        nodes, links = world.node_tree.nodes, world.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputWorld")
        coordinates = nodes.new("ShaderNodeTexCoord")
        _, height, _ = separate(nodes, links, coordinates.outputs["Generated"])
        remap = nodes.new("ShaderNodeMapRange")
        remap.inputs["From Min"].default_value = -0.15
        remap.inputs["From Max"].default_value = 1.0
        links.new(height, remap.inputs["Value"])

        def gradient(below_horizon, strength):
            ramp = nodes.new("ShaderNodeValToRGB")
            elements = ramp.color_ramp.elements
            elements[0].position = 0.0
            elements[0].color = (*[srgb_to_linear(value) for value in below_horizon], 1.0)
            elements[1].position = 1.0
            elements[1].color = (*[srgb_to_linear(value) for value in SKY_ZENITH], 1.0)
            elements.new(0.135).color = (*[srgb_to_linear(value) for value in SKY_HORIZON], 1.0)
            elements.new(0.11).color = (*[srgb_to_linear(value) for value in below_horizon], 1.0)
            links.new(remap.outputs["Result"], ramp.inputs["Fac"])
            background = nodes.new("ShaderNodeBackground")
            background.inputs["Strength"].default_value = strength
            links.new(ramp.outputs["Color"], background.inputs["Color"])
            return background.outputs["Background"]

        lighting_sky = gradient(SKY_GROUND, SKY_STRENGTH)
        seen_sky = gradient(SKY_HAZE, 1.0)
        backdrop = nodes.new("ShaderNodeBackground")
        backdrop.inputs["Color"].default_value = (*[srgb_to_linear(value) for value in BACKDROP], 1.0)
        backdrop.inputs["Strength"].default_value = 1.0
        switch = nodes.new("ShaderNodeValue")
        switch.outputs[0].default_value = 0.0
        seen = nodes.new("ShaderNodeMixShader")
        links.new(switch.outputs[0], seen.inputs[0])
        links.new(seen_sky, seen.inputs[1])
        links.new(backdrop.outputs["Background"], seen.inputs[2])
        light_path = nodes.new("ShaderNodeLightPath")
        mix = nodes.new("ShaderNodeMixShader")
        links.new(light_path.outputs["Is Camera Ray"], mix.inputs[0])
        links.new(lighting_sky, mix.inputs[1])
        links.new(seen.outputs["Shader"], mix.inputs[2])
        links.new(mix.outputs["Shader"], output.inputs["Surface"])
        return switch

    def setup_sun(self):
        lighting = self.data.get("lighting") or {}
        direction = Vector(lighting.get("sun", (-0.55, 0.72, -0.4)))
        if direction.length < 1e-6 or direction.normalized().y < 0.2:
            direction = Vector((-0.55, 0.72, -0.4))
        direction.normalize()
        sun_data = bpy.data.lights.new("ShotSun", "SUN")
        sun_data.energy = SUN_ENERGY
        sun_data.angle = math.radians(6)
        sun_data.color = (1.0, 0.98, 0.95)
        sun = bpy.data.objects.new("ShotSun", sun_data)
        sun.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        self.scene.collection.objects.link(sun)

    def stud_normal(self, nodes, links, tile):
        coordinates = nodes.new("ShaderNodeTexCoord")
        geometry = nodes.new("ShaderNodeNewGeometry")
        transform = nodes.new("ShaderNodeVectorTransform")
        transform.vector_type = "NORMAL"
        transform.convert_from = "WORLD"
        transform.convert_to = "OBJECT"
        links.new(geometry.outputs["True Normal"], transform.inputs["Vector"])
        normal_x, normal_y, normal_z = separate(nodes, links, transform.outputs["Vector"])
        point_x, point_y, point_z = separate(nodes, links, coordinates.outputs["Object"])
        absolute_x = socket_math(nodes, links, "ABSOLUTE", normal_x)
        absolute_y = socket_math(nodes, links, "ABSOLUTE", normal_y)
        absolute_z = socket_math(nodes, links, "ABSOLUTE", normal_z)
        use_x = socket_math(nodes, links, "MULTIPLY", socket_math(nodes, links, "GREATER_THAN", absolute_x, absolute_y), socket_math(nodes, links, "GREATER_THAN", absolute_x, absolute_z))
        use_y = socket_math(nodes, links, "MULTIPLY", socket_math(nodes, links, "SUBTRACT", 1.0, use_x), socket_math(nodes, links, "GREATER_THAN", absolute_y, absolute_z))
        across = socket_math(nodes, links, "ADD", point_x, socket_math(nodes, links, "MULTIPLY", use_x, socket_math(nodes, links, "SUBTRACT", point_z, point_x)))
        along = socket_math(nodes, links, "ADD", point_y, socket_math(nodes, links, "MULTIPLY", use_y, socket_math(nodes, links, "SUBTRACT", point_z, point_y)))
        cell_u = socket_math(nodes, links, "FRACT", socket_math(nodes, links, "DIVIDE", across, tile))
        cell_v = socket_math(nodes, links, "FRACT", socket_math(nodes, links, "DIVIDE", along, tile))
        offset_u = socket_math(nodes, links, "ABSOLUTE", socket_math(nodes, links, "SUBTRACT", cell_u, 0.5))
        offset_v = socket_math(nodes, links, "ABSOLUTE", socket_math(nodes, links, "SUBTRACT", cell_v, 0.5))
        rounded = socket_math(
            nodes,
            links,
            "POWER",
            socket_math(nodes, links, "ADD", socket_math(nodes, links, "POWER", offset_u, STUD_ROUNDNESS), socket_math(nodes, links, "POWER", offset_v, STUD_ROUNDNESS)),
            1.0 / STUD_ROUNDNESS,
        )
        profile = nodes.new("ShaderNodeMapRange")
        profile.interpolation_type = "SMOOTHSTEP"
        profile.inputs["From Min"].default_value = STUD_HALF_WIDTH - STUD_EDGE
        profile.inputs["From Max"].default_value = STUD_HALF_WIDTH + STUD_EDGE
        profile.inputs["To Min"].default_value = 1.0
        profile.inputs["To Max"].default_value = 0.0
        links.new(rounded, profile.inputs["Value"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 1.0
        bump.inputs["Distance"].default_value = tile * STUD_HEIGHT
        links.new(profile.outputs["Result"], bump.inputs["Height"])
        return bump.outputs["Normal"]

    def image(self, path):
        image = self.image_cache.get(path)
        if image is None:
            image = bpy.data.images.load(path, check_existing=True)
            image.alpha_mode = "STRAIGHT"
            self.image_cache[path] = image
        return image

    def material(self, material_name, tile, texture_path, alpha_mode="Transparency"):
        key = (material_name, tile, texture_path, alpha_mode)
        cached = self.material_cache.get(key)
        if cached:
            return cached
        name = material_name + ("" if tile is None else f"_studs{tile:g}") + ("" if texture_path is None else "_textured")
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        info = nodes.new("ShaderNodeObjectInfo")
        paint = nodes.new("ShaderNodeVertexColor")
        paint.layer_name = "Col"
        tint = nodes.new("ShaderNodeVectorMath")
        tint.operation = "MULTIPLY"
        links.new(paint.outputs["Color"], tint.inputs[0])
        links.new(info.outputs["Color"], tint.inputs[1])
        color = tint.outputs["Vector"]
        alpha = info.outputs["Alpha"]
        if texture_path:
            texture = nodes.new("ShaderNodeTexImage")
            texture.image = self.image(texture_path)
            if alpha_mode != "Transparency":
                # alpha is a tint amount or ignored, not coverage: straight alpha would black out alpha-0 texels
                texture.image.alpha_mode = "CHANNEL_PACKED"
            mapping = nodes.new("ShaderNodeUVMap")
            mapping.uv_map = "UVMap"
            links.new(mapping.outputs["UV"], texture.inputs["Vector"])
            # SurfaceAppearance.AlphaMode decides what the texture's alpha means: Transparency (and plain
            # TextureIDs) cut the surface, TintMask is how much SurfaceAppearance.Color (the object colour here)
            # tints the texel, Overlay lays the texture over the part colour, Opaque ignores alpha
            surface_colour = color
            if alpha_mode == "TintMask":
                amount = nodes.new("ShaderNodeMix")
                amount.data_type = "RGBA"
                links.new(texture.outputs["Alpha"], amount.inputs["Factor"])
                amount.inputs["A"].default_value = (1.0, 1.0, 1.0, 1.0)
                links.new(color, amount.inputs["B"])
                surface_colour = amount.outputs["Result"]
            textured = nodes.new("ShaderNodeVectorMath")
            textured.operation = "MULTIPLY"
            links.new(texture.outputs["Color"], textured.inputs[0])
            links.new(surface_colour, textured.inputs[1])
            color = textured.outputs["Vector"]
            if alpha_mode == "Overlay":
                overlay = nodes.new("ShaderNodeMix")
                overlay.data_type = "RGBA"
                links.new(texture.outputs["Alpha"], overlay.inputs["Factor"])
                links.new(surface_colour, overlay.inputs["A"])
                links.new(texture.outputs["Color"], overlay.inputs["B"])
                color = overlay.outputs["Result"]
            elif alpha_mode == "Transparency":
                alpha = socket_math(nodes, links, "MULTIPLY", texture.outputs["Alpha"], alpha)
        if material_name == "Neon":
            emission = nodes.new("ShaderNodeEmission")
            emission.inputs["Strength"].default_value = NEON_STRENGTH
            links.new(color, emission.inputs["Color"])
            transparent = nodes.new("ShaderNodeBsdfTransparent")
            mix = nodes.new("ShaderNodeMixShader")
            links.new(alpha, mix.inputs[0])
            links.new(transparent.outputs[0], mix.inputs[1])
            links.new(emission.outputs[0], mix.inputs[2])
            surface = mix.outputs[0]
        else:
            shader = nodes.new("ShaderNodeBsdfPrincipled")
            links.new(color, shader.inputs["Base Color"])
            links.new(alpha, shader.inputs["Alpha"])
            shader.inputs["Roughness"].default_value = ROUGHNESS.get(material_name, 0.8)
            shader.inputs["Metallic"].default_value = METALLIC.get(material_name, 0.0)
            if tile:
                links.new(self.stud_normal(nodes, links, tile), shader.inputs["Normal"])
            surface = shader.outputs[0]
        links.new(one_sided(nodes, links, surface), output.inputs["Surface"])
        self.material_cache[key] = material
        return material

    def decal_material(self, path):
        key = ("decal", path)
        cached = self.material_cache.get(key)
        if cached:
            return cached
        material = bpy.data.materials.new("Decal")
        material.use_nodes = True
        nodes, links = material.node_tree.nodes, material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        info = nodes.new("ShaderNodeObjectInfo")
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = self.image(path)
        texture.extension = "CLIP"
        mapping = nodes.new("ShaderNodeUVMap")
        mapping.uv_map = "UVMap"
        links.new(mapping.outputs["UV"], texture.inputs["Vector"])
        color = nodes.new("ShaderNodeVectorMath")
        color.operation = "MULTIPLY"
        links.new(texture.outputs["Color"], color.inputs[0])
        links.new(info.outputs["Color"], color.inputs[1])
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Roughness"].default_value = 0.6
        links.new(color.outputs["Vector"], shader.inputs["Base Color"])
        links.new(socket_math(nodes, links, "MULTIPLY", texture.outputs["Alpha"], info.outputs["Alpha"]), shader.inputs["Alpha"])
        links.new(one_sided(nodes, links, shader.outputs[0]), output.inputs["Surface"])
        self.material_cache[key] = material
        return material

    def arrays_for(self, key):
        if key in self.arrays:
            return self.arrays[key]
        data = self.meshes.get(key)
        entry = None
        if data:
            positions = np.asarray(data.get("positions", []), dtype=np.float64).reshape(-1, 3) / POSITION_SCALE
            faces = np.asarray(data.get("faces", []), dtype=np.int64).reshape(-1, 3)
            if positions.size and faces.size:
                keep = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2]) & (faces.max(axis=1) < len(positions)) & (faces.min(axis=1) >= 0)
                entry = {"positions": positions, "faces": faces, "keep": keep, "low": positions.min(axis=0), "high": positions.max(axis=0), "data": data}
        self.arrays[key] = entry
        return entry

    def finish_mesh(self, mesh, triangles):
        mesh.materials.append(None)
        self.triangle_cache[mesh.name] = triangles
        return mesh

    def mesh_for(self, info, size):
        key = info.get("mesh")
        entry = self.arrays_for(key) if key else None
        if entry is None:
            return None
        if info.get("fit", "size") == "size":
            extent = entry["high"] - entry["low"]
            factor = np.where(extent > 1e-6, np.asarray(size, dtype=np.float64) / np.maximum(extent, 1e-9), 1.0)
            offset = -(entry["low"] + entry["high"]) / 2.0 * factor
        else:
            factor = np.asarray(info.get("meshScale", (1, 1, 1)), dtype=np.float64)
            offset = np.asarray(info.get("meshOffset", (0, 0, 0)), dtype=np.float64)
        cache_key = (key, tuple(np.round(factor, 5)), tuple(np.round(offset, 5)))
        cached = self.mesh_cache.get(cache_key)
        if cached:
            return cached
        data = entry["data"]
        keep = entry["keep"]
        corner_keep = np.repeat(keep, 3)
        faces = entry["faces"][keep]
        mesh = bpy.data.meshes.new(key.split(":")[0])
        mesh.from_pydata((entry["positions"] * factor + offset).tolist(), [], faces.tolist())
        corner_count = entry["faces"].shape[0] * 3
        colors = np.ones((corner_count, 4))
        if "colors" in data and "faceColors" in data:
            table = np.asarray(data["colors"], dtype=np.float64).reshape(-1, 4) / 255.0
            table[:, :3] = linear_array(table[:, :3])
            index = np.asarray(data["faceColors"], dtype=np.int64)
            if index.size == corner_count:
                valid = (index >= 0) & (index < len(table))
                colors[valid] = table[index[valid]]
        attribute = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        attribute.data.foreach_set("color", colors[corner_keep].astype(np.float32).ravel())
        if "normals" in data and "faceNormals" in data:
            table = np.asarray(data["normals"], dtype=np.float64).reshape(-1, 3) / NORMAL_SCALE
            index = np.asarray(data["faceNormals"], dtype=np.int64)
            if len(table) and index.size == corner_count and (index >= 0).all() and (index < len(table)).all():
                normals = table[index] / np.where(np.abs(factor) > 1e-9, factor, 1.0)
                normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
                mesh.shade_smooth()
                mesh.normals_split_custom_set(normals[corner_keep].tolist())
        if data.get("hasUV") and "uvs" in data:
            table = np.asarray(data["uvs"], dtype=np.float64).reshape(-1, 2) / UV_SCALE
            index = np.asarray(data["faceUVs"], dtype=np.int64)
            if index.size == corner_count:
                uv = np.zeros((corner_count, 2))
                valid = (index >= 0) & (index < len(table))
                uv[valid] = table[index[valid]]
                uv[:, 1] = 1.0 - uv[:, 1]
                layer = mesh.uv_layers.new(name="UVMap")
                layer.data.foreach_set("uv", uv[corner_keep].astype(np.float32).ravel())
        self.finish_mesh(mesh, int(faces.shape[0]))
        self.mesh_cache[cache_key] = mesh
        return mesh

    def shape_for(self, shape, size, scale, offset):
        dimensions = np.asarray(size, dtype=np.float64) * np.asarray(scale, dtype=np.float64)
        if shape == "Ball":
            dimensions = np.full(3, dimensions.min())
        cache_key = ("shape", shape, tuple(np.round(dimensions, 5)), tuple(np.round(offset, 5)))
        cached = self.mesh_cache.get(cache_key)
        if cached:
            return cached
        bm = bmesh.new()
        smooth = False
        if shape in ("Ball", "MeshSphere"):
            bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=0.5)
            smooth = True
            stretch = dimensions
        elif shape in ("Cylinder", "MeshCylinder"):
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=24, radius1=0.5, radius2=0.5, depth=1.0)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
            diameter = min(dimensions[1], dimensions[2])
            stretch = (dimensions[0], diameter, diameter)
            smooth = True
        elif shape in ("LegacyCylinder", "MeshHead"):
            bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=24, radius1=0.5, radius2=0.5, depth=1.0)
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
            if shape == "MeshHead":
                rims = [edge for edge in bm.edges if all(abs(abs(vertex.co.y) - 0.5) < 1e-4 for vertex in edge.verts) and all(abs(vertex.co.xz.length - 0.5) < 1e-3 for vertex in edge.verts)]
                bmesh.ops.bevel(bm, geom=rims, offset=0.16, segments=3, profile=0.5, affect="EDGES", clamp_overlap=True)
            diameter = min(dimensions[0], dimensions[2])
            stretch = (diameter, dimensions[1], diameter)
            smooth = True
        elif shape in ("Wedge", "MeshWedge", "CornerWedge"):
            if shape == "CornerWedge":
                points = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (0.5, 0.5, -0.5)]
            else:
                points = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5)]
            for point in points:
                bm.verts.new(point)
            bmesh.ops.convex_hull(bm, input=list(bm.verts))
            stretch = dimensions
        else:
            bmesh.ops.create_cube(bm, size=1.0)
            stretch = dimensions
        bmesh.ops.scale(bm, vec=Vector(stretch), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(offset), verts=bm.verts)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(shape)
        bm.to_mesh(mesh)
        bm.free()
        attribute = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        attribute.data.foreach_set("color", np.ones(len(mesh.loops) * 4, dtype=np.float32))
        if smooth:
            mesh.shade_smooth()
            mesh.set_sharp_from_angle(angle=math.radians(40))
        self.finish_mesh(mesh, sum(len(polygon.vertices) - 2 for polygon in mesh.polygons))
        self.mesh_cache[cache_key] = mesh
        return mesh

    def decal_object(self, decal, mesh, matrix, collection):
        path = self.images.get(decal.get("image"))
        face = FACES.get(decal.get("face"))
        if not path or not face:
            return None
        normal, right, up = (np.asarray(axis, dtype=np.float64) for axis in face)
        corners = np.array([vertex.co[:] for vertex in mesh.vertices]) if len(mesh.vertices) else np.zeros((1, 3))
        depth = float((corners @ normal).max()) + 0.004
        across = corners @ right
        height = corners @ up
        quad = []
        for horizontal, vertical in ((across.min(), height.min()), (across.max(), height.min()), (across.max(), height.max()), (across.min(), height.max())):
            quad.append(tuple(normal * depth + right * horizontal + up * vertical))
        decal_mesh = bpy.data.meshes.new("Decal")
        decal_mesh.from_pydata(quad, [], [(0, 1, 2, 3)])
        layer = decal_mesh.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", np.array([0, 0, 1, 0, 1, 1, 0, 1], dtype=np.float32))
        decal_mesh.materials.append(self.decal_material(path))
        holder = bpy.data.objects.new("Decal", decal_mesh)
        holder.matrix_world = matrix
        color = decal.get("color", (1, 1, 1))
        holder.color = (*[srgb_to_linear(value) for value in color], 1.0 - float(decal.get("transparency", 0)))
        holder.visible_shadow = False
        collection.objects.link(holder)
        return holder

    def build_frame(self, frame_index, frame):
        collection = bpy.data.collections.new(f"Frame{frame_index}")
        self.scene.collection.children.link(collection)
        objects = []
        for record in frame["parts"]:
            info = self.parts[int(record[0])]
            matrix = matrix_from(record[1:13])
            size = record[13:16]
            color = record[16:19]
            transparency = float(record[19])
            mesh = None
            if info.get("kind") == "mesh":
                mesh = self.mesh_for(info, size)
            if mesh is None:
                shape = info.get("shape", "Block") if info.get("kind") == "shape" else "Block"
                scale = info.get("meshScale", (1, 1, 1)) if info.get("kind") == "shape" else (1, 1, 1)
                offset = info.get("meshOffset", (0, 0, 0)) if info.get("kind") == "shape" else (0, 0, 0)
                mesh = self.shape_for(shape, size, scale, offset)
            for decal in info.get("decals", []):
                holder = self.decal_object(decal, mesh, matrix, collection)
                if holder:
                    objects.append(holder)
            if transparency >= 0.999:
                continue
            texture_path = self.images.get(info.get("texture")) if info.get("texture") else None
            tint = info.get("tint", (1, 1, 1))
            base = tint if texture_path else [value * shade for value, shade in zip(color, tint)]
            variant = (info.get("variant") or "").lower()
            tile = float(info["tile"]) if "stud" in variant and info.get("tile") else None
            holder = bpy.data.objects.new(info.get("name", "Part"), mesh)
            holder.matrix_world = matrix
            holder.color = (*[srgb_to_linear(value) for value in base], 1.0 - transparency)
            holder.material_slots[0].link = "OBJECT"
            holder.material_slots[0].material = self.material(info.get("material", "Plastic"), tile, texture_path, info.get("alphaMode", "Transparency"))
            if not info.get("castShadow", True) or transparency > 0.05:
                holder.visible_shadow = False
            collection.objects.link(holder)
            objects.append(holder)
            self.object_count += 1
            self.triangle_count += self.triangle_cache.get(mesh.name, 0)
        return collection, objects

    def points(self, objects):
        corners = []
        for holder in objects:
            world = np.array(holder.matrix_world)
            box = np.array([corner[:] for corner in holder.bound_box])
            corners.append(box @ world[:3, :3].T + world[:3, 3])
        return np.concatenate(corners) if corners else np.zeros((1, 3))

    def aim_ortho(self, points, back, up, aspect):
        matrix = look_matrix((0, 0, 0), back, up)
        axis_x = np.array(matrix.col[0][:3])
        axis_y = np.array(matrix.col[1][:3])
        axis_z = np.array(matrix.col[2][:3])
        across, height, depth = points @ axis_x, points @ axis_y, points @ axis_z
        centre = axis_x * (across.min() + across.max()) / 2 + axis_y * (height.min() + height.max()) / 2 + axis_z * (depth.max() + 5.0)
        data = self.camera.data
        data.type = "ORTHO"
        data.sensor_fit = "AUTO"
        data.ortho_scale = max(across.max() - across.min(), (height.max() - height.min()) * aspect, 0.01) * 1.1
        data.clip_start = 0.01
        data.clip_end = float(depth.max() - depth.min()) + 50.0
        self.camera.matrix_world = look_matrix(Vector(centre), back, up)

    def aim_icon(self, points, back, up, padding):
        # Orthographic and square, fitted to the asset's extent across the view, so long thin items fill the frame.
        matrix = look_matrix((0, 0, 0), back, up)
        axis_x = np.array(matrix.col[0][:3])
        axis_y = np.array(matrix.col[1][:3])
        axis_z = np.array(matrix.col[2][:3])
        across, height, depth = points @ axis_x, points @ axis_y, points @ axis_z
        centre = axis_x * (across.min() + across.max()) / 2 + axis_y * (height.min() + height.max()) / 2 + axis_z * (depth.max() + 5.0)
        data = self.camera.data
        data.type = "ORTHO"
        data.sensor_fit = "AUTO"
        data.ortho_scale = max(across.max() - across.min(), height.max() - height.min(), 0.01) * padding
        data.clip_start = 0.01
        data.clip_end = float(depth.max() - depth.min()) + 50.0
        self.camera.matrix_world = look_matrix(Vector(centre), back, up)

    def run_icons(self):
        icon = self.options["icon"]
        size = int(icon.get("size", 512))
        padding = float(icon.get("padding", 1.04))
        roll = math.radians(float(icon.get("roll", 0)))
        view = icon.get("view", "persp")
        default_forward = self.options.get("forward", "-z")
        built = [self.build_frame(index, frame) for index, frame in enumerate(self.data["frames"])]
        tiles = []
        for index, frame in enumerate(self.data["frames"]):
            collection, objects = built[index]
            for other_index, (other, _) in enumerate(built):
                other.hide_render = other_index != index
            label = frame.get("label", f"frame {index + 1}")
            if not objects:
                self.warnings.append(f"{label}: nothing visible to draw")
                continue
            rotation = matrix_from(frame["frame"]).to_3x3()
            forward = Vector(FORWARDS.get(frame.get("forward") or default_forward, (0, 0, -1)))
            up = Vector((0.0, 1.0, 0.0))
            right = forward.cross(up)
            named = {
                "front": forward, "back": -forward, "left": -right, "right": right, "top": up,
                "persp": (forward - right + up * 0.75).normalized(),
                "persp-right": (forward + right + up * 0.75).normalized(),
                "persp-back": (-forward - right + up * 0.75).normalized(),
                "persp-back-right": (-forward + right + up * 0.75).normalized(),
            }
            back_local = named[view] if isinstance(view, str) else Vector(view).normalized()
            screen_up_local = forward if abs(back_local.dot(up)) > 0.99 else up
            screen_up_local = (screen_up_local - back_local * screen_up_local.dot(back_local)).normalized()
            # Roll turns the picture about the view axis: up' = up cos r + (back x up) sin r.
            screen_up_local = screen_up_local * math.cos(roll) + back_local.cross(screen_up_local) * math.sin(roll)
            self.aim_icon(self.points(objects), rotation @ back_local, rotation @ screen_up_local, padding)
            path = icon.get("file") if len(self.data["frames"]) == 1 and icon.get("file") else os.path.join(self.out_dir, f"{slug(label)}.png")
            self.render_tile(path, size, size, True)
            tiles.append((path, label))
        return tiles

    def aim_perspective(self, location, back, up, fov, clip_start, clip_end):
        data = self.camera.data
        data.type = "PERSP"
        data.sensor_fit = "VERTICAL"
        data.angle_y = math.radians(fov)
        data.clip_start = clip_start
        data.clip_end = clip_end
        self.camera.matrix_world = look_matrix(location, back, up)

    def aim_fit(self, points, back, up, aspect, fov):
        centre = (points.min(axis=0) + points.max(axis=0)) / 2
        radius = max(float(np.linalg.norm(points - centre, axis=1).max()), 0.01)
        vertical = math.radians(fov)
        horizontal = 2 * math.atan(math.tan(vertical / 2) * aspect)
        distance = radius / math.sin(min(vertical, horizontal) / 2) * 1.02
        location = Vector(centre) + Vector(back).normalized() * distance
        self.aim_perspective(location, back, up, fov, max(distance - radius * 1.5, distance * 0.01), distance + radius * 4)

    def render_tile(self, path, width, height, flat):
        self.flat_switch.outputs[0].default_value = 1.0 if flat else 0.0
        self.scene.render.resolution_x = int(width)
        self.scene.render.resolution_y = int(height)
        self.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    def run(self):
        frames = self.data["frames"]
        built = [self.build_frame(index, frame) for index, frame in enumerate(frames)]
        default_forward = self.options.get("forward", "-z")
        tiles = []
        for index, frame in enumerate(frames):
            collection, objects = built[index]
            for other_index, (other, _) in enumerate(built):
                other.hide_render = other_index != index
            label = frame.get("label", f"frame {index + 1}")
            if not objects:
                self.warnings.append(f"{label}: nothing visible to draw")
                continue
            if frame.get("camera"):
                aspect = float(frame.get("aspect") or 16 / 9)
                width = CAMERA_WIDTH
                height = int(round(width / aspect))
                if height > 720:
                    height = 720
                    width = int(round(height * aspect))
                self.aim_perspective(matrix_from(frame["camera"]).translation, matrix_from(frame["camera"]).to_3x3() @ Vector((0, 0, 1)), matrix_from(frame["camera"]).to_3x3() @ Vector((0, 1, 0)), float(frame.get("fov", 70)), 0.02, 10000.0)
                path = os.path.join(self.out_dir, f"{len(tiles) + 1:02d}_{slug(label)}.png")
                self.render_tile(path, width, height, False)
                tiles.append((path, label))
            views = frame.get("views")
            if views is None:
                views = [] if frame.get("camera") else self.options.get("views") or DEFAULT_VIEWS
            focus_list = frame.get("focus") or []
            if not views and not focus_list:
                continue
            frame_matrix = matrix_from(frame["frame"])
            rotation = frame_matrix.to_3x3()
            forward_local = Vector(FORWARDS.get(frame.get("forward") or default_forward, (0, 0, -1)))
            up_local = Vector((0.0, 1.0, 0.0))
            right_local = forward_local.cross(up_local)
            left_local = -right_local
            directions = {
                "front": (forward_local, up_local),
                "back": (-forward_local, up_local),
                "left": (left_local, up_local),
                "right": (right_local, up_local),
                "top": (up_local, forward_local),
                "bottom": (-up_local, forward_local),
                "persp": ((forward_local + left_local + up_local * 0.75).normalized(), up_local),
                "persp-back": ((-forward_local + left_local + up_local * 0.75).normalized(), up_local),
                "persp-right": ((forward_local + right_local + up_local * 0.75).normalized(), up_local),
                "persp-back-right": ((-forward_local + right_local + up_local * 0.75).normalized(), up_local),
            }
            points = self.points(objects)
            aspect = VIEW_TILE[0] / VIEW_TILE[1]
            for view in views:
                if view not in directions:
                    self.warnings.append(f"unknown view {view}")
                    continue
                back_local, screen_up_local = directions[view]
                back, screen_up = rotation @ back_local, rotation @ screen_up_local
                if view.startswith("persp"):
                    self.aim_fit(points, back, screen_up, aspect, VIEW_FOV)
                    name = view.upper()
                else:
                    self.aim_ortho(points, back, screen_up, aspect)
                    name = f"{view.upper()} ({axis_name(back_local)})"
                tile_label = f"{label} - {name}"
                path = os.path.join(self.out_dir, f"{len(tiles) + 1:02d}_{slug(tile_label)}.png")
                self.render_tile(path, VIEW_TILE[0], VIEW_TILE[1], True)
                tiles.append((path, tile_label))
            diagonal = float(np.linalg.norm(points.max(axis=0) - points.min(axis=0)))
            for focus_index, focus in enumerate(focus_list):
                point = frame_matrix @ Vector(focus[0:3])
                radius = float(focus[3]) if len(focus) > 3 and focus[3] > 0 else max(diagonal * 0.12, 0.02)
                local_back = Vector(focus[4:7]).normalized() if len(focus) >= 7 and Vector(focus[4:7]).length > 1e-6 else directions["persp"][0]
                back = rotation @ local_back
                distance = radius / math.tan(math.radians(FOCUS_FOV) / 2)
                self.aim_perspective(point + back.normalized() * distance, back, rotation @ up_local, FOCUS_FOV, distance * 0.02, distance + diagonal * 4 + 10)
                tile_label = f"{label} - focus {focus_index + 1} ({focus[0]:g}, {focus[1]:g}, {focus[2]:g})"
                path = os.path.join(self.out_dir, f"{len(tiles) + 1:02d}_{slug(tile_label)}.png")
                self.render_tile(path, VIEW_TILE[0], VIEW_TILE[1], True)
                tiles.append((path, tile_label))
        return tiles


def read_png(path):
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return np.flipud(pixels.reshape(height, width, 4)).copy()


def write_png(path, array):
    height, width = array.shape[:2]
    image = bpy.data.images.new("ShotOut", width, height, alpha=False)
    image.pixels.foreach_set(np.flipud(array).astype(np.float32).ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def draw_label(array, text):
    text = text.upper()
    glyph_width = 6 * LABEL_SCALE
    width = min(array.shape[1], len(text) * glyph_width + LABEL_PAD * 2 - LABEL_SCALE)
    height = 7 * LABEL_SCALE + LABEL_PAD * 2
    array[:height, :width, :3] *= 0.3
    for position, character in enumerate(text):
        rows = GLYPHS.get(character)
        left = LABEL_PAD + position * glyph_width
        if rows is None or left + 5 * LABEL_SCALE > array.shape[1]:
            continue
        for row_index, row in enumerate(rows.split()):
            for column_index, bit in enumerate(row):
                if bit == "1":
                    top = LABEL_PAD + row_index * LABEL_SCALE
                    column = left + column_index * LABEL_SCALE
                    array[top:top + LABEL_SCALE, column:column + LABEL_SCALE, :3] = 1.0


def compose(tiles, path):
    images = []
    for tile_path, label in tiles:
        array = read_png(tile_path)
        draw_label(array, label)
        write_png(tile_path, array)
        images.append(array)
    rows, row, row_width = [], [], 0
    for array in images:
        if row and row_width + array.shape[1] > SHEET_WIDTH:
            rows.append(row)
            row, row_width = [], 0
        row.append(array)
        row_width += array.shape[1]
    if row:
        rows.append(row)
    width = max(sum(array.shape[1] for array in line) for line in rows)
    height = sum(max(array.shape[0] for array in line) for line in rows)
    sheet = np.empty((height, width, 4), dtype=np.float32)
    sheet[:, :, :3] = SHEET_BACKGROUND
    sheet[:, :, 3] = 1.0
    top = 0
    for line in rows:
        left = 0
        for array in line:
            sheet[top:top + array.shape[0], left:left + array.shape[1]] = array
            left += array.shape[1]
        top += max(array.shape[0] for array in line)
    write_png(path, sheet)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    scene_path, out_dir = argv[0], argv[1]
    started = time.time()
    with open(scene_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    os.makedirs(out_dir, exist_ok=True)
    renderer = Renderer(data, out_dir)
    icon = data.get("options", {}).get("icon")
    tiles = renderer.run_icons() if icon else renderer.run()
    if not tiles:
        raise RuntimeError("nothing to render: every snapshot was empty")
    if icon:
        sheet = tiles[0][0]
    else:
        sheet = os.path.join(out_dir, f"{slug(data.get('name', 'shot'))}_sheet.png")
        compose(tiles, sheet)
    report = {
        "sheet": sheet,
        "tiles": [path for path, _ in tiles],
        "device": renderer.device,
        "objects": renderer.object_count,
        "triangles": renderer.triangle_count,
        "warnings": renderer.warnings,
        "seconds": round(time.time() - started, 2),
        "blender": bpy.app.version_string,
    }
    print("ASSETSHOT " + json.dumps(report), flush=True)


try:
    main()
except Exception:
    traceback.print_exc()
    sys.stdout.flush()
    sys.exit(1)
