# Tank · C-03 岩樁 · 遊戲素材

本套已接到遊戲裝甲 ID `02`，商店、換裝和遊戲人物共用 `assets/armors/tank_v1/tank.scn`。頭盔最新造型基準為使用者新附的 [頭盔參考](approved_helmet_reference.png)，身體保持原先確認的 [部件美術](approved_parts_reference.png)；[完整概念](../fusion_v2_generated/c03_tank_fusion.jpg) 保留作頭盔與配色參考。這是可套用的模型、貼圖與 Skin，後續美術修改可在 [比較頁](index.html) 逐項評價。

- 原 Tank 四個換裝部件、796 個三角形、28 個骨架節點全部保留。
- 六個材質 surface 共用五張新 diffuse；頭盔第二個 surface 的深色頸襯共用手臂貼圖上方區域。
- 731 個原 UV 座標的數量與原分區數量保持不變。頭盔中央改 4／149 個座標（2.68%），前胸綠色 U 領改 12／210（5.71%）；肩甲、手臂、腿及共享頸襯為 0%。每個材質分別驗證，沒有把肩甲加入身體分母來放寬限制。
- 最新 head surface0 實際改圓冠層次、壓薄前眉、收小深 V 缺口、縮短近平頂呼吸器與斜護頰；86 個頂點位置 entries 改動。原版最大局部位移為最小頭尺寸的 11.8456%，Y尺寸差 2.4218%，X/Z尺寸不變。共享頸襯 surface1、身體與手腳所有 arrays 精確不變。
- 此輪最新授權 `20%` 是相對原版的總上限，分別限制各材質改動 UV 座標占比、局部頂點位移、三軸尺寸與同相機灰模輪廓；不是概念圖像素相似度，也不限制貼圖可以重畫的面積。

前一輪 style v2 的零追加幾何／UV 與 15% PASS 已完整凍結在 `revisions/before_helmet_refinement_v3/`（73檔索引），更早 `before_style_unification_v2/` 的319檔也保持不變。最新頭盔迭代獨立使用 `review/helmet_refinement_scene_invariants.json` 與 `review/helmet_refinement_invariants.json`，僅允許 head surface0 positions／normals 改動，所有 UV 精確相同、indices／Skin／weights／骨架／材質參數，以及 neck／body／limbs 都精確相同。相對原版20%逐項重新計算，不把前輪或本輪增量相加。

頭盔造型細修的必要基底為 `docs/art/armor_style_unification_v1/tank_helmet_refinement_prompt.txt`，全身風格仍沿用 `base_prompt.txt`，各階段實際 atlas 提示詞完整包含對應基底，並追加部位映射和 Tank 身份限制。`generation_inputs.json` 保存 5 份完整實送提示詞與 SHA、18 份不可變來源及原生生成檔；舊採用稿只標記為被本輪取代，沒有刪除。

製作流程以原模型的 rest-space 座標、Skin bind、三角形索引與 UV 快照作基準：`build/source.json → Blender 局部調整／打包貼圖 → target.json → Godot 原 Skin 套用 → SCN／GLB → 原動作與實機驗證`。`build/tank_master.blend` 可編輯；SCN 是實際換裝用的四部件容器，GLB 是保留原骨架的交換格式。

`generation_inputs.json` 保存實際 image_gen 提示詞、參考圖、原生成檔、未採用稿與採用稿。`manifest.json` 記錄採用 PNG、來源、模型、打包 master、驗證及實機畫面的 SHA256。完整部件展示圖是設計參考，不能直接拿來當肩甲 UV atlas。

前一輪採用頭盔 v2、身體 v4、肩甲 v2、手臂與腿 v1；完整來源及舊實機畫面已凍結在 `revisions/before_style_unification_v2/`。前一輪五張貼圖更新為 `style_unified_v2`，最新頭部改為 `helmet_refinement_v4`，其餘四張圖SHA保持精確相同，原生 1254 × 1254 PNG 直接複製，不改尺寸或色彩。較寬柔的手繪高光、減少細白裂紋及黑色接縫是此輪重點；部分接觸邊仍偏亮，藝術結果等待使用者評價。沿用的少量 UV 取樣修正讓中央短橫進氣口相接、綠色 U 領落在可見胸甲頂部；所有原 chart 與三角形方向保持不變。最大 UV 絕對位移為 0.135 atlas 單位，另行記錄，不能當成改動座標占比。`guides/*_uv.*` 保留生成當時的原 UV，`guides/*_authored_uv.*` 是最終 UV。舊 0% 版本驗收留在 `review/drafts/uv0_head1_body2/`，不代表目前採用內容。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python tools/tank_runtime_v1/build.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/tank_runtime_v1/compile.gd
python tools/tank_runtime_v1/glb_unique_joints.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/tank_runtime_v1/render_uv.gd
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . tests/tank_v1_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . tests/tank_v1_roundtrip.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --rendering-driver opengl3_angle tools/tank_runtime_v1/capture.tscn
python tools/tank_runtime_v1/measure.py
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background docs/art/tank_runtime_v1/build/tank_master.blend --python-exit-code 1 --python tools/tank_runtime_v1/validate_delivery.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/tank_runtime_v1/validate_helmet_refinement_scene.gd
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python-exit-code 1 --python tools/tank_runtime_v1/validate_helmet_refinement.py
python tools/tank_runtime_v1/validate_glb_images.py
python tools/tank_runtime_v1/review.py
python tools/tank_runtime_v1/provenance.py
```

實際驗證包含待機、跑動與 gun00 換彈共 15 個姿勢，混搭、重複換裝、商店與換裝預覽，以及 GLB 回讀的 9 個姿勢。GPU 檢視使用 Godot 4.7.2 Compatibility：全身／頭盔為 640 × 720，兩個實際關卡為 1280 × 720，共 64 張原版／新版畫面。四視角灰模最大輪廓差異為 0.347%，真實存檔 SHA 不變。這些檢查驗證模型與 UV；美術仍可依使用者評價修正。

首次 import 有既有的 `audio-missing-archive-tfpon_0v` 掃描訊息，退出碼為 0；本套 runtime、GLB、GPU 與 Blender 檢查均分別實測 PASS。材質為不透明、手繪明暗的 diffuse／unshaded，沒有透明玻璃或額外 PBR 質感需求。屬性、技能、購買與存檔 ID、背包和原動作不變。

最新工程驗證區分可調的 head surface0 positions／normals 與精確保留的全部 UV、面索引、權重、Skin、rest骨架和transform。頭部無反轉三角形、無零面積三角形，原重複位置接縫差為0。五張 GLB 內嵌圖片逐 RGB 像素與 canonical 相同，頭材質回讀另採 30 個實際取樣、誤差上限保持 0.05。部分接觸邊仍偏亮，後腦保留原來多層板片及三角面低模輪廓；這是本輪保留造型的限制，沒有宣稱藝術完全一致。

實際新atlas先出 v3 未採用稿（仍有四條橫冠槽、誤画額外上脊／重複通氣槽），定向修正 v4 保留連續窄藍中脊、薄眉和單一底槽。兩份實送提示詞、native outputs、參考圖順序及 SHA 都在 `helmet_refinement_v3_generation.json` 與完整 generation history 中。正式 normal imports、15姿勢／GLB9姿勢／64ANGLE D3D11畫面另行重跑，真存檔SHA保持相同。

後腦缺色修正：選用原生 v6 全底色延展稿，原UV保持不變。v3–v5未採用稿及24項rear UV候選均保存；候選沒有套用。正式64圖第二次擷取 PASS，實際存檔前後 SHA 相同；首次 save_unchanged=false 的擷取索引與日誌保留在 review/failed_capture_v6_savecheck，未重現其變動來源。
