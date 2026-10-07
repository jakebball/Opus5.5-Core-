"""brushes.wrap: painter wrappers and combinators. These are not brushes (they take painters, so a style profile
cannot pin them); they change how any painter is lit, tinted or overlaid. No brushes live here.

    with_alpha(rgb, alpha)                 RGB -> RGBA (alpha = TintMask amount)
    untinted(painter)                      any RGB painter on a TintMask part at alpha 0, so the tint never reaches it
    baked_tint(painter, tint)              bake a tint colour into a near-white tinted painter with TintMask's own
                                           maths, so an untinted part matches a tinted one in that colour
    in_frame(painter, rotation)            light a turning piece in its own frame (a windmill sail at any angle)
    banded(context, wood, metal, bands)    timber with metal bands between object-space heights (a mast's collars)
    sooted(painter, centre, reach)         posterised soot round a point (a forge mouth, a chimney top)
    glowing(painter, centre, reach)        a painted ember glow round a point in three hard toon bands, no light

Copied verbatim from Joust Tycoon's Greenmeadow painters (farmpaint.in_frame, fairpaint.banded, hubpaint.sooted /
glowing / colourway, villagerpaint.with_alpha / fixed; approved 2026-10-05); baked_tint is hubpaint.colourway with
the colour passed in rather than looked up in the fair's colourways."""

import numpy as np

from paintlib import Context, fbm, mix, shade, smoothstep, solid

from .core import colour, posterize


def _hex(value):
    return np.array([int(value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)])


def with_alpha(rgb, alpha):
    alpha = np.broadcast_to(np.asarray(alpha, dtype=np.float64), (len(rgb),))
    return np.concatenate([rgb, alpha[:, None]], axis=1)


def untinted(painter):
    """An RGB painter (a library brush) on a TintMask part: alpha 0, so the dye never reaches it."""
    return lambda context: with_alpha(np.asarray(painter(context))[:, :3], 0.0)


def baked_tint(painter, tint):
    """Bake a tint (hex, or a palette name) into a near-white tinted painter, with TintMask's own maths (texture x
    colour by alpha), so a part painted this way matches a tinted part set to that colour, without a TintMask."""
    tint = _hex(colour(tint))

    def paint(context):
        rgba = painter(context)
        rgb, alpha = rgba[:, :3], rgba[:, 3:4]
        return rgb * (1 - alpha) + rgb * tint * alpha
    return paint


def in_frame(painter, rotation):
    """Wrap `painter` so the finish lights the piece as if `rotation` (3x3, the piece's frame in the world) were the
    identity: a part that spins (a windmill sail) keeps one lighting at every angle instead of baking the light of
    the pose it was built in."""
    rotation = np.asarray(rotation, dtype=np.float64)

    def turned(context):
        # world -> frame for row vectors: n_frame = R^T n, written n @ R
        normal = context.normal @ rotation
        return painter(Context(context.pos, normal, context.ao, context.curvature, context.edge, context.local, context.coord))

    return turned


def banded(context, wood, metal, bands, base=0.0):
    """Timber with iron bands at the given (low, high) object-space heights (a mast's collars and ferrules). wood and
    metal are painters."""
    rgb = wood(context)
    z = context.local[:, 2] - base
    band = np.zeros(context.count)
    for low, high in bands:
        band = np.maximum(band, smoothstep(low - 0.01, low + 0.01, z) * (1 - smoothstep(high - 0.01, high + 0.01, z)))
    rgb = mix(rgb, metal(context), band)
    for low, high in bands:
        rim = 1 - smoothstep(0.0, 0.03, np.minimum(np.abs(z - low), np.abs(z - high)))
        rgb = mix(rgb, shade(rgb, 0.55), rim * 0.6)
    return rgb


def _soot(rgb, context, centre, reach, strength=0.75, soot="MeadowHubSoot"):
    distance = np.linalg.norm((context.pos - np.asarray(centre)) * np.array((1.0, 1.0, 0.55)), axis=1)
    blotch = 0.75 + 0.5 * fbm(context.pos, scale=1.4, octaves=2, seed=223.0)
    amount = np.clip((1 - smoothstep(reach * 0.25, reach, distance)) * blotch, 0, 1) * strength
    return mix(rgb, solid(context.count, colour(soot)), posterize(amount, 4))


def sooted(painter, centre, reach, strength=0.75, soot="MeadowHubSoot"):
    """Soot over any painter's colour round a point (a forge mouth, a chimney top), in posterised steps. Applied
    after the finish, since soot is dull whatever the light."""
    def paint(context):
        return _soot(painter(context), context, centre, reach, strength, soot)
    return paint


def glowing(painter, centre, reach, strength=1.0, glow="MeadowHubGlow", hot="MeadowHubEmberHot"):
    """A painted ember glow over any painter: warm light falling off from `centre` in three hard toon bands, faces
    turned toward the fire lit most. Paint, not a light, pushed hard enough to read in shade."""
    centre = np.asarray(centre)

    def paint(context):
        rgb = painter(context)
        offset = context.pos - centre
        distance = np.maximum(np.linalg.norm(offset, axis=1), 1e-3)
        facing = np.clip(-(context.normal * offset).sum(axis=1) / distance, 0, 1)
        amount = np.clip((1 - smoothstep(0.0, reach, distance)) ** 1.2 * (0.7 + 0.3 * facing) * strength, 0, 1)
        bands = np.select([amount > 0.6, amount > 0.35, amount > 0.12], [0.95, 0.72, 0.42], 0.0)
        warm = np.clip(rgb * 0.35 + _hex(colour(glow)) * 0.95, 0, 1)
        hot_rgb = np.clip(rgb * 0.2 + _hex(colour(hot)) * 0.9, 0, 1)
        return mix(mix(rgb, warm, bands), hot_rgb, (amount > 0.8) * 0.6)
    return paint
