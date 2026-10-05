# Titan · C-06 · 頭盔圓弧修正 v3

**新版已套用到遊戲的 Titan（ID 5），以大片金色玻璃面罩、較薄的鋼藍護框與實際 3D 圓弧貼近草稿。** 上額與前緣只加入少量頂點，保留遊戲的大頭比例；身體、肩甲、手腳與原骨架不變。美術效果仍待使用者評價。

## 改動與預算

**頭盔僅小幅切分，沒有增加連續 UV 區域。** 新頂點在原邊上取中點，再調整弧度；新增權重繼承同一原邊的原始 bind。原三角形保留父面對應，驗證會拒絕重複／遺失面。

| 實測項目 | 真正原版 | 本版 |
| --- | ---: | ---: |
| 頭盔三角形 | 124 | 132（+6.45%） |
| 頭盔 UV 座標 | 294 | 302（+2.72%） |
| 頭盔連續 UV 區域 | 3 | 3 |
| 原頭盔 UV 取樣改動 | — | 10 / 294（3.40%） |
| 整套三角形 | 700 | 708 |
| 整套 UV 座標 | 1607 | 1615 |
| 原骨架 | 28 bones | 28 bones |

原 UV 的局部取樣修正用來避開貼圖邊框，消除玻璃下緣中央的尖角。頭盔最大局部位移為原最短邊的 18.29%；寬度縮小 12.51%，高度差 0.028%，深度差 0.0011%。這些是幾何量測，不是美術相似率。面數／座標增量的 10% 是這次保守實作預算；使用者本次放寬不自動授權修改其他裝甲。

## 如何看

**在商店或配裝選 Titan 的頭、身體、手臂、腿部，就會使用目前素材。** 模組入口與 ID 不變，正式資源是 `assets/armors/titan_v1/titan.scn`；`titan.glb` 是可回讀的交換版本，`build/titan_master.blend` 是可編輯的 Blender 模型。

[開啟修正前／新版對照](revisions/helmet_refinement_v3/index.html)。對照頁使用同相機、同姿勢的實際 Godot 擷取；「修正前」指這次開始前的新版 Titan，與「真正原版」分開標示。

## 生成與來源

**頭圖使用實際 image_gen 工具編修，正式 PNG 與生成原圖位元組相同。** 沒有用程式重畫、改色或縮放遊戲貼圖；其餘四張 diffuse 與本次開始前的檔案 SHA 相同。生成器輸入為實際 atlas、草稿及 UV 區域圖；最後再於模型上做少量 UV 取樣修正，完成原生素材的對位。

- [實送 prompt／參考／輸出紀錄](revisions/helmet_refinement_v3/generation_record.json)與各次原生輸出保留在同一資料夾。
- [變更前快照](revisions/before_helmet_refinement_v3/snapshot.json)保留當時的素材、模型、規格與 manifest。
- 真正原版 source／atlas 快照仍在 `revisions/original_source_v1`；原件未修改。
- 共用做法已補入 [ARMOR_TEXTURE_STYLE_SPEC.md](../ARMOR_TEXTURE_STYLE_SPEC.md#titan大片玻璃與局部圓弧2026-10-05)。

## 驗證與限制

**本版工程驗證通過；使用者美術接受與手機效能測試仍未完成。** `manifest.json` 記錄本版實際資源 SHA、檢查與擷取。舊首次整合 manifest 保留於變更前快照，不能把舊版的面數、PNG 名稱或 Windows 擷取結果當成本版證據。

| 檢查 | 狀態 | 範圍 |
| --- | --- | --- |
| 實際 SCN／原件比對 | PASS | 原 skin bind 不變；身體／四肢全部 mesh arrays 精確相同；頭部逐頂點符合目標 |
| 頭盔切分契約 | PASS | 132 tris／302 UV 座標、父面覆蓋、權重；負向案例拒絕改權重與重複／遺失面 |
| 遊戲換裝與動作 | PASS | 15 個待機／跑動／換彈姿勢，混搭、重複換裝、商店／配裝入口 |
| GLB 回讀 | PASS | 9 個實際姿勢；30 個匯入頭圖 RGB 取樣，沿用 0.05 codec 容差 |
| GLB 完整貼圖／UV／skin | PASS | 五張內嵌 RGB 與原生 PNG 零差異；每個三角形符合目標；28 原骨架 |
| Blender master | PASS | 模型／UV／權重與目標一致；5 張內嵌原生 PNG 位元組相同 |
| Godot 視覺擷取 | PASS（擷取與選定視圖檢視） | Godot 4.7.2，Compatibility，Apple M4；64 張 640×720／1280×720，真實存檔 SHA 不變 |
| 美術接受／實機手機效能 | NOT RUN | 待使用者評價；本版沒有手機 profiler 數據 |

草稿只有斜視圖，側後方深度是依原頭殼推測。保留少量低多邊形折面，沒有聲稱完整還原成人概念比例、100% 風格相同或概念像素相似度。

## 可重現流程

**本版需使用頭盔局部更新器；首次整合的 adopt／compile／provenance／review 工具會拒絕這版，避免還原舊貼圖或寫入過時的規格。** 先正常匯入貼圖，再建模與匯出；`.import`／`.uid` 由 Godot 正常生成。

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python tools/armor_runtime_v1/build.py -- --armor=titan
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/armor_runtime_v1/update_titan_helmet.gd
python3 tools/armor_runtime_v1/glb_unique_joints.py --armor=titan
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/armor_runtime_v1/validate_scene.gd -- --armor=titan
godot --headless --path . --script res://tests/armor_head_refinement_contract_test.gd
godot --headless --path . res://tests/armor_runtime_v1_test.tscn -- --armor=titan
godot --headless --path . res://tests/armor_runtime_v1_roundtrip.tscn -- --armor=titan
python3 tools/armor_runtime_v1/validate_titan_helmet.py
/Applications/Blender.app/Contents/MacOS/Blender -b docs/art/titan_runtime_v1/build/titan_master.blend --python-exit-code 1 --python tools/armor_runtime_v1/validate_titan_helmet.py
godot --path . --rendering-method gl_compatibility res://tools/armor_runtime_v1/capture.tscn -- --armor=titan --preview-revision=helmet_v3_final
```
