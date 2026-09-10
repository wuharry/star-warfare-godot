import os
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = REPO_ROOT / "assets" / "redesigned_armors"

# 29 sets specifications
SET_DEFINITIONS = [
    # Star Warfare sets (00-20)
    {
        "id": 0, "orig_name": "Viper", "source": "Star Warfare",
        "name": "Apex Viper", "slug": "set_00_apex_viper",
        "role": "流線型輕量刺客裝甲",
        "primary": (32, 105, 58),     # 科技墨綠
        "secondary": (210, 160, 45),  # 琥珀金
        "accent": (60, 230, 130),     # 螢光綠導光
        "dark": (22, 28, 25),         # 碳素黑
        "pattern": "hex"
    },
    {
        "id": 1, "orig_name": "Fortune", "source": "Star Warfare",
        "name": "Gilded Fortune", "slug": "set_01_gilded_fortune",
        "role": "防暴護衛裝甲",
        "primary": (35, 38, 45),      # 啞光鍛鐵黑
        "secondary": (225, 185, 55),  # 鍛造純金
        "accent": (255, 230, 120),    # 閃耀金光
        "dark": (18, 19, 22),         # 深墨底裝
        "pattern": "stripe"
    },
    {
        "id": 2, "orig_name": "Tank", "source": "Star Warfare",
        "name": "Iron Bulwark", "slug": "set_02_iron_bulwark",
        "role": "超重型步兵裝甲",
        "primary": (75, 80, 88),      # 工業重鋼灰
        "secondary": (220, 170, 30),  # 警戒黃
        "accent": (255, 200, 50),     # 警戒發光燈
        "dark": (25, 26, 28),         # 鎢鋼深底
        "pattern": "hazard"
    },
    {
        "id": 3, "orig_name": "Hydra", "source": "Star Warfare",
        "name": "Hydra Corrosive", "slug": "set_03_hydra_corrosive",
        "role": "生化防護戰鬥服",
        "primary": (70, 35, 85),      # 曜石深紫
        "secondary": (40, 180, 90),   # 耐酸酸蝕綠
        "accent": (80, 255, 120),     # 毒液高光
        "dark": (26, 18, 30),         # 生化密封深色
        "pattern": "scales"
    },
    {
        "id": 4, "orig_name": "Strike", "source": "Star Warfare",
        "name": "Vanguard Strike", "slug": "set_04_vanguard_strike",
        "role": "快速反應特種作戰甲",
        "primary": (28, 65, 125),     # 深空海軍藍
        "secondary": (210, 220, 235), # 疾風亮白
        "accent": (70, 170, 255),     # 巡航推進藍光
        "dark": (18, 24, 38),         # 低反光消光底
        "pattern": "chevron"
    },
    {
        "id": 5, "orig_name": "Titan", "source": "Star Warfare",
        "name": "Colossus Titan", "slug": "set_05_colossus_titan",
        "role": "荒地重裝攻堅甲",
        "primary": (145, 125, 90),    # 荒漠卡其土黃
        "secondary": (60, 62, 65),    # 鑄造生鐵灰
        "accent": (230, 150, 40),     # 工業橙光
        "dark": (35, 30, 25),         # 泥砂密封底
        "pattern": "plate"
    },
    {
        "id": 6, "orig_name": "Thunder", "source": "Star Warfare",
        "name": "Storm Thunder", "slug": "set_06_storm_thunder",
        "role": "高壓放電外骨骼",
        "primary": (25, 85, 160),     # 電弧湛藍
        "secondary": (205, 215, 230), # 超導純銀白
        "accent": (100, 220, 255),    # 高頻電弧發光
        "dark": (16, 26, 42),         # 絕緣橡膠黑
        "pattern": "circuit"
    },
    {
        "id": 7, "orig_name": "Atom", "source": "Star Warfare",
        "name": "Quantum Atom", "slug": "set_07_quantum_atom",
        "role": "微型反應爐重甲",
        "primary": (205, 85, 25),     # 核子危險橙
        "secondary": (45, 48, 55),    # 散熱黑曜石
        "accent": (255, 170, 40),     # 聚變高熱發光
        "dark": (20, 20, 24),         # 防輻射鎢黑
        "pattern": "hazard"
    },
    {
        "id": 8, "orig_name": "Pegasus", "source": "Star Warfare",
        "name": "Aurora Pegasus", "slug": "set_08_aurora_pegasus",
        "role": "空降推進作戰服",
        "primary": (225, 232, 242),   # 珍珠雪白
        "secondary": (35, 155, 175),  # 幻彩極光青
        "accent": (70, 235, 255),     # 矢量噴口青藍
        "dark": (28, 35, 45),         # 航空複合底層
        "pattern": "aero"
    },
    {
        "id": 9, "orig_name": "Draco", "source": "Star Warfare",
        "name": "Draconic Drake", "slug": "set_09_draconic_drake",
        "role": "侵略型前鋒重甲",
        "primary": (145, 28, 28),     # 熔岩深紅
        "secondary": (42, 38, 40),    # 焦炭黑曜
        "accent": (255, 80, 40),      # 熔岩裂隙發光
        "dark": (22, 18, 20),         # 耐高溫內襯
        "pattern": "scales"
    },
    {
        "id": 10, "orig_name": "Phoenix", "source": "Star Warfare",
        "name": "Solar Phoenix", "slug": "set_10_solar_phoenix",
        "role": "能量強化熱能甲",
        "primary": (215, 105, 25),    # 耀斑金紅
        "secondary": (195, 160, 40),  # 熾熱烈金
        "accent": (255, 220, 70),     # 涅槃金焰
        "dark": (28, 20, 18),         # 餘燼炭黑
        "pattern": "chevron"
    },
    {
        "id": 11, "orig_name": "Cygni", "source": "Star Warfare",
        "name": "Cygni Sentinel", "slug": "set_11_cygni_sentinel",
        "role": "深空巡航突擊甲",
        "primary": (30, 75, 140),     # 星際靛青
        "secondary": (180, 195, 210), # 航空鈦銀
        "accent": (60, 190, 255),     # 姿態傳感光
        "dark": (16, 22, 35),         # 隔熱真空底
        "pattern": "hex"
    },
    {
        "id": 12, "orig_name": "Andromedae", "source": "Star Warfare",
        "name": "Nebula Andromeda", "slug": "set_12_nebula_andromeda",
        "role": "先驅者能量護盾服",
        "primary": (105, 45, 130),    # 星雲深紫
        "secondary": (190, 60, 140),  # 等離子品紅
        "accent": (240, 120, 220),    # 護盾過載流光
        "dark": (25, 16, 32),         # 超維矩陣黑
        "pattern": "circuit"
    },
    {
        "id": 13, "orig_name": "Perseus", "source": "Star Warfare",
        "name": "Perseus Valiant", "slug": "set_13_perseus_valiant",
        "role": "古代勇士幾何動力甲",
        "primary": (155, 115, 65),    # 復古青銅金
        "secondary": (75, 80, 85),    # 戰術骨架鋼
        "accent": (235, 180, 95),     # 鍛造亮邊
        "dark": (28, 25, 22),         # 鍛鐵皮革黑
        "pattern": "plate"
    },
    {
        "id": 14, "orig_name": "Chaos", "source": "Star Warfare",
        "name": "Abyssal Chaos", "slug": "set_14_abyssal_chaos",
        "role": "隱密掠食者外裝",
        "primary": (35, 36, 42),      # 虛空暗灰
        "secondary": (160, 25, 40),   # 狂暴緋紅
        "accent": (255, 45, 65),      # 裂隙能量紅
        "dark": (14, 15, 18),         # 深淵虛空純黑
        "pattern": "scales"
    },
    {
        "id": 15, "orig_name": "DEC.24", "source": "Star Warfare",
        "name": "Frost Winterguard", "slug": "set_15_frost_dec24",
        "role": "極地耐寒特戰服",
        "primary": (210, 225, 235),   # 寒帶雪白
        "secondary": (45, 125, 175),  # 冰川冰藍
        "accent": (130, 225, 255),    # 低溫超導青光
        "dark": (20, 32, 42),         # 密閉防凍橡膠
        "pattern": "camo"
    },
    {
        "id": 16, "orig_name": "Knight", "source": "Star Warfare",
        "name": "Paladin Knight", "slug": "set_16_paladin_knight",
        "role": "儀仗重裝防禦甲",
        "primary": (195, 202, 212),   # 鏡面拋光鋼銀
        "secondary": (35, 60, 140),   # 皇家群青藍
        "accent": (235, 210, 95),     # 騎士金徽飾
        "dark": (22, 24, 30),         # 鎖子甲黑鐵
        "pattern": "plate"
    },
    {
        "id": 17, "orig_name": "R.O.M.E", "source": "Star Warfare",
        "name": "Centurion Rome", "slug": "set_17_centurion_rome",
        "role": "重裝方陣指揮甲",
        "primary": (140, 25, 30),     # 帝國鮮血紅
        "secondary": (175, 135, 55),  # 仿古鍛銅金
        "accent": (235, 190, 80),     # 羅馬鷹標亮金
        "dark": (28, 20, 20),         # 軍團重革深色
        "pattern": "plate"
    },
    {
        "id": 18, "orig_name": "Black Hole", "source": "Star Warfare",
        "name": "Singularity Vortex", "slug": "set_18_singularity_blackhole",
        "role": "引力扭曲防護服",
        "primary": (20, 18, 26),      # 暗物質純黑
        "secondary": (85, 35, 125),   # 事件視界深紫
        "accent": (160, 70, 255),     # 引力波發光環
        "dark": (10, 8, 14),          # 奇點極黑
        "pattern": "circuit"
    },
    {
        "id": 19, "orig_name": "X-Field", "source": "Star Warfare",
        "name": "Vector X-Field", "slug": "set_19_vector_xfield",
        "role": "賽博矩陣外骨骼服",
        "primary": (28, 30, 35),      # 科技啞黑
        "secondary": (30, 160, 95),   # 脈衝矩陣綠
        "accent": (50, 255, 140),     # 向量節點高光
        "dark": (14, 16, 18),         # 電路基底暗黑
        "pattern": "circuit"
    },
    {
        "id": 20, "orig_name": "Wrath", "source": "Star Warfare",
        "name": "Fury Wrath", "slug": "set_20_fury_wrath",
        "role": "近戰突擊狂戰甲",
        "primary": (155, 30, 25),     # 硫磺焰紅
        "secondary": (195, 185, 170), # 骨白強化角質
        "accent": (255, 90, 40),      # 狂暴怒火高光
        "dark": (25, 16, 16),         # 焦黑硬化碳鋼
        "pattern": "hazard"
    },
    # Call of Mini sets (21-28)
    {
        "id": 21, "orig_name": "Assault Armor", "source": "Call of Mini",
        "name": "Assault Enforcer", "slug": "set_21_assault_enforcer",
        "role": "警備特勤突入甲",
        "primary": (45, 48, 56),      # 戰術暗金屬黑
        "secondary": (225, 110, 25),  # 反應裝甲橘
        "accent": (255, 165, 50),     # 突入警示燈
        "dark": (20, 22, 26),         # 特勤內襯
        "pattern": "hex"
    },
    {
        "id": 22, "orig_name": "Combat Suit", "source": "Call of Mini",
        "name": "Tactical Operative", "slug": "set_22_tactical_operative",
        "role": "現代野戰作戰服",
        "primary": (62, 78, 55),      # 叢林暗橄欖綠
        "secondary": (38, 42, 45),    # 啞光特警黑
        "accent": (145, 185, 110),    # 夜視微光淡綠
        "dark": (22, 26, 20),         # 迷彩底色
        "pattern": "camo"
    },
    {
        "id": 23, "orig_name": "Drillmaster", "source": "Call of Mini",
        "name": "Iron Drillmaster", "slug": "set_23_drillmaster_iron",
        "role": "基地防禦指揮裝甲",
        "primary": (52, 56, 62),      # 警衛鐵灰
        "secondary": (225, 180, 25),  # 亮黃反光帶
        "accent": (255, 220, 60),     # 指揮反光高標
        "dark": (24, 25, 28),         # 戰術常服黑
        "pattern": "hazard"
    },
    {
        "id": 24, "orig_name": "Heavy Battlesuit", "source": "Call of Mini",
        "name": "Heavy Juggernaut", "slug": "set_24_heavy_juggernaut",
        "role": "重度火力要塞重甲",
        "primary": (38, 40, 45),      # 鎢鋼消光黑
        "secondary": (210, 145, 25),  # 防撞警示橙黃
        "accent": (255, 190, 50),     # 液壓排氣口亮光
        "dark": (18, 19, 22),         # 超厚重鉛襯
        "pattern": "plate"
    },
    {
        "id": 25, "orig_name": "Mark-6 117R", "source": "Call of Mini",
        "name": "Aegis-117 Orbital", "slug": "set_25_aegis_117",
        "role": "軌道空降突擊傘兵甲",
        "primary": (26, 52, 108),     # 深海軍鈷藍 (徹底割席士官長綠)
        "secondary": (215, 222, 235), # 鍛造白金飾邊
        "accent": (65, 160, 255),     # 宙斯盾目鏡深藍光
        "dark": (16, 22, 38),         # 軌道高抗壓內層
        "pattern": "hex"
    },
    {
        "id": 26, "orig_name": "Recon Suit", "source": "Call of Mini",
        "name": "Recon Phantom", "slug": "set_26_recon_shadow",
        "role": "輕量高機動偵察服",
        "primary": (88, 92, 98),      # 匿蹤迷霧冷灰
        "secondary": (32, 75, 115),   # 幽暗深邃青
        "accent": (80, 205, 230),     # 匿蹤傳感弱光
        "dark": (26, 28, 32),         # 吸波塗料底層
        "pattern": "aero"
    },
    {
        "id": 27, "orig_name": "Sanguine Chaos", "source": "Call of Mini",
        "name": "Crimson Carnage", "slug": "set_27_crimson_carnage",
        "role": "生物侵蝕變異戰甲",
        "primary": (145, 22, 32),     # 惡魔猩紅
        "secondary": (32, 30, 36),    # 脊椎黑鋼
        "accent": (255, 60, 75),      # 猩紅外骨骼流光
        "dark": (18, 14, 18),         # 變異肌肉深底
        "pattern": "scales"
    },
    {
        "id": 28, "orig_name": "Training Suit", "source": "Call of Mini",
        "name": "Cadet Exosuit", "slug": "set_28_cadet_exosuit",
        "role": "初階動力輔助骨架",
        "primary": (220, 224, 230),   # 測試防摔白
        "secondary": (225, 95, 25),   # 醒目警戒橘
        "accent": (255, 140, 45),     # 學院通訊信號燈
        "dark": (35, 38, 42),         # 彈性纖維防磨底
        "pattern": "stripe"
    }
]

def bleed_edges(img: Image.Image, iterations: int = 2) -> Image.Image:
    result = img.copy()
    for _ in range(iterations):
        alpha = result.split()[-1]
        dilated_alpha = alpha.filter(ImageFilter.MaxFilter(3))
        rgb = result.convert("RGB").filter(ImageFilter.GaussianBlur(1))
        bg = rgb.convert("RGBA")
        bg.putalpha(dilated_alpha)
        result = Image.alpha_composite(bg, result)
        result.putalpha(alpha)
    return result

def transform_texture(src_img: Image.Image, set_def: dict, part_name: str) -> Image.Image:
    src = src_img.convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w, h))
    
    src_pixels = src.load()
    out_pixels = out.load()
    
    pr, pg, pb = set_def["primary"]
    sr, sg, sb = set_def["secondary"]
    ar, ag, ab = set_def["accent"]
    dr, dg, db = set_def["dark"]
    pat = set_def.get("pattern", "hex")
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = src_pixels[x, y]
            if a == 0:
                out_pixels[x, y] = (0, 0, 0, 0)
                continue
            
            # Perceived luminance
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            
            # Procedural surface pattern modulation
            pat_val = 0.0
            if pat == "hex":
                hx = (x // 6) % 2
                hy = (y // 6) % 2
                pat_val = 0.06 if (hx == hy) else -0.06
            elif pat == "hazard":
                pat_val = 0.10 if ((x + y) // 8 % 2 == 0) else -0.08
            elif pat == "scales":
                pat_val = 0.08 * math.sin(x * 0.4) * math.cos(y * 0.4)
            elif pat == "circuit":
                pat_val = 0.12 if (x % 16 == 0 or y % 16 == 0) else -0.03
            elif pat == "stripe":
                pat_val = 0.08 if (y // 8 % 2 == 0) else -0.05
            elif pat == "aero":
                pat_val = 0.07 * math.sin(x * 0.15)
            elif pat == "camo":
                pat_val = 0.09 * math.sin(x * 0.08 + y * 0.05) * math.cos(x * 0.04 - y * 0.09)
            else: # plate
                pat_val = -0.08 if (x % 24 < 2 or y % 24 < 2) else 0.04
            
            # Color stratification
            if lum < 0.28:
                t = lum / 0.28
                fr = int(max(0, min(255, dr * (0.6 + 0.5 * t) + pat_val * 30)))
                fg = int(max(0, min(255, dg * (0.6 + 0.5 * t) + pat_val * 30)))
                fb = int(max(0, min(255, db * (0.6 + 0.5 * t) + pat_val * 30)))
            elif lum < 0.72:
                t = (lum - 0.28) / 0.44
                curve = math.pow(t, 1.15) + pat_val
                fr = int(max(0, min(255, pr * 0.5 + pr * curve * 0.75)))
                fg = int(max(0, min(255, pg * 0.5 + pg * curve * 0.75)))
                fb = int(max(0, min(255, pb * 0.5 + pb * curve * 0.75)))
            else:
                t = (lum - 0.72) / 0.28
                fr = int(max(0, min(255, sr * (1.0 - t) + ar * t + pat_val * 40)))
                fg = int(max(0, min(255, sg * (1.0 - t) + ag * t + pat_val * 40)))
                fb = int(max(0, min(255, sb * (1.0 - t) + ab * t + pat_val * 40)))
                
                if lum > 0.88:
                    st = (lum - 0.88) / 0.12
                    fr = int(min(255, fr * (1 - st) + 245 * st))
                    fg = int(min(255, fg * (1 - st) + 245 * st))
                    fb = int(min(255, fb * (1 - st) + 255 * st))
            
            out_pixels[x, y] = (fr, fg, fb, a)
            
    return bleed_edges(out)

def create_godot_material(texture_rel_path: str, set_def: dict) -> str:
    ar, ag, ab = set_def["accent"]
    emission_color = f"{ar/255.0:.3f}, {ag/255.0:.3f}, {ab/255.0:.3f}, 1"
    
    content = f"""[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://{texture_rel_path}" id="1_tex"]

[resource]
resource_name = "{set_def['slug']}_mat"
cull_mode = 2
albedo_texture = ExtResource("1_tex")
metallic = 0.55
roughness = 0.42
emission_enabled = true
emission = Color({emission_color})
emission_energy_multiplier = 0.35
texture_filter = 5
"""
    return content

def get_starwarfare_texture_map():
    with open(REPO_ROOT / "assets/models/player/animated/player.gltf", "r") as f:
        gltf = json.load(f)
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    images = gltf.get("images", [])
    textures = gltf.get("textures", [])
    
    mapping = {f"{i:02d}": {"head": [], "body": [], "arms": [], "legs": []} for i in range(21)}
    for node in nodes:
        name = node.get("name", "")
        if "Armor" in name and "mesh" in node:
            parts = name.split("_")
            part_type = parts[0].replace("Armor", "").lower()
            if part_type == "hand": pk = "arms"
            elif part_type == "foot": pk = "legs"
            else: pk = part_type
            
            set_id = parts[1]
            mesh = meshes[node["mesh"]]
            for p in mesh.get("primitives", []):
                mi = p.get("material")
                if mi is not None and mi < len(materials):
                    mat = materials[mi]
                    bct = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
                    if "index" in bct:
                        img_idx = textures[bct["index"]]["source"]
                        uri = images[img_idx]["uri"]
                        if set_id in mapping and pk in mapping[set_id]:
                            mapping[set_id][pk].append(uri)
    return mapping

def run():
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    sw_map = get_starwarfare_texture_map()
    
    catalog_summary = []
    
    print(f"Starting asset generation for {len(SET_DEFINITIONS)} armor sets...")
    
    for sdef in SET_DEFINITIONS:
        set_id = sdef["id"]
        slug = sdef["slug"]
        set_dir = OUTPUT_ROOT / slug
        tex_dir = set_dir / "textures"
        mat_dir = set_dir / "materials"
        tex_dir.mkdir(parents=True, exist_ok=True)
        mat_dir.mkdir(parents=True, exist_ok=True)
        
        parts_data = {}
        
        if set_id < 21: # Star Warfare
            key = f"{set_id:02d}"
            set_textures = sw_map.get(key, {})
            for part_key in ["head", "body", "arms", "legs"]:
                tex_uris = set_textures.get(part_key, [])
                if not tex_uris:
                    continue
                # For each texture in this part (e.g. body may have body + shoulder/jian)
                for idx, uri in enumerate(tex_uris):
                    src_file = REPO_ROOT / "assets/models/player/animated" / uri
                    if not src_file.exists():
                        continue
                    part_file_name = f"{part_key}.png" if idx == 0 else f"{part_key}_accent_{idx}.png"
                    out_tex_path = tex_dir / part_file_name
                    
                    src_img = Image.open(src_file)
                    redesigned_img = transform_texture(src_img, sdef, part_key)
                    redesigned_img.save(out_tex_path)
                    
                    # Create Godot material
                    rel_tex_path = f"assets/redesigned_armors/{slug}/textures/{part_file_name}"
                    mat_content = create_godot_material(rel_tex_path, sdef)
                    mat_file_name = part_file_name.replace(".png", ".tres")
                    (mat_dir / mat_file_name).write_text(mat_content, encoding="utf-8")
                    
                parts_data[part_key] = {
                    "texture": f"assets/redesigned_armors/{slug}/textures/{part_key}.png",
                    "material": f"assets/redesigned_armors/{slug}/materials/{part_key}.tres"
                }
        else: # Call of Mini (21-28)
            orig_set_name = sdef["orig_name"]
            com_dir = REPO_ROOT / "assets/callOfMini/enhanced" / orig_set_name
            
            # Texture files for Call of Mini
            files_to_process = []
            for png in com_dir.glob("*.png"):
                if "source" in str(png).lower() or ".import" in png.name:
                    continue
                files_to_process.append(png)
                
            for png in files_to_process:
                src_img = Image.open(png)
                part_tag = png.stem
                redesigned_img = transform_texture(src_img, sdef, part_tag)
                out_tex_path = tex_dir / png.name
                redesigned_img.save(out_tex_path)
                
                rel_tex_path = f"assets/redesigned_armors/{slug}/textures/{png.name}"
                mat_content = create_godot_material(rel_tex_path, sdef)
                mat_file_name = png.stem + ".tres"
                (mat_dir / mat_file_name).write_text(mat_content, encoding="utf-8")
                
            parts_data["all_parts"] = {
                "texture_dir": f"assets/redesigned_armors/{slug}/textures/",
                "material_dir": f"assets/redesigned_armors/{slug}/materials/"
            }
            
        catalog_summary.append({
            "id": set_id,
            "original_name": sdef["orig_name"],
            "original_source": sdef["source"],
            "redesigned_name": sdef["name"],
            "folder": f"assets/redesigned_armors/{slug}/",
            "role": sdef["role"],
            "pattern_style": sdef["pattern"],
            "palette": {
                "primary": list(sdef["primary"]),
                "secondary": list(sdef["secondary"]),
                "accent": list(sdef["accent"]),
                "dark": list(sdef["dark"])
            },
            "parts": parts_data
        })
        print(f"Generated Set {set_id:02d}: {sdef['name']} -> assets/redesigned_armors/{slug}/")
        
    # Write JSON catalog
    json_path = OUTPUT_ROOT / "mapping_catalog.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(catalog_summary, f, ensure_ascii=False, indent=2)
    print(f"Mapping catalog saved to: {json_path}")
    
    # Write Markdown catalog
    md_path = OUTPUT_ROOT / "mapping_catalog.md"
    md_content = generate_markdown_catalog(catalog_summary)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"Markdown catalog saved to: {md_path}")
    print("All 29 armor sets redesigned and mapped successfully!")

def generate_markdown_catalog(catalog):
    lines = [
        "# 裝甲美術商業化改造：1 對 1 映射目錄 (Armor Redesign Catalog)",
        "",
        "> 本目錄記錄專案內所有裝甲從原本版權素材（Star Warfare / Call of Mini）轉移至全新商業化風格裝甲的 1 對 1 對應規格與資產檔案路徑。",
        "",
        "## 1 對 1 裝甲映射總覽表",
        "",
        "| ID | 原版名稱 (Original) | 來源體系 (Source) | 商業化改版名稱 (Redesigned) | 風格定位與幾何重塑 | 專屬資產目錄 (Asset Directory) |",
        "|:--:|:-------------------|:-----------------|:---------------------------|:------------------|:-------------------------------|"
    ]
    for item in catalog:
        lines.append(
            f"| {item['id']:02d} | {item['original_name']} | {item['original_source']} | **{item['redesigned_name']}** | {item['role']} | `{item['folder']}` |"
        )
    lines.append("")
    lines.append("## 資產目錄結構說明")
    lines.append("")
    lines.append("```")
    lines.append("assets/redesigned_armors/")
    lines.append("├── mapping_catalog.json           # 完整機器可讀 JSON 對照表")
    lines.append("├── mapping_catalog.md             # 人讀風格指南與規格說明")
    lines.append("├── set_00_apex_viper/             # Set 00: Apex Viper")
    lines.append("│   ├── textures/                  # 四部位高解析紋理 (head.png, body.png...)")
    lines.append("│   └── materials/                 # Godot StandardMaterial3D (.tres)")
    lines.append("├── ...")
    lines.append("└── set_28_cadet_exosuit/          # Set 28: Cadet Exosuit")
    lines.append("```")
    lines.append("")
    return "\n".join(lines)

if __name__ == "__main__":
    run()
