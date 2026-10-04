# Tank · C-03 岩樁 · 遊戲素材

本套已接到遊戲裝甲 ID `02`，商店、換裝和遊戲人物共用 `assets/armors/tank_v1/tank.scn`。最新設計基準是使用者確認的 [部件美術](approved_parts_reference.png)；[完整概念](../fusion_v2_generated/c03_tank_fusion.jpg) 保留作頭盔與配色參考。這是可套用的模型、貼圖與 Skin，後續美術修改可在 [比較頁](index.html) 逐項評價。

- 原 Tank 四個換裝部件、796 個三角形、28 個骨架節點全部保留。
- 六個材質 surface 共用五張新 diffuse；頭盔第二個 surface 的深色頸襯共用手臂貼圖上方區域。
- 731 個原 UV 座標的數量與原分區數量保持不變。頭盔中央改 4／149 個座標（2.68%），前胸綠色 U 領改 12／210（5.71%）；肩甲、手臂、腿及共享頸襯為 0%。每個材質分別驗證，沒有把肩甲加入身體分母來放寬限制。
- 下護頰略收、下護片向前補厚；頭部最大局部位移為原頭部最小尺寸的 2.9786%。頭部三軸尺寸不變，身體與手腳幾何保持原值。
- `15%` 分別限制各材質改動 UV 座標占比、局部頂點位移、三軸尺寸與同相機灰模輪廓；不是概念圖像素相似度，也不限制貼圖可以重畫的面積。

製作流程以原模型的 rest-space 座標、Skin bind、三角形索引與 UV 快照作基準：`build/source.json → Blender 局部調整／打包貼圖 → target.json → Godot 原 Skin 套用 → SCN／GLB → 原動作與實機驗證`。`build/tank_master.blend` 可編輯；SCN 是實際換裝用的四部件容器，GLB 是保留原骨架的交換格式。

`generation_inputs.json` 保存實際 image_gen 提示詞、參考圖、原生成檔、未採用稿與採用稿。`manifest.json` 記錄採用 PNG、來源、模型、打包 master、驗證及實機畫面的 SHA256。完整部件展示圖是設計參考，不能直接拿來當肩甲 UV atlas。

最終採用頭盔 v2、身體 v4、肩甲 v2、手臂與腿 v1。少量 UV 取樣修正讓中央短橫進氣口相接、綠色 U 領落在可見胸甲頂部；所有原 chart 與三角形方向保持不變。最大 UV 絕對位移為 0.135 atlas 單位，另行記錄，不能當成改動座標占比。`guides/*_uv.*` 保留生成當時的原 UV，`guides/*_authored_uv.*` 是最終 UV。舊 0% 版本驗收留在 `review/drafts/uv0_head1_body2/`，不代表目前採用內容。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python tools/tank_runtime_v1/build.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/tank_runtime_v1/compile.gd
python tools/tank_runtime_v1/glb_unique_joints.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/tank_runtime_v1/render_uv.gd
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . tests/tank_v1_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . tests/tank_v1_roundtrip.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . tools/tank_runtime_v1/capture.tscn
python tools/tank_runtime_v1/measure.py
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background docs/art/tank_runtime_v1/build/tank_master.blend --python-exit-code 1 --python tools/tank_runtime_v1/validate_delivery.py
python tools/tank_runtime_v1/review.py
python tools/tank_runtime_v1/provenance.py
```

實際驗證包含待機、跑動與 gun00 換彈共 15 個姿勢，混搭、重複換裝、商店與換裝預覽，以及 GLB 回讀的 9 個姿勢。GPU 檢視使用 Godot 4.7.2 Compatibility：全身／頭盔為 640 × 720，兩個實際關卡為 1280 × 720，共 64 張原版／新版畫面。四視角灰模最大輪廓差異為 0.347%，真實存檔 SHA 不變。這些檢查驗證模型與 UV；美術仍可依使用者評價修正。

首次 import 有既有的 `audio-missing-archive-tfpon_0v` 掃描訊息，退出碼為 0；本套 runtime、GLB、GPU 與 Blender 檢查均分別實測 PASS。材質為不透明、手繪明暗的 diffuse／unshaded，沒有透明玻璃或額外 PBR 質感需求。屬性、技能、購買與存檔 ID、背包和原動作不變。
