# Viper 可套用遊戲素材

開啟 `index.html`，比對原版、最新版頭盔美術與實際遊戲素材。頁面提供四向、頭盔近照、灰模、待機／跑動、完整換彈進度、兩個遊戲關卡，以及五組原版／新版貼圖與各自 UV 線圖。

遊戲預設 Viper 已改用 `assets/armors/viper_v2/viper.scn`，仍是 visual ID 00，四個原節點與混搭／存檔 ID 不變。`--armor-style=legacy` 保留之前的 refined Viper；`--viper-angular-trial` 可看較早的 angular 版本。比較頁的「原版」採未改動的原始 player.gltf，並非上述兩個舊試作。

這套包含五張實際生成的 diffuse、四部件 scene、帶骨架的 GLB 和 `build/viper_master.blend`。Master 包含貼圖；GLB 匯出產生的 `viper_*_diffuse.png` 是引擎寫出的 portable 副本。概念圖不當成 UV 貼圖。

生成基底完整沿用指定 commits 13d6836／48f0a12a 的 `docs/art/legacy_armor_base_v2/base_prompt.txt`，兩個 commit 的該檔內容相同。每次實際送出的全文保存在 `prompts/`；指定頭盔是 25f11d9 的 C-01 Viper。`manifest.json` 和 `build/generation.json` 記錄輸入、輸出、SHA256、尺寸及未採用稿。第一版黑眉沿位置錯誤，已保留但未套用；最後選用 v7，擴大連續紫色面甲、收窄下半部、縮薄藍色下巴，並減少黑色斜塊侵入面罩。

模型保持原 682 tris 與五個 surface。頭盔130個 UV 座標數量不變、分區數量不變，僅18個面甲座標（13.85%）改為完整正面展開；其他部位 UV 保持原樣。使用者本輪明確允許修改貼圖及UV，將容許誤差放寬到20%。身體、手臂、靴子頂點完全相同；頭盔局部改動的最大 rest 位移 .05306 m，約為原頭最小尺寸的 10.24%；頭部尺寸差異最大 5.00%。四視角灰模輪廓差異最大 1.42%，符合本輪「改動稍大一點」的方向，仍在本輪 20% 局部幾何上限內。這些是幾何測量，不把貼圖與美術相似度稱為已量化或已獲使用者確認。

`review/runtime_test.json` 驗證身體 UV／索引／bones／weights 精確相等；頭盔 UV 數量不變，18個面甲座標局部調整、原 skin binds、骨架／掛點、15 個動作樣本、混搭與商店／自訂顯示，並確認真實存檔未變。`review/roundtrip_test.json` 驗證 GLB 重新匯入後 9 個動作樣本；`review/blender_roundtrip/roundtrip.json` 記錄 4 mesh、28 bone、5 images、身高與零錯誤。`review/blender_validate.json` 零 fail；原 mesh 因 UV／法線拆點而有重合頂點，以及原 body 的 4 個小權重，均保留且列為 warning。

仍保留原版低面數外殼的切面及側面耳部的大體積，以保留遊戲比例及主要 UV 分區；新版頭盔設計已轉成其上的前額、面罩、冠槽、下巴貼圖與局部形狀。美術品質仍可在比較頁逐項調整。

重建順序（在 repo 根執行，使用專案 Godot／Blender）：

1. Godot `--headless --path . --script res://tools/viper_runtime_v2/inspect.gd`。
2. Blender `--background --python tools/viper_runtime_v2/build.py`，Godot `render_uv.gd -- --head-v6` 輸出目前頭盔 UV 線圖。原版及生成時使用的 guide 均保留，不覆寫來源參考。
3. 套用已提交的生成 diffuse；Godot `--headless --editor --path . --import` 讓引擎匯入。
4. Godot `--headless --path . --script res://tools/viper_runtime_v2/compile.gd`，再 `python tools/viper_runtime_v2/glb_unique_joints.py`。不要以 Blender 普通匯出取代原 Skin 的引擎編譯。
5. 執行 `tests/viper_v2_test.tscn`、`tests/viper_v2_roundtrip.tscn`；可視 renderer 執行 `tools/viper_runtime_v2/capture.tscn`，再 `python tools/viper_runtime_v2/measure.py`、`python tools/viper_runtime_v2/review.py`。

`.import`／`.uid` 由引擎產生。此工作沒有修改 Claude hooks。編輯器掃描會另外報既有 `audio-missing-archive-tfpon_0v` 目錄不可讀，Viper 的匯入與執行測試均完成。
