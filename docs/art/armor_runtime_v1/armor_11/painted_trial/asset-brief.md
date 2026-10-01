# Cygni：原版風格貼合試稿

ASSET CH_Cygni_PaintedTrial
CATEGORY character / modular human-worn armor
VIEWS 原模型與原 UV 是尺寸權威；anubis_gold_t_swept.png 是斜前頭盔造型參考，c12_turnaround.png 的身材比例不帶入。
SCALE 原 Cygni 頭盔 x=±0.3416、y=1.1964..1.9784、z=-0.4447..0.2551；遊戲 Y-up / -Z forward，原骨架未改。
PROPORTIONS 各部位原三軸範圍逐表面對照，詳 asset-manifest.json 的 original_bounds / candidate_bounds；目前 15 個軸向尺寸變化均為 0%，不表示局部形狀完全不變。
PARTS 頭：頭盔、短側翼；身：胸腹、肩、上臂、骨盆、大腿；手：前臂和原手套；腿：脛甲、原腳。每個原材質表面保留自己的 UV 和 skin binding。
SILHOUETTE 大頭短身、原側翼和站姿；眉甲薄層、內收護頰；不加厚下巴。
MATERIALS 原手繪漆面與布料明暗；身體、肩、手、腳仍使用既有精修版圖集；頭盔是原 UV 布局的白灰／金色玻璃編輯圖。
ARTICULATION 原 Bip01 rig；原待機、跑步、射擊與換彈動畫，未另製作 animation clips。
INFERRED 概念薄層投影輪廓和厚度；後腦保留原模型；不能宣稱完整概念圖三視圖重建。
TARGET Godot 4.7.2；原生 .scn，2435 tris / 5 material surfaces，實際引擎低解析度約 125 px 角色高度。這是美術風格驗收試稿，尚未批次正式套用。
