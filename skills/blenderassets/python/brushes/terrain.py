"""brushes.terrain: tileable ground textures for Roblox Terrain MaterialVariants. These brushes paint a flat image,
not an atlas: painter(tile, **options) -> RGB for every texel of a Tile, the texel grid of one square texture covering
`period` studs (Tile(16) at 1024 is the Greenmeadow size). Everything that varies across it comes from
surface.tiled_fbm with the tile's period, or is rasterised with wrap-around indices, so the texture repeats exactly
at its edges. Each painter lays flat palette tones (posterised patches, blades, straws, pebbles with a lit top and a
hard cool shadow on the down-light side), builds a micro height field from what it laid, and hands colour, that
field's normals and occlusion to core.finish, so the style's finish applies as on any atlas.

    tile = brushes.terrain.Tile(16)
    rgb = style.painter("tileable turf")(tile)          # (1024 * 1024, 3), row 0 at y = 0
    brushes.terrain.tiling_error(rgb)                   # ~1 when the seam is no harsher than the paint itself

Copied verbatim from Joust Tycoon's Greenmeadow terrain painters (blender-source/world/terrain/terrainpaint.py;
approved 2026-10-05) with default palettes and seeds added, so the library brushes paint exactly what the project's
copies paint for the same options."""

import math

import numpy as np

from paintlib import Context, mix, ramp, smoothstep, solid

from .core import colour, finish, posterize
from .registry import brush
from .surface import tiled_fbm

SOURCE = "Joust Tycoon Greenmeadow, 2026-10-05 (Greenmeadow terrain MaterialVariants)"
# default palettes: Greenmeadow's meadow grass and its packed-earth road (the MeadowTurf and MeadowPackedEarth looks)
TURF_PALETTE = {"base": "MeadowGrass", "light": "MeadowGrassLight", "dark": "MeadowGrassDark", "sun": "MeadowGrassSun", "cool": "MeadowGrassCool", "earth": "MeadowEarth", "earth_dark": "MeadowEarthDark"}
EARTH_PALETTE = {"base": "MeadowPath", "light": "MeadowPathLight", "dark": "MeadowPathDark", "deep": "MeadowEarthDark", "pebble": "MeadowStone", "pebble_light": "MeadowStoneLight", "pebble_dark": "MeadowStoneDark"}

SIZE = 1024
SHADOW_OFFSET = (0.55, 0.75)


class Tile:
    def __init__(self, period, size=SIZE):
        self.period = float(period)
        self.size = size
        self.pixels_per_stud = size / self.period
        axis = (np.arange(size) + 0.5) / size * self.period
        x, y = np.meshgrid(axis, axis)
        self.x = x.ravel()
        self.y = y.ravel()
        self.count = size * size

    def noise(self, scale, octaves, seed, stretch=(1, 1)):
        points = np.stack([self.x * stretch[0], self.y * stretch[1], np.zeros(self.count)], axis=1)
        return tiled_fbm(points, scale, octaves, (self.period * stretch[0], self.period * stretch[1], 0.0), seed)

    def diagonal_noise(self, scale, octaves, seed, stretch=4):
        # (x + y, x − y) shifts by (P, P) when x or y moves one period, so noise periodic in both diagonal axes still
        # tiles; stretching the second axis by an integer keeps that period whole and turns blobs into strokes
        points = np.stack([self.x + self.y, (self.x - self.y) * stretch, np.zeros(self.count)], axis=1)
        return tiled_fbm(points, scale, octaves, (self.period, self.period * stretch, 0.0), seed)

    def grid(self, values):
        return values.reshape(self.size, self.size)


class Layer:
    """Shapes rasterised onto a wrapping grid: coverage, the shape's own 0..1 parameter (base to tip), a per-shape
    tone, and a shadow coverage offset down-light."""

    def __init__(self, tile):
        size = tile.size
        self.tile = tile
        self.cover = np.zeros((size, size))
        self.along = np.zeros((size, size))
        self.tone = np.zeros((size, size))
        self.shadow = np.zeros((size, size))
        self.dome = np.zeros((size, size))

    def _window(self, centre_x, centre_y, reach):
        size = self.tile.size
        columns = np.arange(int(centre_x - reach), int(centre_x + reach) + 2)
        rows = np.arange(int(centre_y - reach), int(centre_y + reach) + 2)
        grid_x, grid_y = np.meshgrid(columns, rows)
        return grid_x, grid_y, grid_y % size, grid_x % size

    def _stamp(self, rows, columns, inside, along, tone, dome):
        take = inside > self.cover[rows, columns] * 0.5
        self.along[rows, columns] = np.where(take, along, self.along[rows, columns])
        self.tone[rows, columns] = np.where(take, tone, self.tone[rows, columns])
        self.dome[rows, columns] = np.where(take, dome, self.dome[rows, columns])
        self.cover[rows, columns] = np.maximum(self.cover[rows, columns], inside)

    def blade(self, centre_x, centre_y, angle, length, width, tone, shadow=True, bend=0.0):
        """A tapered leaf stroke from its base (along 0) to its tip (1), widest a third of the way up."""
        reach = length / 2 + width + 4
        grid_x, grid_y, rows, columns = self._window(centre_x, centre_y, reach)
        cosine, sine = math.cos(angle), math.sin(angle)
        for pass_index, (shift_x, shift_y) in enumerate(((SHADOW_OFFSET[0] * width, SHADOW_OFFSET[1] * width), (0.0, 0.0))):
            offset_x = grid_x + 0.5 - centre_x - shift_x
            offset_y = grid_y + 0.5 - centre_y - shift_y
            along = (offset_x * cosine + offset_y * sine) / length + 0.5
            across = -offset_x * sine + offset_y * cosine - bend * width * (along - 0.5) ** 2 * 4
            # leaf profile: half-width (w/2)·sin(π·a^0.75), widest near a third of the way to the tip
            profile = width / 2 * np.sin(math.pi * np.clip(along, 0, 1) ** 0.75)
            inside = np.clip(profile - np.abs(across) + 0.5, 0, 1) * ((along >= 0) & (along <= 1))
            if pass_index == 0:
                if shadow:
                    self.shadow[rows, columns] = np.maximum(self.shadow[rows, columns], inside)
            else:
                self._stamp(rows, columns, inside, np.clip(along, 0, 1), tone, 1 - np.abs(across) / np.maximum(profile, 1e-3))

    def pebble(self, centre_x, centre_y, radius_x, radius_y, angle, tone):
        """A flattened oval stone; dome is its height (1 at the centre), used for its lit top and shadow side."""
        reach = max(radius_x, radius_y) * 1.6 + 3
        grid_x, grid_y, rows, columns = self._window(centre_x, centre_y, reach)
        cosine, sine = math.cos(angle), math.sin(angle)
        for pass_index, (shift_x, shift_y) in enumerate(((SHADOW_OFFSET[0] * radius_x, SHADOW_OFFSET[1] * radius_y), (0.0, 0.0))):
            offset_x = grid_x + 0.5 - centre_x - shift_x
            offset_y = grid_y + 0.5 - centre_y - shift_y
            local_x = (offset_x * cosine + offset_y * sine) / radius_x
            local_y = (-offset_x * sine + offset_y * cosine) / radius_y
            distance = np.sqrt(local_x * local_x + local_y * local_y)
            inside = np.clip((1 - distance) * min(radius_x, radius_y) + 0.5, 0, 1)
            if pass_index == 0:
                self.shadow[rows, columns] = np.maximum(self.shadow[rows, columns], inside * 0.9)
            else:
                # upper-left of the stone faces the key light: lit share = −(x + y)/√2 of the unit dome
                lit = np.clip(-(offset_x + offset_y) / (math.sqrt(2) * max(radius_x, radius_y)), -1, 1)
                self._stamp(rows, columns, inside, lit * 0.5 + 0.5, tone, np.sqrt(np.clip(1 - distance * distance, 0, 1)))

    def flat(self, name):
        return getattr(self, name).ravel()


def height_context(tile, height, occlusion):
    """A Context for the finish from a micro height field (studs) on the tile: normals from its wrapped gradient,
    ao from the occlusion field (0 open .. 1 shut)."""
    step = tile.period / tile.size
    gradient_x = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2 * step)
    gradient_y = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2 * step)
    normal = np.stack([-gradient_x.ravel(), -gradient_y.ravel(), np.ones(tile.count)], axis=1)
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)
    pos = np.stack([tile.x, tile.y, height.ravel()], axis=1)
    ao = np.clip(1 - occlusion.ravel(), 0, 1)
    return Context(pos, normal, ao, np.full(tile.count, 0.5), np.zeros(tile.count), pos)


def _patches(tile, seed, levels=3, scale=0.09):
    return posterize(np.clip(0.5 + tile.noise(scale, 3, seed) * 1.6, 0, 1), levels)


def _scatter(tile, count, seed):
    rng = np.random.default_rng(seed)
    return rng, rng.uniform(0, tile.size, (count, 2))


@brush("terrain.turf", version=1, material="grass", fixture="tile", tint=False, styles=("painted-toon",), source=SOURCE, summary="Tileable grass seen from above, for a 1024 Terrain MaterialVariant (paint a Tile(period)): a dark cool undergrowth under thousands of tapered blades leaning one way, root dark to tip light, toned by broad posterised patches, each with a hard cool shadow down-light; `earth` lets bare earth show (trodden ground); palette names base, light, dark, sun, cool, earth, earth_dark")
def turf(tile, palette=TURF_PALETTE, seed=0, density=1.0, blade_length=0.75, blade_width=0.2, earth=0.0, sun=0.12, lean=0.6):
    """Painted-toon grass seen from above: a dark, cool undergrowth, then thousands of tapered blades leaning
    roughly one way (a painted stroke direction), dark at the root to light at the tip, toned by broad posterised
    patches, each with a hard cool shadow down-light. `earth` (0..1) lets bare earth show between thinner blades
    (trodden ground); `palette` names base, light, dark, sun, cool and earth colours."""
    px = tile.pixels_per_stud
    patches = _patches(tile, seed + 1)
    under = ramp(np.clip(0.5 + tile.noise(0.35, 2, seed + 2) * 1.4, 0, 1), [(0.0, colour(palette["cool"])), (1.0, colour(palette["dark"]))])
    if earth > 0:
        bare = smoothstep(0.55 - earth * 0.5, 0.7 - earth * 0.5, 0.5 + tile.noise(0.22, 3, seed + 3) * 1.5)
        soil = mix(solid(tile.count, colour(palette["earth"])), solid(tile.count, colour(palette["earth_dark"])), smoothstep(0.1, 0.4, tile.noise(1.4, 2, seed + 4)))
        under = mix(under, soil, bare)
    else:
        bare = np.zeros(tile.count)
    layer = Layer(tile)
    blade_area = 0.55 * blade_length * blade_width * px * px
    count = int(tile.size * tile.size * 1.25 * density / blade_area)
    rng, centres = _scatter(tile, count, seed + 5)
    bare_grid = tile.grid(bare)
    for centre_x, centre_y in centres:
        if bare_grid[int(centre_y) % tile.size, int(centre_x) % tile.size] > rng.uniform(0.2, 1.0):
            continue
        angle = -math.pi / 2 + rng.normal(0.35, lean)
        tone = rng.uniform(0, 1)
        layer.blade(centre_x, centre_y, angle, blade_length * px * rng.uniform(0.6, 1.35), blade_width * px * rng.uniform(0.7, 1.3), tone, bend=rng.uniform(-0.6, 0.6))
    cover, along, tone = layer.flat("cover"), layer.flat("along"), layer.flat("tone")
    shadow = layer.flat("shadow")
    stops = [(0.0, colour(palette["dark"])), (0.45, colour(palette["base"])), (1.0, colour(palette["light"]))]
    blade_value = np.clip(along * 0.75 + patches * 0.45 - 0.2 + (tone - 0.5) * 0.25, 0, 1)
    blades = ramp(posterize(blade_value, 4), stops)
    blades = mix(blades, solid(tile.count, colour(palette["sun"])), (tone > 1 - sun) * smoothstep(0.55, 0.8, along))
    rgb = mix(under, solid(tile.count, colour(palette["cool"])), shadow * (1 - cover) * 0.75)
    rgb = mix(rgb, blades, cover)
    height = tile.grid(cover * (0.08 + 0.12 * along))
    occlusion = tile.grid(shadow * (1 - cover) * 0.6 + (1 - cover) * (1 - bare) * 0.25)
    return finish(rgb, height_context(tile, height, occlusion), ao_strength=0.5, edge_light=0.0)


@brush("terrain.ground", version=1, material="earth", fixture="tile", tint=False, styles=("painted-toon",), source=SOURCE, summary="Tileable bare ground seen from above, for a 1024 Terrain MaterialVariant (paint a Tile(period)): three-tone posterised mottling, dark grit, flat oval pebbles with a lit top and hard shadow, optional strewn straw, wet sheen or moss sprigs; palette names base, light, dark, deep, pebble, pebble_light, pebble_dark (+ straw, straw_dark, straw_light, sheen, moss, moss_dark when used)")
def ground(tile, palette=EARTH_PALETTE, seed=0, pebbles=0.6, grit=0.5, straw=0.0, sheen=0.0, moss=0.0):
    """Painted-toon bare ground seen from above: posterised mottling in three tones, dark grit, flat oval pebbles
    with a lit top and a hard shadow, and optionally strewn straw (fair paths), a wet sheen (pond banks) or moss
    sprigs. `palette` names base, light, dark, deep, pebble, pebble_light, pebble_dark, and straw / straw_dark /
    sheen / moss when used."""
    px = tile.pixels_per_stud
    mottle = _patches(tile, seed + 1, levels=3, scale=0.2)
    rgb = mix(solid(tile.count, colour(palette["base"])), ramp(mottle, [(0.0, colour(palette["dark"])), (0.5, colour(palette["base"])), (1.0, colour(palette["light"]))]), 0.5)
    fine = tile.noise(0.9, 2, seed + 2)
    rgb = mix(rgb, solid(tile.count, colour(palette["light"])), smoothstep(0.2, 0.32, fine) * 0.35)
    speck = tile.noise(3.2, 1, seed + 3)
    rgb = mix(rgb, solid(tile.count, colour(palette["deep"])), smoothstep(0.32, 0.42, speck) * grit)
    if sheen > 0:
        streak = tile.diagonal_noise(0.7, 2, seed + 4, stretch=2)
        rgb = mix(rgb, solid(tile.count, colour(palette["sheen"])), smoothstep(0.18, 0.3, streak) * sheen)
        rgb = mix(rgb, solid(tile.count, colour(palette["deep"])), smoothstep(-0.18, -0.32, streak) * sheen * 0.6)
    height = np.zeros(tile.count)
    occlusion = np.zeros(tile.count)

    stones = Layer(tile)
    stone_count = int(pebbles * tile.period * tile.period * 1.1)
    rng, centres = _scatter(tile, stone_count, seed + 5)
    for centre_x, centre_y in centres:
        radius = rng.uniform(0.07, 0.2) * px * (1.8 if rng.uniform() < 0.08 else 1.0)
        stones.pebble(centre_x, centre_y, radius, radius * rng.uniform(0.55, 0.9), rng.uniform(0, math.pi), rng.uniform())
    cover, lit, tone = stones.flat("cover"), stones.flat("along"), stones.flat("tone")
    stone = ramp(posterize(np.clip(lit * 0.8 + tone * 0.3 - 0.05, 0, 1), 3), [(0.0, colour(palette["pebble_dark"])), (0.5, colour(palette["pebble"])), (1.0, colour(palette["pebble_light"]))])
    rgb = mix(rgb, solid(tile.count, colour(palette["deep"])), stones.flat("shadow") * (1 - cover) * 0.55)
    rgb = mix(rgb, stone, cover)
    height += cover * stones.flat("dome") * 0.08
    occlusion += stones.flat("shadow") * (1 - cover) * 0.5

    if straw > 0 or moss > 0:
        strands = Layer(tile)
        strand_count = int((straw * 2.2 + moss * 0.9) * tile.period * tile.period)
        rng, centres = _scatter(tile, strand_count, seed + 6)
        for centre_x, centre_y in centres:
            if moss > 0 and rng.uniform() < moss / (straw + moss):
                strands.blade(centre_x, centre_y, -math.pi / 2 + rng.normal(0, 0.7), 0.45 * px * rng.uniform(0.6, 1.2), 0.16 * px, 2.0 + rng.uniform())
            else:
                strands.blade(centre_x, centre_y, rng.uniform(0, math.tau), rng.uniform(0.5, 1.1) * px, rng.uniform(0.05, 0.08) * px, rng.uniform(), bend=rng.uniform(-1.5, 1.5))
        cover, along, tone = strands.flat("cover"), strands.flat("along"), strands.flat("tone")
        is_moss = tone >= 2.0
        straw_rgb = ramp(posterize(np.clip(tone * 0.7 + along * 0.4, 0, 1), 3), [(0.0, colour(palette.get("straw_dark", palette["dark"]))), (0.6, colour(palette.get("straw", palette["light"]))), (1.0, colour(palette.get("straw_light", palette["light"])))])
        if moss > 0:
            moss_rgb = ramp(along, [(0.0, colour(palette["moss_dark"])), (1.0, colour(palette["moss"]))])
            straw_rgb = np.where(is_moss[:, None], moss_rgb, straw_rgb)
        rgb = mix(rgb, solid(tile.count, colour(palette["deep"])), strands.flat("shadow") * (1 - cover) * 0.45)
        rgb = mix(rgb, straw_rgb, cover)
        height += cover * 0.05
        occlusion += strands.flat("shadow") * (1 - cover) * 0.4

    return finish(rgb, height_context(tile, tile.grid(height), tile.grid(np.clip(occlusion, 0, 1))), ao_strength=0.5, edge_light=0.0)


def mean_hex(rgb):
    mean = np.clip(rgb[:, :3].mean(axis=0), 0, 1)
    return "".join(f"{int(round(value * 255)):02X}" for value in mean)


def tiling_error(rgb, size=SIZE):
    """Largest jump across the wrap seam compared with the largest jump between neighbouring texels inside: near
    1 means the seam is no harsher than the paint itself."""
    image = rgb[:, :3].reshape(size, size, 3)
    seam = max(np.abs(image[:, 0] - image[:, -1]).mean(), np.abs(image[0] - image[-1]).mean())
    inside = max(np.abs(image[:, 1:] - image[:, :-1]).mean(), np.abs(image[1:] - image[:-1]).mean())
    return seam / max(inside, 1e-9)
