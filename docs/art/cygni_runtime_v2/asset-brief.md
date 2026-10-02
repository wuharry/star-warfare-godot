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
| 新頭殼寬 | 約 0.48–0.49；依原主殼 0.4606 與新較圓頭盔形狀適配，屬設計推定 |
| 新頭盔頂 | 1.9784；依原頭頂保持角色整體高度 |
| 新頭盔下緣 | 約 1.33；短下巴取代原 1.1964 長護頷，屬有意改動 |
| 新面罩橫帶寬／中央條寬 | 約 0.416 / 0.11；依所選概念的 T 結構轉換 |
| 新面罩前緣 | 約 -0.385；從原 -0.4447 縮短前伸，深度推定，需側視驗證 |
| 膝／肘／髖位置 | 完全沿用原 cage 與原 bone rests，不由生圖猜測 |

PARTS      Head：重建連接式盔殼、內收頰甲、T 面罩、短下巴、雙短側翼；側接片下緣往後上收。Body：保留原短身 cage、肩甲與雙翼主輪廓，肩翼尖端收短，胸前新增 V 分片與銅色胸骨片。Arm／Leg：沿用原手掌、前臂、膝位與靴底 cage，重做 UV 與 diffuse。四件分開，沿用同一 skeleton。
SILHOUETTE 金 T、分層眉甲、斜收頰甲／短下巴、頭肩短翼、白甲／深綠身體分區。
MATERIALS  白灰 painted armor、深綠 secondary shell、煤黑 soft joints、少量銅橙 inserts、金色 opaque painted visor。UNSHADED painted diffuse，以實際生成圖為表面來源，不把 PBR／純色灰模稱完成材質。
ARTICULATION 原 28 bone names/rests；最多 4 influences；保留 r hand gun / l hand gun / fly_bag，沿用既有遊戲動作，不新造動畫。實測發現原 cage 的 legacy inverse-bind 與靴子重複 bind 不能換成一般 inverse-rest；最終 scene 保留原綁定，GLB 用 29 個 identity child 作 bind 別名。
INFERRED   新頭殼深度、耳後連接、內面厚度、背甲與原身體 cage 的接合皆屬推定；候選三視圖不是使用者外形驗收。
TARGET     Godot 4.7.2 Compatibility；native .blend、GLB、四件 PackedScene、diffuse PNG；原型預算 3,000 tris（原 Cygni 1,006），新增幾何用於面罩／眉頰及接合而不是微型刻線。128px 為暫定縮小檢視；實際 gameplay 視圖另擷取，不宣稱已量測遊戲高度。

Owned paths：docs/art/cygni_runtime_v2/、tools/cygni_runtime_v2/、assets/armors/cygni_v2/；loader 僅增加 --cygni-v2 比較入口。
Inputs：ref/sources.json、原 player rig、已選 c12_concept、風格基底。
Outputs：四件 skin meshes／UV／生成 diffuse／Blender master／GLB／engine scene／原新比較與動作驗證。
Acceptance：原版與新版並排應像同一位美術製作的不同裝甲（使用者於 2026-10-02 明確設定的底線）；比較遊戲比例、甲片明暗、邊緣畫法、材料表現與細節分配。可載入、四件混搭、存檔不變、掛點不變、動作不爆裂；逐視圖檢查外形、UV 與甲片穿插。工程測試不能替代這項美術門檻。
Handoff：本示範通過工程檢查後仍須使用者看效果；不擴至其他套，不覆蓋 Phoenix、Thunder 或後段裝甲。

實作結果（2026-10-02）：頭盔／胸片新幾何、四張生成 diffuse、四件 runtime scene、GLB 已完成。原肩甲、手套與靴子主輪廓保留，肩翼尖端收短；原先的「短單翼」列為概念差異，這版沒有宣稱完成所有局部重建。Body／Hand／Foot 以原 UV 與源 cage 對應保留 legacy bind；Blender bind-space 包絡不能冒充最終 Godot posed bounds。工程、亮度統計與人工美術選定分開，實際結果見 README.md。


## 2026-10-02：原版局部改造方向

**使用者要求新版非常接近原版，僅接受局部改動。** 原先碎片化的頭盔 checkpoint 已保存；本輪改用 Blender 重塑原 Cygni 的連續 cage，保留原 UV 與 legacy Skin bind。頭冠微收、下巴縮短、頰部內收、側翼收短；金 T 面罩及淺眉甲層次由貼圖表現，不新增浮動面甲。這是模型與貼圖都改的試作，並非只在舊幾何上換色。

實作在 `tools/cygni_runtime_v2/build.py::helmet`。參數按原 game-space 座標調整，含從概念推定的局部形狀；不能將此形狀記成使用者已驗收。原 Spine1 collar、原骨架與掛點保留。其他三件沿用上一個 checkpoint，本輪不宣稱其 UV 已改回原版。
