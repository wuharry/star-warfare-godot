# 原版高清備用分支

**`codex/original-hd-backup` 保留原版裝甲幾何與既有高清貼圖，等版權方回覆使用者的授權 email 後，再決定是否使用。** 前身是 `art/thunder-original-helmet`；新版裝甲開發改在 `codex/new-armor-design` 繼續，見 [分支入口](../../ART_BRANCHES.md)。

## 本次修正

**原版備用線預設不再載入新版造型覆寫。** Thunder 使用原 glTF 網格，搭配 `assets/equipment_refined/armors/armor_06.scn` 的高清材質，沒有 v5 頭盔或 `thunder_original.scn` 額外貼上的甲片；Viper 也回到原件，其他裝甲繼續使用既有原模型高清素材。歷史概念／場景留存，沒有刪除。

**原版 Cygni、Pegasus 的頭盔與身體恢復同套配色。** glTF 的頭盔色彩乘值分別是粉紅與純紅，現在複製材質後改用同套身體的中性色乘值。修正涵蓋 BaseMaterial3D 原件和 ShaderMaterial 高清版，不改原 PNG、UV、骨架或裝備數值。共用 loader 讓商店／配裝／玩家一致。

## 查看與接續

**正常啟動就會顯示原版高清外觀。** 商店／配裝沿用 Thunder、Pegasus、Cygni 的既有四部件，無須任何頭盔啟動旗標。

```bash
git switch codex/original-hd-backup
git pull --ff-only
godot --path .
```

## 驗證

**實際檢查結果存於 [validation.json](review/validation.json)，不以分支名稱宣稱完成新一輪高清生成。** 本輪沿用已有高清 PNG；尚未依授權回覆重新規劃更多內容。

```bash
godot --headless --path . tests/original_helmet_color_test.tscn
godot --headless --path . tests/equipment_refinement_test.tscn
godot --path . tests/original_hd_backup_test.tscn -- --capture
```

- `original_hd_backup_test` 對照原 glTF 的全 21 套／84 部件，按三角形展開角點檢查原幾何、UV 及 transform；擷取 Thunder、Pegasus、Cygni 正側面。
- `original_helmet_color_test` 驗證兩套原件與遊戲材質修色、來源資產未改寫、重複修正與真實存檔保護。
- `equipment_refinement_test` 現在也涵蓋 Thunder 原版的既有嚴格幾何／動作檢查，只有明確修正的兩頂頭盔改用中性色期望值。
- 舊的 `thunder_armor_test`／`thunder_original_helmet_test` 屬歷史改造版的驗收，不能拿來當這個原版備用分支的預設外觀契約。

![Thunder 原版](review/armor_06_front.png)
![Pegasus 修色](review/armor_08_front.png)
![Cygni 修色](review/armor_11_front.png)

**SW1 高清場景原本包含倒角網格；本分支只取其高清材質。** 共用 loader 保留玩家 avatar 原 mesh、UV、Skin 和 transform，複製 mesh 後替換材質。這樣不是以外形容差宣稱原版，而是保留實際原三角形／UV；原始檔也未改寫。

### 本輪實測結果

**指定的原版幾何、配色與動作檢查均通過，原玩家存檔未改。** Godot 4.7.2／Compatibility 擷取六張 640×720 正側面圖片，已逐張檢視。

| 檢查 | 結果 |
| --- | --- |
| SW1 全 21 套、84 部件的原三角形／UV／transform | PASS |
| Cygni／Pegasus 原件、高清材質修色及重複換裝 | PASS |
| 28 套裝甲、85 武器 mesh、129 裝甲貼圖及既有姿勢檢查 | PASS |
| 真實存檔保護、harness 投遞、diff whitespace | PASS |
| 手機實機與瀏覽器互動頁驗收 | NOT RUN；本輪使用實際 Godot 擷取 |

裝備回歸另有既有 `gun05.obj`、`gun18.obj` 外部資源 UID 警告；引擎已使用檔案路徑載入，斷言通過。本輪沒有手動改 `.uid`、`.import` 或 `.godot`。
