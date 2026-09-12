# Viper 原版裝甲細修

本次以原版 Viper 網格為基底，保留紫色面罩、盔框、胸甲分件、肩甲、四肢和原本比例；參考 `068f4785eee8542217b2e0a3ab4f72b16056f5bf` 的 v2 概念圖改善表面質感。已接入遊戲、商店預覽與換裝系統。本次是 **Viper 一套樣板**；其餘 28 套尚未替換。

| 原版 | 細修版 |
| --- | --- |
| ![原版](original.png) | ![細修版](refined.png) |

## 修改內容

| 項目 | 實作與依據 |
| --- | --- |
| 模型 | 直接使用 `player.gltf` 的 `ArmorHead_00`、`ArmorBody_00`、`ArmorHand_00`、`ArmorFoot_00`，修整既有銳邊；維持原 UV 分區與關節位置 |
| 貼圖 | 使用內建 image_gen 逐張細修原 UV 圖，共頭、身、肩、手、腿五張；實際輸出均為 1254 × 1254 |
| 材質 | 保留原手繪明暗的主要貢獻，加少量實際光源反應，避免暗地圖中變黑或產生過強塑膠高光 |
| 骨骼 | 沿用原 28 個骨骼綁定名稱；新增邊緣頂點的權重先排除插值產生的負值，再正規化 |
| 換裝 | 保留四個部位名稱、商品 ID、混搭與原動作；遊戲和商店共用 `armor_visuals.gd` 載入細修資產 |
| 可編輯來源 | `viper.blend`；製作腳本在 `tools/armor_rework/` |

材質的 `ALBEDO = paint × 0.25`、`EMISSION = paint × 0.75` 是維持原手繪風格的美術取捨。後者提供不受場景光源影響的底色，不代表整套裝甲在世界中發光或照亮其他物件。

| 部位 | 原三角形 | 細修三角形 | 外框尺寸最大變化 |
| --- | ---: | ---: | ---: |
| 頭 | 136 | 578 | 0.271 mm |
| 身／肩 | 298 | 1294 | 0.819 mm |
| 手 | 112 | 584 | 0.520 mm |
| 腿 | 136 | 856 | 1.179 mm |
| 合計 | 682 | 3312 | — |

以上數值讀取實際網格；外框變化比較各軸的最小／最大位置，不是所有表面的最大誤差，也不是效能量測。詳見 `assets/armors/viper/build_report.json`。

## 預覽與重建

[離線 HTML 動作比較](../../../test_output/armor_rework/index.html) 包含原版／細修轉台、FR28a 三套和 RPG-21 兩套換彈、跑步／飛行姿勢及兩張實際地圖。HTML 與完整逐格畫面位於忽略的 test_output；本目錄保留四張可隨 commit 查看之截圖。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python-exit-code 1 --python tools/armor_rework/build_viper.py
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --editor --quit
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/armor_rework/compile_viper.gd
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/viper_art_capture.tscn
python tools/armor_rework/build_preview.py
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://tools/render_armor_thumbnails.gd -- --set-id=0
```

建模腳本只在 test_output 的暫存匯入檔移除 Blender 不支援的 `KHR_node_visibility`；不修改原 `player.gltf`。原始網格保留在原路徑。

五張貼圖的可重用生成提示、輸入參考與輸出路徑見 [texture_prompts.json](texture_prompts.json)；提示文字經整理，不是原始工具呼叫逐字紀錄。頭、身、肩以各自原 UV 圖作編輯輸入；手、腿另附 v2 Viper 概念圖作表面質感參考。生成圖仍需在原 UV 上逐視角檢查；不能把圖片生成成功當成對位正確。

## 驗證紀錄

使用 Godot 4.7.2，Compatibility renderer；展示圖為 800 × 900，實際地圖截圖為 1280 × 720。

| 檢查 | 結果 |
| --- | --- |
| Viper 網格／權重／混搭／材質 | PASS |
| 裝甲系統／商店／持槍／步槍與火箭筒換彈／鏡頭 | PASS |
| 全武器換彈斷言／跑動與飛行換彈斷言 | PASS；headless 日誌另有 null material 訊息 |
| 遊戲 smoke／設定 | PASS |
| 原版／新版擷取、四張商品縮圖 | PASS |
| HTML 切換六種檢視、播放暫停、拖曳、放大 | PASS |
| harness 生成文件同步 | FAIL；既有生成文件不同步 |

- `viper_armor_test`：檢查四部位、骨骼反向綁定、權重、法線、反覆換裝、混搭與材質恢復。
- `menu_equipment_test`：商店保留原裝甲材質，Viper 使用自己的細修材質。
- `reload_catalog_test`／`reload_catalog_running_test`：檢查持槍和換彈行為，另以擷取圖檢視新版裝甲。
- 本次目視範圍包含前、側、背、步槍／火箭筒裝填及兩張地圖。沒有宣稱所有裝甲組合或所有武器都已逐格完成穿模驗收。
- 測試退出仍可能有 ObjectDB／RID 資源清理訊息；部分全武器 headless 測試另有 dummy renderer 的 null material 訊息。應用斷言結果和這些訊息分開記錄。
- `.harness/verify.py` 的生成文件同步檢查未通過；本次未修改 harness 政策與入口文件。

後續其他套裝也應以各自原模型和辨識特徵為底，逐套細修，不沿用另一套裝甲的輪廓。
