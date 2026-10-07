"""brushes.roof: roofing brushes (fish-scale tiles round a cone; tiles, slates, shingles and thatch laid in a roof
plane's own frame). Each is painter(context, **options) -> RGB or RGBA; see brushes/README.md."""

import numpy as np

from paintlib import fbm, lift, mix, shade, smoothstep, solid

from .core import colour, finish
from .fibre import _hay_rgb
from .registry import brush
from .surface import _surface_uv
from .wrap import _soot


@brush("roof.fish_scale", version=1, material="roof tile", fixture="cone", tint=True, styles=("painted-toon",), source="Joust Tycoon castle (Rebirth 0), 2026-10-05 (tower and gate-drum cone roofs, woodpile lean-to)", summary="Fish-scale roof tiles, near-white for TintMask: rounded rims lit, overlap shaded, cool gaps; around=(x, y, radius) lays rows round a cone, None for a flat pitch; alpha 1, so the whole roof takes the team colour")
def roof_tiles(context, around=(0.0, 0.0, 10.0), tile=(2.2, 1.5), scallop=0.42, base="CastleTile", shade_name="CastleTileShade", gap="CastleTileGap"):
    """Fish-scale roof tiles round a vertical axis, near-white for TintMask: each scale lit at its rounded rim and
    shaded where the row above overlaps it. Alpha 1 everywhere, so the whole roof takes the castle colour."""
    count = context.count
    u, v, _ = _surface_uv(context, around)
    row = np.floor(v / tile[1])
    shifted = u / tile[0] + 0.5 * np.mod(row, 2.0)
    across = shifted - np.floor(shifted)
    up = v / tile[1] - row
    # the scale's rounded bottom rim: a half-ellipse dipping `scallop` of a row below the course line
    rim = scallop * np.sqrt(np.clip(1 - (2 * across - 1) ** 2, 0, 1))
    rgb = solid(count, colour(base))
    overlap = smoothstep(0.55, 1.0, up)
    rgb = mix(rgb, solid(count, colour(shade_name)), overlap * 0.9)
    gap_line = 1 - smoothstep(0.03, 0.09, np.abs(up - rim))
    side_gap = 1 - smoothstep(0.02, 0.06, np.minimum(across, 1 - across))
    rgb = mix(rgb, solid(count, colour(gap)), np.clip(gap_line + side_gap * (up > rim), 0, 1))
    rgb = lift(rgb, smoothstep(0.16, 0.0, np.abs(up - rim - 0.08)) * 0.18, toward=colour(base))
    wear = fbm(context.pos, scale=1.2, octaves=3, seed=31.0)
    rgb = shade(rgb, 0.94 + wear * 0.1)
    lit = finish(rgb, context, ao_strength=0.7, edge_light=0.18)
    return np.concatenate([lit, np.ones((count, 1))], axis=1)


# ---- Greenmeadow hub roofs (Joust Tycoon, approved 2026-10-05): courses laid in a sloped roof plane's own frame
# (local X along the eave, local Y up the slope). Copied verbatim from the project's hubpaint.py and the castle's
# paint_keep._scales, so these paint exactly what the project's copies paint.

MEADOW = "Joust Tycoon Greenmeadow, 2026-10-05"


def _scales(context, u, v, tile, scallop, base, shade_name, gap):
    # roof.fish_scale's scale pattern on caller-supplied surface coordinates (studs, v up the slope)
    count = context.count
    row = np.floor(v / tile[1])
    shifted = u / tile[0] + 0.5 * np.mod(row, 2.0)
    across = shifted - np.floor(shifted)
    up = v / tile[1] - row
    rim = scallop * np.sqrt(np.clip(1 - (2 * across - 1) ** 2, 0, 1))
    rgb = solid(count, colour(base))
    rgb = mix(rgb, solid(count, colour(shade_name)), smoothstep(0.55, 1.0, up) * 0.9)
    gap_line = 1 - smoothstep(0.03, 0.09, np.abs(up - rim))
    side_gap = 1 - smoothstep(0.02, 0.06, np.minimum(across, 1 - across))
    rgb = mix(rgb, solid(count, colour(gap)), np.clip(gap_line + side_gap * (up > rim), 0, 1))
    rgb = lift(rgb, smoothstep(0.16, 0.0, np.abs(up - rim - 0.08)) * 0.18, toward=colour(base))
    return shade(rgb, 0.94 + fbm(context.pos, scale=1.2, octaves=3, seed=31.0) * 0.1)


@brush("roof.courses", version=1, material="roof tile", fixture="roof", tint=False, styles=("painted-toon",), source=MEADOW + " (hub roofs: smithy slate, quartermaster clay tiles, well shingles)", summary="Roof courses in a roof plane's own frame (local X along the eave, local Y up the slope): roof.fish_scale's scales at `tile` (u, v) studs; scallop 0.42 is a fish scale, near 0 a straight-cut slate or shingle; moss greens the lower courses, soot=((x, y, z), reach) darkens round a chimney, undersides take the shade tone")
def roof_courses(context, tile=(2.2, 1.5), scallop=0.42, base="MeadowHubClay", shade_name="MeadowHubClayShade", gap="MeadowHubClayGap", moss=0.0, soot=None):
    """The castle's roof scales (paint_keep) laid in a roof plane's own frame: u along the eave (local X), v up the
    slope (local Y). scallop 0.42 is the castle's fish scale; near 0 it is a straight-cut slate or shingle. moss greens
    the lower courses; soot = ((x, y, z), reach) darkens round a chimney. Undersides take the shade tone."""
    count = context.count
    u, v = context.local[:, 0], context.local[:, 1]
    rgb = _scales(context, u, v, tile, scallop, base, shade_name, gap)
    rgb = mix(rgb, solid(count, colour(shade_name)), smoothstep(-0.2, -0.5, context.normal[:, 2]))
    if moss > 0:
        patch = smoothstep(0.0, 0.3, fbm(context.pos, scale=0.6, octaves=3, seed=211.0))
        low = 1 - smoothstep(0.6, 3.2, v)
        rgb = mix(rgb, solid(count, colour("CastleMoss")), np.clip(patch * (0.35 + low), 0, 1) * moss)
    if soot is not None:
        rgb = _soot(rgb, context, *soot)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.18)


@brush("roof.thatch", version=1, material="thatch", fixture="roof", tint=False, styles=("painted-toon",), source=MEADOW + " (hub stable roof)", summary="Long-straw thatch in a roof plane's own frame (local Y up the slope): fibre.hay strands combed down the slope in thatch golds, laid in courses whose butt ends show as a dark line under a lit lip every `course` studs, greying and greening in patches")
def thatch(context, course=1.05, strands=11.0, seed=0.0):
    """Long-straw thatch in a roof plane's own frame (local Y up the slope): the library's hay strands combed down
    the slope in the hub's thatch golds, laid in courses whose butt ends show as a dark line under a lit lip every
    `course` studs up the slope, greying and greening low on the roof."""
    count = context.count
    rgb = _hay_rgb(context, (0.05, 1.0, 0.0), (0.25, 1.0, 0.1), strands, seed, base="MeadowHubThatch", light="MeadowHubThatchLight", dark="MeadowHubThatchDark", gap="MeadowHubThatchGap", green="MeadowHubThatchGreen")
    v = context.local[:, 1] + 0.18 * fbm(context.pos, scale=0.8, octaves=2, seed=seed + 31.0)
    phase = np.mod(v / course, 1.0)
    rgb = mix(rgb, solid(count, colour("MeadowHubThatchGap")), (1 - smoothstep(0.0, 0.07, phase)) * 0.7)
    rgb = lift(rgb, (1 - smoothstep(0.07, 0.2, phase)) * (phase > 0.07) * 0.18, toward=colour("MeadowHubThatchLight"))
    rgb = mix(rgb, solid(count, colour("MeadowHubThatchDark")), smoothstep(-0.2, -0.6, context.normal[:, 2]) * 0.6)
    weather = smoothstep(0.1, 0.4, fbm(context.pos, scale=0.5, octaves=3, seed=seed + 37.0)) * 0.35
    rgb = mix(rgb, solid(count, colour("MeadowHubThatchGreen")), weather)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)
