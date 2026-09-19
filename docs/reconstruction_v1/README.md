# 三作來源拆解與現有遊戲套用

[離線 HTML：數值查詢、音效試聽、UI 圖集](index.html)

本輪按使用者提供的「拆解 → 規格 → 重構 → 驗證」方法，讀取 `原資料/` 內三個 XAPK，以及各自內含的 APK／OBB。沒有執行原 APK，也沒有查詢原作帳號、商店或下載伺服器。

| 階段 | 可核對的產物 |
| --- | --- |
| 原始依據 | `sources.json`；各作 `source.json` 記錄版本、包內路徑、檔案長度與 SHA-256 |
| 拆解 | 各作 `inventory.json` 記錄每個 Unity 物件的類別、檔案、path ID、名稱與 Resources 路徑 |
| 理解體驗 | [EXPERIENCE.md](EXPERIENCE.md)；三作的循環、差異，以及靜態材料能／不能證明的事 |
| 定義規則 | [SYSTEMS.md](SYSTEMS.md)；原始值、欄位證據、整套裝甲到四部件的規則 |
| 素材依據 | [REFERENCE.md](REFERENCE.md)、`media_mapping.json`；逐項重用／補入的正式路徑 |
| 套用範圍 | [MODERNIZATION.md](MODERNIZATION.md)；保留、實作、尚未接入明確分開 |
| 驗證 | `verification.json`、`store_applied.png`；真實 Godot 玩家／商店／資源載入 |

## 交付與界線

SW1 的 APK `resDataSets` 與專案來源檔逐位元相同，保留已使用的原數值。CoM 的 8 套現有裝甲改用自己的 HP、護盾、基礎售價和解鎖門檻，接入護盾恢復、整套購買與原圖示；原先的「套用 Viper 數值」已移除。所有可恢復的 AudioClip 都有可載入的去重路徑，並補入適用的 UI 圖集。

SW2 的 227 張表與 CoM 的 39 份設定（含原包內版本差異）已完整解碼、可查閱；它們不等於整個遊戲已重製。沒有新增尚不存在的 SW2 武器、任務／Boss 狀態機、職業、連線服務或 CoM 全部升級被動。SW2 尚未證實意義的欄位保留原順序與字串，不猜測欄名或覆蓋 SW1。

原版完整皮膚與場景網格都在索引內，必要的現有素材也已比對；本輪沒有把其他作品的所有模型、光照貼圖和廣告圖一股腦放入遊戲。既有高清裝甲、Thunder 頭盔、換彈與商店布局保留。

## 重建

使用目前已安裝的 Python、UnityPy、Pillow，以及 Unity 隨附的 Mono.Cecil；沒有安裝依賴。

```powershell
python tools/reconstruct_sources.py unpack
python tools/reconstruct_sources.py export
./tools/inspect_managed_source.ps1 -Assembly 'test_output/source_reconstruction/com/raw/assets/bin/Data/Managed/Assembly-CSharp.dll' -Output 'test_output/source_reconstruction/com/assembly_il.txt'
python tools/build_source_catalogs.py
python tools/import_source_media.py
python tools/update_recovered_game_data.py --check
python tools/build_reconstruction_report.py
& './.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --import
& './.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/source_reconstruction_test.tscn
```

中間原檔與批量匯出位於忽略的 `test_output/source_reconstruction/`，有 `.gdignore`，不進 Godot 匯入或 Git。正式媒體在 `assets/recovered_sources/`，原素材只讀。重建不依賴過去的外部素材位置。

Windows／Android 的匯出設定明確包含新 catalog、圖集 JSON 與使用的 SW1 圖集／翻譯資料，避免只在編輯器工作目錄可讀、打包後找不到資料。

`inspect_managed_source.ps1` 只讀 assembly metadata／IL，不載入或執行遊戲程式；`com/consumer_evidence.txt` 保留這輪使用的欄位與計算證據。

`com/xml/` 保留原包的換行與空白，SHA-256 可直接對回來源；該目錄的 `.gitattributes` 禁止 Git 轉換換行。原 XML 的行尾空白不清理，程式與撰寫文件另做 whitespace 檢查。
