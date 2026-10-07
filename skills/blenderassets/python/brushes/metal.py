"""brushes.metal: metal brushes. Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import math

import numpy as np

import paintlib as paint
from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

from .core import _dashes, _gold, _streaks, colour, finish, posterize, stitch_lines
from .registry import brush
from .wrap import with_alpha



@brush("metal.iron", version=1, material="metal", fixture="box", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Mottled forged metal with scratches and optional rust; pass base/light/dark for brass or steel')
def iron(context, base="Iron", light="IronLight", dark="IronDark", rust=True):
    count = context.count
    rgb = solid(count, colour(base))
    variation = fbm(context.pos, scale=2.5, octaves=3, seed=4.0)
    rgb = mix(rgb, solid(count, colour(dark)), np.clip(-variation * 2.4, 0, 1) * 0.55)
    band = smoothstep(0.55, 0.85, context.normal[:, 2]) * (1 - smoothstep(0.96, 1.0, context.normal[:, 2]))
    rgb = mix(rgb, solid(count, colour(light)), band * 0.4)
    scratches = fbm(context.pos, scale=7.0, octaves=2, stretch=(1.0, 7.0, 1.0), seed=6.0)
    rgb = mix(rgb, solid(count, colour(light)), smoothstep(0.42, 0.46, scratches) * 0.35)
    if rust:
        rust_field = fbm(context.pos, scale=3.4, octaves=3, seed=11.0)
        rgb = mix(rgb, solid(count, colour("Rust")), smoothstep(0.24, 0.36, rust_field) * 0.65)
    return finish(rgb, context, ao_strength=0.8, light=1.5, edge_light=0.55, top_light=0.08)


@brush("metal.riveted", version=1, material="metal", fixture="points", tint=False, styles=("painted-toon", "soft-painted"), source="Joust Tycoon starter set (Ashwood Lance, Padded Gambeson, Farm Rouncey), 2026-10-04", summary='Metal with rivet heads at given world points (centres, radius)')
def rivets(context, centres, radius=0.035):
    rgb = iron(context, rust=False)
    distance = paint.dots(context.pos, centres, radius)
    head = 1 - smoothstep(0.85, 1.0, distance)
    spot = 1 - smoothstep(0.0, 0.45, paint.dots(context.pos, [np.asarray(centre) + np.array((0.0, -0.01, 0.012)) for centre in centres], radius))
    rgb = mix(rgb, solid(context.count, colour("IronDark")), head * 0.6)
    return mix(rgb, solid(context.count, colour("IronLight")), spot * 0.9)


# ---- Greenmeadow (Joust Tycoon, approved 2026-10-05). Copied verbatim from the project's fairpaint.py.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("metal.gilt", version=1, material="gilt", fixture="dome", tint=False, styles=("painted-toon",), source=MEADOW + " (fair finials, pole caps, lantern knobs; hub well)", summary="Gilded turned wood (finials, knobs): the knights' embroidery gold, mottled with darker wear, warm rims; tinted=True returns alpha 0 so it stays gold on a TintMask part")
def gilt(context, tinted=False):
    """Gilded turned wood (finials): the gold of the knights' embroidery, mottled, with warm rims."""
    count = context.count
    rgb = _gold(context.local[:, 0] * 2.0, context.local[:, 2] * 2.0, count)
    wear = fbm(context.pos, scale=3.0, octaves=2, seed=113.0)
    rgb = mix(rgb, solid(count, colour("MeadowFairGiltDark")), smoothstep(0.15, 0.4, wear) * 0.45)
    lit = finish(rgb, context, ao_strength=0.7, edge_light=0.4)
    return with_alpha(lit, 0.0) if tinted else lit
