"""Real Minecraft / mod block textures for the Factory v2 viewer.

Reads textures from local sparse clones (not committed: the textures belong to Mojang and the mod authors)
and returns {type_key: {top, side, front: data-URI PNG 16x16}}. Types with no entry keep the drawn texture.

Roots (clone with git sparse-checkout, see docs in factoryv2.py):
  V  misode/mcmeta 1.21.1-assets            assets/minecraft/textures/block
  C  Creators-of-Create/Create mc1.21.1/dev src/main/resources/assets/create/textures/block
  E  AppliedEnergistics/Applied-Energistics-2 1.21.1  .../assets/ae2/textures
  X  GlodBlock/ExtendedAE                   .../assets/extendedae/textures/block
  M  mekanism/Mekanism 1.21.x               .../assets/mekanism/textures/block
  K  cc-tweaked/CC-Tweaked mc-1.21.x        .../assets/computercraft/textures/block
"""
import base64, io, os
from PIL import Image, ImageChops

T = "/home/claude/tex/"
ROOTS = {
    "V": T + "van/assets/minecraft/textures/block/",
    "C": T + "create/src/main/resources/assets/create/textures/block/",
    "E": T + "ae2/src/main/resources/assets/ae2/textures/",
    "X": "/home/claude/glodblock/extendedae/src/main/resources/assets/extendedae/textures/block/",
    "M": T + "mek/src/main/resources/assets/mekanism/textures/block/",
    "K": T + "cct/projects/common/src/main/resources/assets/computercraft/textures/block/",
}
Q = {"tl": (0, 0, .5, .5), "tr": (.5, 0, 1, .5), "bl": (0, .5, .5, 1), "br": (.5, .5, 1, 1)}


def load(spec):
    """spec: 'R:path' | ('R:path', crop|None, tint|None) | [layer, layer...] composited."""
    if isinstance(spec, list):
        out = None
        for s in spec:
            im = load(s)
            out = im if out is None else Image.alpha_composite(out, im)
        return out
    if isinstance(spec, str):
        spec = (spec, None, None)
    path, crop, tint = (list(spec) + [None, None])[:3]
    r, p = path.split(":", 1)
    im = Image.open(ROOTS[r] + p + ".png").convert("RGBA")
    if im.height > im.width and not crop:           # animation strip: first frame
        im = im.crop((0, 0, im.width, im.width))
    if crop:
        if isinstance(crop, str):
            crop = Q[crop]
        w, h = im.width, im.height
        im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
    if im.size != (16, 16):
        im = im.resize((16, 16), Image.BOX if im.width > 16 else Image.NEAREST)
    if tint:
        n = int(tint[1:], 16)
        col = Image.new("RGBA", im.size, (n >> 16 & 255, n >> 8 & 255, n & 255, 255))
        a = im.getchannel("A")
        im = ImageChops.multiply(im, col)
        im.putalpha(a)
    return im


def uri(im):
    b = io.BytesIO(); im.save(b, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()


def all3(s): return dict(top=s, side=s, front=s)
def ts(top, side, front=None): return dict(top=top, side=side, front=front or side)


MEK = lambda d, side="left": ts("M:%s/top" % d, "M:%s/%s" % (d, side), "M:%s/front_active" % d if False else "M:%s/front" % d)
STEEL = "M:steel_casing"
TERM = lambda t: ts("E:part/monitor_sides", "E:part/monitor_sides", ["E:part/monitor_back", ("E:part/%s_terminal_medium" % t, None, "#3a7bd0"), ("E:part/%s_terminal_bright" % t, None, "#9fe8ff")])
COPPER_PIPE = ("C:pipes", "tl")

MAP = {
    # vanilla
    "pd": all3("V:polished_deepslate"), "dt": all3("V:deepslate_tiles"), "path": all3("V:deepslate_tiles"),
    "cap": all3("V:deepslate_tiles"), "db": all3("V:deepslate_bricks"), "sb": all3("V:stone_bricks"),
    "cob": all3("V:cobblestone"), "gl": all3("V:glass"), "sk_sky": all3("V:glass"),
    "iglass": all3("V:gray_stained_glass"), "sk_win": all3("V:gray_stained_glass"),
    "sk_wlit": all3(["V:gray_stained_glass", ("V:glowstone", None, "#ffd27a")]),
    "gfloor": all3("V:tinted_glass"), "sk_pod": all3("V:tinted_glass"),
    "grass": ts(("V:grass_block_top", None, "#79c05a"), ["V:grass_block_side", ("V:grass_block_side_overlay", None, "#79c05a")]),
    "deck": all3("V:gray_concrete"), "sk_road": all3("V:gray_concrete"), "sk_roof": all3("V:gray_concrete"), "sk_grey": all3("V:gray_concrete"),
    "iwall": all3("V:light_gray_concrete"), "sk_conc": all3("V:light_gray_concrete"), "sk_pil": all3("V:light_gray_concrete"),
    "redcol": all3("V:red_concrete"), "sk_red": all3("V:red_concrete"),
    "sk_white": all3("V:white_concrete"), "sk_line": all3("V:white_concrete"),
    "sk_band": ts("V:smooth_stone", "V:smooth_stone_slab_side"), "sk_pave": all3("V:smooth_stone"),
    "sk_hedge": all3("V:azalea_leaves"), "sk_leaf": all3(("V:oak_leaves", None, "#59ae30")),
    "sk_moss": all3("V:moss_block"), "sk_log": ts("V:oak_log_top", "V:oak_log"),
    "sk_core": all3("V:polished_deepslate"),
    "lava": all3("V:lava_still"), "water": all3(("V:water_still", None, "#3f76e4")),
    "lamp": all3("V:lantern"), "hlamp": all3("V:lantern"), "sk_lamp": all3("V:lantern"),
    "baylamp": all3("V:copper_bulb_lit"), "cyan": all3("V:waxed_copper_bulb_lit" if os.path.exists(ROOTS["V"] + "waxed_copper_bulb_lit.png") else "V:copper_bulb_lit"),
    "furn": ts("V:furnace_top", "V:furnace_side", "V:furnace_front_on"),
    "cauld": ts("V:cauldron_top", "V:cauldron_side"), "ore": all3("V:raw_iron_block"),
    "rail": all3("V:iron_bars"), "sk_bars": all3("V:iron_bars"), "hook": all3("V:chain"),
    "chain": all3("V:chain"), "sk_chain": all3("V:chain"),
    # Create
    "belt": ts("C:belt", ("C:belt/andesite_belt_casing", "tl")),
    "bigcog": all3(("C:large_cogwheel", "tl")),
    "basin": ts(("C:basin", "tl"), ("C:basin", "tr")),
    "board": ts("C:flap_display_top", "C:flap_display_side", "C:flap_display_front"),
    "boiler": ts("C:fluid_tank_top", "C:fluid_tank"),
    "burner": ts("C:blaze_active" if os.path.exists(ROOTS["C"] + "blaze_active.png") else ("C:blaze_heater_brazier", "br"), ("C:blaze_heater_brazier", "br")),
    "catwalk": all3(("C:girder", "tl")), "girder": all3(("C:girder", "tl")),
    "chainpost": ts("C:andesite_casing", "C:andesite_casing"), "sk_chainpost": ts("C:andesite_casing", "C:andesite_casing"),
    "chute": ts(("C:chute", "tr"), ("C:chute", "tl")),
    "crafter": ts("C:brass_casing", "C:brass_casing", "C:crafter_side"),
    "deployer": ts("C:andesite_casing", "C:andesite_casing", "C:deployer"),
    "flue": all3(COPPER_PIPE), "lavapipe": all3(COPPER_PIPE), "waterpipe": all3("C:glass_fluid_pipe"),
    "frogport": ts("C:andesite_casing", ("C:packager_frame", "tl")),
    "gate": ts("C:industrial_iron_block_top", "C:industrial_iron_block"), "iron": ts("C:industrial_iron_block_top", "C:industrial_iron_block"),
    "shelf": ts("C:industrial_iron_block_top", "C:industrial_iron_block"),
    "gateglass": all3("C:palettes/framed_glass"),
    "gcar": ts("C:andesite_casing", "C:andesite_casing", "C:gantry_shaft_powered"),
    "gshaft": all3("C:gantry_shaft"), "shaft": all3("C:axis"),
    "mixer": ts("C:andesite_casing", "C:mixer_base_side"),
    "press": ts("C:mechanical_press_top", "C:mechanical_press_side"),
    "packager": ts(("C:packager_frame", "tl"), ("C:packager_horizontal_powered", "tl")),
    "requester": ts(("C:redstone_requester", "tl"), ("C:redstone_requester", "br")),
    "sengine": ts(("C:engine", "bl"), ("C:engine", "bl")),
    "ticker": ts(("C:stock_ticker", "tr"), ("C:stock_ticker", "bl"), ("C:stock_ticker", "tl")),
    "tunnel": ts(("C:tunnel/brass_tunnel_top", None), "C:brass_casing"),
    "pkg": ts("C:cardboard_block_top", "C:cardboard_block_side", "C:cardboard_block_front"),
    "sk_pkg": ts("C:cardboard_block_top", "C:cardboard_block_side", "C:cardboard_block_front"),
    "motor": ts("C:copper_casing", "C:copper_casing"),
    # AE2
    "ctrl": all3("E:block/controller_powered"),
    "cpu_a": all3(["E:block/crafting/accelerator", ("E:block/crafting/accelerator_light", None, "#7df9ff")]),
    "cpu_m": ts("E:block/crafting/unit", "E:block/crafting/unit", ["E:block/crafting/monitor", ("E:block/crafting/monitor_light_medium", None, "#7df9ff")]),
    "cpu_s": all3(["E:block/crafting/64k_storage", ("E:block/crafting/64k_storage_light", None, "#7df9ff")]),
    "dcell": all3("E:block/dense_energy_cell_4"),
    "iface": all3("E:block/interface"), "fuel": all3("E:block/interface"),
    "prov": all3("E:block/pattern_provider"), "insc": all3("E:block/inscriber"),
    "chg": all3("E:block/charger"), "cond": all3("E:block/condenser"),
    "accel": ts("E:block/growth_accelerator_top_on", "E:block/growth_accelerator_side_on"),
    "qglass": all3("E:block/glass/quartz_glass_a"), "sky": all3("E:block/sky_stone_block"),
    "bud": all3("E:block/flawed_budding_quartz"), "clus": all3("E:block/quartz_cluster"),
    "term_a": TERM("pattern_access"), "term_c": TERM("crafting"), "term_p": TERM("pattern_encoding"),
    "plane": all3("E:part/annihilation_plane"), "feed": all3("E:part/export_bus"),
    "wap": all3("E:part/monitor_sides"),
    # ExtendedAE
    "exprov": all3("X:ex_pattern_provider"), "iface2": all3("X:ex_interface"),
    "exdrive": ts("X:extended_drive/ex_drive_top", "X:extended_drive/ex_drive_side", "E:block/drive/drive_front"),
    "exinsc": all3("X:extended_inscriber/base"), "exchg": ts("X:extended_charger/base", "X:extended_charger/ex_charger_side", "X:extended_charger/ex_charger"),
    "mxf": all3("X:assembler_matrix/frame_block_on"), "mxc": all3("X:assembler_matrix/crafter_core"),
    "mxp": all3("X:assembler_matrix/pattern_core"), "mxs": all3("X:assembler_matrix/speed_core"),
    "cryasm": ts("X:crystal_assembler/top", "X:crystal_assembler/on"),
    "caner": all3("X:caner/base"), "cutter": all3("X:circuit_cutter/frame"), "fixer": all3("X:crystal_fixer/base"),
    "wcon": all3("X:wireless_connector/wireless_connect_fluix"),
    # Mekanism
    "enrich": MEK("enrichment_chamber"), "smelt": MEK("energized_smelter", "side"), "crush": MEK("crusher", "side"),
    "comb": MEK("combiner"), "inject": MEK("chemical_injection_chamber"), "purif": MEK("purification_chamber"),
    "ocomp": MEK("osmium_compressor"),
    "inf": all3(STEEL), "cinf": all3(STEEL), "cryst": all3(STEEL), "dissol": all3(STEEL), "oxid": all3(STEEL),
    "wash": all3(STEEL), "sep": all3(STEEL), "prc": all3(STEEL), "rotary": all3(STEEL), "react": all3(STEEL),
    "ctank": all3(STEEL), "qe": all3(STEEL), "evap": all3("M:thermal_evaporation_block"),
    # CC:Tweaked
    "console": ts("K:computer_advanced_top", "K:computer_advanced_side", "K:computer_advanced_front"),
    "pc": ts("K:computer_normal_top", "K:computer_normal_side", "K:computer_normal_front"),
    "monitor": ts("K:monitor_advanced_0", "K:monitor_advanced_0", "K:monitor_advanced_15"),
    "drone": ts("K:turtle_normal_top", "K:turtle_normal_left", "K:turtle_normal_front"),
    "guard": ts("K:turtle_advanced_top", "K:turtle_advanced_left", "K:turtle_advanced_front"),
    "speaker": ts("K:speaker_top", "K:speaker_side", "K:speaker_front"),
    "bridge": all3(STEEL),
}


def build(keys=None):
    out, bad = {}, []
    for k, faces in MAP.items():
        if keys is not None and k not in keys:
            continue
        try:
            out[k] = {f: uri(load(s)) for f, s in faces.items()}
        except Exception as e:
            bad.append((k, str(e)[:120]))
    return out, bad


if __name__ == "__main__":
    o, bad = build()
    print(len(o), "textured;", len(bad), "missing")
    for b in bad: print(" ", *b)
    print(sum(len(v) for f in o.values() for v in f.values()) // 1024, "KB")
