# Viper 遊戲素材 v2

ASSET: CH_Viper；遊戲原 Viper，visual ID 00，C-01 對應。

CATEGORY: 可混搭四部件的人類科幻裝甲。

VIEWS: 原版與新版均使用實際 Godot 玩家骨架，全身正／側／背／四分之三採相同相機與構圖，另提供頭盔近照。指定的完整裝甲美術圖是 `../fusion_v2_generated/c01_viper_fusion.jpg`，來自25f11d9，作為整套表面設計與配色權威；成人全身比例仍轉換為原遊戲的短壯比例。實際 viewport、影像與構圖以 `review/` 輸出為準。

SCALE: 原版遊戲空間 1 unit=1 m；整套 rest bounds 高 1.912585 m。保留原 28 骨架、武器／背包掛點，不調整遊戲角色身高。

PROPORTIONS: 由原版 skinned rest bounds 測量，頭部尺寸包含頸部殼，並非解剖頭高：頭寬 .518323 m、頭高 .675655 m、頭深 .660211 m；身體寬 1.075294 m、高 1.096469 m；雙手整體跨度 1.125677 m；雙足跨度 .802098 m、高 .448828 m。頭高／全高=.3533；頭寬／手部跨度=.4604；身體寬／頭寬=2.0746；身體寬／身體高=.9807；足跨度／頭寬=1.5475；頭深／頭寬=1.2737；身體高／全高=.5733；足高／全高=.2347。精確數值以 `build/source.json`、`build/geometry.json` 為準。

PARTS: ArmorHead_00、ArmorBody_00、ArmorHand_00、ArmorFoot_00。肩甲仍是 body 的第二個 surface，不新增第五個換裝節點。全部沿用原權重；頭盔收下巴、內收臉頰、略推眉沿，其他部件幾何保持完全相同。

SILHOUETTE: 原版短壯比例、寬肩、雙胸斜窗、大手套／靴子；新版頭盔保留黑眉沿＋小藍梯形、連續紫面罩、較薄藍色下巴與藍色冠槽。整套表面設計以鋼藍甲片、炭黑肩頂／接縫、中央腹甲凹槽、藍色大腿外甲、黑色護膝及前臂／小腿長條凹槽為目標。

MATERIALS: 五張由 image_gen 生成的 opaque sRGB painted diffuse，head/body/shoulder/hand/foot，實際尺寸以 `manifest.json` 為準。`concept_match_v8` 依完整美術圖重畫鋼藍／炭黑配色及甲片細節；胸甲與腹甲正面少量 UV 重映射到生成貼圖中的正確甲片、斜窗及較長黑色腹甲凹槽，原 UV 座標／分區數量與鏡像使用保持一致。Godot 使用 unshaded 以符合原遊戲 painted diffuse，無透明玻璃或 PBR 法線需求；生成來源與先前版本保存在 `build/generation.json`。

ARTICULATION: 原 28 骨架與每個 Skin bind、逐頂點骨骼／權重保持一致，使用原待機、跑動與實際換彈流程。GLB 是裝甲／骨架輸出，不重製動畫庫；遊戲沿用既有 clips。

INFERRED: 新稿透視圖不能給出精確深度，局部下巴／臉頰／眉沿深度為受限推估；原版提供隱藏背面、頸部、關節與原 UV。身體、肩甲、手臂、靴子幾何完全保留；肩甲、手臂、靴子 UV 完全保留；胸甲與腹甲局部 UV 調整用於正確對位生成的表面細節。原版短壯外殼與鏡像胸甲使斜窗比概念圖更寬；低面數曲面保留，因此近距離輪廓仍帶低多邊形切面。

TARGET: Godot 4.7.2，四部件 scene＋GLB＋內嵌貼圖的 editable Blender master；682 tris，五個材質 surface，28骨架。UV 的15%上限按「改動座標數量占原版座標總數」驗收，頭盔與身體材質分別計算。最後重建的 source／target 實測：頭盔18／130（13.846%）、身體貼圖32／221（14.480%，胸甲20個及腹甲12個）、含肩甲 body 部件32／295（10.847%）、全套50／667（7.496%）。精確數量記錄於 `manifest.json`／`build/geometry.json`；四部件的 UV 座標及分區數量不變，肩甲、手臂、靴子 UV 精確保留。這不是每個 UV 點距離不得超過0.15的定義。身體及四肢幾何、全部三角形索引、骨架、權重及 Skin binds 保持原樣；繼續使用原待機、跑動與換彈。`review/delivery_validate.json` 核對本輪 master 的 packed maps 與 authored UV；一般 Blender 檢查的舊警告保留作歷史背景，不宣稱全套 validator 已重新跑過。
