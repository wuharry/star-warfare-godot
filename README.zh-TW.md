# Star Warfare：Godot 離線復原版

這是與原始 Unity 2017 專案分開存放的 Godot 4 重建版。原專案檔沒有被覆寫；完整 Godot 專案位於 `E:\Star-Warfare-Godot-Restoration`。

目前可遊玩內容：

- 17 個離線關卡入口（原 PvE 關卡及已退役線上地圖的離線戰役版本）
- 17 張原始 `Level*.unity` 的 Static Batch 場景配置、材質貼圖、Transform 與原生碰撞；不再使用程序化競技場
- 原始 Respawn、EnemySpawnPoint、BossSpawnPoint、FlagSpawn、GiftSpawn、Grave、WayPoint 座標及 Level 1–8 的 waypoint 鄰接圖；敵人會用原路徑節點繞過場景障礙
- 第三人稱移動、肩後視角、衝刺、護盾與生命
- 從原始 `resDataSets.bytes` 還原的 47 把武器、原名、傷害、冷卻、Energy 消耗及 8 格裝備欄
- 原作使用共用 Energy，沒有一般彈匣換彈；`R`、控制器 X 與手機 `PREV` 會切換上一把武器
- Crawler、Spitter、Brute、Elite 與 Boss，波次上限維持原版約 8 隻同時在場
- Credits、Energy、Shield 掉落，分數、進度及本機 JSON 存檔
- 鍵鼠、Xbox 相容控制器及手機橫向雙拇指操作
- 原專案選單／戰鬥音樂，以及按鈕、武器、爆炸、敵人、玩家、腳步與撿取音效；連發武器保留開始／循環／停止音效時序
- 原始 NGUI HUD、武器圖示、選單背景、按鈕、關卡預覽與 `ZEROTWOS` 字型
- 從 Unity YAML 還原的角色蒙皮、30 節點骨架、44 組原始動作，以及 44 把可直接解碼武器的原始模型與貼圖

## Windows 直接玩

可直接執行已匯出的 `builds/windows/StarWarfare.exe`。若要從 Godot 專案啟動，請在本資料夾雙擊 `PLAY_STAR_WARFARE.bat`，或於 PowerShell 執行：

```powershell
.\PLAY_STAR_WARFARE.ps1
```

開啟 Godot 編輯器：

```powershell
.\PLAY_STAR_WARFARE.ps1 -Editor
```

## Android 安裝

把 `builds/android/StarWarfare.apk` 複製到 Android 手機後開啟即可安裝。若已開啟 USB 偵錯，也可在本資料夾執行：

```powershell
& .\.tools\android-sdk\platform-tools\adb.exe install -r .\builds\android\StarWarfare.apk
```

此 APK 是供本機測試的 ARM64 debug-signed 版本，不是商店發行簽章。

## 操作

- 鍵盤滑鼠：`WASD` 移動、滑鼠瞄準、左鍵射擊、右鍵聚焦、`R` 上一把武器、`Shift` 衝刺、`1`–`4` 指定武器、`Esc` 暫停。
- 控制器：左／右搖桿移動與瞄準、RB 射擊、LB 聚焦、X 上一把武器、左搖桿按下衝刺、Start 暫停。
- 手機：左側原版樣式虛擬搖桿移動，右半畫面拖曳瞄準，右側 `FIRE`／`PREV`／`DASH`／`SWAP` 操作。Android 以橫向全螢幕執行。

## 測試與匯出

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\BUILD_STAR_WARFARE.ps1 -Target All
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/smoke_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/texture_upscale_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_ui_smoke_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/restoration_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/level_restoration_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/avatar_import_test.gd
```

Windows 與 Android 的匯出設定已放在 `export_presets.cfg`。本機工具鏈位於本專案的 `.tools`，建置腳本會自動設定 Android SDK 與 Java 路徑；將資料夾搬到另一台電腦時需另行安裝 Godot 4.7.2 export templates 與 JDK 17+。

## 復原範圍

此版本重建原作的離線遊戲循環並保留可讀取的原始音訊、美術、角色動作與武器資料。17 個 sector 已直接從原始 `Level1`–`Level8`、`Level13`–`Level21` Unity YAML 場景轉換：Static Batch 的 `firstSubMesh/subMeshCount`、世界座標、原材質貼圖、1,851 個 Box／Sphere／Capsule Collider、315 個 MeshCollider 與各類出生標記均已接入 Godot。原倉庫本身是未完成的反編譯重建，而且不含線上伺服器，因此舊帳號、配對及官方多人服務無法直接復活；Level 13–21 現以其原始多人地圖配置作離線戰役使用。

`tools/unity_level_exporter` 會唯讀解析 17 個 Unity 場景並重建 Godot 關卡資源；`tools/yaml_mesh_converter` 是不需 Unity 授權的可重跑 Mesh 轉換器；`tools/unity_avatar_exporter` 會直接把舊 Unity YAML 骨架、蒙皮權重與 `.anim` 曲線輸出成 Godot 可用的 glTF。`gun23`、`gun36`、`gun37` 的來源 Mesh 使用舊版壓縮格式，目前以同類武器的程序化模型作安全替代；舊自訂 shader 則以 diffuse/PBR 材質近似。
