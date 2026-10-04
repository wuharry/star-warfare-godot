# Viper 可套用遊戲素材

2026-10-04：目前最新版為 `style_unified_v9`。保留已確認的 v8 頭盔／黑眉／連續紫色面甲、胸窗、腹甲、大腿與背甲配置，重新生成五張實際 diffuse，統一為較寬柔和的手繪高光；降低連續細白描邊、長裂痕和面甲中央硬亮柱。這是表面畫法試作，仍待使用者美術驗收，不把任何工程百分比稱作畫風相似度。

本輪不新增模型或 UV 調整；`build/target.json` 與 `build/geometry.json` 的 bytes 與 `../armor_style_unification_v1/before/viper/delivery/` 的 v8 快照完全一致。原版累計的 18／130 頭部 UV、32／221 胸腹 UV，以及原頭最大 rest 位移 10.24% 均沿用 v8，不再次消耗 15% 預算。原索引、四個部件、五個材質、28 bones／Skin／weights／動作及掛點保留。

本輪每張生成 prompt 都完整包含 [後續優化必用基底](../armor_style_unification_v1/base_prompt.txt)，再接 Viper 部位 addendum。原版貼圖只供畫法參考；不可變 v8 atlas 為 UV 配置和新版設計權威。`revisions/style_unified_v9/generation_inputs.json` 保存實際送出的 prompt、三張輸入及 SHA、生成原路徑、輸出和生成檔 UTC 修改時間；五張 native 1254 × 1254 PNG 均直接複製，沒有 Python 改色、縮放或拼圖。過去 v8 prompt／生成檔與歸屬完整保留，`previous_manifest.json`／`previous_generation_records.json` 為本輪前快照。

`index.html` 是目前可套用素材的原版／新版四向、面甲、待機、跑動、九個換彈進度與兩關卡檢視。畫法統一前後請看 [v8 → v9 比較頁](../armor_style_unification_v1/index.html)。`review/engine/capture.json` 現在記錄啟動時 SCN／五張 atlas SHA 與每張輸出 SHA；实际 ANGLE／D3D11 renderer 啟動資訊在 `revisions/style_unified_v9/capture.log`，`configured_windows_driver` 只表示專案設定。技術測試、packed master 和 GLB 都針對本輪重新產生；舊 `blender_validate.json`／`blender_roundtrip/` 保留歷史證據。

本輪重建沿用下方既有流程，唯 `review.py --runtime-only` 可只更新本套頁面，避免同時改寫共用裝甲 gallery。新增 `validate_style_invariants.gd` 直接比較目前 SCN 與不可變 prepass SCN 的所有 mesh arrays（positions／normals／UV／bones／weights／indices）、transform、skeleton path、skin binds 與材質模式；四部件全部精確相等。`revisions/style_unified_v9/glb_atlas_validation.json` 另外核對 GLB 內嵌圖、Godot portable 副本與 canonical 五張 diffuse 的 RGBA pixels 完全相同，PNG 壓縮 bytes 可不同。`provenance.py` 驗證選定生成圖與 canonical bytes 相同、不可變輸入 SHA、prepass target／geometry 完全相同，以及最新 capture／delivery／runtime／實機 mesh invariant／GLB 貼圖資料後，才更新目前 manifest。

以下為 **v8 製作紀錄與沿用的原版工程限制**：

2026-10-03：依使用者要求，從原版基準量測的局部模型與各材質 UV 改動上限收緊為15%。UV 座標及分區總數仍須完全相同；模型量測分為三軸尺寸、最大 rest 位移與同相機輪廓。這不是美術相似度的百分比。

開啟 `index.html`，比對原版、修訂前 v7、指定的完整裝甲美術圖與本輪遊戲素材。頁面提供四向、頭盔近照、灰模、待機／跑動、完整換彈進度、兩個遊戲關卡，以及五組原版／新版貼圖與各自 UV 線圖。

遊戲預設 Viper 已改用 `assets/armors/viper_v2/viper.scn`，仍是 visual ID 00，四個原節點與混搭／存檔 ID 不變。`--armor-style=legacy` 保留之前的 refined Viper；`--viper-angular-trial` 可看較早的 angular 版本。比較頁的「原版」採未改動的原始 player.gltf，並非上述兩個舊試作。

這套包含五張實際生成的 diffuse、四部件 scene、帶骨架的 GLB 和 `build/viper_master.blend`。Master 包含貼圖；GLB 匯出產生的 `viper_*_diffuse.png` 是引擎寫出的 portable 副本。概念圖不當成 UV 貼圖。

本輪 `concept_match_v8` 以 `../fusion_v2_generated/c01_viper_fusion.jpg` 的整套鋼藍／炭黑裝甲為設計權威，包含胸甲、腹甲、大腿、護膝、前臂與最新紫色連續面甲。原版提供遊戲短壯比例、模型外殼與 UV；貼圖的板件分區及配色按完整美術圖調整。先前「保留 85–90% 原版外觀」的生成條件已被使用者這次要求取代，15% 限制不套用到貼圖重畫面積。

生成基底完整沿用指定 commits 13d6836／48f0a12a 的 `docs/art/legacy_armor_base_v2/base_prompt.txt`，兩個 commit 的該檔內容相同。每次實際送出的完整提示詞保存在 `prompts/`；完整裝甲參考來自 25f11d9 的 C-01 Viper。`revisions/concept_match_v8/generation_inputs.json` 列出本輪五張生成圖的真實 prompt、輸入快照、輸出與生成時間；`manifest.json` 和 `build/generation.json` 記錄 SHA256、尺寸及歷史稿。先前 v7 的五張貼圖與預覽留作比較，不再將新版 canonical 貼圖歸因於舊生成結果。最新頭盔沿用 v7 已修正的連續紫色面甲、較窄的下半部與藍色下巴，並與身體配色一起調整。

模型保持原 682 tris 與五個 surface。頭盔沿用 v7 的局部面甲 UV；本輪另將胸甲與腹甲正面的少量 UV 重映射到生成貼圖中正確的藍色甲片、黑色斜窗及較長的中央腹甲凹槽，修正生成圖把細節畫到相鄰區域與腹甲凹槽過短的問題。原有 UV 座標及分區數量不變，肩甲、手臂、靴子 UV 完全相同；身體及四肢幾何完全相同。

由最後重建的 `build/source.json`／`build/target.json` 對比並與 `build/geometry.json` 核對，頭盔沿用18／130個面甲座標（13.846%）；身體貼圖調整32／221（14.480%，胸甲20個、腹甲12個），含肩甲的整個 body 部件為32／295（10.847%）；全套改動50／667（7.496%）。「15%」按頭盔與身體材質分別計算改動座標的數量占比，不代表每個點的 UV 位移距離均小於0.15，也不代表已量化美術相似度。

頭盔局部改動仍沿用前一輪：最大 rest 位移 .05306 m，約為原頭最小尺寸的 10.24%；頭部尺寸差異最大 5.00%。前一輪四視角灰模輪廓差異最大 1.42%，仍在15%局部幾何上限內；本輪實際量測與構圖以更新的 `review/` 報告為準，不把舊量測當作新畫面驗收。

`review/runtime_test.json` 驗證頭盔、胸甲及腹甲 UV 的預期局部調整與15%預算、其他部位 UV 精確相等，以及原索引／bones／weights／skin binds、骨架／掛點、15個動作樣本、混搭、商店／自訂顯示和真實存檔保留。`review/roundtrip_test.json` 驗證 GLB 重新匯入後9個動作樣本。

`review/delivery_validate.json` 是本輪的 focused Blender 檢查，核對 packed master 的4 mesh、28 bone、5個內嵌 diffuse 的實際 bytes、原 topology／rig，以及本輪 authored UV／position。它不判斷美術相似度，且不等同重新跑過所有一般 Blender 檢查。`review/blender_validate.json` 與 `review/blender_roundtrip/roundtrip.json` 保留前一輪證據；原版重合頂點與 body 的4個小權重仍以歷史 warning 列出，不把舊報告稱為本輪新驗證。

仍保留原版低面數外殼的切面及側面耳部的大體積，以保留遊戲比例及主要 UV 分區；完整美術圖的表面設計轉成對應的 diffuse 貼圖。現有短壯、鏡像胸甲外殼限制胸窗的寬度，套用後的黑色斜窗仍比概念圖寬；概念圖中的成人身形與所有立體細節也不能逐項完全一致。比較頁呈現真正套用後的差異，供使用者繼續評價。

重建順序（在 repo 根執行，使用專案 Godot／Blender）：

1. Godot `--headless --path . --script res://tools/viper_runtime_v2/inspect.gd`。
2. Blender `--background --python tools/viper_runtime_v2/build.py`，Godot `render_uv.gd -- --head-v6` 輸出目前頭盔 UV 線圖。原版及生成時使用的 guide 均保留，不覆寫來源參考。
3. 套用已提交的生成 diffuse；Godot `--headless --editor --path . --import` 讓引擎匯入。
4. Godot `--headless --path . --script res://tools/viper_runtime_v2/compile.gd`，再 `python tools/viper_runtime_v2/glb_unique_joints.py`。不要以 Blender 普通匯出取代原 Skin 的引擎編譯。
5. 執行 `tests/viper_v2_test.tscn`、`tests/viper_v2_roundtrip.tscn`；可視 renderer 執行 `tools/viper_runtime_v2/capture.tscn`，再 `python tools/viper_runtime_v2/measure.py`、`python tools/viper_runtime_v2/review.py`。
6. Blender `--background docs/art/viper_runtime_v2/build/viper_master.blend --python tools/viper_runtime_v2/validate_delivery.py` 產生本輪 packed master 驗證。
7. 本輪輸入、版本化生成圖與 canonical 貼圖均保存完畢後，執行 `python tools/viper_runtime_v2/provenance.py`。程式驗證每張已選輸出與 canonical SHA256 相同、動態計算 UV 修改數量，並拒絕 master／target／貼圖 SHA 已過期的 delivery 報告；將被替換的舊稿指向不可變輸入快照，保留歷史歸屬並更新 manifest。

`.import`／`.uid` 由引擎產生。此工作沒有修改 Claude hooks。編輯器掃描會另外報既有 `audio-missing-archive-tfpon_0v` 目錄不可讀，Viper 的匯入與執行測試均完成。
