"""brushes.food: market goods: fruit and vegetables, heaps of fruit, loaves, and provisions in posterised tones. Each
is painter(context, **options) -> RGB; see brushes/README.md. Colours are palette names passed as options where a
brush paints many goods (produce, goods), so one brush serves the whole stall.

Copied verbatim from Joust Tycoon's Greenmeadow fair and hub painters (blender-source/world/renfair/fairpaint.py,
hub/hubpaint.py; approved 2026-10-05), so the library brushes paint exactly what the project's copies paint."""

import math

import numpy as np

from paintlib import fbm, mix, ramp, smoothstep, solid

from .core import colour, finish, posterize
from .registry import brush

SOURCE = "Joust Tycoon Greenmeadow, 2026-10-05"


@brush("food.produce", version=1, material="produce", fixture="dome", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowFairStall and barrel apples, pears, carrots, cabbage stalks)", summary="A piece of fruit or veg round its object origin (base, light, dark colour names): mottled skin, an optional sunny `blush` on the top, a dark stem dimple at the very top (stem=False for none)")
def produce(context, base, light, dark, blush=None, seed=0.0, stem=True):
    """A piece of fruit or veg (apple, pear, carrot) round its object origin: mottled skin, a sunny blush on the
    top, a dark stem dimple at the top."""
    count = context.count
    variation = fbm(context.pos, scale=2.8, octaves=3, seed=151.0 + seed)
    rgb = mix(solid(count, colour(base)), solid(count, colour(dark)), np.clip(0.45 - variation * 2.2, 0, 1) * 0.6)
    rgb = mix(rgb, solid(count, colour(light)), np.clip(variation * 2.5 - 0.2, 0, 1) * 0.5)
    if blush:
        rgb = mix(rgb, solid(count, colour(blush)), smoothstep(0.1, 0.8, context.normal[:, 2]) * 0.5)
    if stem:
        top = smoothstep(0.93, 0.99, context.normal[:, 2])
        rgb = mix(rgb, solid(count, colour("MeadowFairTimberGrain")), top * 0.8)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.35)


@brush("food.loaf", version=1, material="bread", fixture="dome", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowFairStall bakery)", summary="A loaf: golden crust darkening to the top, paler sides, blisters, a floury underside (`flour`), slashes `scores` = [((x, y), angle, length)] in object space opened pale")
def loaf(context, scores=(), seed=0.0, flour=0.35):
    """A loaf: golden crust darkening to the top, paler sides and a floury underside, slashes `scores` = list of
    ((x, y), angle, length) in object space opened pale."""
    count = context.count
    up = context.normal[:, 2]
    rgb = mix(solid(count, colour("MeadowFairCrustLight")), solid(count, colour("MeadowFairCrust")), smoothstep(-0.2, 0.5, up))
    rgb = mix(rgb, solid(count, colour("MeadowFairCrustDark")), smoothstep(0.6, 1.0, up) * 0.45)
    blister = fbm(context.pos, scale=4.0, octaves=2, seed=181.0 + seed)
    rgb = mix(rgb, solid(count, colour("MeadowFairCrustDark")), smoothstep(0.15, 0.35, blister) * 0.4)
    local = context.local
    for (x, y), angle, length in scores:
        direction = np.array((math.cos(angle), math.sin(angle)))
        offset = local[:, :2] - np.array((x, y))
        along = offset @ direction
        across = offset @ np.array((-direction[1], direction[0]))
        cut = (1 - smoothstep(0.03, 0.07, np.abs(across))) * (1 - smoothstep(length / 2 - 0.05, length / 2, np.abs(along))) * (up > 0.2)
        rgb = mix(rgb, solid(count, colour("MeadowFairCanvas")), cut * 0.85)
    rgb = mix(rgb, solid(count, colour("MeadowFairCanvas")), smoothstep(-0.2, -0.7, up) * flour)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.3)


@brush("food.fruit_heap", version=1, material="produce", fixture="fruit", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowFairBarrels apple barrel)", summary="A heap of round fruit painted onto a mound: each texel takes the nearest of `centres` (object space, fruit of `radius` sitting on the mound), coloured per fruit (every third `alternate` if given), lit upper left, dark gaps where fruit meet, a stem dimple on each top")
def fruit_heap(context, centres, radius, base="MeadowFairApple", light="MeadowFairAppleLight", dark="MeadowFairClayDark", alternate=None, seed=0.0):
    """A heap of round fruit painted onto a mound: each texel takes the nearest of `centres` (object space, the
    fruit sitting on the mound), coloured per fruit (every third one `alternate` if given), lit on its upper left,
    with dark gaps where neighbouring fruit meet and a stem dimple at each top."""
    count = context.count
    local = context.local
    centres = np.asarray(centres, dtype=np.float64)
    distance = np.linalg.norm(local[:, None, :] - centres[None, :, :], axis=2)
    order = np.argsort(distance, axis=1)
    nearest = order[:, 0]
    first = distance[np.arange(count), nearest]
    second = distance[np.arange(count), order[:, 1]]
    rgb = solid(count, colour(base))
    if alternate:
        chosen = np.mod(nearest, 3) == 1
        rgb[chosen] = solid(int(chosen.sum()), colour(alternate))
    tone = np.sin(nearest * 2.399 + seed) * 0.5 + 0.5
    rgb = mix(rgb, solid(count, colour(dark)), tone * 0.25)
    offset = local - centres[nearest]
    shine = 1 - smoothstep(0.0, radius * 0.9, np.linalg.norm(offset - np.array((-0.3, -0.3, 0.6)) * radius, axis=1))
    rgb = mix(rgb, solid(count, colour(light)), shine * 0.6)
    gap = 1 - smoothstep(0.0, radius * 0.35, second - first)
    rgb = mix(rgb, solid(count, colour(dark)), gap * 0.85)
    stem = 1 - smoothstep(radius * 0.06, radius * 0.14, np.linalg.norm(offset - np.array((0.0, 0.0, radius * 0.8)), axis=1))
    rgb = mix(rgb, solid(count, colour("MeadowFairTimberGrain")), stem * 0.8)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.3)


@brush("food.gourd", version=1, material="produce", fixture="dome", tint=False, styles=("painted-toon",), source=SOURCE + " (MeadowFairStall pumpkins)", summary="A ribbed pumpkin or gourd round object Z: dark grooves between `ribs` swollen lobes with a light crown, a sunken dark stem well on top, mottled skin")
def gourd(context, ribs=8, base="MeadowFairPumpkin", light="MeadowFairPumpkinLight", dark="MeadowFairPumpkinDark", seed=0.0):
    """A ribbed pumpkin round object Z: dark grooves between `ribs` swollen lobes that catch a light crown, a sunken
    dark stem well at the top, mottled skin."""
    count = context.count
    local = context.local
    angle = np.arctan2(local[:, 1], local[:, 0])
    lobe = np.abs(np.sin(angle * ribs / 2))
    rgb = mix(solid(count, colour(dark)), solid(count, colour(base)), smoothstep(0.05, 0.45, lobe))
    rgb = mix(rgb, solid(count, colour(light)), smoothstep(0.7, 1.0, lobe) * 0.45)
    variation = fbm(context.pos, scale=3.0, octaves=2, seed=211.0 + seed)
    rgb = mix(rgb, solid(count, colour(dark)), np.clip(0.4 - variation * 2.4, 0, 1) * 0.3)
    well = smoothstep(0.85, 0.97, context.normal[:, 2])
    rgb = mix(rgb, solid(count, colour(dark)), well * 0.7)
    return finish(rgb, context, ao_strength=0.8, edge_light=0.35)


@brush("food.goods", version=1, material="provisions", fixture="dome", tint=False, styles=("painted-toon",), source=SOURCE + " (hub quartermaster's hams, garlic, onions, cheeses, loaves, apples, crocks)", summary="Goods in three posterised tones of one colour family (base, light, dark names): hams, cheeses, onions, garlic, loaves, crocks; crease > 0 adds a crease pattern from low pointiness (a garlic bulb's cloves)")
def goods(context, base, light, dark, seed=0.0, crease=0.0):
    """Goods painted in three posterised tones of a colour family (hams, cheeses, onions, garlic, loaves), with an
    optional crease pattern from low pointiness (a garlic bulb's cloves)."""
    tone = np.clip(0.5 + fbm(context.local, scale=2.2, octaves=2, seed=seed + 61.0) * 1.4, 0, 1)
    rgb = ramp(posterize(tone, 3), [(0.0, colour(dark)), (0.5, colour(base)), (1.0, colour(light))])
    if crease > 0:
        rgb = mix(rgb, solid(context.count, colour(dark)), smoothstep(0.48, 0.42, context.curvature) * crease)
    return finish(rgb, context, ao_strength=0.7, edge_light=0.3)
