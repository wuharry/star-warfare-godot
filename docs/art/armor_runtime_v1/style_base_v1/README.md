# 裝甲 base prompt：先建立原版風格基準

> 2026-10-02：本頁是九套樣本與 Cygni 試作的歷史紀錄。後續請使用 [全 29 套原素材的 Claude＋Codex 整合規格](../../ARMOR_TEXTURE_STYLE_SPEC.md) 與 [完整參考](../../legacy_armor_base_v2/README.md)。原圖的畫法及遊戲比例仍是基準，但新概念的頭盔輪廓不能被舊 Cygni 長下巴覆蓋。

原版的比例與畫法是權威；新的草稿只提供造型特徵，不能再直接帶入寫實人體比例。

## 已查到的做法

- 原 `player.gltf` 包含可獨立換裝的 `ArmorHead_XX`、`ArmorBody_XX`、`ArmorHand_XX`、`ArmorFoot_XX`，共用 28 根匯入骨頭。肩甲屬於 body 的 surface，不能把外觀拆件誤當成新的裝備槽。
- `armor_visuals.gd::_restore_original_materials` 記錄 Unity 原裝甲 shader 不使用 Lighting On，並在 Godot 恢復 `UNSHADED`。大塊明暗、玻璃反光與細倒角主要畫在 diffuse 貼圖；glTF 的 metallic/roughness 是匯出預設，不能當成原版材質設計。
- 本次量測的九套原網格只有 682～1,168 triangles；例如 Cygni 是 head 238、body 460、arms 152、legs 156。這是造型簡化的參考，並非所有裝甲通用硬上限，也不是效能實測。
- 這九套使用的匯入貼圖為 512²。`unity_avatar_exporter/export.py` 的 `TEXTURE_EXPORT_SCALE = 2` 使用 LANCZOS 放大，因此來源尺寸推得為 256²；本次沒有直接讀回外部 Unity 原圖。`equipment_refined` 的較大 AI 重繪圖不列入原版風格基準。
- 原版樣本整套高度／主頭盔連通網格高度約為 2.53～3.04。這不是人體解剖頭身數；Cygni 的長下巴也在主殼裡。每套依其自身前／側面圖，不統一套用 4.5～6.5 頭身。

來源與量測方法見 [mesh_measurements.json](mesh_measurements.json)。原始截圖由 `capture_legacy_style.gd` 直接載入 `player.gltf`，保留原 tint／貼圖、停止動畫、使用原骨架 rest pose，未經遊戲替換 loader。Godot 4.7.2、Compatibility、SubViewport 640 × 720；完整紀錄見 [capture_record.json](capture_record.json)。

## 前一版為什麼看起來怪

外框一致掩蓋了主殼比例錯誤；v4 的主殼更寬、更短，側翼與領口卻讓整體外框仍接近原版。

| Cygni 部位／量測 | 原版 | 被拒絕的 v4 |
| --- | ---: | ---: |
| 主殼寬度 | 0.4606 | 0.6000 |
| 主殼高度 | 0.7820 | 0.7004 |
| 主殼深度 | 0.6998 | 0.6998 |
| 含側翼的完整寬度 | 0.6832 | 0.6832 |

v4 主殼寬度增加約 30.26%，所以「完整外框相同」不能當作造型合格。主殼以位置焊接後三角形數最大的連通網格辨識；這是可重現的幾何近似，面罩與護頰的設計仍須看實機圖。v4 已被使用者指出大小、長寬與外型都不對，不再繼續修成正式資產。

## 可重複使用的 prompt

- [base_prompt.txt](base_prompt.txt)：原版共通比例、甲片、畫法、細節密度與參考圖優先順序。
- [cygni_addon.txt](cygni_addon.txt)：Cygni 特有尺寸、白色同色頭盔、金色 T 字面罩與側翼；修改其他套時只換這類身分資料。
- `cygni_generation_prompt.txt`：上述兩份串接的實際完整生成輸入。
- [cygni_proportion_correction_prompt.txt](cygni_proportion_correction_prompt.txt)：初稿仍偏寬短，改以原版三視圖再校正主殼與短頸的實際編輯輸入。v1、v2 各自保存完整 prompt、參考圖雜湊及生成紀錄。

參考圖順序固定：**原版家族 → 目標套裝的原版前／側面 → 已核准新草稿的局部特徵**。例如 Halo/天命參考可以改眉甲設計，不能把 Cygni 變成長身人形，也不能把無玻璃的 Draco 加上玻璃。

## 圖稿與 3D 的分工

圖片 prompt 只能產生施工參考；新的可玩模型仍需要網格、UV、權重與實機驗收。

```text
原版 mesh／貼圖／實機視圖
→ 共通 base prompt ＋ 單套造型資料
→ 符合遊戲比例的前／側面草稿
→ 比對主殼、面罩、護頰與全身輪廓
→ 建模／UV／手繪 diffuse
→ 原骨架與換裝／動畫實機驗收
```

後續建模以原版量測／輪廓建立施工邊界，幾何負責真正影響剪影的面、細縫用貼圖表現。沿用原 28 骨與四個部位契約，依部位保留合理權重與 skin binds；不把整件長頭盔及領口一律猜成同一根骨頭。只有尺寸報告與技術測試 PASS，仍不能宣稱視覺「100% 對齊」。

Phoenix、Andromedae 之後及 CoM 套裝維持既定保留範圍。本輪先做 Cygni 風格參考，沒有把新 bitmap 冒充遊戲已套用的 3D 資產。

## 新風格參考狀態

v2 已修正 v1 偏寬短的頭盔、外露長頸與較長的身體；仍然是待使用者審查的施工圖。

| 檢查 | 結果／限制 |
| --- | --- |
| 原始網格與截圖研究 | PASS，九套原網格、36 張 rest-pose 截圖，沒有重繪原始貼圖 |
| prompt 與生成 provenance | PASS，兩次完整輸入、參考圖與檔案雜湊保存 |
| v2 視覺檢查 | 主殼較 v1 長窄、短頸與身形較接近原版；金色反光仍較強，未宣稱完全一致 |
| 使用者美術驗收 | PENDING |
| 新 v2 的 3D／UV／動畫／遊戲套用 | NOT RUN，圖稿不是模型 |

![Cygni 遊戲比例風格參考 v2](cygni_style_trial_v2.png)

[相同全身顯示高度的原版／v1／v2 比較](cygni_same_height_comparison.png)：只裁切與等比例縮放，沒有重畫原版或改光影。

## 重現原版研究

```bash
godot --headless --path . --script res://tools/armor_facets/export.gd
godot --path . --rendering-method gl_compatibility --script res://tools/armor_concept_runtime/capture_legacy_style.gd
python3 tools/armor_concept_runtime/analyze_legacy_style.py
```

原版 contact sheet：

![原版家族基準](references/original_style_sheet.png)
