# SW1 手機裝備頁還原

本次修改手機 CUSTOMIZE 與 PACK. 頁面，保留桌面版布局、高清模型及貼圖。

## 原始依據

- `E:/Star-Warfare-1.0.2/Assets/Scripts/Assembly-CSharp/CustomizeUI.cs`：擁有篩選、循環部位、整套試穿套用、背包縮小處理。
- 同目錄 `MakePackageUI.cs`、`UISliderStorage.cs`、`UIDragGrid.cs`：八頁九宮格、方向判斷、交換、堆疊、最後一把武器保護。
- `E:/Star-Warfare-1.0.2/Assets/Resources/ui/resUI.bytes`：vUI[10] 裝備、[12] PACKAGE、[20] 武器／道具圖示；與已提取的 SW1 APK 同名資料 SHA-256 一致。
- `scripts/ui/sw1_store_layout.gd`：解析器生成的原始座標與圖集區域；新增 units 10、12、20，未改寫既有 units 11、13、19。

## 對應檔案

| 檔案 | 責任 |
| --- | --- |
| `scripts/ui/mobile_sw1_equipment_shell.gd` | 手機裝備頁、六種部位、EQUIP、能力比較與 PACK. 入口 |
| `scripts/ui/mobile_sw1_package.gd` | 倉庫滑動、道具拖曳、欄位交換、取消 |
| `scripts/core/game_state.gd` | 驗證整套配置，保存 package_slots / package_storage；既有所有權與 battle_weapons 保持權威 |
| `tests/mobile_customize_sw1_test.gd` | 真實 ScreenTouch / ScreenDrag、隔離存檔、畫面截取 |

PACKAGE 儲存的道具欄位是對已擁有數量的預留。倉庫可用數量 = owned_props − 攜帶欄中的同類道具數量；拖曳不消耗所有權。武器順序同步到 battle_weapons，現有玩家腳本直接使用該順序。桌面改變武器配置後，再開 PACK. 會重新對齊，避免舊手機排序覆蓋桌面操作。

## 驗證

| 項目 | 結果 |
| --- | --- |
| 裝備與 PACKAGE 測試／GPU capture | PASS；stderr 空白 |
| 手機商店回歸 | PASS |
| 桌面 menu_equipment_test | PASS |
| armor_system_test（含舊存檔與損壞主存檔備份復原） | PASS；預期的復原 warning 保留於紀錄 |
| 桌面 shell 與 main_menu | 和 `2be7b5c8788ee2ea62196a30a305245a81c8852e` 逐位元比較一致（換行正規化） |
| Harness | FAIL：既有 generated drift；本次未修改政策檔 |
| Android / iOS 實機 | NOT RUN |

使用 Godot 4.7.2 Compatibility / OpenGL 3.3。檢查了七張實際截圖，包含試穿、套用、堆疊及寬螢幕，未對圖片修圖。

## 保留的差異

- UPGRADE 尚未接入武器等級規則，呈現 LV 1 與停用按鈕；不會把該按鈕拿來裝備或扣款。
- AMMO 延用目前每場任務補給的規則，沒有加入付費共用能量池。
- 道具完成攜帶、堆疊與存檔；戰鬥道具使用介面／消耗效果不在本次 UI 範圍。
- 原版外部分享／廣告不新增。文字沿用現有語言設定，高清模型沿用現有專案。

## 重現

```powershell
python tools/ui_extractor/extract_mobile_store_layout.py --assets-root E:/Star-Warfare-1.0.2/Assets
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_customize_sw1_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_store_sw1_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/menu_equipment_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/armor_system_test.tscn
# GPU capture：同場景移除 --headless，於場景路徑後加入 -- --capture。
# 將上述紀錄存入 test_output/mobile_customize_sw1 的對應 log 後：
python tools/build_mobile_customize_review.py
```

測試覆寫 GameState.save_path 指向隔離 JSON，結束後清除測試檔案，未調整玩家實際裝備或金額。
