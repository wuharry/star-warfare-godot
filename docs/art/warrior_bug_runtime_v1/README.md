# 兵蟲概念圖 → 遊戲模型：甲片結構與手繪細節

本輪處理「與原版精細度差太多」的回饋：上一版只有基本形體、分區漸層和通用甲殼細紋，缺少能在遊戲距離看清楚的甲片明暗與關節結構。現在改用六區域手繪貼圖，重做尖形覆蓋式腿甲，並補強頭罩折面。[index.html](index.html) 提供上一版與這一版的側面、頭部對照，也保留原版模型作為品質比較依據。

| 本輪修正 | 做法 |
| --- | --- |
| 所有部位共用細紋，缺少結構明暗 | 新增六區域手繪 atlas（把各部位的貼圖放在同一張圖片），UV 分別取用頭罩、腹甲、腿甲、刀刃、臉甲與關節區域 |
| 新貼圖細節會被舊材質壓平 | `chitin_palette.gdshader` 保留貼圖的 RGB 顏色與明暗，只混入少量既有頂點底色 |
| 腿部像光滑管件 | 改為上下覆蓋的尖形甲片、外向中央稜線、窄深色關節及短皺褶；保留骨點、原站姿和足尖位置 |
| 頭罩大面過於平整 | 補強中央脊與折面，配合頭罩專用貼圖；保留上一輪已加寬、加高並前移的頭部比例 |

本輪新增 `warrior_anatomy_v4.png`，依既有概念圖的紅褐、暗紫與赭金方向生成，使用 [warrior_anatomy_v4.txt](prompts/warrior_anatomy_v4.txt) 的完整提示詞。貼圖包含甲片邊緣高光、接縫陰影及關節皺褶；[detail_record.json](detail_record.json) 記錄本輪來源與修改。[palette_record.json](palette_record.json) 和 [polish_record.json](polish_record.json) 僅作歷史紀錄，不代表本輪驗證結果。

| 歷史階段 | 當時改動 | 追溯資料 |
| --- | --- | --- |
| 初次接入遊戲 | 以原圖集為參考製作貼圖，接入模型替換流程 | [generation_record.json](generation_record.json) |
| 結構改造 | 拱形頭罩、嵌入式六眼、向下彎的大顎、頰甲與喉甲、曲刃；改用通用甲殼紋理 | [polish_record.json](polish_record.json) |
| 配色與頭部比例 | 分區頂點上色，頭部加寬 14%、加高 12%、加深 4%，作者座標向前 0.10 | [palette_record.json](palette_record.json) |

## 對應與製作範圍

| 項目 | 對應 |
| --- | --- |
| 遊戲種類 | `crawler` |
| 復原來源 | `Monster ID 0 / bug01 / Warrior` |
| 概念依據 | [01_mantis_turnaround.jpg](../enemy_art/images/warrior_bug_concept__images__01_mantis_turnaround.jpg) |
| 原模型 | `assets/models/enemies/animated/bug01/bug01.gltf` |
| 本版模型 | `assets/models/enemies/concept/warrior/warrior.gltf` |
| 本版貼圖 | `assets/models/enemies/concept/warrior/warrior_anatomy_v4.png` |
| 貼圖實際尺寸 | 1024 × 1536；2 欄 × 3 列，共 6 個部位區域 |
| 模型實際規模 | 7,554 頂點／13,024 三角形／1 蒙皮網格／5 材質 |
| 骨架 | 原 22 骨 + 鐮臂 6 骨 + 大顎 2 骨，共 30 骨 |
| 動畫 | 原 8 段全部保留，新增骨另補動作；30 FPS 匯出保留原片段時長 |
| 載入位置 | `MonsterCatalog.visual_scene_path()` → `WarfareEnemy._build_visual()` |

概念圖提供紅褐甲殼、紫色甲縫、六顆綠眼、高頭罩、雙鐮臂與四條步足。本輪 imagegen 貼圖把甲殼與關節分成六個區域，模型重新配置 UV 對應取樣。眼睛、口器、刀刃與紫色紋路仍由模型部件決定；手繪貼圖補足甲片明暗。較早的 `warrior_albedo_v1.png` 與 `warrior_chitin_v2.png` 保留追溯，已不被目前模型引用。

```text
原模型的骨架與四足動畫 ─────┐
既有兵蟲概念圖 ────────────┼→ 改造模型 + 專用貼圖 + 新增骨骼動畫
六區域手繪貼圖＋分區 UV ──┘           ↓
                          warrior.gltf / warrior.bin / warrior_anatomy_v4.png
                                      ↓
                          crawler 的正常生成、命中與死亡流程
```

原有血量、傷害、速度、獎勵、存檔種類和 AI 繼續由既有遊戲資料控制。本版新增的部位使用同一套蒙皮與傷害碰撞流程，沒有新增弱點倍率或新攻擊規則。

## 如何在遊戲內看

正常第一關產生的 `crawler` 會優先載入這版模型。其他種類仍載入原模型。比較場景會同時建立原版與新版，將原版實例的 `use_concept_visuals` 設成 `false`；此值必須在節點加入 SceneTree 前設定。

```powershell
# 首次拉取資產後，先取回 LFS 並匯入。已追蹤的匯入設定會自動套用手繪貼圖 shader。
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

匯入時 `tools/enemy_concept/import_warrior.gd` 替換指定的甲殼與深色關節材質，遊戲和編輯器使用同一 shader。若遺失匯入設定，先用 Godot `--headless --path . --script tools/enemy_concept/configure_import.gd` 恢復，再重建及匯入模型。這個設定程式使用 Godot 的 ConfigFile API；不手工改寫 `.import`。新 atlas 啟用 mipmaps（縮小觀看時使用較小的貼圖版本）及 3D 壓縮，減少細亮邊在遊戲距離產生的閃點。

來源與貼圖以唯讀輸入使用。建置檢查貼圖 SHA256、材質貼圖宣告、動畫名稱及時長，失敗會退出非零；診斷 `.blend` 與完整 `build_report.json` 寫入 `test_output/enemy_concept_runtime/model_build/`。重建後仍需重新匯入 Godot 並跑測試。

## 視覺取捨

本輪把可辨識的輪廓與貼圖明暗一起修改：尖形腿甲、中央稜線與頭罩折面由實際網格形成，較小的甲片起伏、邊緣亮線和接縫陰影由手繪貼圖表達。因原關卡主要使用烘焙背景照明，材質保留跟隨貼圖顏色的最低亮度，讓暗處仍可辨識；沒有修改關卡燈光。

待機總高度沿用 `crawler` 的 2 m 規格，包含高舉的鐮臂，因此軀幹比原版低。四足仍用原動畫，側面仍偏蹲，腿部比例和動作質感有後續調整空間。這一版不宣稱已達原版精細度；還需檢查遊戲距離的輪廓、貼圖對位及整體美術風格。未做大量敵人效能基準測試，不宣稱面數增加沒有成本。

## 實際驗證

| 檢查 | 結果 |
| --- | --- |
| 模型重建與素材實際載入 | PASS：新模型、六格 atlas 與骨骼載入通過專用場景檢查 |
| Godot editor 匯入 | 完成、exit 0；log 有 1 條其他目錄掃描錯誤，詳見下文 |
| 兵蟲專用場景 | PASS：128 checks、27 條射線，包含六格 atlas 載入 |
| 既有敵人動畫 | PASS：4 種敵人 |
| 遠近命中範圍 | PASS：209 checks |
| 命中與音效 | NOT RUN：本輪未重跑 |
| 遊戲 smoke test | NOT RUN：本輪未重跑 |
| Godot 畫面擷取 | PASS：21 張，1280 × 720、GL Compatibility；已檢視啟用 mipmaps 後的側面與頭部 |
| 比較頁檔案與 JavaScript 檢查 | PASS：35 個本機引用均存在，包含姿勢及頭部切換圖片；`node --check` 通過 |
| 比較頁瀏覽器驗證 | NOT RUN：尚未執行 |
| harness 同步檢查 | FAIL：原有 13 項 generated drift，本輪未修改 harness 檔案 |
| 大量敵人效能測量 | NOT RUN |

本輪驗證結果以 [validation.json](validation.json) 與 [validation_logs/](validation_logs/) 為準，不以歷史 PASS 代替。[capture_manifest.json](capture_manifest.json) 記錄每張截圖的姿勢、實際場景路徑及 SHA256。

Godot editor 匯入雖完成，但兩次 log 都出現 `ERROR: Cannot go into subdir 'audio-missing-archive-tfpon_0v'.`，屬於音效工作目錄的掃描錯誤，本輪未處理。兵蟲的新模型與貼圖另由實際載入測試確認通過。

這輪的前後對照使用 `detail_v3_*` 保存修改前畫面，`after_*` 顯示最新模型。頭部近景都用尺度 1.40、焦點 [0,0.94,-0.57]；全身原版／新版比較仍使用同一光線、尺度與姿勢時間。較早的 `palette_v2_*` 與 `prototype_v1_*` 只作歷史參考。程式測試通過不能替代美術驗收，也不代表使用者已接受造型。

## 素材來源與限制

[本輪細節紀錄](detail_record.json)與[六區域貼圖提示詞](prompts/warrior_anatomy_v4.txt)記錄新 atlas；[歷史結構精修紀錄](polish_record.json)、[當時初稿提示詞](prompts/warrior_chitin_v2.txt)、[當時修訂提示詞](prompts/warrior_chitin_v2_refine.txt)保留上一版紋理的生成來源。[第一版紀錄](generation_record.json)保留原圖集參考的歷史，不改寫成新 atlas 的生成來源。

這是新建網格、沿用復原骨架與四足動畫的改造原型。新貼圖和新甲片不會自動改善原四足動作；動作質感及最終美術品質仍需後續調整與驗收。
