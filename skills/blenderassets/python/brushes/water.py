"""brushes.water: water brushes (toon water that tiles, still water in a vessel). Each is painter(context, **options)
-> RGB; see brushes/README.md."""

import numpy as np

from paintlib import fbm, mix, ramp, shade, smoothstep, solid

from .core import colour, finish, posterize
from .registry import brush
from .surface import tiled_fbm


@brush("water.toon", version=1, material="water", fixture="pool", tint=False, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (moat runs and corners)", summary="Toon water on noise that tiles every period: posterised depth bands, crisp ripple lines (ripple_lines), AO contact foam round anything standing in it (contact), and with banks(pos) -> studs a wobbling foam band plus a broken second line at the bank; mapping(pos) bends the pattern")
def water(context, period=(21.0, 0.0, 0.0), banks=None, foam_ao=0.45, mapping=None, ripple_lines=True, contact=True):
    """Toon water on tiling noise: posterised depth bands, crisp ripple lines, and foam. banks(pos) gives
    the distance in studs from the nearest bank at the waterline: a crisp foam band with a wobbling edge and a
    broken second line hug it. AO adds contact foam round reeds and pads. mapping(pos) -> pos moves the pattern
    (the moat corner bends it round from one run into the other). contact=False drops the AO foam and contact
    shading, so floating pads leave no baked mark when they drift; ripple_lines=False leaves the lines to a
    scrolling ripple layer."""
    count = context.count
    pos = mapping(context.pos) if mapping else context.pos
    depth = tiled_fbm(pos, 0.08, 2, period, 61.0)
    rgb = ramp(posterize(np.clip(0.5 + depth * 1.8, 0, 1), 3), [(0.0, colour("CastleWaterDark")), (0.6, colour("CastleWater")), (1.0, colour("CastleWater"))])
    ripples = tiled_fbm(pos * np.array((1.0, 1.0, 0.0)), 0.35, 2, period, 67.0)
    if ripple_lines:
        lines = 1 - smoothstep(0.01, 0.035, np.abs(np.sin(ripples * 9.0)))
        rgb = mix(rgb, solid(count, colour("CastleWaterLight")), lines * 0.75)
    foam = smoothstep(foam_ao, foam_ao - 0.12, np.clip(context.ao, 0, 1)) if contact else np.zeros(count)
    if banks is not None:
        distance = banks(context.pos)
        wobble = tiled_fbm(pos, 1.3, 2, period, 83.0)
        width = 0.3 + wobble * 0.35
        band = 1 - smoothstep(width - 0.03, width, distance)
        second = (1 - smoothstep(0.035, 0.06, np.abs(distance - width - 0.28))) * (tiled_fbm(pos, 0.9, 2, period, 89.0) > -0.05)
        foam = np.maximum(foam, np.maximum(band, second * 0.8))
    rgb = mix(rgb, solid(count, colour("CastleWaterFoam")), foam * 0.85)
    return finish(rgb, context, ao_strength=0.1 if contact else 0.0, edge_light=0.0, poster=0.3)


@brush("water.still", version=1, material="water", fixture="basin", tint=False, styles=("painted-toon",), source="Joust Tycoon Greenmeadow, 2026-10-05 (hub quench barrel, trough and well)", summary="Still water seen at an angle in a vessel (barrel, trough, well): dark posterised water, a lit rim band toward the vessel wall (object-space radius over the piece's widest), a sooty sheen")
def still(context):
    """Still water seen at an angle in a quench barrel: dark, a lit rim band, a sooty sheen."""
    count = context.count
    rgb = ramp(posterize(np.clip(0.5 + fbm(context.pos, scale=2.0, octaves=2, seed=251.0) * 1.6, 0, 1), 3), [(0.0, colour("CastleWaterDark")), (1.0, colour("CastleWater"))])
    ring = smoothstep(0.55, 0.8, np.linalg.norm(context.local[:, :2], axis=1) / max(np.linalg.norm(context.local[:, :2], axis=1).max(), 1e-3))
    rgb = shade(rgb, 0.72)
    rgb = mix(rgb, solid(count, colour("CastleWater")), ring * 0.45)
    return finish(rgb, context, ao_strength=0.2, edge_light=0.0, poster=0.3)
