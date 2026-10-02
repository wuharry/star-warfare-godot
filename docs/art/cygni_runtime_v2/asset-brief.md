# Cygni：遊戲素材示範 v2

ASSET      CH_Cygni / ID 11 / C-12；objective：四件可換裝的新設計示範，保留原遊戲骨架與掛點。
CATEGORY   character / armored biped / modular armor。
VIEWS      原 Cygni 正、側、背為 Godot orthographic 640×720、相機中心 (0,1.04,0)、size=2.35；新概念為 perspective，正側背設計圖不是尺寸藍圖。新生成三視圖只補充造型，不替代原骨架比例。
SCALE      原始全套 bounds 高 1.9802 Godot units；沿用現有單位，原最低點約 0.02066，不改角色碰撞／腳底基準。Blender 展示轉為 Z-up/-Y forward，輸出時映回原座標。
PROPORTIONS

| 項目 | 來源與目標 |
| --- | --- |
| 身體高度／關節／28 bone rests | 原 player.gltf；保持數據，不重做成人身材 |
| 原身甲寬 | 1.26469；新肩翼保持同一包絡，尖端取捨允許 ±5% |
| 原手部包絡寬／高 | 1.2434 / 0.5257；前臂縮窄不超過 2% |
| 原腿部包絡寬／高 | 0.83094 / 0.48402；靴底保留 |
| 原頭部包絡寬 | 0.68324（含側翼）；新側翼最大約 0.68 |
| 新頭殼寬 | 約 0.48–0.49；依原主殼 0.4606 與新較圓頭盔形状適配，屬設計推定 |
| 新頭盔頂 | 1.9784；依原頭頂保持角色整體高度 |
| 新頭盔下緣 | 約 1.33；短下巴取代原 1.1964 長護頷，屬有意改動 |
| 新面罩橫帶寬／中央條寬 | 約 0.416 / 0.11；依所選概念的 T 結構轉換 |
| 新面罩前緣 | 約 -0.385；從原 -0.4447 縮短前伸，深度推定，需側視驗證 |
| 膝／肘／髖位置 | 完全沿用原 cage 與原 bone rests，不由生圖猜測 |

PARTS      Head：重建連接式盔殼、內收頰甲、T 面罩、短下巴、雙短側翼，主要 rigid head bind，頸封跟 neck/head。Body：原 cage 是短身與關節基底，替換胸前 V 分片／頸肩層次，改雙翼為短單翼；Arm：原手掌與前臂骨架基底、護臂微調；Leg：保留原腳底與膝位、收斂外張翼。四件分開，全部同一 skeleton。
SILHOUETTE 金 T、分層眉甲、斜收頰甲／短下巴、頭肩短翼、白甲／深綠身體分區。
MATERIALS  白灰 painted armor、深綠 secondary shell、煤黑 soft joints、少量銅橙 inserts、金色 opaque painted visor。UNSHADED painted diffuse，以實際生成圖為表面來源，不把 PBR／純色灰模稱完成材質。
ARTICULATION 原 28 bone names/rests；最多 4 influences；保留 r hand gun / l hand gun / fly_bag，沿用遊戲 79 動作，不新造動畫。
INFERRED   新頭殼深度、耳後連接、內面厚度、背甲與原身體 cage 的接合皆屬推定；候選三視圖不是使用者外形驗收。
TARGET     Godot 4.7.2 Compatibility；native .blend、GLB、四件 PackedScene、diffuse PNG；原型預算 3,000 tris（原 Cygni 1,006），新增幾何用於面罩／眉頰及接合而不是微型刻線。128px 為暫定縮小檢視；實際 gameplay 視圖另擷取，不宣稱已量測遊戲高度。

Owned paths：docs/art/cygni_runtime_v2/、tools/cygni_runtime_v2/、assets/armors/cygni_v2/；loader 僅增加 --cygni-v2 比較入口。
Inputs：ref/sources.json、原 player rig、已選 c12_concept、風格基底。
Outputs：四件 skin meshes／UV／生成 diffuse／Blender master／GLB／engine scene／原新比較與動作驗證。
Acceptance：可載入、四件混搭、存檔不變、掛點不變、動作不爆裂；逐視圖檢查外形、UV 與甲片穿插。數據驗證和使用者美術選定分別記錄。
Handoff：本示範通過工程檢查後仍須使用者看效果；不擴至其他套，不覆蓋 Phoenix、Thunder 或後段装甲。
