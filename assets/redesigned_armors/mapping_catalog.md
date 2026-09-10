# 裝甲美術商業化改造：1 對 1 映射目錄 (Armor Redesign Catalog)

> 本目錄記錄專案內所有裝甲從原本版權素材（Star Warfare / Call of Mini）轉移至全新商業化風格裝甲的 1 對 1 對應規格與資產檔案路徑。

## 1 對 1 裝甲映射總覽表

| ID | 原版名稱 (Original) | 來源體系 (Source) | 商業化改版名稱 (Redesigned) | 風格定位與幾何重塑 | 專屬資產目錄 (Asset Directory) |
|:--:|:-------------------|:-----------------|:---------------------------|:------------------|:-------------------------------|
| 00 | Viper | Star Warfare | **Apex Viper** | 流線型輕量刺客裝甲 | `assets/redesigned_armors/set_00_apex_viper/` |
| 01 | Fortune | Star Warfare | **Gilded Fortune** | 防暴護衛裝甲 | `assets/redesigned_armors/set_01_gilded_fortune/` |
| 02 | Tank | Star Warfare | **Iron Bulwark** | 超重型步兵裝甲 | `assets/redesigned_armors/set_02_iron_bulwark/` |
| 03 | Hydra | Star Warfare | **Hydra Corrosive** | 生化防護戰鬥服 | `assets/redesigned_armors/set_03_hydra_corrosive/` |
| 04 | Strike | Star Warfare | **Vanguard Strike** | 快速反應特種作戰甲 | `assets/redesigned_armors/set_04_vanguard_strike/` |
| 05 | Titan | Star Warfare | **Colossus Titan** | 荒地重裝攻堅甲 | `assets/redesigned_armors/set_05_colossus_titan/` |
| 06 | Thunder | Star Warfare | **Storm Thunder** | 高壓放電外骨骼 | `assets/redesigned_armors/set_06_storm_thunder/` |
| 07 | Atom | Star Warfare | **Quantum Atom** | 微型反應爐重甲 | `assets/redesigned_armors/set_07_quantum_atom/` |
| 08 | Pegasus | Star Warfare | **Aurora Pegasus** | 空降推進作戰服 | `assets/redesigned_armors/set_08_aurora_pegasus/` |
| 09 | Draco | Star Warfare | **Draconic Drake** | 侵略型前鋒重甲 | `assets/redesigned_armors/set_09_draconic_drake/` |
| 10 | Phoenix | Star Warfare | **Solar Phoenix** | 能量強化熱能甲 | `assets/redesigned_armors/set_10_solar_phoenix/` |
| 11 | Cygni | Star Warfare | **Cygni Sentinel** | 深空巡航突擊甲 | `assets/redesigned_armors/set_11_cygni_sentinel/` |
| 12 | Andromedae | Star Warfare | **Nebula Andromeda** | 先驅者能量護盾服 | `assets/redesigned_armors/set_12_nebula_andromeda/` |
| 13 | Perseus | Star Warfare | **Perseus Valiant** | 古代勇士幾何動力甲 | `assets/redesigned_armors/set_13_perseus_valiant/` |
| 14 | Chaos | Star Warfare | **Abyssal Chaos** | 隱密掠食者外裝 | `assets/redesigned_armors/set_14_abyssal_chaos/` |
| 15 | DEC.24 | Star Warfare | **Frost Winterguard** | 極地耐寒特戰服 | `assets/redesigned_armors/set_15_frost_dec24/` |
| 16 | Knight | Star Warfare | **Paladin Knight** | 儀仗重裝防禦甲 | `assets/redesigned_armors/set_16_paladin_knight/` |
| 17 | R.O.M.E | Star Warfare | **Centurion Rome** | 重裝方陣指揮甲 | `assets/redesigned_armors/set_17_centurion_rome/` |
| 18 | Black Hole | Star Warfare | **Singularity Vortex** | 引力扭曲防護服 | `assets/redesigned_armors/set_18_singularity_blackhole/` |
| 19 | X-Field | Star Warfare | **Vector X-Field** | 賽博矩陣外骨骼服 | `assets/redesigned_armors/set_19_vector_xfield/` |
| 20 | Wrath | Star Warfare | **Fury Wrath** | 近戰突擊狂戰甲 | `assets/redesigned_armors/set_20_fury_wrath/` |
| 21 | Assault Armor | Call of Mini | **Assault Enforcer** | 警備特勤突入甲 | `assets/redesigned_armors/set_21_assault_enforcer/` |
| 22 | Combat Suit | Call of Mini | **Tactical Operative** | 現代野戰作戰服 | `assets/redesigned_armors/set_22_tactical_operative/` |
| 23 | Drillmaster | Call of Mini | **Iron Drillmaster** | 基地防禦指揮裝甲 | `assets/redesigned_armors/set_23_drillmaster_iron/` |
| 24 | Heavy Battlesuit | Call of Mini | **Heavy Juggernaut** | 重度火力要塞重甲 | `assets/redesigned_armors/set_24_heavy_juggernaut/` |
| 25 | Mark-6 117R | Call of Mini | **Aegis-117 Orbital** | 軌道空降突擊傘兵甲 | `assets/redesigned_armors/set_25_aegis_117/` |
| 26 | Recon Suit | Call of Mini | **Recon Phantom** | 輕量高機動偵察服 | `assets/redesigned_armors/set_26_recon_shadow/` |
| 27 | Sanguine Chaos | Call of Mini | **Crimson Carnage** | 生物侵蝕變異戰甲 | `assets/redesigned_armors/set_27_crimson_carnage/` |
| 28 | Training Suit | Call of Mini | **Cadet Exosuit** | 初階動力輔助骨架 | `assets/redesigned_armors/set_28_cadet_exosuit/` |

## 資產目錄結構說明

```
assets/redesigned_armors/
├── mapping_catalog.json           # 完整機器可讀 JSON 對照表
├── mapping_catalog.md             # 人讀風格指南與規格說明
├── set_00_apex_viper/             # Set 00: Apex Viper
│   ├── textures/                  # 四部位高解析紋理 (head.png, body.png...)
│   └── materials/                 # Godot StandardMaterial3D (.tres)
├── ...
└── set_28_cadet_exosuit/          # Set 28: Cadet Exosuit
```
