# 電腦版商店 UI：SW1 / Call of Mini

電腦版商店與裝備頁使用已提取的原作美術，修正過粗邊框及按鈕切角破圖，補齊下拉選單、捲軸、提示框與鍵盤焦點樣式。互動截圖見 [index.html](index.html)。

## 修正原因

- 數值條改為三種亮度：基準區段用正常實色，減少區段用暗色，增加區段用亮色。既有素材的 `_fill` 是半透明、`_loss` 是不透明實色，因此依實際亮度重新對應，保留原始 PNG。HP／POW／SPD 與手機共用這個修正。
- 先前直接把高解析原圖的切片寬度當成畫面寬度，造成外框過粗；切片落在按鈕斜角內，縮放時產生尖刺。
- `ImageTexture.set_size_override()` 只改變繪圖邏輯尺寸，保留原始像素。SW1 面板為 1/4 尺寸、14 px 切片；CoM 小按鈕為 1/2 尺寸、8 px 切片，涵蓋完整切角。面板的 14 px 是完整角落區域，並非 14 px 粗線。
- 一般按鈕與商品卡採深藍灰色調，選取／滑過為青藍色；使用原始高光與邊緣，沒有新增平面色塊外框。
- 縮窄視窗時，`ScrollContainer.SCROLL_MODE_DISABLED` 會保留舊商品格的最小寬度。改為 `SCROLL_MODE_SHOW_NEVER`，讓商品格依可用寬度重排；測試確認所有商品卡的水平邊界均在欄內。

## 素材來源與範圍

| 素材 | 權威來源 | 用途 |
| --- | --- | --- |
| `assets/ui/components/armory_detail_panel.png` | SW1 原始 resUI 模組，既有提取工具組合 | 商品／詳情／選單／提示外框 |
| `assets/ui/components/armory_nav_bar.png` | SW1 NavigationMenuUI 模組 | 頁首斜紋，避開手機貨幣圖示 |
| `assets/recovered_sources/com/ui/CommonUI.png` | CoM 原始 CommonUI 圖集，既有提取檔 | 小按鈕、箭頭、選取標記、捲軸、分隔線 |
| `assets/recovered_sources/com/ui/CommonUI.json` | `test_output/source_reconstruction/com/text/CommonUI_cfg__sharedassets18.assets_11.bytes` | 本次新增 87 個命名區域及來源 SHA-256 |

原始 PNG 未修改。CommonUI 座標直接使用此 2048 × 2048 圖集的像素座標，不能套用 SW1 `OriginalAtlas` 的雙倍座標換算。

實作集中在 `scripts/ui/recovered_armory_skin.gd`；`unity_equipment_shell.gd` 的桌面背景建構時啟用。手機子類覆寫背景與布局，未啟用桌面 skin。共享細節區依此旗標保留手機樣式。

保留既有購買、所有權、裝備欄位及資料。這是桌面尺寸的原作素材改造，並非宣稱 CoM / SW1 手機布局的 1:1 桌面移植。

## 實際驗證

| 檢查 | 結果 |
| --- | --- |
| `desktop_armory_ui_test` GPU 互動與十三張截圖 | PASS；stderr 空白；新增基準／數值增加／數值減少三個案例 |
| 下拉選單鍵盤確認、Esc、點擊外部取消、箭頭方向 | PASS |
| 實際購買與最後一個欄位裝備、其他欄位保留 | PASS；隔離存檔 |
| 縮窄畫布，商品卡不溢出；底部選單可見 | PASS |
| `menu_equipment_test` | PASS；6 類別、141 裝甲項目、47 武器 |
| `mobile_store_sw1_test` | PASS |
| `mobile_customize_sw1_test` | PASS |
| Godot 編輯器 headless import | PASS |
| Harness | FAIL：既有 generated drift；未改政策檔或基準 |
| Android / iOS 實機、打包版本 | NOT RUN |

GPU：Godot 4.7.2 Compatibility / OpenGL 3.3，NVIDIA RTX 4080 Laptop GPU。截圖檢視包含一般／展開／選取／停用狀態、寬窄尺寸、裝甲與補給。自動測試驗證互動與邊界，美術偏好仍由使用者驗收。

## 重現

```powershell
python tools/ui_extractor/extract_com_common_ui.py
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/menu_equipment_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_store_sw1_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_customize_sw1_test.tscn
# 以下需 GPU；測試自行建立截圖目錄，使用隔離存檔。
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . res://tests/desktop_armory_ui_test.tscn -- --capture
```

截圖位於 `test_output/desktop_armory_ui/`，報告內 `captures/` 為同一批原尺寸輸出副本。

Theme API 依據：Godot 官方 [PopupMenu](https://docs.godotengine.org/en/stable/classes/class_popupmenu.html)、[OptionButton](https://docs.godotengine.org/en/stable/classes/class_optionbutton.html)、[ScrollBar](https://docs.godotengine.org/en/stable/classes/class_scrollbar.html)。
