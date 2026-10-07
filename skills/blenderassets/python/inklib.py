"""inklib: toon ink outlines for blendlib assets, as inverted hulls.

A hull is a copy of a piece inflated along its vertex normals with its faces flipped. Roblox draws MeshParts
single-sided, so only the hull's far rim shows: a black outline round the silhouette that costs triangles, not
textures or post-processing. Outlines vanish below about a pixel (roughly 70 studs at 0.05 thick), so colour
and silhouette still carry an asset at range.

    import inklib as ink
    hull = ink.outline(piece, part="Torso")           # -> the hull object (part "TorsoInk"), or None if skipped

Rules learned building the Joust Tycoon starter set:
  - a hull must not wrap anything the paint bake sees: paintlib hides objects with obj["ink"] while baking;
  - open ends (an uncapped tube) show the hull's black inside through the opening: cap them;
  - faces flagged ink_skip are left out of the hull (shapelib.cloth_band flags its underside; flag buried tops
    with shapelib.mark_ink_skip), or the hull slivers out where the piece lifts off or meets another;
  - skip pieces too small or thin to outline (they turn into noise), and pieces whose outline only pokes
    through something else (a collar against the head): obj["no_ink"] = True;
  - a piece can set obj["ink_thickness"] to override the thickness (a thin band bridging a gap reads cleaner
    with a thinner hull).
"""

import bmesh
import bpy
from mathutils import Vector

import blendlib as bl

INK = 0.05
INK_COLOUR = "0B0B10"


def hull(obj, thickness=INK, name=None, colour=INK_COLOUR):
    copy = obj.copy()
    copy.data = obj.data.copy()
    copy.name = name or f"{obj.name}Ink"
    bpy.context.scene.collection.objects.link(copy)
    for key in list(copy.keys()):
        del copy[key]
    builder = bmesh.new()
    builder.from_mesh(copy.data)
    skip = builder.faces.layers.int.get("ink_skip")
    if skip is not None:
        bmesh.ops.delete(builder, geom=[face for face in builder.faces if face[skip]], context="FACES")
    bmesh.ops.remove_doubles(builder, verts=builder.verts, dist=1e-5)
    builder.normal_update()
    for vertex in builder.verts:
        normal = vertex.normal
        if normal.length < 1e-6:
            continue
        vertex.co += normal * thickness
    bmesh.ops.reverse_faces(builder, faces=builder.faces)
    builder.to_mesh(copy.data)
    builder.free()
    for layer in list(copy.data.uv_layers):
        copy.data.uv_layers.remove(layer)
    bl.flat(copy)
    bl.paint(copy, colour)
    return copy


def mark(hull_obj, part, colour=INK_COLOUR):
    """Make a hull exportable: its own part, no shadow, flagged so paint bakes ignore it."""
    bl.roblox(hull_obj, part=part, material="SmoothPlastic", shadow=False)
    hull_obj["ink"] = True
    hull_obj["stage_material"] = "Ink"
    hull_obj["solid_colour"] = colour
    return hull_obj


def size_of(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = Vector(map(min, *corners))
    high = Vector(map(max, *corners))
    return (high - low).length


def outline(obj, part=None, thickness=INK, min_size=0.32, thin_below=1.2, thin_factor=0.6, colour=INK_COLOUR):
    """Outline one piece into part "<part>Ink" (part defaults to the piece's roblox_part). Pieces under min_size
    studs (bounding-box diagonal) or flagged no_ink are skipped; pieces under thin_below get a thinner hull."""
    if obj.get("no_ink"):
        return None
    size = size_of(obj)
    if size < min_size:
        return None
    part = part or obj.get("roblox_part", obj.name)
    thickness = obj.get("ink_thickness", thickness if size > thin_below else thickness * thin_factor)
    return mark(hull(obj, thickness, name=f"{obj.name}Ink", colour=colour), f"{part}Ink", colour)
