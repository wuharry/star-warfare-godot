# 原版裝備細修

已將 Viper 的原版細修方向套用到其餘 **28 套裝甲、47 把武器**。保留原比例、配色、輪廓和辨識特徵，整理既有貼圖及小幅修整模型銳邊。遊戲、裝備頁、商店及換彈拆件均使用新資源；Viper 維持既有版本。

參考：Viper `415d800`；概念方向 `068f4785eee8542217b2e0a3ab4f72b16056f5bf`。概念只輔助細修，原版辨識特徵優先。

## 交付與比較

- [75 件裝備對應表](EQUIPMENT_REFINEMENT_TABLE.md)
- [離線 HTML 比較](../../test_output/equipment_refinement/preview/index.html)：75 件裝備，每件提供原版／細修版正面、側面、背面，共 450 張比較圖；另有 12 張移動換彈與 6 張實際關卡截圖。支援分類、逐件切換、表格跳轉與放大。
- `assets/equipment_refined/manifest.json`：逐張来源、提示文字、採用結果與逐件檢視紀錄。`approved` 表示製作端目視檢查通過，並不代表使用者已驗收美術。提示文字包含整理後的可重用版本；本機生成快取路徑只用於追溯，遊戲不依賴該路徑。

160 張貼圖使用內建 image_gen 依原 UV 圖細修。12 張特效遮罩沿用原圖；`gun_17.png` 保留原生 2048×2048 圖，因生成候選只有 1254×1254，不採用會降低解析度的候選。其使用者包括 LG002B、WHITE DRILL。來源素材沒有被覆寫。

WHITE DRILL 與 Spreader 原 OBJ 材質漏掉 Unity 的主貼圖／發光疊圖，本次從原 Unity 專案補回。WHITE DRILL 使用原 2048 圖與原發光遮罩，Spreader 使用細修主圖和原發光遮罩。HTML 原版側也補回正確材質，便於比較美術細修本身。

## 模型與材質

28 個裝甲場景保留原 MeshInstance 名稱、Skin、節點變換、UV 和骨骼。47 把武器共 85 個完整／拆分網格。只對封閉面之間的既有銳邊做小幅倒角：装甲約 0.002 原模型單位、手部約 0.0012，武器約最長邊的 0.12%。材質切口、換彈接縫、布料四肢及特效面保留；若尖角產生過大偏移則保留該面的原幾何。

新增頂點插值原 UV、法線、頂點色和骨骼權重，維持最多四個有效權重並正規化。全部 197 個網格的三角面合計由 54,229 增至 235,723；這包含完整武器與拆件，並非單次繪製面數。逐面報告見 `assets/equipment_refined/mesh_report.json`。尚未進行手機實機效能量測。

武器顯示尺寸、彈匣定位和碰撞盒使用原始外框，避免微小倒角改變裝配位置。`ArrayMesh.custom_aabb` 保存原尺寸，執行時由 `EquipmentRefinement.authored_bounds` 取得。完整槍身與換彈零件共用相同貼圖對應。

裝甲材質保留原本的雙面顯示、頭盔色調和重複 UV；Black Hole 的負 UV／跨格 UV 也正確重複取樣。Legacy 裝甲使用偏手繪的低反光材質，Call of Mini 裝甲沿用原 unshaded 表現。武器維持既有特效材質並降低金屬鏡面感。特殊武器共用不可變疊圖材質，避免快速切槍時材質提早釋放造成渲染錯誤。

## 驗證

- `equipment_refinement_test`：28 套裝甲、85 個武器網格；幾何數值、法線、UV、骨骼權重、待機／跑步／換彈形變外框、材質對應及特殊武器雙貼圖。
- `reload_system_test`：換彈流程、原模型拆件、FR28a 分段動作。
- `reload_catalog_test`：24 把可裝填武器、55 種既有隨機動作；亦以實際 OpenGL 渲染後端通過。
- `weapon_pose_test`：47 把武器、11 組持槍姿勢及雙手定位。
- `callofmini_gameplay_test`：8 套裝甲、32 個部位、混搭與動畫。
- `menu_equipment_test`：6 個頁籤、141 個裝甲／背包項目、47 把武器。

上述檢查通過。逐套裝甲正／側／背面與全部武器正面比較已目視檢查；另檢查四組移動換彈及兩個關卡中的三組配裝。部分舊測試退出時仍回報資源清理警告；舊 OBJ 快取也有可回退到文字路徑的 UID 警告。這些與腳本解析或測試斷言失敗不同，未宣稱整個專案零警告。

## 重建與預覽

資產與工具納入版本控制；大型比較截圖位於忽略追蹤的 `test_output`，可用以下命令重建。已接受的貼圖保存在專案中，無須重新生成。

```powershell
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/equipment_refinement_capture.tscn
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tests/equipment_game_capture.tscn
python tools/equipment_refinement/build_preview.py
```

若要重新計算模型，依序執行 `export_sources.gd`、Blender `refine_meshes.py`、Godot `compile_assets.gd`；沿用現有 manifest，勿以初始化清單覆蓋已完成的檢視紀錄。`configure_imports.gd` 設定細修圖的 mipmap 與 VRAM 壓縮，之後需再跑編輯器匯入。Windows／Android 匯出設定已包含執行時需要的貼圖映射 manifest；本次未產生新的平台發行包。
