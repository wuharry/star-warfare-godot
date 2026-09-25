# 兵蟲概念圖 → 遊戲美術原型

這一版把既有兵蟲概念圖的方向接進遊戲，先驗證一隻敵人的模型、貼圖、動畫與命中流程。對照畫面放在 [index.html](index.html)。

## 對應與製作範圍

| 項目 | 對應 |
| --- | --- |
| 遊戲種類 | `crawler` |
| 復原來源 | `Monster ID 0 / bug01 / Warrior` |
| 概念依據 | [01_mantis_turnaround.jpg](../warrior_bug_concept/images/01_mantis_turnaround.jpg) |
| 原模型 | `assets/models/enemies/animated/bug01/bug01.gltf` |
| 本版模型 | `assets/models/enemies/concept/warrior/warrior.gltf` |
| 本版貼圖 | `assets/models/enemies/concept/warrior/warrior_albedo.png` |
| 貼圖實際尺寸 | 1254 × 1254；保留 imagegen 原始輸出 |
| 模型實際規模 | 2,288 頂點／3,224 三角形／1 蒙皮網格／5 材質 |
| 骨架 | 原 22 骨 + 鐮臂 6 骨 + 大顎 2 骨，共 30 骨 |
| 動畫 | 原 8 段全部保留，新增骨另補動作；30 FPS 匯出保留原片段時長 |
| 載入位置 | `MonsterCatalog.visual_scene_path()` → `WarfareEnemy._build_visual()` |

概念圖提供紅褐甲殼、紫色甲縫、六顆綠眼、高頭罩、雙鐮臂與四條步足。貼圖參照原圖集的分區生成，再為新建的甲殼、步足、頭部與鐮臂指派 UV；本版沒有直接保留原網格的頂點和 UV。新輪廓需要真正的立體網格，不能只靠平面色彩。

```text
原模型的骨架與四足動畫 ─────┐
既有兵蟲概念圖 ────────────┼→ 改造模型 + 專用貼圖 + 新增骨骼動畫
imagegen 生成的 UV 貼圖 ───┘           ↓
                          warrior.gltf / warrior.bin / warrior_albedo.png
                                      ↓
                          crawler 的正常生成、命中與死亡流程
```

原有血量、傷害、速度、獎勵、存檔種類和 AI 繼續由既有遊戲資料控制。本版新增的部位使用同一套蒙皮與傷害碰撞流程，沒有新增弱點倍率或新攻擊規則。

## 如何在遊戲內看

正常第一關產生的 `crawler` 會優先載入這版模型。其他種類仍載入原模型。比較場景會同時建立原版與新版，將原版實例的 `use_concept_visuals` 設成 `false`；此值必須在節點加入 SceneTree 前設定。

```powershell
# 首次拉取資產後，先取回 LFS 並匯入。
git lfs pull
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit

# 產生比較圖；加 -- --keep-open 可保留並排的動畫預覽。
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/enemy_concept_visual_capture.tscn

# 模型、骨骼動畫、貼地、貼圖與命中行為測試。
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/enemy_concept_test.tscn
```

測試與比較場景會指定 `GameState.TEST_SAVE_PATH`。截圖使用固定 1280 × 720、GL Compatibility，直接儲存 Godot viewport，沒有修圖。第一關截圖經正常 `_spawn_enemy` 生成，再隱藏玩家、HUD 並換近距離鏡頭，屬於場景內美術觀察畫面。

保留動畫預覽時，按 `1` 播待機、`2` 播跑步、`3` 播攻擊、`4` 播死亡；`Space` 暫停／繼續。攻擊與死亡播放一次，再按對應按鍵可重播。

## 如何重建模型

`build_warrior.py` 讀取來源 glTF 與已生成的 PNG，在原骨架的待機姿勢建立新網格，再轉回骨骼的基準位置。它會輸出同資料夾的 glTF／bin；貼圖必須已存在，程式不會再次呼叫 imagegen。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --python-exit-code 1 --python tools/enemy_concept/build_warrior.py
```

來源與貼圖以唯讀輸入使用。建置檢查貼圖 SHA256、材質貼圖宣告、動畫名稱及時長，失敗會退出非零；診斷 `.blend` 與完整 `build_report.json` 寫入 `test_output/enemy_concept_runtime/model_build/`。重建後仍需重新匯入 Godot 並跑測試。

## 視覺取捨

第一版刻意先確立雙鐮臂、六眼與有厚度的甲殼。新部件 UV 取用圖集較乾淨的甲殼區域，紫色甲縫另外做成幾何，避免每片小甲殼重複整條原貼圖的關節紋。因原關卡主要使用烘焙背景照明，甲殼材質加入低強度、隨貼圖顏色的發光，讓暗處仍可辨識；沒有修改關卡燈光。

待機總高度沿用 `crawler` 的 2 m 規格，包含高舉的鐮臂，因此軀幹比原版低。原四足動畫繼續使用，腿部比例、關節銜接與背甲目前仍屬第一版，可再依遊戲鏡頭修形；不是概念圖逐像素重建，也未做大量敵人效能基準測試。

## 實際驗證

| 檢查 | 結果 |
| --- | --- |
| 兵蟲專用場景 | PASS：126 checks，27 條射線，確認真正載入新模型／貼圖及 8 根新骨 |
| 既有敵人動畫 | PASS：4 種敵人 |
| 遠近命中範圍 | PASS：209 checks |
| 命中與音效 | PASS：4 種敵人 |
| 遊戲 smoke test | PASS |
| Godot 畫面擷取 | PASS：18 張，1280 × 720，GL Compatibility |
| 比較頁 | PASS：8 組姿勢切換，桌面／手機寬度無橫向溢出，15 個本機連結有效 |
| harness 同步檢查 | FAIL：原有 13 項 generated drift，本次沒有修改 harness 檔案 |
| 大量敵人效能測量 | NOT RUN |

上述遊戲測試與擷取的最終執行均無錯誤或警告。驗證時另修正桌面 HUD 建立孤立觸控按鈕的問題，以及測試結束前等待音訊釋放的清理流程；沒有放寬玩法斷言。[validation.json](validation.json) 與 [validation_logs/](validation_logs/) 保留結果；[capture_manifest.json](capture_manifest.json) 記錄每張截圖的姿勢、實際場景路徑及 SHA256。

畫面已由助理檢視：待機可見雙鐮臂、六眼與四足，攻擊時鐮臂向前揮下，死亡時隨身體倒下。材質接縫和腿部形狀目前符合原型用途，仍需使用者確認美術方向。

## 素材來源與限制

[生成提示詞](prompts/warrior_albedo_v1.txt)與[生成紀錄](generation_record.json)記錄實際參考圖、尺寸及 SHA256。貼圖要求為 1024 × 1024，但工具回傳 1254 × 1254，因此保留實際輸出尺寸。

這是新建網格、沿用復原骨架與動畫的改造原型，貼圖也以原圖集作為生成參考；並非已完成所有來源替換的原創資產。分支名稱或新生成貼圖不代表取得來源素材授權。後續仍可依遊戲距離調整輪廓、接縫與動作質感。
