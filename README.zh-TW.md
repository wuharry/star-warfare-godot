# Star Warfare：Godot 離線復原版

這是與原始 Unity 2017 專案分開存放的 Godot 4 重建版。原專案檔沒有被覆寫；完整 Godot 專案位於 `E:\Star-Warfare-Godot-Restoration`。

目前可遊玩內容：

- 單人模式與多人模式分開：單人戰役為 Level 1–8；多人入口保留原版 9 張 PvP 競技場 Level 13–21。目前尚未恢復官方配對服務，因此只提供離線場地預覽，且不會再套用 PvE 敵人波次。`GameState.CAMPAIGN_FULLY_UNLOCKED` 為 `true`，單人 8 關全部開放以便測試；進度仍照常記錄，改回 `false` 即恢復逐關解鎖
- 17 張原始 `Level*.unity` 的 Static Batch 場景配置、材質貼圖、Transform 與原生碰撞；不再使用程序化競技場
- 原始 Respawn、EnemySpawnPoint、BossSpawnPoint、FlagSpawn、GiftSpawn、Grave、WayPoint 座標及 Level 1–8 的 waypoint 鄰接圖；敵人會用原路徑節點繞過場景障礙
- 第三人稱移動、肩後視角、衝刺、護盾與生命
- 從原始 `resDataSets.bytes` 還原的 47 把武器、原名、傷害、冷卻、Energy 消耗及 8 格裝備欄；缺少匯入模型或動作時會安全降級，不會因裝備／射擊而中止
- 商店與軍械庫依 Unity 原始資料分成頭盔、胸甲、護臂、腿甲、背包與槍械六頁，顯示解鎖階級、Credits／Mithril 售價、持有／裝備狀態與 3D 預覽；新購武器依原版先換入裝備欄第 1 格
- 109 件原版裝甲（21 套四部位裝甲與 25 個背包）、套裝加成、背包武器容量與 Unity 原始技能數值；角色外觀會同步切換 84 個蒙皮部件與 25 個背包模型
- 10 種原版裝甲主動技能、持續時間與冷卻；HUD 會依目前裝備動態顯示 Unity 技能圖示、啟用時間與剩餘冷卻
- 原作使用共用 Energy，沒有一般彈匣換彈；`R`、控制器 X 與手機 `PREV` 會切換上一把武器
- Crawler、Spitter、Brute、Elite 與 Boss，波次上限維持原版約 8 隻同時在場
- Credits、Energy、Shield 掉落，分數、進度及本機 JSON 存檔
- 「大陸戰場」開放世界模式：3000×3000 單位的連續大陸，17 張原作場景各自裁切成可玩核心後當作地標種進程序化地形，地形在地標footprint下被壓平成高原以消除接縫；地形與碰撞依玩家位置串流，荒野散佈可掩蔽的岩層。沒有波次，敵人依玩家所在區域持續生成，強度取自該 sector 原本的關卡資料，離開太遠會回收
- 每張地圖固定光影，取自原始 Unity 場景的 RenderSettings：17 張場景全部沒有 skybox、`m_Sun` 皆為空、`m_AmbientMode` 為平面環境光，光影本體烘焙在貼圖裡，因此環境光是唯一可還原的逐圖光照資料，且各圖確實不同（01／05–08／14–18 為 0.2 灰、02–04 為純白、13／19–21 為近黑紫）。主光為固定角度的授權近似值——原始場景沒有平行光可還原
- 選項內建繁體中文／英文即時切換的多語言介面，以及低／中／高三段畫質（3D 解析度縮放、MSAA、陰影、泛光、霧、天空）
- 鍵鼠、Xbox 相容控制器及手機橫向雙拇指操作
- 原專案選單／戰鬥音樂，以及按鈕、武器、爆炸、敵人、玩家、腳步與撿取音效；連發武器保留開始／循環／停止音效時序
- 原始 NGUI HUD、武器圖示、選單背景、按鈕、關卡預覽與 `ZEROTWOS` 字型
- 從 Unity YAML 還原的角色蒙皮、28 根骨骼、79 組地面／飛行原始動作，以及 47 把武器的模型與貼圖

## Windows 直接玩

可直接執行已匯出的 `builds/windows/StarWarfare.exe`。若要從 Godot 專案啟動，請在本資料夾雙擊 `PLAY_STAR_WARFARE.bat`，或於 PowerShell 執行：

```powershell
.\PLAY_STAR_WARFARE.ps1
```

開啟 Godot 編輯器：

```powershell
.\PLAY_STAR_WARFARE.ps1 -Editor
```

專案固定使用 Godot 4.7.x。若之前曾以 Godot 4.5 開啟，請先關閉所有該專案的編輯器與遊戲視窗，再雙擊 `UPGRADE_TO_GODOT_4_7.bat`；它會保留舊 `.godot` 匯入快取作備份、以內附的 4.7.2 完整重建素材，然後開啟正確版本的編輯器。4.7 可以升級讀取 4.5 專案，但 4.7 儲存／匯入後不應再用 4.5 開啟同一份工作目錄。

## Android 安裝

把 `builds/android/StarWarfare.apk` 複製到 Android 手機後開啟即可安裝。若已開啟 USB 偵錯，也可在本資料夾執行：

```powershell
& .\.tools\android-sdk\platform-tools\adb.exe install -r .\builds\android\StarWarfare.apk
```

此 APK 是供本機測試的 ARM64 debug-signed 版本，不是商店發行簽章。

## 操作

- 鍵盤滑鼠：`WASD` 移動、滑鼠瞄準、左鍵射擊、右鍵聚焦、`R` 上一把武器、`Shift` 衝刺、`1`–`4` 指定武器、`F1`–`F10` 觸發目前裝備提供的主動技能、`Esc` 暫停。
- 控制器：左／右搖桿移動與瞄準、RB 射擊、LB 聚焦、X 上一把武器、左搖桿按下衝刺、Start 暫停。
- 手機：左側原版樣式虛擬搖桿移動，右半畫面拖曳瞄準，右側 `FIRE`／`PREV`／`DASH`／`SWAP` 操作。Android 以橫向全螢幕執行。

## 測試與匯出

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\BUILD_STAR_WARFARE.ps1 -Target All
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/smoke_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/texture_upscale_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/settings_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sector_lighting_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/campaign_access_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/level_icon_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/expanse_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/mobile_ui_smoke_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/restoration_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/level_restoration_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/scene_asset_integrity_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/armor_system_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/armor_power_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/menu_equipment_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/weapon_pose_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/run_shoot_animation_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/avatar_import_test.gd
```

大陸戰場的實際畫面可另外產出對照圖（需要顯示器，不能加 `--headless`）：

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . res://tests/expanse_visual_capture.tscn
```

輸出 `tests/expanse_preview.png`，含出生點、地標與地形的接縫、區間曠野，以及整片大陸的空拍。

Windows 與 Android 的匯出設定已放在 `export_presets.cfg`。本機工具鏈位於本專案的 `.tools`，建置腳本會自動設定 Android SDK 與 Java 路徑；將資料夾搬到另一台電腦時需另行安裝 Godot 4.7.2 export templates 與 JDK 17+。

## 復原範圍

此版本重建原作的離線遊戲循環並保留可讀取的原始音訊、美術、角色動作與武器資料。17 個 sector 已直接從原始 `Level1`–`Level8`、`Level13`–`Level21` Unity YAML 場景轉換：Static Batch 的 `firstSubMesh/subMeshCount`、世界座標、原材質貼圖、1,851 個 Box／Sphere／Capsule Collider、315 個 MeshCollider 與各類出生標記均已接入 Godot。原倉庫本身是未完成的反編譯重建，而且不含線上伺服器，因此舊帳號、配對及官方多人服務無法直接復活；Level 13–21 現從獨立的「多人模式」入口載入，並明確標示為原版 PvP 競技場。目前僅能離線進入地圖，尚未等同於已恢復 PvP 對戰邏輯。

`tools/ui_extractor/extract_stage_icons.py` 會從 `Resources/ui/res.bytes` 與 `resUI.bytes` 還原關卡選單的縮圖對照表：單人取自 `StageChoiseUI` 用的 `vUI[3]` frame 8（module i 對應 stage i、載入 `Level i+1`），PVP 取自 `CreateRoomUI` 用的 `vUI[5]` frame 6（索引 n 載入 `Level 13+n`）。原版圖塊在圖集上是打散的、且跨三張圖頁——Level 7 在第 15 頁左上角、Level 1 在中列、Level 8 在第 20 頁、PVP 多數在第 14 頁——所以無法用網格推導。17 張地圖的原始名稱只以像素形式烘焙在各自的縮圖名牌上，資料表與程式碼中都沒有，因此由美術直接判讀；單人 8 張的難度星等 ★1–★8 正好遞增，可佐證順序。

`tools/unity_level_exporter` 會唯讀解析 17 個 Unity 場景並重建 Godot 關卡資源；`tools/yaml_mesh_converter` 是不需 Unity 授權、可解出一般與舊版壓縮 Mesh 的重跑工具；`tools/unity_avatar_exporter` 會直接把舊 Unity YAML 骨架、蒙皮權重與 `.anim` 曲線輸出成 Godot 可用的 glTF。原先缺失的 `gun23`、`gun36`、`gun37` 已從壓縮 Unity Mesh 轉回實際幾何；舊自訂 shader 則依 alpha／additive 規則映射成 Godot 材質。
