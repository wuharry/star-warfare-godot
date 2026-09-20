# 武器與廠商介紹

桌面與手機商店／改裝頁新增方形 `!`。點擊後顯示武器名稱、製造商縮寫／正式名稱、武器介紹與廠商背景。見 [全部對應與文案、實際畫面](index.html)。

名稱依使用者本輪提供的改名表，分配沿用已接受的七廠方案。故事為本專案原創世界觀，不宣稱來自 APK；沒有添加廠商屬性加成，也沒有修改武器模型、貼圖、傷害或升級規則。

| ID | 縮寫 | 中文正式名稱 | 英文正式名稱 | 武器數 |
| --- | --- | --- | --- | --- |
| lattice | ILD | 鐵衡聯邦防務 | Iron-Lattice Defense | 8 |
| rimward | RFA | 邊垣野戰軍械 | Rimward Field Armaments | 7 |
| helion | HPD | 赫曜光電動力 | Helion Photodynamics | 6 |
| vectorline | VSD | 矢界超導防務 | Vectorline Superconductor Dynamics | 6 |
| crucible | CHO | 坩堝重裝兵械 | Crucible Heavy Ordnance | 8 |
| parallax | PAL | 裂相前沿實驗室 | Parallax Advanced Labs | 8 |
| thornring | THS | 棘環搜救工造 | Thornring Hazard Systems | 4 |

## 資料與操作

- 權威資料是 `scripts/core/manufacturer_catalog.gd`。`MANUFACTURERS` 記錄廠商背景與武器 ID 清單；`WEAPON_STORIES` 記錄每把武器的繁中／英文介紹。
- 使用 `gun00` 等穩定 ID 建立歸屬，不以顯示名稱反查。改名不會改變製造商，也不會接觸 `recovered_game_data.gd` 的原始數值。
- `weapon_information_dialog.gd` 只讀取介紹資料，使用已有 SW1／CoM 外框與按鈕樣式。長文使用 ScrollContainer；滑鼠滾輪、原生觸控捲動與上下方向鍵可閱讀。
- 桌面入口放在武器名稱右側。手機入口位於原詳情面板內，名稱預留空間，避免輪播的全域輸入先吃掉點擊，也不覆蓋等級星號。
- 未持有／階級不足仍能閱讀。裝甲及補給不顯示此武器入口。介紹與升級視窗不會同時開啟；閱讀期間手機輪播停用，返回／Esc／關閉後恢復。
- 介面沒有把故事當成已生效的能力描述；現有數值與原武器特性仍在原本的裝備頁顯示。

## 驗證

| 檢查 | 結果 |
| --- | --- |
| `weapon_manufacturer_test` | PASS：七廠、47 把武器完整且無重複、繁中／英文文案、正確改名、穩定 ID、回傳資料不可修改原 catalog。 |
| 介紹操作 | PASS：桌面點擊、手機 ScreenTouch、未購買／未解鎖可讀、固定介紹目標、鍵盤焦點、Esc／返回／關閉、輪播鎖定與恢復、讀完仍可開啟升級。 |
| 存檔／金額 | PASS：閱讀不更動金額、所有權或升級等級；隔離存檔測試核對正式存檔雜湊。 |
| 回歸 | PASS：`equipment_upgrade_ui_test`、`mobile_customize_sw1_test`、`desktop_armory_ui_test`。 |
| GPU 畫面 | PASS：Godot 4.7.2 Compatibility / OpenGL 3.3，1280 × 720，七張原尺寸截圖；已檢視桌面、手機與英文版。 |
| Android／iOS 實機 | NOT RUN；手機測試為強制手機布局及引擎輸入事件。 |
| Harness | FAIL：既有 13 個 generated drift；本輪未修改規則檔或提高基準。 |

```powershell
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --quit
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/weapon_manufacturer_test.tscn
# 移除 --headless 並於場景路徑後加入 -- --capture，可取得圖片與 catalog.json。
```

`data.js` 為 GPU 測試從實際 catalog 匯出的 `test_output/weapon_manufacturers/catalog.json` 加上 `window.manufacturerReview =`，供 HTML 離線查閱；圖片為同目錄直接截圖副本。
