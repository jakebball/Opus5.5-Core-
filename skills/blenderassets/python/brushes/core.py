"""brushes.core: the active style's palette and finish, and the helpers every brush shares."""

import math

import numpy as np

from paintlib import fbm, hex_rgb, lift, mix, painted_light, ramp, shade, smoothstep, solid

DEFAULT_PALETTE = {
    "Ash": "B97F45",
    "AshLight": "DDA868",
    "AshDark": "7E4C26",
    "AshGrain": "573117",
    "Iron": "4D525D",
    "IronLight": "A3ACBA",
    "IronDark": "1F2228",
    "Rust": "8A4F2E",
    "Rope": "C9A060",
    "RopeDark": "7A5527",
    "Leather": "7E4321",
    "LeatherLight": "B06B3A",
    "LeatherDark": "3F200F",
    "Linen": "E9D7B0",
    "LinenShade": "B89C70",
    "LinenStitch": "6F5638",
    "Wool": "5F78AE",
    "WoolDark": "3C4F7E",
    "Bay": "9C4E22",
    "BayLight": "C27236",
    "BayDark": "5A2A12",
    "Points": "2A1A12",
    "Muzzle": "5C3828",
    "Blaze": "F2EADB",
    "Feather": "E9DCC4",
    "Hoof": "3A302B",
    "HoofLight": "6B5B50",
    "Eye": "1A1210",
    "TeamBase": "F0F0F0",
    "TeamShade": "A9A9B6",
    "Brass": "C9932E",
    "BrassLight": "F6D47A",
    "Gold": "D8A23E",
    "GoldLight": "FFE28C",
    "GoldDark": "7E5016",
    "Binding": "5B2F17",
    "BindingLight": "8C5330",
    "PatchRed": "A4553F",
    "PatchOlive": "7C7F4C",
    # Joust Tycoon castle (Rebirth 0), approved 2026-10-05: the world a notch less saturated than the knights.
    # Sandstone ashlar, mortar and moss
    "CastleStone": "B2A790",
    "CastleStoneLight": "D8CEB5",
    "CastleStoneDark": "877D6C",
    "CastleStoneWarm": "B8A07E",
    "CastleStoneCool": "959893",
    "CastleMortar": "4E473F",
    "CastleMoss": "6E8A47",
    "CastleMossDark": "4A6331",
    "CastleTimberGrain": "34200F",
    "CastleSlit": "17141A",
    # team roof tile (TintMask): near-white, cool gaps between the scales
    "CastleTile": "F4F4F4",
    "CastleTileShade": "B4B4C0",
    "CastleTileGap": "55556A",
    # toon water
    "CastleWater": "3F8EA3",
    "CastleWaterLight": "7DCCD9",
    "CastleWaterDark": "245B75",
    "CastleWaterFoam": "E2F4F1",
    # turf, earth, reeds and lily pads
    "CastleGrass": "6F9447",
    "CastleGrassLight": "9DBE5E",
    "CastleGrassDark": "466A2E",
    "CastleEarth": "7A5E3E",
    "CastleEarthDark": "4D3A27",
    "CastleReed": "7E9A45",
    "CastleReedLight": "B9C470",
    "CastleReedDark": "4B6229",
    "CastleLily": "4F8A3A",
    "CastleLilyLight": "86BA5A",
    "CastleLilyDark": "2F5A26",
    # courtyard flagstones: cooler grey-sand, a step away from the wall sandstone
    "CastlePave": "A49F8F",
    "CastlePaveLight": "C9C3B0",
    "CastlePaveDark": "7B7668",
    "CastlePaveWarm": "B3A283",
    "CastlePaveCool": "8E9391",
    # straw, burlap, hemp rope, firewood
    "CastleHay": "D6AC4E",
    "CastleHayLight": "F0D584",
    "CastleHayDark": "A47A2E",
    "CastleHayGap": "6B4A1C",
    "CastleHayGreen": "AFA24E",
    "CastleBurlap": "B4946A",
    "CastleBurlapLight": "D3B98D",
    "CastleBurlapDark": "7D6243",
    "CastleBurlapWeave": "5A4430",
    "CastleGrain": "E2C77C",
    "CastleRope": "C2A06A",
    "CastleRopeLight": "E0C58F",
    "CastleRopeDark": "7E6034",
    "CastleBark": "5C4130",
    "CastleBarkLight": "7F604A",
    "CastleBarkDark": "34251B",
    "CastleSplit": "D8B27C",
    "CastleSplitDark": "AF8452",
    "CastleEndGrain": "E3C38F",
    "CastleEndRing": "A0723F",
    # Joust Tycoon Greenmeadow (zone 1 and the hub), approved 2026-10-05: the world a notch less saturated than the
    # knights; the toon finish adds the punch. Only the names the promoted brushes and their roles read.
    # Greenmeadow base: grass, leaves, earth and road, bark, field stone, wildflower accents, straw
    "MeadowGrass": "6F9447",
    "MeadowGrassLight": "9DBE5E",
    "MeadowGrassDark": "466A2E",
    "MeadowGrassSun": "B6CF6C",
    "MeadowGrassCool": "3F6239",
    "MeadowLeaf": "5A8C3C",
    "MeadowLeafLight": "8CBF52",
    "MeadowLeafDark": "355E2A",
    "MeadowLeafDeep": "24452A",
    "MeadowEarth": "7A5E3E",
    "MeadowEarthDark": "4D3A27",
    "MeadowPath": "B0926A",
    "MeadowPathLight": "CDB287",
    "MeadowPathDark": "8A6C47",
    "MeadowBark": "6B4A30",
    "MeadowBarkDark": "46301F",
    "MeadowStone": "A49F8F",
    "MeadowStoneLight": "C9C3B0",
    "MeadowStoneDark": "7B7668",
    "MeadowMoss": "7E9A45",
    "MeadowPoppy": "D9473A",
    "MeadowButtercup": "F2C93B",
    "MeadowDaisy": "F4EFE4",
    "MeadowDaisyEye": "E8B23A",
    "MeadowCornflower": "5A7BD8",
    "MeadowClover": "C77BB0",
    "MeadowStraw": "E3C46E",
    "MeadowStrawDark": "B8963F",
    # foliage: leaf sun flecks, the cool shadow band and gaps, blossom, poplar leaves, bark ridges
    "MeadowLeafSun": "B4CF63",
    "MeadowLeafShade": "2E5546",
    "MeadowLeafGap": "1E3A2A",
    "MeadowFoliageRose": "EC9AB4",
    "MeadowLeafPoplar": "4C7F44",
    "MeadowLeafPoplarLight": "7DAD55",
    "MeadowLeafPoplarDark": "2F5434",
    "MeadowFoliageBarkRidge": "A07B52",
    "MeadowFoliageBarkFissure": "33231A",
    "MeadowFoliagePoplarBark": "8C7B66",
    "MeadowFoliagePoplarBarkLight": "B3A389",
    "MeadowFoliagePoplarBarkDark": "5B4D3F",
    # ground cover: petals and eyes, clover, seed heads, bulrushes, toadstools, field-stone lichen
    "MeadowFlowerPoppyLight": "EC745C",
    "MeadowFlowerPoppyDark": "A8352E",
    "MeadowFlowerPoppyEye": "2A1F1D",
    "MeadowFlowerPod": "8C9A55",
    "MeadowFlowerButtercupLight": "FAE07C",
    "MeadowFlowerButtercupDark": "C9952A",
    "MeadowFlowerDaisyShade": "DCD6CB",
    "MeadowFlowerDaisyBlush": "E6C3C6",
    "MeadowFlowerDaisyEyeDark": "B47E25",
    "MeadowFlowerCornflowerLight": "8AA4EA",
    "MeadowFlowerCornflowerDark": "3D57AA",
    "MeadowFlowerCornflowerEye": "2E3270",
    "MeadowFlowerCloverLight": "E3A9D0",
    "MeadowFlowerCloverDark": "93507F",
    "MeadowFlowerSepal": "4E7B33",
    "MeadowFlowerChevron": "A9C98A",
    "MeadowCoverSeed": "D8C27C",
    "MeadowCoverSeedDark": "A28C4F",
    "MeadowCoverBulrush": "6B4527",
    "MeadowCoverBulrushLight": "8E6238",
    "MeadowCoverBulrushDark": "45291A",
    "MeadowCoverToadstool": "C83F31",
    "MeadowCoverToadstoolLight": "E2654D",
    "MeadowCoverToadstoolDark": "8A2A23",
    "MeadowCoverSpot": "F4EFE4",
    "MeadowCoverStalk": "ECE2CB",
    "MeadowCoverStalkShade": "C4B394",
    "MeadowCoverGill": "D6C29E",
    "MeadowCoverGillDark": "A88F68",
    "MeadowRockWarm": "B2A386",
    "MeadowRockCool": "8F9592",
    "MeadowRockCrack": "4F4A42",
    "MeadowRockLichen": "C7BE72",
    "MeadowRockLichenPale": "D9D5BC",
    # farm: dressed timber, dry-stone wall, wheat, thatch, sailcloth, sign paint
    "MeadowFarmRail": "9A8971",
    "MeadowFarmLichen": "A8B06A",
    "MeadowFarmLichenDark": "7D8A4C",
    "MeadowFarmTimber": "8A603C",
    "MeadowFarmTimberLight": "B0835A",
    "MeadowFarmTimberDark": "573A22",
    "MeadowFarmTimberGrain": "3A2614",
    "MeadowFarmStoneWarm": "B09C7E",
    "MeadowFarmStoneCool": "8F9290",
    "MeadowFarmStoneVoid": "3B3630",
    "MeadowFarmMossDark": "566B32",
    "MeadowFarmWheatEar": "D7A944",
    "MeadowFarmWheatEarLight": "F1D27A",
    "MeadowFarmWheatGap": "7C5A22",
    "MeadowFarmWheatStem": "9C9A48",
    "MeadowFarmWheatFoot": "5E7434",
    "MeadowFarmThatch": "BE9C5A",
    "MeadowFarmThatchLight": "DDBF7F",
    "MeadowFarmThatchDark": "86683A",
    "MeadowFarmThatchGap": "4F3B20",
    "MeadowFarmCanvas": "E6DCC4",
    "MeadowFarmCanvasShade": "BFB194",
    "MeadowFarmCanvasSeam": "8E8068",
    "MeadowFarmShield": "4E7A3A",
    "MeadowFarmShieldDark": "33532A",
    "MeadowFarmShieldRim": "C9A24A",
    # fair: festive dyes, gilt, timber, goods, wicker
    "MeadowFairWoad": "3E68A8",
    "MeadowFairSaffron": "DC9A3E",
    "MeadowFairMadder": "A8463E",
    "MeadowFairTeal": "2E8C86",
    "MeadowFairCream": "EEE3C6",
    "MeadowFairPlum": "7E4A8E",
    "MeadowFairRose": "CC6A82",
    "MeadowFairCanvas": "E9DFC6",
    "MeadowFairTimber": "9A6D44",
    "MeadowFairTimberLight": "C29462",
    "MeadowFairTimberDark": "604126",
    "MeadowFairTimberGrain": "3D2815",
    "MeadowFairGiltDark": "8C6424",
    "MeadowFairApple": "B8423A",
    "MeadowFairAppleLight": "E2775A",
    "MeadowFairAppleGreen": "9DB04A",
    "MeadowFairPear": "C2BC52",
    "MeadowFairPearLight": "E2D77E",
    "MeadowFairPearDark": "8A8A34",
    "MeadowFairCabbage": "7FAE56",
    "MeadowFairCabbageDark": "4C7A3A",
    "MeadowFairPumpkin": "D08A34",
    "MeadowFairPumpkinLight": "ECB862",
    "MeadowFairPumpkinDark": "8E5220",
    "MeadowFairCrust": "C6823C",
    "MeadowFairCrustLight": "E6B068",
    "MeadowFairCrustDark": "8A5224",
    "MeadowFairClayDark": "7A3E26",
    "MeadowFairWicker": "C49A5A",
    "MeadowFairWickerLight": "E2C080",
    "MeadowFairWickerDark": "7E5C2C",
    # hub: roof clay, slate and shingle, thatch, forge coals and embers, soot, provisions, chalk board
    "MeadowHubSlate": "6B7380",
    "MeadowHubSlateShade": "4C535F",
    "MeadowHubSlateGap": "272B33",
    "MeadowHubThatch": "C4A257",
    "MeadowHubThatchLight": "E0C47E",
    "MeadowHubThatchDark": "8A6D33",
    "MeadowHubThatchGap": "5A4323",
    "MeadowHubThatchGreen": "9C9550",
    "MeadowHubClay": "B8653F",
    "MeadowHubClayShade": "8C4A30",
    "MeadowHubClayGap": "4C2A1E",
    "MeadowHubShingle": "8E7258",
    "MeadowHubShingleShade": "66513F",
    "MeadowHubShingleGap": "33271E",
    "MeadowHubCoal": "2B2624",
    "MeadowHubCoalLight": "4A403A",
    "MeadowHubSoot": "3A332F",
    "MeadowHubEmberDeep": "B8401F",
    "MeadowHubEmber": "EE8A2E",
    "MeadowHubEmberHot": "FFD36E",
    "MeadowHubGlow": "F0A050",
    "MeadowHubHam": "A85444",
    "MeadowHubHamLight": "D68A6C",
    "MeadowHubHamRind": "6E3424",
    "MeadowHubCheese": "E8C25A",
    "MeadowHubCheeseRind": "C08A34",
    "MeadowHubBoard": "2F3833",
    "MeadowHubBoardLight": "45504A",
    "MeadowHubChalk": "E6E4DA",
    # villagers: near-white dye ground, linen, tablet-woven trim, motley and bells, plaited straw, fur
    "MeadowVillagerDyeBase": "F2F0EB",
    "MeadowVillagerDyeShade": "BEB9B1",
    "MeadowVillagerDyeDeep": "8F8A84",
    "MeadowVillagerLinen": "E6DCC4",
    "MeadowVillagerLinenShade": "BFAF8E",
    "MeadowVillagerLinenStitch": "7A6748",
    "MeadowVillagerTrimCream": "EADFC2",
    "MeadowVillagerTrimUmber": "4E3B2C",
    "MeadowVillagerTrimRusset": "8E5236",
    "MeadowVillagerMotley": "E4D7B4",
    "MeadowVillagerMotleyShade": "B9A986",
    "MeadowVillagerBell": "C9A44A",
    "MeadowVillagerBellLight": "F1D98C",
    "MeadowVillagerLace": "3A2618",
    "MeadowVillagerStraw": "D9B867",
    "MeadowVillagerStrawLight": "EDD592",
    "MeadowVillagerStrawDark": "A1803A",
    "MeadowVillagerStrawGap": "6E5226",
    "MeadowVillagerFur": "9B8A78",
    "MeadowVillagerFurLight": "CDBFA9",
    "MeadowVillagerFurDark": "5E5046",
    # terrain: warm and trodden grass, straw dirt, bank sheen
    "MeadowTerrainGrassWarm": "809F4B",
    "MeadowTerrainGrassWarmLight": "ADC463",
    "MeadowTerrainGrassWarmDark": "58712F",
    "MeadowTerrainTrodden": "98955A",
    "MeadowTerrainTroddenLight": "BDB57C",
    "MeadowTerrainTroddenDark": "6C6B3F",
    "MeadowTerrainStrawDirt": "C4A86C",
    "MeadowTerrainEarthSheen": "9A7D58",
}
PALETTE = {}
DEFAULT_FINISH = {
    "toon": False,
    "saturation": 1.3,
    "poster_step": 0.09,
    "poster": 0.65,
    "shadow": "5B4A8C",
    "shadow_level": 0.7,
    "shadow_tint": 0.18,
    "highlight": 1.12,
    "highlight_lift": 0.04,
    "warm": "FFE7B8",
    "cool": "3C3157",
}
FINISH = dict(DEFAULT_FINISH)


def activate(palette, finish):
    PALETTE.clear()
    PALETTE.update(DEFAULT_PALETTE)
    PALETTE.update(palette or {})
    FINISH.clear()
    FINISH.update(DEFAULT_FINISH)
    FINISH.update(finish or {})


def colour(name):
    if name in PALETTE:
        return PALETTE[name]
    if isinstance(name, str) and len(name) == 6 and all(char in "0123456789abcdefABCDEF" for char in name):
        return name
    raise KeyError(f"colour {name!r} is not in the active style's palette (brushes.use_style) and is not a hex colour")


def posterize(value, levels=7):
    return np.round(value * levels) / levels


def saturate(rgb, amount):
    grey = (rgb @ np.array((0.299, 0.587, 0.114)))[:, None]
    return np.clip(grey + (rgb - grey) * amount, 0.0, 1.0)


def posterize_luma(rgb, step=0.09, softness=0.16, amount=0.65):
    luma = np.maximum(rgb @ np.array((0.299, 0.587, 0.114)), 1e-4)
    scaled = luma / step
    floor = np.floor(scaled)
    stepped = (floor + smoothstep(0.5 - softness, 0.5 + softness, scaled - floor)) * step
    return mix(rgb, np.clip(rgb * (stepped / luma)[:, None], 0.0, 1.0), amount)


def toon_finish(rgb, context, ao_strength, edge_light, poster=None):
    # mostly top-down light (so the baked bands read from any heading): posterised paint, a hard cool shadow
    # band and a top highlight band
    count = context.count
    key = np.array((-0.35, -0.45, 0.82))
    key /= np.linalg.norm(key)
    light = 0.7 * context.normal[:, 2] + 0.3 * (context.normal @ key)
    rgb = posterize_luma(saturate(rgb, FINISH["saturation"]), step=FINISH["poster_step"], amount=FINISH["poster"] if poster is None else poster)
    shadow = mix(shade(rgb, FINISH["shadow_level"]), shade(solid(count, FINISH["shadow"]), FINISH["shadow_level"]), FINISH["shadow_tint"])
    lit = mix(shadow, rgb, smoothstep(-0.15, -0.09, light))
    lit = mix(lit, np.clip(rgb * FINISH["highlight"] + FINISH["highlight_lift"], 0.0, 1.0), smoothstep(0.75, 0.81, light))
    occlusion = smoothstep(0.38, 0.62, np.clip(context.ao, 0.0, 1.0))
    lit = mix(mix(lit, shadow, ao_strength), lit, occlusion)
    return lift(lit, smoothstep(0.1, 0.18, context.edge) * edge_light * 1.2, toward=FINISH["warm"])


def finish(rgb, context, ao_strength=0.6, light=1.0, edge_light=0.35, top_light=0.22, under_shadow=0.32, poster=None):
    """Bake the style's light into painted colour: the toon pass when the style's finish says toon, else the soft
    painted look (gentle key light, warm top, cool underside, AO, warm convex edges)."""
    if FINISH["toon"]:
        return toon_finish(rgb, context, ao_strength, edge_light, poster)
    count = context.count
    up = context.normal[:, 2]
    key = painted_light(context.normal, strength=0.18 * light, floor=0.9)
    lit = shade(rgb, key)
    lit = mix(lit, np.tile(hex_rgb(FINISH["warm"]), (count, 1)), smoothstep(0.35, 0.95, up) * top_light)
    lit = mix(lit, shade(lit, 0.62), smoothstep(-0.15, -0.85, up) * under_shadow)
    lit = mix(lit, np.tile(hex_rgb(FINISH["cool"]), (count, 1)), smoothstep(-0.2, -0.9, up) * under_shadow * 0.25)
    occlusion = np.clip(context.ao, 0.0, 1.0) ** 1.5
    lit = mix(shade(lit, 0.5), lit, occlusion + (1 - ao_strength) * (1 - occlusion))
    lit = mix(lit, np.tile(hex_rgb(FINISH["cool"]), (count, 1)), (1 - occlusion) * 0.16 * ao_strength)
    convex = smoothstep(0.05, 0.24, context.edge)
    return lift(lit, convex * edge_light, toward=FINISH["warm"])


def stitch_lines(phase, along, width=0.1, dash=0.075, gap=0.5):
    distance = np.abs(phase - np.round(phase))
    groove = 1 - smoothstep(width * 0.5, width, distance)
    dashes = (np.mod(along / dash, 1.0) < gap).astype(np.float64)
    thread = groove * dashes * (1 - smoothstep(0.0, width * 0.45, distance))
    return groove, thread


def _dashes(distance, run, dash=0.065, duty=0.55):
    return (np.mod(run / dash, 1.0) < duty).astype(np.float64) * (1 - smoothstep(0.0, 0.011, distance))


def _gold(across, along, count):
    threads = np.abs(np.sin(along * math.tau / 0.018 + across * 40.0))
    return mix(solid(count, colour("Gold")), solid(count, colour("GoldLight")), threads * 0.55)


def _streaks(pos, flow, scale=1.0, along=0.35, across=7.0, seed=0.0, octaves=3):
    flow = np.asarray(flow, dtype=np.float64)
    flow /= np.linalg.norm(flow)
    helper = np.array((1.0, 0.0, 0.0)) if abs(flow[0]) < 0.9 else np.array((0.0, 0.0, 1.0))
    first = np.cross(flow, helper)
    first /= np.linalg.norm(first)
    second = np.cross(flow, first)
    coords = np.stack([pos @ flow * along, pos @ first * across, pos @ second * across], axis=1)
    return fbm(coords, scale=scale, octaves=octaves, seed=seed)


PALETTE.update(DEFAULT_PALETTE)
