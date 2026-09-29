# 瞄準鏡與兩套準星

未開鏡與開鏡使用不同準星；各槍的鏡內準星有不同形狀，共用 Call of Mini 參考的金色細線、細圓框與半透明暗角。鏡具設定決定準星樣式、淡鏡片色調與倍率。

```text
按住右鍵／手把左肩鍵，或手機點 AIM
→ player 判斷目前武器的 scope 設定
  ├─ 有瞄準鏡：即時畫面放大＋專屬鏡框、鏡內準星、倍率
  └─ 無瞄準鏡：沿用原本 FOV 放大＋第三人稱準星
→ 退出瞄準：恢復正常視野與第三人稱準星
```

## 素材與對應原則

現有素材足以支援腰射準星與操作按鈕；這次新增的鏡框和鏡內準星由 Godot 向量繪製，不需要生成 PNG。

- `assets/ui/HUD.png`／`HUD.json` 的 `hud0`～`hud13` 繼續用於第三人稱準星，`skill_bk` 用於手機按鈕。
- 檢查範圍包含 `assets/callOfMini`、SW1 HUD、SW2 BattleHUD、CoM UI 圖集。本機現有圖片未包含完整 CoM 狙擊畫面；`docs/reconstruction_v1/com/inventory.json` 有記錄 `sharedassets22.assets` 的 `JUJI-weapon_007`（1136×768）及 `level22` 的 `SniperPanel`，但對應匯出圖片與原始封包不在本機。不能把清單存在說成已看過圖片。
- 武器檢查走遊戲實際使用的 `EquipmentRefinement.weapon_mesh()`，查看側面與後方。單看側面會漏掉 R100、R700 的內建瞄準顯示器。
- 有無鏡具由逐把模型檢查決定，不從武器類別或腰射 `aim_id` 推測。以 Reflection 為例，現有模型是開放式照門／準星，維持原有放大。
- 鏡片色調保留模型的淡色提示；鏡內刻線及倍率是本專案的新設計，沒有宣稱是原作還原數值或真實光學規格。

## 2026-09-29 視覺修訂

鏡框保留細圓框和半透明外圍暗角；準星改為五種可明顯辨識的形狀，避免所有槍都只差圓環大小。

- 參考實際影片 [Call of Mini Infinity: Sniper Gameplay，約 0:54–0:57](https://www.youtube.com/watch?v=3j1gM6l4d5w&t=54s)：可見細圓形邊界、外圍仍透出場景，以及金黃色中心圓環、對角分段弧線、四方向導線。這只代表該影片中的鏡具，未推定原作每把槍都相同。
- 本專案以 Godot 向量重新繪製這套視覺，不載入原作狙擊貼圖。圓框表示聚焦視野，外部鏡殼的五邊形／螢幕長寬不再直接裁切整張開鏡畫面。
- 五把槍共用金色細線，形狀分別是分段圓環、開口尖角、精密十字、四角菱形與 T 型柱線。FR28a 延用參考影片的環形方向，其餘為本專案依鏡具定位設計的變化，未宣稱五款皆為 CoM 原版樣式。
- `scope.reticle` 選擇繪製樣式，`reticle_name` 用於對照頁標示。中心點始終對準相機射線；腰射準星仍由原本 `aim_id` 決定。
- 鏡外只壓暗，鏡內外使用同一個已放大的相機。沒有宣稱實作「只有鏡片內放大、外圍保持腰射倍率」的雙相機效果。
- 分段弧線目前是靜態方向標記，不表示未實作的充能進度。刻線不標公尺／彈道距離。

## 目前鏡具設定

五把已確認有可辨識鏡具／瞄準顯示器的武器，分別綁定自己的鏡內設定。設定權威是 `scripts/core/weapon_optics.gd`，資料經 `GameState` 傳給 player 與 HUD；沒有設定的武器維持原本放大方式。

| 武器 | 模型上的瞄準裝置 | 鏡內準星 | 可用倍率 |
| --- | --- | --- | --- |
| FR28a / gun00 | 紫色稜角鏡筒、五邊形橙色鏡片 | 分段圓環：中心環、對角弧線、四方向導線 | 2×、4× |
| Vox-07 / gun14 | 短型方殼、圓形青綠鏡片 | 開口尖角：朝上尖角與左右短括線，保持視野簡潔 | 固定 2× |
| R100-RAILGUN / gun34 | 機身內建直向藍框瞄準螢幕 | 精密十字：長十字軸與等距短刻線 | 2×、4×、6× |
| R700-AA / gun35 | 機身內建青綠瞄準螢幕 | 四角菱形：四個分離角標與中心小菱形 | 2×、4×、6× |
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

輸出在 `test_output/scope_aim/`：`desktop.html`／`mobile.html` 頁首顯示五款準星的實際遊戲中心裁切，全部使用第一檔 2×，可直接比較形狀；下方比較模型後方、第三人稱與各倍率鏡內畫面。PNG 和 JSON 記錄每張圖的武器、準星樣式、倍率、FOV、viewport。若本機保留 `before_com_style/` 的舊圖，也會顯示鏡框修訂前後對照。產物不提交；測試、擷取場景與設定會保留。擷取與回歸測試使用獨立測試存檔。
