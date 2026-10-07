"""brushes.fire: fire painted rather than lit (no Neon, no light): toon flame tongues and a bed of coals. Each is
painter(context, **options) -> RGB, painted unlit (the fire is its own light), so neither calls the style's finish.
For the glow a fire throws on what stands round it, wrap that thing's painter in brushes.wrap.glowing.

Copied verbatim from Joust Tycoon's Greenmeadow hub painters (blender-source/world/hub/hubpaint.py, the smithy's
forge; approved 2026-10-05), so the library brushes paint exactly what the project's copies paint."""

import numpy as np

from paintlib import fbm, mix, ramp, shade, smoothstep

from .core import colour, posterize
from .registry import brush

SOURCE = "Joust Tycoon Greenmeadow, 2026-10-05 (hub smithy forge)"


@brush("fire.flame", version=1, material="fire", fixture="blades", tint=False, styles=("painted-toon",), source=SOURCE, summary="Toon flame tongues, unlit: white-gold at the root (base_z) through orange to a deep red tip `height` studs up, in hard bands, a darker rim")
def flame(context, base_z, height):
    """Toon flame tongues: white-gold at the root through orange to a deep red tip, in hard bands, unlit."""
    rise = np.clip((context.pos[:, 2] - base_z) / height, 0, 1)
    rgb = ramp(posterize(1 - rise, 3), [(0.0, colour("MeadowHubEmberDeep")), (0.5, colour("MeadowHubEmber")), (1.0, colour("MeadowHubEmberHot"))])
    rim = smoothstep(0.1, 0.3, context.edge)
    return mix(rgb, shade(rgb, 0.82), rim * 0.4)


@brush("fire.embers", version=1, material="fire", fixture="hearth", tint=False, styles=("painted-toon",), source=SOURCE, summary="A bed of coals, unlit: dark lumps, glowing orange cracks between them, white-hot toward `centre` (world) within `radius`, in hard toon bands; undersides stay dark coal")
def embers(context, centre, radius):
    """A bed of coals: dark lumps, glowing orange cracks between them, white-hot at the heart. Painted unlit (the fire
    is its own light), banded for the toon look."""
    count = context.count
    distance = np.linalg.norm((context.pos - np.asarray(centre))[:, :2], axis=1)
    heat = np.clip(1 - distance / radius, 0, 1)
    lumps = fbm(context.pos, scale=3.2, octaves=2, seed=233.0)
    crack = 1 - smoothstep(0.02, 0.12, np.abs(lumps))
    coal = ramp(posterize(np.clip(0.5 + fbm(context.pos, scale=5.0, octaves=2, seed=239.0) * 2, 0, 1), 3), [(0.0, colour("MeadowHubCoal")), (1.0, colour("MeadowHubCoalLight"))])
    fire = ramp(posterize(heat, 3), [(0.0, colour("MeadowHubEmberDeep")), (0.5, colour("MeadowHubEmber")), (1.0, colour("MeadowHubEmberHot"))])
    glow_amount = np.clip(crack * (0.5 + heat) + smoothstep(0.55, 0.8, heat) * 0.8, 0, 1)
    rgb = mix(coal, fire, posterize(glow_amount, 3))
    top = smoothstep(0.3, 0.7, context.normal[:, 2])
    rgb = mix(shade(coal, 0.8), rgb, top)
    return rgb
