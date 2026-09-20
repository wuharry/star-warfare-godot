# 手機版 SW1 商店還原

裝備頁已另行還原：請看 [CUSTOMIZE / PACKAGE 最新實際畫面](../mobile_customize_sw1/index.html)。本頁較早的 EQUIP 截圖保留作為商店階段紀錄。

手機商店使用 SW1 的原始 960 × 640 版面、中央持槍角色、橫向裝備／分類滑動與直向道具頁。桌面繼續使用原本的 `UnityEquipmentShell` 商品格；沒有改動該檔案。

## 資料流與邊界

```text
Android / iOS / 測試 force_mobile_ui
  → MainMenu 選用 MobileSW1EquipmentShell
  → SW1StoreScroller 捕捉單指、慣性與停靠
  → 暫存各分類預覽選擇 → 角色、商品說明與整套比較
  → 按 BUY / EQUIP → 既有 GameState 交易 → 存檔及訊號
Desktop → 原本 UnityEquipmentShell
```

瀏覽不會購買或裝備。整套 CoM 裝甲的授予、價格、階級、存檔仍由既有 GameState 負責。修改範圍沒有新增升級倍率或付費共用能量，也沒有改動戰鬥數據。

## 原始依據

- 原始碼：`E:/Star-Warfare-1.0.2/Assets/Scripts/Assembly-CSharp/` 的 `StoreUI.cs`、`UIScroller.cs`、`UISliderTag.cs`、`UISliderAvatar.cs`、`PropsStoreUI.cs`、`UISliderProps.cs`、`NavigationBarUI.cs`、`NavigationMenuUI.cs`、`UIAvatar3D.cs`、`ShopAndCustomize.cs`、`UnitUI.cs`。
- `Assets/Resources/ui/resUI.bytes` 與此次 SW1 3.01 APK 抽出的同名 TextAsset 位元組一致。SHA-256：`4e4483438b125cb0e7e63fcf74be1e5d34f026d908cbf6a20f2d927252b36dbf`。
- `tools/ui_extractor/extract_mobile_store_layout.py` 讀取 binary，檢查每個 UI unit 的結束位置等於下一個 unit 的起點，產生可隨遊戲匯出的 GDScript 常數。商品原文來自 `res.bytes` 的 `strGameDatas`，不是重新撰寫的介紹。
- Unity 的左下原點轉為 Godot 左上原點：`x = anim.x + module.x + 480`；`y = 320 + anim.y + module.y - height`。

| 控制項 | SW1 資料 | Godot 邏輯座標／規則 |
|---|---|---|
| 分類滑動範圍 | vUI[11] module 2 | (177, 494, 450, 99)，循環，間隔 90 |
| 裝備滑動範圍 | StoreUI.SetAvatar | 寬 600、高 135、間隔 120；高度跟隨預覽部位 |
| 商品名稱 | vUI[11] module 52 | (726, 248, 188, 21) |
| 解鎖／狀態 | vUI[11] module 53 | (715, 274, 212, 22) |
| 說明 | vUI[11] module 50 | (714, 386, 212, 136) |
| 購買 | vUI[11] module 19 | (747, 526, 150, 58) |
| 價格 | vUI[11] module 58 | (756, 529, 129, 24) |
| 比較條 | vUI[11] module 30/34/38 | x=712，y=126/166/206，214×12 |
| 道具滑動範圍 | vUI[13] module 2 | (275, 107, 685, 450)，有邊界，間隔 150 |
| 頂部導覽 | vUI[19]、NavigationBarUI | 返回、標題、秘銀／金錢／能量圖示 |
| 軍階下拉選單 | NavigationMenuUI | 重用已有原版導覽選單，在手機商店上方開啟 |

滑動依原碼的速度上限 30（分類 10）、每秒減速 60、速度降至 5 後以每秒 1000 邏輯像素停靠。移植版使用短時間步進，避免低幀率越過停靠點；加入 4 像素手指抖動容許值與觸控取消處理。切換分類時保留裝備收回／展開階段。

## 與原作仍有差異

| 項目 | 目前處理 |
|---|---|
| 武器 UPGRADE／等級 | 既有遊戲未實作；擁有的商品顯示 OWNED，沒有偽造可執行升級 |
| 共用能量／付費 AMMO | 按 AMMO 說明任務開始補充能量；沒有扣款。頂部能量顯示「—」 |
| 線上儲值、促銷與社群 | 保留既有離線提示，未連接原作服務 |
| 畫素及人物完全一致 | 使用專案現有高清模型、貼圖、字型與本地化；Godot 3D 預覽需重新取景，未宣稱與 Unity 截圖逐像素相同 |
| 手機實機 | 尚未在 Android／iOS 實機驗收；目前為 Godot Compatibility 下的手機模式及真實輸入事件測試 |

因此本次是原版佈局與主要商店操作的移植，並非全部原作交易系統已完成。

## 重現驗證

```powershell
python tools/ui_extractor/extract_mobile_store_layout.py --assets-root E:/Star-Warfare-1.0.2/Assets
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_store_sw1_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/menu_equipment_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/source_reconstruction_test.tscn
```

`mobile_store_sw1_test` 使用獨立暫存存檔，涵蓋觸控滑動、雙向循環、取消／第二手指、分類切換、各類商品、預覽保留、導覽遮擋、道具滑動不誤購、餘額不足、重複購買、裝備、CoM 整套解鎖、返回及三種比例。`-- --capture` 另外輸出實際渲染截圖至 `test_output/mobile_store_sw1/`。

已執行結果在 [檢視頁](index.html)。手機測試及桌面回歸 PASS，Compatibility 擷取無錯誤。資料回歸 assertions PASS，但該既有測試退出仍回報 2 個 ObjectDB 與 1 個 resource 清理問題。`python .harness/verify.py` FAIL：既有生成政策檔案漂移；本次未修改這些檔案。
