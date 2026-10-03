# Viper 遊戲素材 v2

ASSET: CH_Viper；遊戲原 Viper，visual ID 00，C-01 對應。

CATEGORY: 可混搭四部件的人類科幻裝甲。

VIEWS: 原版與新版均使用實際 Godot 玩家骨架。全身正／側／背／四分之三正交相機 size=2.35，中心 (0,1.04,0)；頭盔近照 size=.83，中心 (0,1.58,-.07)。指定的新頭盔是 `../fusion_v2_generated/c01_viper_fusion.jpg`，來自 25f11d9，僅作局部設計權威，成人全身比例不採用。

SCALE: 原版遊戲空間 1 unit=1 m；整套 rest bounds 高 1.912585 m。保留原 28 骨架、武器／背包掛點，不調整遊戲角色身高。

PROPORTIONS: 由原版 skinned rest bounds 測量，頭部尺寸包含頸部殼，並非解剖頭高：頭寬 .518323 m、頭高 .675655 m、頭深 .660211 m；身體寬 1.075294 m、高 1.096469 m；雙手整體跨度 1.125677 m；雙足跨度 .802098 m、高 .448828 m。頭高／全高=.3533；頭寬／手部跨度=.4604；身體寬／頭寬=2.0746；身體寬／身體高=.9807；足跨度／頭寬=1.5475；頭深／頭寬=1.2737；身體高／全高=.5733；足高／全高=.2347。精確數值以 `build/source.json`、`build/geometry.json` 為準。

PARTS: ArmorHead_00、ArmorBody_00、ArmorHand_00、ArmorFoot_00。肩甲仍是 body 的第二個 surface，不新增第五個換裝節點。全部沿用原權重；頭盔收下巴、內收臉頰、略推眉沿，其他部件幾何保持完全相同。

SILHOUETTE: 原版短壯比例、寬肩、雙胸斜窗、大手套／靴子；新版頭盔保留黑眉沿＋小藍梯形、紫面罩、藍色 U 下巴與藍色冠槽。

MATERIALS: 五張生成的 opaque sRGB painted diffuse，head/body/shoulder/hand/foot，1254×1254。沿用原版低頻筆觸與材質分區；Godot 使用 unshaded 以符合原遊戲 painted diffuse，無透明玻璃或 PBR 法線需求。

ARTICULATION: 原 28 骨架與每個 Skin bind、逐頂點骨骼／權重保持一致，使用原待機、跑動與實際換彈流程。GLB 是裝甲／骨架輸出，不重製動畫庫；遊戲沿用既有 clips。

INFERRED: 新稿透視圖不能給出精確深度，局部下巴／臉頰／眉沿深度為受限推估；原版提供頸、背面、軀幹、四肢與全部 UV。原版殼的低面數曲面保留，因此近距離輪廓仍帶低多邊形切面。

TARGET: Godot 4.7.2，四部件 scene＋GLB＋內嵌貼圖的 editable Blender master；682 tris，五個材質 surface。使用者要求局部誤差控制約 10%–15%：實作為 15% 上限，並非各處刻意改滿 10%。所有 UV 座標、三角形索引、鏡像使用與權重精確沿用原版。
