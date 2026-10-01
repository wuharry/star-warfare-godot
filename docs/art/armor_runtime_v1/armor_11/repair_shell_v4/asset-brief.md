# Cygni 頭盔：連續外殼灰模 v4

**狀態：2026-10-01 使用者拒絕大小、長寬比例與外型；以下保留為歷史施工紀錄，不再當成下一輪基準。** 主殼實際寬 0.6000，原版為 0.4606；外框含側翼相同掩蓋了主殼差異。後續改用 `../../style_base_v1/README.md` 的原版研究與 base prompt。

- **ASSET**：CH_Cygni_ConnectedHelmet；本階段只重建頭盔。
- **CATEGORY**：character / biped / modular rigid helmet。
- **VIEWS**：選定 `anubis_gold_t_swept.png` 為透視概念，只作造型參考；原版 Godot 固定正／側／斜前／背面作比例依據。概念的人體比例不帶入遊戲。
- **SCALE**：原遊戲 Y-up／-Z-forward、原 mesh attachment transform；骨架不縮放或重命名。
- **PROPORTIONS**：保留原頭盔整體範圍 X ±0.3416、Y 1.1964–1.9784、Z -0.4447–0.2551。中間剖面、鏡片轉折與側翼厚度是推定，不是從單張圖量出的精確三維資訊。
- **PARTS**：共邊的冠甲→眉線→T 形窗→斜收護頰→短下巴；領口藏於主殼內；四片短側翼的根部埋入主殼。每個部件綁同一 `Bip01 Head`，無新增 animation。
- **SILHOUETTE**：遊戲大頭／短身；前額往鏡片連續收斜；護頰向兩側及下巴包覆；T 窗不凸成獨立鼻樑板；短側翼。
- **MATERIALS**：本階段只有灰模外殼、深灰 T 窗、暗灰領口。UV 是臨時技術座標，未烘焙、未生成生產用貼圖。
- **ARTICULATION**：原 28-bone player rig、原 head skin binds、原待機／跑步／換彈動畫；混搭仍使用既有 equipment IDs。
- **INFERRED**：前側深度曲線、看不到的後殼、側翼厚度。未用舊頭盔 mesh 當新模型，舊模型只提供尺寸基準。
- **TARGET**：Godot 4.7.2 Compatibility；PackedScene／原四部位 loader；原相機與角色比例。當前頭盔 644 tris，完整套裝 1,412 tris；這是灰模，非已驗收正式素材。
- **ACCEPTANCE**：先檢查正、側、背面是否連續、有沒有漂浮或穿插；再確認概念輪廓與原遊戲造型相容。工程檢查通過不能代替美術驗收。
