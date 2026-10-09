# Titan · C-06 · 玻璃與護框修正版 v5

**本輪採用原生 attempt 3 頭圖，收整耳側與下護框，面罩上緣反光更連續、玻璃的細橫線更克制。** v4 的大面罩已達工程門檻，這次修正較不透明的玻璃畫法與硬側框。肩、胸、手、靴四張貼圖與非頭部模型保留 v4；遊戲 ID 5、四件裝備、獨立背包與 28 原骨架對應不變。

**v5 是可用的本輪修正版；工程 PASS，使用者美術接受與手機效能仍為 NOT RUN。** 不宣稱完美或與成人概念逐像素重合。冠頂與耳側仍可見原低面數切面，沒有新增概念中的獨立小圓耳與單一中心銀扣，側後方由指定斜視概念和原頭殼推定。

## 比對與歷史

[開啟真原版／固定 v4／本輪 v5 比對](revisions/helmet_refinement_v5/index.html)。四向、兩版／三版並排與大圖使用正式 PNG 和各自 SHA；第三欄為本輪最新 Windows ANGLE 正常資源擷取，可展開全部 64 圖。

- 真原版是遊戲原素材與原模型；上一版 v4 不是原版。
- [本輪前固定 v4 快照](revisions/before_helmet_refinement_v5/snapshot.json)保留素材、模型、報告與擷取；[v4 歷史頁](revisions/helmet_refinement_v4/index.html)與 [v3 歷史頁](revisions/helmet_refinement_v3/index.html)沒有覆寫。
- [系列比對頁](../armor_style_unification_v1/index.html#titan)的 Titan after15 已切換 v5；[前一版 v4 固定15圖](../armor_style_unification_v1/revisions/titan_v4_before_helmet_refinement_v5/snapshot.json)與[最早 v2 首版歷史](../armor_style_unification_v1/revisions/titan_v2_before_helmet_refinement_v4/snapshot.json)保留。
- [C06 原概念圖庫](../original_armors_v1/index.html#C-06)仍是設計參考；技能提案與背包設計沒有因此實作或更改。
- 2026-10-06 的 [Mac 草稿對齊試作](review/draft_alignment_20261006/index.html)另保留當時狀態；正式 v5 使用下面的新工程與視覺證據。

## 模型、UV 與面罩覆蓋

**本輪沒有再增加 UV 或三角形；334 個頭部 UV 與索引和固定 v4 逐項相同。** 十個原 UV 改動、40 個原邊中點均承襲上一版，3 個連續 UV 區域保持。只收整既有耳側與下框座標，形狀仍從真正原版計算總 20% 上限，頭部計數仍按原版 35% 上限。

| 實測項目 | 真正原版 | 固定 v4 | 本輪 v5 |
| --- | ---: | ---: | ---: |
| 頭盔三角形 | 124 | 164 | 164（對原版 +32.2581%） |
| 頭盔 UV 座標 | 294 | 334 | 334（對原版 +13.6054%） |
| 頭盔連續 UV 區域 | 3 | 3 | 3 |
| 原頭盔 UV 修改 | — | 10／294 | 10／294（3.4014%）；本輪新增 0 |
| 對原版新增頭部座標 | — | 40 | 40；繼承原父面 UV 與綁定 |
| 整套三角形／UV | 700／1607 | 740／1647 | 740／1647 |
| 原骨架 | 28 bones | 28 bones | 28 bones |

[最新幾何](build/geometry.json)的原版總最大位移為 **19.4967%**，寬／高／深度差為 **15.6456%／1.3127%／3.5622%**。反轉與零面積三角形均為 0，接縫間隙 0。四向整體灰模最大 1−IoU 為 **3.7609%**；上述均是工程量測，不能當作風格相似率。

**正面玻璃投影覆蓋為 58.0930%，達到至少 50% 門檻。** [覆蓋報告](review/helmet_v5_visor_coverage.json)用本輪正式材質與相同相機的白色 silhouette，計算可見琥珀玻璃像素／整個頭盔 mesh 的正面投影；分母包含該 mesh 的頸部。固定顏色分類沒有因本輪調高或放寬；這不是 3D 表面面積、圓度評分或美術接受。

## 原生貼圖與必要 prompt

**採用頭圖為 1254×1254 的 opaque 原生 PNG，和 image_gen attempt 3 輸出位元組相同。** 沒有程式重畫、改色、縮放或合成；alpha 仍為 255。玻璃質感是 diffuse 中的反光畫法，沒有新增實際透明材質。其他四張 diffuse 與 v4 固定快照完全相同。

- [採用 attempt 3 完整實送 prompt](revisions/helmet_refinement_v5/head_diffuse_prompt_attempt_03.txt)與[完整生成記錄](revisions/helmet_refinement_v5/generation_record.json)。
- [未採用 attempt 1 記錄](revisions/helmet_refinement_v5/generation_record_attempt_01.json)與[未採用 attempt 2 記錄](revisions/helmet_refinement_v5/generation_record_attempt_02.json)及各自原生 PNG／實送 prompt 全部保留。
- [後續頭盔優化的必要 prompt 條件](revisions/helmet_refinement_v5/asset_brief.md)：UV 鏡像取樣、連續反光、冠部與護框畫法、原版預算、原生來源及驗收流程。
- [目前設定](runtime_config.json)與[目前 manifest](manifest.json)記錄實際遊戲素材；[真正原版固定來源](revisions/original_source_v1/snapshot.json)不變。

## 本輪實際驗證

**下面所有 PASS 均使用本輪新素材與新報告，沒有引用 v4 PASS。** 平台為 Windows Compatibility／ANGLE／RTX 4080 Laptop GPU；頭部／姿勢 640×720，遊戲場景 1280×720。64 張使用正常引擎匯入資源，存檔前後 SHA 相同。遊戲場景為停止戰鬥的鏡頭擷取，不是效能測量。

| 檢查 | v5 狀態 | 實際範圍 |
| --- | --- | --- |
| SCN／原部件／模型目標 | PASS | 頭部符合目標；其他三部件 arrays、skin、掛點保留 |
| UV／拓撲／綁定契約 | PASS | 164 tris／334 UV／3 區域；與 v4 UV／索引相同 |
| 正面面罩投影 | PASS | 58.0930% ≥50%；整個頭盔 mesh 投影 |
| 遊戲換裝與動作 | PASS | 15 個 runtime 姿勢，真實存檔不變 |
| GLB 回讀 | PASS | 9 姿勢；頭圖 30 RGB 取樣誤差 0，容差仍 0.05 |
| 五圖／packed master | PASS | 五張 canonical／GLB／master 原生圖與模型目標 |
| 防護與故意破壞契約 | PASS | 五項工具防護與實際契約測試 |
| 四向整體灰模 | PASS | 最大差 3.7609%，相機一致 |
| 正常資源擷取 | PASS | 最新64圖、SCN／target／貼圖 SHA 及存檔綁定 |
| 使用者美術接受 | NOT RUN | 待使用者評價玻璃、冠部、耳側與整體風格 |
| 手機效能 | NOT RUN | 未進行實機 profiler 或 GPU 記憶體量測 |

- [最新64圖與資源／存檔綁定](review/helmet_v5_final/capture.json)
- [GLB](review/helmet_v5_glb_test.json)、[packed master](review/helmet_v5_master_test.json)、[五項防護](review/helmet_v5_contract_and_guards_test.json)
- [四向灰模](review/helmet_v5_proportion_test.json)、[正面覆蓋](review/helmet_v5_visor_coverage.json)、[lossless 引擎匯入](review/helmet_v5_lossless_import.json)

Lossless 匯入讓頭圖 30 個 GLB RGB 取樣誤差為 0；手機 GPU 記憶體成本未量測。沿用專案既有素材來源與授權假設，本次製作不新增原素材授權證明。
