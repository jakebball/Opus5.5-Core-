import math

import blendlib as bl

bl.reset()

crate = bl.box("Crate", (1.6, 1.6, 1.0), at=(0, 0, 0.5), bevel=0.06, colour="9A6B3F")
bl.paint_faces(crate, lambda face: "B8895A" if face.normal.z > 0.9 else None)
bl.roblox(crate, material="Wood")

radius = 0.62
squash = 0.72
pumpkin = bl.sphere("Pumpkin", radius, segments=12, rings=8, colour="E8892B")
for vertex in pumpkin.data.vertices:
    rib = 1.0 + 0.09 * math.cos(math.atan2(vertex.co.y, vertex.co.x) * 6)
    vertex.co.x *= rib
    vertex.co.y *= rib
    vertex.co.z *= squash
pumpkin.location.z = 1.0 + radius * squash

top = 1.0 + 2 * radius * squash
stem = bl.tube("Stem", [(0, 0, top - 0.08), (0.02, 0, top + 0.12), (0.22, 0.05, top + 0.28)], radius=0.07, sides=6, colour="5E7D2E")
bl.roblox(pumpkin, part="Pumpkin")
bl.roblox(stem, part="Pumpkin")

bl.finish("PumpkinCrate", budget=600)
