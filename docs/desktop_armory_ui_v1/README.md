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

實作集中在 `scripts/ui/recovered_armory_skin.gd`；`unity_equipment_shell.gd` 的桌面背景建構時啟用。手機子類覆寫背景與布局，共享細節區依此旗標保留手機樣式。

2026-10-03：商店樣式延伸至設定、一般彈窗、關卡選擇，以及進入房間後的暫停／結算選單。外層主菜單與商店保留先前的外觀和專用按鈕；只有內部彈窗使用 `make_theme(true)`，預設的 `make_theme()` 保持原商店 theme。

設定的滑桿、開關、名稱輸入與下拉選單共用現有圖集，無需新增點陣素材。手機 AMMO 彈窗的 OK 按鈕以樣式內距維持至少 44 px 點擊高度，避免 `AcceptDialog` 排版時重設自訂最小尺寸。同時修正補給頁切回裝備頁時，可見性回呼讀到舊補給 ID 的問題；不改購買或裝備規則。

房間內暫停選單的「重新進入競技場／重啟區域」改為「選項」，提供低／中／高畫質並立即保存與套用。更新既有 viewport、陰影、場景效果及 lightmap 光照參數，保留原場景的霧設定，不重建房間或重置玩家與分數。返回按鈕回到暫停選單；Esc 或系統返回依序關閉畫質下拉選單、選項頁，最後才繼續遊戲。結算頁的重試功能保留。

房間內選項分為「畫面、音效、操作、語言」四頁，新增音樂／音效音量與百分比、視角靈敏度、反轉 Y 軸、行動觸控開關及中英文切換，全部使用既有存檔設定。語言切換會更新選項與暫停文字，保留同一場景與 UI 節點。觸控開關放入操作頁，省去暫停頁的重複入口。

下拉選單改用自製 16×16 SVG 青色勾勾表示目前套用值；游標／手把焦點仍使用商店金屬高亮，未選項保留同尺寸透明位置以維持文字對齊。只調整 `style_picker()` 的下拉標示；預設商店 theme 保留原樣。SVG 來源為 `assets/ui/components/dropdown_check*.svg`，`.import` 由 Godot 產生。

手把 Start 開啟暫停後預選「繼續」，方向鍵與 A 可開啟選項；B 沿下拉選單、選項、暫停的順序返回。進入暫停或結算會釋放兩個觸控搖桿並清除尚未處理的觸控射擊、移動、換彈與衝刺輸入。搖桿在暫停或父節點隱藏時不接受新觸控，仍處理既有手指的放開事件。

`pause_options_test` 在 PvP 13 與單人 1 驗證實際點擊、畫質儲存、返回層級及暫停期間進度不變；`live_quality_test` 驗證畫質往返時同一組場景與材質即時更新。可用 `tests/pause_options_test.tscn -- --capture --locale=zh_TW` 取得實際 GPU 畫面，輸出至 `test_output/pause_options/`。

四頁版本驗證：`in_game_options_test` headless PASS 80 checks，實際滑鼠驗證音量 bus、瞄準反應、觸控開關、中英文即時切換與重開保留值，原玩家存檔 SHA256 未變。`pause_options_test` 最終 Compatibility GPU 四輪皆 PASS：中文滑鼠、手把，以及 844×390 中文／640×360 英文觸控模擬，每輪含兩種模式與四頁，共 12 張圖。保留生產 `canvas_items` 拉伸與邏輯畫布，已檢視完整面板、文字與勾選標示；輸出位於 `test_output/pause_options_v2/`。Android／iOS 實機未執行。

Godot 4.7.2 的現有 `ui_accept` 未含手把按鍵，已在既有輸入建構流程加上 A 確認／B 返回，保留鍵盤設定。測試送滑鼠移動後再點擊，讓原生 GPU 視窗的游標命中位置與合成輸入一致；面板邊界只檢查外層置中的面板，排除原生下拉視窗的內部面板。

本輪 `menu_equipment_test`、`desktop_armory_ui_test`、`mobile_store_sw1_test`、`mobile_customize_sw1_test`、`equipment_upgrade_ui_test` 與煙霧測試均 PASS。Compatibility / OpenGL、1280 × 720 實際截圖確認設定、暫停與勝負結算文字清楚；手機彈窗的確認按鈕可正常關閉。商店及導覽抽屜與修改前的參考圖逐像素相同，主菜單底部按鈕區域也相同；標題差異來自進場動畫的拍攝時間。截圖與參考比對記錄位於 `test_output/ui_unified/`，不改原商店展示頁的圖片。Harness integrity PASS；該檢查不代表應用測試。

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
