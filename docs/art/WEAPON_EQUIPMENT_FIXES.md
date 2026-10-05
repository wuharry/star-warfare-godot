# 武器與背包修復驗收 — 2026-10-05

六類修復共用原始資產，戰鬥與裝備預覽使用相同握點、旋轉和尺寸規則。弓按使用者指定維持橫持；刀的完整出招和收招須在戰鬥狀態結束前播放完。

| 類別 | 修復行為 | 驗收 |
| --- | --- | --- |
| gun21 雷射加農炮 | 使用 laser 槍口、分層光束和命中光斑；逐個排除命中的傷害碰撞體，穿透敵人，遇牆停止，同一角色不重複扣血 | projectile_vfx_test：有牆／無牆、多角色、重複 hitbox，普通步槍仍只命中第一個目標 |
| gun24／25／39 加特林 | 已烘焙成 -Z 槍管的 OBJ 使用 -90° X 手部轉換；槍口標記由模型前端取得 | weapon_pose_test：實際槍管與瞄準軸對齊，子彈起點在槍管前端 |
| gun27／28／33 刀 | 統一刀身軸、保留手部握點；取消槍械後退與閃光；刀身兩端產生會淡出的揮砍殘影；刀鞘跟隨 Spine1，切換槍械時移除 | weapon_fire_feedback_test：完整 1.2 秒 clip 在 0.3 秒出招內播放，18 次取樣檢查握點和刀尖移動；逐格渲染與背面檢視 |
| gun22／29／44 弓 | 橫持，弓臂與射箭軸垂直；移除光弓橫向殘留座標；取消槍械後退 | weapon_pose_test 與射箭逐格渲染：握點留在左手，射箭軸跟隨瞄準掛點 |
| gun23／36 手部武器 | 以袖口中心對齊手部，前端朝前，取消槍械後退 | weapon_pose_test：袖口貼合、長度與出招掛點檢查；實際渲染 |
| 背包 | 每個 surface 分別覆寫為 unshaded 與白色乘色，保留各自貼圖、alpha 和 blend 設定 | weapon_pose_test：0–24 號全部 surface；menu_equipment_test：裝備預覽；1／14／21 號低光渲染 |

## 尺寸與動作規則

`scripts/core/weapon_visual_pose.gd` 集中管理模型旋轉、尺寸、握點、槍口和刀鞘；`player.gd` 與 `unity_equipment_shell.gd` 共用，手機裝備預覽沿用同一套 avatar 掛載。一般槍械保留原有尺寸規則；以下長度是呈現調整，不改傷害、射程或射擊間隔。

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

圖片輸出到忽略的 `test_output/weapon_*.png`；射箭和揮刀各取完整 clip 的八個階段。已檢視橫持射箭、揮刀刀光、背面刀鞘、加特林槍口方向、手套尺寸、低光背包，以及加農炮紅色光束與命中光斑。刀鞘是程序生成的簡單外殼，未新增美術模型。
