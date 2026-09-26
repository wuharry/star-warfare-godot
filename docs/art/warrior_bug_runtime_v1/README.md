# 兵蟲概念圖 → 遊戲模型：頭部與甲殼精修

本輪依照「頭部與草稿差太多、模型太粗糙」的回饋，重建頭罩、臉甲與大顎，並替換甲殼貼圖。已套用到正常遊戲生成的兵蟲；[index.html](index.html) 最前方提供精修前後的正面、側面與斜角近景。

| 部位 | 原型問題 | 本輪改動 |
| --- | --- | --- |
| 頭罩與臉 | 封閉尖殼前面接一片圓盤 | 有厚度的拱形頭罩，包住收尖的曲面臉甲 |
| 六眼 | 直列凸起，像外掛零件 | 改為兩組三眼，嵌入眼窩；移除黑色長瞳孔 |
| 大顎與口器 | 側面向前伸得太長 | 寬顎根接兩頰，向下、向內彎；中央保留短口器 |
| 頸部、胸腹 | 大片球狀關節外露 | 增加頰甲、喉甲、胸甲，背甲向兩側包覆 |
| 鐮刃與材質 | 折線硬、原圖集亮邊被拉長 | 增加曲線取樣與實體刃面，改用乾淨甲殼色彩貼圖 |

## 對應與製作範圍

| 項目 | 對應 |
| --- | --- |
| 遊戲種類 | `crawler` |
| 復原來源 | `Monster ID 0 / bug01 / Warrior` |
| 概念依據 | [01_mantis_turnaround.jpg](../enemy_art/images/warrior_bug_concept__images__01_mantis_turnaround.jpg) |
| 原模型 | `assets/models/enemies/animated/bug01/bug01.gltf` |
| 本版模型 | `assets/models/enemies/concept/warrior/warrior.gltf` |
| 本版貼圖 | `assets/models/enemies/concept/warrior/warrior_chitin_v2.png` |
| 貼圖實際尺寸 | 1254 × 1254；保留 imagegen 原始輸出 |
| 模型實際規模 | 6,554 頂點／10,912 三角形／1 蒙皮網格／5 材質 |
| 骨架 | 原 22 骨 + 鐮臂 6 骨 + 大顎 2 骨，共 30 骨 |
| 動畫 | 原 8 段全部保留，新增骨另補動作；30 FPS 匯出保留原片段時長 |
| 載入位置 | `MonsterCatalog.visual_scene_path()` → `WarfareEnemy._build_visual()` |

概念圖提供紅褐甲殼、紫色甲縫、六顆綠眼、高頭罩、雙鐮臂與四條步足。本輪使用 imagegen，先依概念圖生成純甲殼材質，再降低過密刮痕。新網格重新配置 UV；刃口、眼窩與紫色紋路由模型位置決定，避免原圖集的亮邊被拉到不相干的部位。第一版貼圖仍保留供追溯，已不被目前模型引用。

```text
原模型的骨架與四足動畫 ─────┐
既有兵蟲概念圖 ────────────┼→ 改造模型 + 專用貼圖 + 新增骨骼動畫
imagegen 生成的甲殼色彩 ───┘           ↓
                          warrior.gltf / warrior.bin / warrior_chitin_v2.png
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

擷取預設輸出 21 張畫面，包含三個頭部近景；加 `-- --art-only` 可略過第一關，輸出 20 張。刪除比較場景後只等待場景清理，不等待已無相機可繪製的 `frame_post_draw`，避免擷取卡在兩個場景之間。

## 如何重建模型

`build_warrior.py` 讀取來源 glTF 與已生成的 PNG，在原骨架的待機姿勢建立新網格，再轉回骨骼的基準位置。它會輸出同資料夾的 glTF／bin；貼圖必須已存在，程式不會再次呼叫 imagegen。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --python-exit-code 1 --python tools/enemy_concept/build_warrior.py
```

來源與貼圖以唯讀輸入使用。建置檢查貼圖 SHA256、材質貼圖宣告、動畫名稱及時長，失敗會退出非零；診斷 `.blend` 與完整 `build_report.json` 寫入 `test_output/enemy_concept_runtime/model_build/`。重建後仍需重新匯入 Godot 並跑測試。

## 視覺取捨

頭罩、眼群、大顎與刃面以實際網格修形；甲殼貼圖只提供表面色彩和細微紋理。因原關卡主要使用烘焙背景照明，甲殼材質保留隨貼圖顏色的低強度發光，讓暗處仍可辨識；沒有修改關卡燈光。

待機總高度沿用 `crawler` 的 2 m 規格，包含高舉的鐮臂，因此軀幹比原版低。四足仍用原動畫，腿部比例和動作質感有後續調整空間。網格增加用於頭罩曲面、彎顎、曲刃與分節甲殼；未做大量敵人效能基準測試，不宣稱面數增加沒有成本。

## 實際驗證

| 檢查 | 結果 |
| --- | --- |
| 兵蟲專用場景 | PASS：126 checks，27 條射線，確認真正載入新模型／貼圖及 8 根新骨 |
| 既有敵人動畫 | 4 種敵人斷言 PASS；首次退出有資源警告，單獨 verbose 複驗 PASS 且無警告 |
| 遠近命中範圍 | PASS：209 checks |
| 命中與音效 | PASS：4 種敵人 |
| 遊戲 smoke test | PASS |
| Godot 畫面擷取 | PASS：21 張，1280 × 720，GL Compatibility |
| 比較頁檔案檢查 | PASS：31 個本機引用，含 8 組姿勢與 3 組頭部圖片 |
| 比較頁瀏覽器驗證 | NOT RUN：自動化啟動遭 policy 拒絕，computer-use 沒有可用瀏覽器 |
| harness 同步檢查 | FAIL：原有 13 項 generated drift，本次沒有修改 harness 檔案 |
| 大量敵人效能測量 | NOT RUN |

本輪結果收錄於 [validation.json](validation.json) 與 [validation_logs/](validation_logs/)；[capture_manifest.json](capture_manifest.json) 記錄每張截圖的姿勢、實際場景路徑及 SHA256。頭部歷史近景保留第一版鏡頭尺度 1.22；本輪尺度 1.40，鏡頭稍下移，以包含完整顎尖。全身原版／新版比較仍使用同一光線、尺度與姿勢時間。

助理檢視範圍包含頭部三方向、待機、跑步、攻擊、死亡與第一關。這些畫面可供使用者評估美術，測試通過不代表使用者已接受造型。

## 素材來源與限制

[本輪紀錄](polish_record.json)與[初稿提示詞](prompts/warrior_chitin_v2.txt)、[修訂提示詞](prompts/warrior_chitin_v2_refine.txt)保留兩次內建 imagegen 的來源和採用情況。實際輸出保留工具原尺寸，沒有修圖。[第一版紀錄](generation_record.json)保留原圖集參考的歷史，不改寫成新貼圖的生成來源。

這是新建網格、沿用復原骨架與動畫的改造原型。本輪色彩貼圖僅以概念圖和本輪初稿為參考，但骨架與既有動畫仍未替換；分支名稱或新貼圖不代表取得來源素材授權。
