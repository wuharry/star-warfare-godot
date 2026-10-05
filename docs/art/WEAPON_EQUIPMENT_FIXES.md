# 武器與背包修復驗收 — 2026-10-05

六類修復共用原始資產，戰鬥與裝備預覽使用相同握點、旋轉和尺寸規則。弓按使用者指定維持橫持；刀的完整出招和收招須在戰鬥狀態結束前播放完。

| 類別 | 修復行為 | 驗收 |
| --- | --- | --- |
| gun21 雷射加農炮 | 使用 laser 槍口、分層光束和命中光斑；逐個排除命中的傷害碰撞體，穿透敵人，遇牆停止，同一角色不重複扣血 | projectile_vfx_test：有牆／無牆、多角色、重複 hitbox，普通步槍仍只命中第一個目標 |
| gun24／25／39 加特林 | 已烘焙成 -Z 槍管的 OBJ 使用 -90° X 手部轉換；槍口標記由模型前端取得 | weapon_pose_test：實際槍管與瞄準軸對齊，子彈起點在槍管前端 |
| gun27／28／33 刀 | 統一刀身軸、保留手部握點；取消槍械後退與閃光；刀身兩端產生會淡出的揮砍殘影；依原始資產移除後加的程序刀鞘 | weapon_fire_feedback_test：完整 1.2 秒 clip 在 0.3 秒出招內播放，18 次取樣檢查握點和刀尖移動；weapon_pose_test、menu_equipment_test：遊戲與裝備預覽都不產生刀鞘 |
| gun22／29／44 弓 | 橫持，弓臂與射箭軸垂直；移除光弓橫向殘留座標；取消槍械後退 | weapon_pose_test 與射箭逐格渲染：握點留在左手，射箭軸跟隨瞄準掛點 |
| gun23／36 手部武器 | 以袖口中心對齊手部，前端朝前，取消槍械後退 | weapon_pose_test：袖口貼合、長度與出招掛點檢查；實際渲染 |
| 背包 | 每個 surface 分別覆寫為 unshaded 與白色乘色，保留各自貼圖、alpha 和 blend 設定 | weapon_pose_test：0–24 號全部 surface；menu_equipment_test：裝備預覽；1／14／21 號低光渲染 |

## 尺寸與動作規則

`scripts/core/weapon_visual_pose.gd` 集中管理模型旋轉、尺寸、握點和槍口；`player.gd` 與 `unity_equipment_shell.gd` 共用，手機裝備預覽沿用同一套 avatar 掛載。一般槍械保留原有尺寸規則；以下長度是呈現調整，不改傷害、射程或射擊間隔。

| 武器形態 | 最長邊目標 |
| --- | --- |
| 弓 | 1.45 m |
| 刀 | 1.15 m |
| 手套／鑽頭／Spring | 0.48 m |

揮刀播放速度使用 `clip.length / _shoot_pose_duration()`；三把刀的正常間隔為 0.30 秒，因此完整 1.20 秒動作以 4 倍速度播放。攻速加成仍走原本間隔規則，出招不額外套用槍械後退。殘影只呈現刀尖／刀根的世界座標歷史，不加入傷害碰撞。

## 檢查與重現

環境：Godot 4.7.2，macOS；視覺檢視使用 GL Compatibility，1280×720。行為斷言與圖片分別驗收。

```sh
python3 .harness/verify.py
python3 .harness/verify.py --run --only godot-smoke
python3 .harness/verify.py --run --only godot-settings
godot --headless --path . res://tests/weapon_pose_test.tscn
godot --headless --path . res://tests/weapon_fire_feedback_test.tscn
godot --headless --path . res://tests/projectile_vfx_test.tscn
godot --headless --path . res://tests/weapon_polish_test.tscn
godot --headless --path . res://tests/menu_equipment_test.tscn
godot --headless --path . res://tests/original_weapon_test.tscn
godot --headless --path . res://tests/weapon_trigger_test.tscn
godot --headless --path . res://tests/reload_system_test.tscn
godot --headless --path . res://tests/rocket_reload_test.tscn
```

行為斷言通過。Godot 日誌仍有部分材質為 null 與退出時資源未釋放訊息，不能視為無警告的執行；已修掉切換武器後殘影讀取離開 SceneTree 的模型所產生的 global_transform 錯誤。`rocket_reload_test` 原先限定 `.obj` 副檔名，但修復前的 `2684dbc` 已使用精修 `.res` 部件，改為比對原始拆分槍身／火箭的實際資源，仍排除整支槍模型。最終複驗通過移動中換彈、換彈取消與原始拆分資源檢查。

```sh
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=machinegun
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=bow --fire-review --review-stage=swing
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=blade --fire-review --review-stage=swing
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=blade --back-review --review-stage=scabbard
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=fist
godot --path . --rendering-method gl_compatibility res://tests/special_weapon_visual_capture.tscn -- --family=bag
godot --path . --rendering-method gl_compatibility res://tests/weapon_polish_visual_capture.tscn -- --cannon-review
```

圖片輸出到忽略的 `test_output/weapon_*.png`；射箭和揮刀各取完整 clip 的八個階段。上述 macOS 檢查是前一版驗收記錄；原射箭 capture 只播放 clip、未更新實際瞄準，因此不能證明瞄準時仍橫持。後加的程序刀鞘已依使用者要求移除，原 player.glTF 與三把刀的 OBJ 未包含刀鞘。

## 本輪弓箭瞄準修正（Windows，2026-10-05）

實際瞄準的 `look_at(target, Vector3.UP)` 會將弓身轉回直立。三把弓 gun22／29／44 現在每幀先瞄準，再繞局部射箭軸轉 90°，保持原左手握點、橫持方向及上下瞄準；旋轉由每幀的新瞄準姿態起算，不累加。步槍仍使用原有直立瞄準姿態。刀鞘的產生函式及遊戲／裝備預覽呼叫皆移除；刀的握點、出招與揮砍殘影保留。

`weapon_pose_test` 增加三弓站立、跑動、飛行、三個動畫階段、0°／±25° 相機角度的 162 個瞄準與射擊樣本，以及 81 個切回步槍樣本。橫持、握點與箭軸檢查沿用原閥值，並檢查實際 muzzle→target；測試使用隔離存檔、明確的起始背包及避開敵人／牆面的方向測試位置。

視覺重現使用 Godot 4.7.2、GL Compatibility（Windows ANGLE／RTX 4080）、1280×720。更新後的 capture 會經過原骨架與實際瞄準函式，保存八個階段的 PNG 與每把弓的方向／握點 JSON，並記錄來源 SHA、renderer 及 viewport。

本輪結果：`weapon_pose_test` 4,202 次檢查、`weapon_fire_feedback_test` 181 次檢查、`menu_equipment_test`、`settings_test`、`smoke_test` 均 PASS；已檢視三把弓橫持瞄準／射擊，以及三把刀背面無刀鞘的實際畫面。煙霧測試原先繼承真實背包的能源加成，已用中性的 `armor_skills` 驗證原成本；裝備測試原先要求新採用裝甲使用舊 shader，已改為和實際裝甲 SCN 的 geometry／material 精確比對並要求 unshaded，舊 shader 分支仍保留。

正常渲染的三弓射擊 27 筆瞄準姿態，其弓臂與世界垂直方向的最大絕對 dot 由修正前 0.999985 降至 0.044743（0 代表水平）；箭軸與槍口掛點軸的 dot 維持 0.999999 以上，握點仍位於左手。渲染後的骨架更新仍有既存的瞄準偏差，箭軸與目標方向最低 dot 在修正前後皆為 0.957421；本輪修正橫持，不把這組圖片宣稱為所有階段的精確瞄準驗收。上述測試仍有既存資源退出未釋放與部分 UID fallback 警告。整套裝甲來源驗收另保留上游 Titan／C-06 證據過期的兩項 FAIL，記錄於 `test_output/arrow_alignment_source_audit_20261005.json`；此輪沒有以修改素材或放寬驗證來清除它們。

```powershell
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/weapon_pose_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/special_weapon_visual_capture.tscn -- --family=bow --fire-review --review-stage=horizontal_after
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/special_weapon_visual_capture.tscn -- --family=bow --aim-review --review-stage=horizontal_aim
```
