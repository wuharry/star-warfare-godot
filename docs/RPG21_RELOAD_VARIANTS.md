# RPG-21 兩套換彈方案

RPG-21（`gun11`）提供兩套換彈動畫，遊戲在每次開始換彈時隨機選擇；`WarfarePlayer.reload_variant_override` 可在 Inspector 固定 A 或 B 方便檢視。選項在開始換彈時固定，途中改選不會突然換姿勢。全武器對應表見 `WEAPON_RELOAD_CATALOG.md`。

| 方案 | 動作 | 差異 |
| --- | --- | --- |
| A 胸前側收 | 離肩、胸前側轉 → 穩住筒身 → 左手取彈、對準、装入 → 回肩 | 筒身較平，操作集中在胸前 |
| B 立筒裝填 | 離肩、抬高筒口 → 身側穩住 → 左手向上對準、装入 → 回肩 | 筒身較直，左手操作較高 |

## 遊戲參考

本次檢視公開影片的抽樣畫面，比較主要姿勢與動作階段；未完整播放、量測角度或據此宣稱精確復刻。

| 來源 | 抽樣畫面可確認 | 採用的部分 |
| --- | --- | --- |
| [Fortnite OG，Rocket launcher，6:08 起](https://www.youtube.com/watch?v=H9eEc6LJqo8&t=368s) | 火箭筒離肩，移到身前操作，再回肩 | 身前操作、裝填後回肩 |
| [GTA Online，第三人稱換彈，3:30 起](https://www.youtube.com/watch?v=g6oDZf93eys&t=210s) | RPG 從肩上移到身前，改變筒身角度 | 先改變持槍姿勢，再進行裝填 |
| [Helldivers 2，GR-8 Recoilless Rifle](https://www.youtube.com/watch?v=J5zr359ZCR0) | 穩住武器，操作後膛、裝填與復位 | 清楚分開穩住、操作、復位；後膛機構不套用到 RPG-21 |

B 的抬筒角度與兩套手部路徑均為配合現有模型設計，並非宣稱上述遊戲都有相同的立筒前裝動作。

## 實作與範圍

`player.gd` 保留換彈狀態與事件；`rocket_reload_pose.gd` 負責兩套姿勢和手部目標。雙臂沿用既有求解器，筒身隨右手移動，左手跟著彈頭。移動時使用 `run_bazinga` 腿部搭配 `idle_bazinga` 上半身，鏡頭仍可自由轉動。

`gun11_body.obj` 與 `gun11_rocket.obj` 從原 `gun11.obj` 拆出，共用原始位置、大小、UV 和材質。分割工具核對來源雜湊；僅略過來源中原本無面積的三角形 174。彈頭發射後隱藏，裝填後顯示；不再丟出一顆未使用的火箭。中途取消依實際彈量恢復顯示，容量與換彈總時間沿用既有設定。

| 持續時間／事件 | 值 |
| --- | --- |
| 容量 | 1 發 |
| 換彈總時間 | 2.42 秒 |
| 完成持槍姿勢調整 | 22% |
| 左手出現新彈 | 30% |
| 裝入、移除手持物件 | 82% |
| 開始回肩 | 86% |
| 實際補入彈量 | 100% |

## 重現與驗證

在 Godot 開啟 `tests/rocket_reload_preview.tscn` 執行，可切換 A/B、四個視角和慢速播放。預覽使用獨立存檔路徑及記憶體中的預設盔甲，不改玩家裝備存檔。

```powershell
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/rocket_reload_preview.tscn -- --capture --sequence
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/rocket_reload_preview.tscn -- --capture --moving
python tools/build_rocket_reload_preview.py
python tools/yaml_mesh_converter/split_rpg21.py --check
```

輸出 `test_output/rocket_reload/reload_preview.html` 是可直接開啟的離線同步比較頁。站立是 30 fps 序列，跑動是關鍵姿勢；各含左前、右前、左側、右後視角。輸出目錄不提交，擷取場景與產生工具有保留。

2026-09-12 實際驗證，Godot 4.7.2、Compatibility、1280 × 720：

| 檢查 | 結果 |
| --- | --- |
| `rocket_reload_test.tscn` | PASS：兩方案、握持接觸、實際跑動與腿部動畫、取消、切槍、發射顯示、補彈時點、自由鏡頭 |
| 實際跑動期間手腕距離彈頭中心 | 最大 0.0701 m；手腕在手掌後方，非幾何接縫誤差 |
| `reload_system_test.tscn` | PASS：五類換彈與 FR28a 站立／跑動 |
| `camera_hit_feedback_test.tscn` | PASS |
| `weapon_pose_test.tscn` | PASS：47 個模型、11 類持槍姿勢 |
| 分割工具 `--check` | PASS：原座標、UV、法線與材質的確定性輸出 |
| 四視角擷取與畫面檢視 | PASS：檢視兩方案的取彈、對準、裝入、回肩與移動姿勢；曾發現筒身穿入胸甲並調整位置 |
| 離線 HTML 預覽 | PASS：Edge headless 實際載入本機圖片與 A/B 同步頁 |
| `git diff --check` | PASS |
| `python .harness/verify.py` | FAIL：現有 `.claude`／`.harness`／入口文件與生成來源不一致（generated drift）；此次未修改這些路徑 |

邏輯測試退出時有 ObjectDB／RID／resource 清理警告；測試斷言通過、退出碼為零，不代表清理警告已修復。視覺檢查以預設盔甲進行，未逐件驗收所有盔甲。
