# 瞄準鏡與兩套準星

未開鏡與開鏡使用不同準星；鏡內保留細圓框與半透明暗角，各槍使用不同準星。分段圓環、精密十字與 T 型柱線已獲使用者選定；Vox-07、R700 改回最初版的青綠準星，2026-09-30 一併確認。

```text
按住右鍵／手把左肩鍵，或手機點 AIM
→ player 判斷目前武器的 scope 設定
  ├─ 有瞄準鏡：即時畫面放大＋專屬鏡框、鏡內準星、倍率
  └─ 無瞄準鏡：沿用原本 FOV 放大＋第三人稱準星
→ 退出瞄準：恢復正常視野與第三人稱準星
```

## 腰射連射散布（2026-09-30）

腰射從各槍的最小散布開始，成功連射後逐步增加到上限，停火後恢復；移動不增加散布。這是本專案新增的手感設定。

```text
每把槍的 hip_spread 設定 → player 保存目前散布
  ├─ 本發：用目前散布計算射線／投射物發射方向
  └─ 發射成功：增加下一發的散布 → HUD 同步小幅放大準心
停止射擊 → 經過恢復延遲 → 散布與準心一起縮回
```

- `scripts/core/weapon_spread.gd` 管理每槍的範圍、每發增量、恢復速度與準心放大上限，`GameState` 把設定放入 `hip_spread`。
- 一般單彈武器首發保持中心精準；霰彈、Morpheus／Spreader 保留原有多彈丸散布，再增加連射散布。Trinity／Spring 的多發形狀也保留。
- 冷卻、換彈、空彈匣或能量不足而未發射時，不累積散布。換槍重設；換彈期間自然恢復；暫停期間凍結。
- 右鍵／AIM 聚焦時不套用新增的腰射散布；劍類不累積。追蹤投射物的初始方向可偏移，發射後仍保留追蹤能力。
- 準心保留原 `aim_id` 圖案，大小反映目前散布在該槍範圍中的比例；圖案邊界不是精確的彈著範圍。開火不再立刻固定跳到原圖的 1.2 倍。
- 中央瞄準解 `get_aim_solution()` 仍供槍身姿勢、目標變色與技能使用；射擊專用的 `get_shot_aim_solution()` 才抽樣散布，避免準心與槍身隨機抖動。

| `hip_spread` 欄位 | 用途 |
| --- | --- |
| `min_degrees`／`max_degrees` | 中央瞄準線到散布邊界的最小／最大角度，單位為度 |
| `per_shot_degrees` | 每次成功腰射後增加的角度 |
| `recovery_delay` | 停火後的恢復延遲；執行時也考量實際射擊間隔，讓慢速槍能累積 |
| `recovery_degrees_per_second` | 恢復時每秒減少的角度 |
| `reticle_max_scale` | 最大散布時，準心相對原尺寸的倍率 |

例如 FR28a 連射後，下一發可稍微偏離中央，但 HUD 判斷敵人變紅仍使用穩定的中央瞄準線。

### 散布驗證（2026-09-30）

| 驗證 | 結果 |
| --- | --- |
| `hip_fire_spread_test`：桌面與手機各 932 項。實際射線落點、實際生成的火箭方向、霰彈丸型樣、冷卻／空匣／換彈／死亡不累積、恢復延遲與速率、移動不影響、聚焦與劍類不累積、換槍重設、暫停凍結 | PASS |
| `scope_aim_test`、`aim_platform_test`、`camera_hit_feedback_test`、`weapon_trigger_test`、`weapon_fire_feedback_test`、`mouse_weapon_cycle_test`、`original_weapon_test`、`weapon_polish_test`、`reload_system_test`、`smoke_test`、`settings_test`、`recovered_data_test` | PASS |
| 桌面真實渲染擷取 1280×720，17 張 | PASS |
| `mobile_ui_smoke_test` | FAIL；`git stash` 後在未套用本次修改的分支上同樣 FAIL，屬既有問題，未在本次處理 |
| 實體手機觸控手感、各槍數值平衡 | NOT RUN |

重現：

```sh
godot --headless --path . res://tests/hip_fire_spread_test.tscn
godot --headless --path . res://tests/hip_fire_spread_test.tscn -- --mobile
godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/hip_fire_spread_capture.tscn
```

輸出在 `test_output/hip_fire_spread/`：`desktop.html` 依武器排出「首發精準 → 約半滿 → 到達上限 → 停火縮回」四張準心裁切，再列出每張的實際角度、佔上限比例與準心倍率。擷取用的散布是連續呼叫 `_try_fire()` 累積出來的，不是直接寫入變數；拍照前清掉同一幀堆疊的曳光與彈著特效，散布值不受影響。產物不提交。

測試把靶牆放在各槍射程內：`gun06` 的還原射程只有 8 公尺，固定 25 公尺的靶牆會完全打不到，看起來像散布壞掉。移動靶牆後要等一個 physics frame，實體位置才會進到物理空間。


## 素材與對應原則

現有素材足以支援腰射準星與操作按鈕；這次新增的鏡框和鏡內準星由 Godot 向量繪製，不需要生成 PNG。

- `assets/ui/HUD.png`／`HUD.json` 的 `hud0`～`hud13` 繼續用於第三人稱準星，`skill_bk` 用於手機按鈕。
- 檢查範圍包含 `assets/callOfMini`、SW1 HUD、SW2 BattleHUD、CoM UI 圖集。本機現有圖片未包含完整 CoM 狙擊畫面；`docs/reconstruction_v1/com/inventory.json` 有記錄 `sharedassets22.assets` 的 `JUJI-weapon_007`（1136×768）及 `level22` 的 `SniperPanel`，但對應匯出圖片與原始封包不在本機。不能把清單存在說成已看過圖片。
- 武器檢查走遊戲實際使用的 `EquipmentRefinement.weapon_mesh()`，查看側面與後方。單看側面會漏掉 R100、R700 的內建瞄準顯示器。
- 有無鏡具由逐把模型檢查決定，不從武器類別或腰射 `aim_id` 推測。以 Reflection 為例，現有模型是開放式照門／準星，維持原有放大。
- 鏡片色調保留模型的淡色提示；鏡內刻線及倍率是本專案的新設計，沒有宣稱是原作還原數值或真實光學規格。

## 2026-09-29 視覺修訂

鏡框保留細圓框和半透明外圍暗角；本次保留三款已選定樣式，僅調整另外兩款。五款皆於 2026-09-30 由使用者看過擷取後確認。

- 參考實際影片 [Call of Mini Infinity: Sniper Gameplay，約 0:54–0:57](https://www.youtube.com/watch?v=3j1gM6l4d5w&t=54s)：可見細圓形邊界、外圍仍透出場景，以及金黃色中心圓環、對角分段弧線、四方向導線。這只代表該影片中的鏡具，未推定原作每把槍都相同。
- 本專案以 Godot 向量重新繪製這套視覺，不載入原作狙擊貼圖。圓框表示聚焦視野，外部鏡殼的五邊形／螢幕長寬不再直接裁切整張開鏡畫面。
- FR28a 的分段圓環、R100 的精密十字、AST-KK 的 T 型柱線保留金色與原有繪製參數。Vox-07 恢復 `30a8307` 的青綠階梯刻線；R700 恢復同版青綠分段環，保留中心點與上方小尖角。後兩款已確認。
- FR28a 延用參考影片的環形方向，其餘為本專案設計，未宣稱五款皆為 CoM 原版樣式。外側圓框仍維持原來金色，不跟著準星換色。
- `scope.reticle` 選擇繪製樣式，`reticle_name` 用於對照頁標示。準星中心點或中央十字交點對準相機射線；腰射準星仍由原本 `aim_id` 決定。
- 鏡外只壓暗，鏡內外使用同一個已放大的相機。沒有宣稱實作「只有鏡片內放大、外圍保持腰射倍率」的雙相機效果。
- 分段弧線目前是靜態方向標記，不表示未實作的充能進度。刻線不標公尺／彈道距離。

## 目前鏡具設定

五把已確認有可辨識鏡具／瞄準顯示器的武器，分別綁定自己的鏡內設定。設定權威是 `scripts/core/weapon_optics.gd`，資料經 `GameState` 傳給 player 與 HUD；沒有設定的武器維持原本放大方式。

| 武器 | 模型上的瞄準裝置 | 鏡內準星 | 可用倍率 |
| --- | --- | --- | --- |
| FR28a / gun00 | 紫色稜角鏡筒、五邊形橙色鏡片 | 分段圓環：中心環、對角弧線、四方向導線 | 2×、4× |
| Vox-07 / gun14 | 短型方殼、圓形青綠鏡片 | 青綠階梯刻線：小十字與下方三層短刻線 | 固定 2× |
| R100-RAILGUN / gun34 | 機身內建直向藍框瞄準螢幕 | 精密十字：長十字軸與等距短刻線 | 2×、4×、6× |
| R700-AA / gun35 | 機身內建青綠瞄準螢幕 | 青綠分段環：小型分段環、中心點、上方小尖角 | 2×、4×、6× |
| AST-KK / gun40 | 白灰色圓筒、青綠鏡片 | T 型柱線：水平雙翼、下方柱線與短刻度，上半部留空 | 2×、4×、6× |

刻線尚未對應實際彈道測距，不標公尺／彈道距離。沒有把雷射武器的能量發光片直接當成瞄準鏡；日後加裝鏡具時應一起更新模型與 `scope` 設定。

## 操作與狀態

倍率由目前鏡具決定，並以透視投影換算 FOV，避免顯示 4× 卻沒有放大四倍。

| 操作 | 電腦 | 手把 | 手機 |
| --- | --- | --- | --- |
| 瞄準 | 按住右鍵 | 按住左肩鍵 | 點 AIM 開／關 |
| 切倍率 | Z | 右搖桿按下 | 點右側倍率按鈕 |
| 換槍 | 原本滾輪／數字鍵 | 既有操作 | 原本武器欄 |

- 固定倍率鏡仍顯示倍率，但沒有切倍率按鈕；切換只在開鏡狀態有效。
- 開鏡時隱藏自己的人物／持槍模型，避免遮住鏡片；命中確認仍在鏡內準星上方獨立顯示。
- 換彈時退出瞄準並停用開鏡。手機需再點 AIM；右鍵持續按住則在換彈完成後恢復瞄準。
- 換槍清除手機開鏡狀態並把倍率重設為該鏡第一檔；持續按住右鍵時使用新武器的瞄準方式。
- 暫停、結算、死亡立即恢復相機與人物顯示。倍率按鈕中途隱藏仍能正確釋放觸控，不會留下按住狀態。
- 手機倍率按鈕與 AIM 同一欄靠右，位於武器欄左邊；不占用移動、射擊搖桿區。

計算：`aim_fov = 2 × atan(tan(hip_fov / 2) / magnification)`。例如基礎垂直 FOV 60° 的 4× 約為 16.43°。準星中心始終對準原本的相機射線；高倍率同時降低轉向靈敏度。

## 驗證與預覽

行為測試與 Godot Compatibility 實際截圖分開驗證；沒有把 headless 通過當成視覺驗收。

| 驗證 | 結果 |
| --- | --- |
| `scope_aim_test`：各鏡具、實際投影倍率、準星互斥與恢復、相機射線對齊、觸控事件、換彈／換槍／暫停／死亡 | PASS |
| `aim_platform_test`、`camera_hit_feedback_test`、`mouse_weapon_cycle_test`、`weapon_trigger_test`、`smoke_test` | 前版 `30a8307` PASS；這次純視覺修訂未重跑 |
| 桌面／手機真實渲染擷取：1280×720；手機另看 1560×720、960×640 | PASS |
| 手機擷取退出清理 | 前版 `cc4cca4` 曾出現 2 個 ObjectDB 殘留警告；本次五樣式擷取未出現，前次原因尚未定位 |
| `.harness/verify.py` 與 `git diff --check` | PASS |
| 實體手機觸控與手把硬體手感 | NOT RUN；觸控已以 Viewport 輸入事件驗證 |

`mouse_weapon_cycle_test` 斷言通過，但退出時仍有 ObjectDB／resource 清理警告；未將它當作零警告通過。

重現：

```sh
godot --headless --path . res://tests/scope_aim_test.tscn
godot --path . --rendering-method gl_compatibility --resolution 960x540 res://tests/weapon_optics_model_capture.tscn
godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/scope_aim_capture.tscn
godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/scope_aim_capture.tscn -- --mobile
```

輸出在 `test_output/scope_aim/`：`desktop.html`／`mobile.html` 頁首顯示五款準星的實際遊戲中心裁切。全部使用第一檔 2×，可直接比較形狀；下方比較模型後方、第三人稱與各倍率鏡內畫面。PNG 和 JSON 記錄每張圖的武器、準星樣式、倍率、FOV、viewport。若本機保留 `before_original_reticles_3be3e8c/`，會顯示 Vox-07、R700 調整前後；若保留 `before_com_style/`，也會顯示鏡框修訂前後。產物不提交；測試、擷取場景與設定會保留。擷取與回歸測試使用獨立測試存檔。
