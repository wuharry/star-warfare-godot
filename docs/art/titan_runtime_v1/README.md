# Titan · C-06 · 圓弧面罩與下護框修正 v4

**本輪以 v3 為基礎，增加頭盔的局部圓弧切分，採用煙燻琥珀面罩與連續鋼藍下護框。** 次要金色側翼已收小，正式擷取與模型／貼圖檢查已完成。修改只涉及頭盔模型與原生頭圖；肩、胸、手、靴四張貼圖、其他三部件與 28 原骨架保留 v3。Titan 遊戲 ID 5、四件裝備與獨立背包對應不變。

**最新要求是面罩更圓，且至少佔正面頭盔投影面積的 50%。** 圓弧已透過模型切分調整；正式正面投影量測為 **54.8105%**，達到 50% 的工程門檻。這是可見琥珀玻璃像素／整個頭盔 mesh 正面投影的比例（包含該 mesh 的頸部），不是 3D 表面面積、圓度評分或美術相似率。

**v4 最新工程檢查 PASS；使用者美術接受與手機效能均為 NOT RUN。** 15 個 runtime 姿勢、9 個 GLB 姿勢、五圖 RGB 一致、packed master、SCN 不變量、五項契約／故意破壞防護、四向整體灰模、正面 coverage 及正常資源 64 圖均有最新報告；不引用 v3 PASS 作本輪證據。

## 預覽與版本

[開啟真原版／上一版 v3／本輪 v4 比對](revisions/helmet_refinement_v4/index.html)。可切四向、選兩版或三版並排及放大原圖；第三欄是 Windows ANGLE 正常資源的最新 v4 原始擷取，可另展開全部 64 圖。

- 「真原版」指遊戲原素材與原模型。
- 「上一版 v3」引用 [本輪開始前的固定快照](revisions/before_helmet_refinement_v4/snapshot.json)，並非真原版。
- [v3 歷史頁](revisions/helmet_refinement_v3/index.html)保留當時的模型擷取、生成與工程結果；不覆寫。
- [C06 原概念圖庫](../original_armors_v1/index.html#C-06)與[系列早期風格對照](../armor_style_unification_v1/index.html#titan)保留原設計及歷史參考。

## 模型與 UV 的實際預算

**v4 本次新增局部圓弧切分，頭盔面數與 UV 座標數按真正原版的 35% 增幅上限檢查；形狀位移仍按原版總 20% 上限。** 新中點從原父面繼承 UV 邊與骨架綁定，保留 3 個連續 UV 區域。十個原有 UV 取樣修改承襲 v3；新增座標數與「原有座標被移動的數量」分開計算，不能把本次描述為 UV／拓撲完全未增加。

| 實測項目 | 真正原版 | 上一版 v3 | v4 正式模型 |
| --- | ---: | ---: | ---: |
| 頭盔三角形 | 124 | 132 | 164（對原版 +32.2581%） |
| 頭盔 UV 座標 | 294 | 302 | 334（對原版 +13.6054%） |
| 頭盔連續 UV 區域 | 3 | 3 | 3 |
| 原頭盔 UV 取樣修改 | — | 10 / 294 | 10 / 294（3.401%；承襲 v3） |
| 對原版新增頭部座標 | — | 8 | 40；各繼承父面的 UV 與綁定 |
| 整套三角形／UV 座標 | 700／1607 | 708／1615 | 740／1647 |
| 原骨架 | 28 bones | 28 bones | 28 bones |

目前 [geometry.json](build/geometry.json) 的模型量測：頭部最大局部位移為原最短邊的 **19.2932%**，低於真原版總 20% 上限；頭部寬度差 12.5119%、高度差 1.3127%、深度差 3.5622%。面數與座標數的增幅均低於 35% 計數上限。最新逐頂點、權重與資源檢查已通過。四向整體灰模的最大 1−IoU 為 **3.6761%**；上述數字均屬工程量測，並非風格相似率。

## 原生美術與歷史來源

**v4 頭圖採用實際 image_gen 的原生輸出，沒有程式重畫、改色、縮放或合成。** 本輪 PNG 與採用生成原圖位元組相同；其他四張 diffuse 已驗證與凍結 v3 位元組相同。

- [採用 attempt 2 的完整實送頭圖 prompt](revisions/helmet_refinement_v4/head_diffuse_prompt_attempt_02.txt)。沒有 attempt 3；正式採用圖為 attempt 2。
- [生成器、參考輸入、採用原圖與 SHA 紀錄](revisions/helmet_refinement_v4/generation_record.json)。
- [目前 runtime 設定](runtime_config.json)、[幾何量測](build/geometry.json)與[目前 manifest](manifest.json)。
- [真正原版固定快照](revisions/original_source_v1/snapshot.json)與 [v3 本輪前快照](revisions/before_helmet_refinement_v4/snapshot.json)保持不變。

沿用專案既有的素材來源與授權假設；本次製作不新增原素材授權證明。C06 概念、技能提案與背包設計不因此修改。

## 本輪驗證

**新 v4 工程證據已確認。** 擷取平台為 Windows Compatibility／ANGLE／RTX 4080 Laptop GPU；頭部與姿勢為 640×720，遊戲場景為 1280×720。64 張使用正常引擎匯入資源，實際存檔前後 SHA 相同。遊戲場景為停止戰鬥的鏡頭擷取，未量測手機效能；v3 歷史頁的 Apple M4 結果只代表該歷史版本。

| 檢查 | v4 狀態 | 範圍 |
| --- | --- | --- |
| SCN／原件／模型目標 | PASS | 頭部符合最新目標；其他三部件 arrays、skin、掛點保留 |
| 頭盔切分／UV 契約 | PASS | 164 tris／334 UV／3 區域；35% 計數上限，20% 形狀上限；原父面與原權重繼承 |
| 面罩正面投影覆蓋 | PASS | 54.8105% ≥ 50%；[coverage 定義與報告](review/helmet_v4_visor_coverage.json) |
| 遊戲換裝與動作 | PASS | 15 個實際姿勢及換裝入口 |
| GLB 回讀 | PASS | 9 姿勢、最新五圖／UV／28 原骨架 |
| Blender master | PASS | 最新目標與五張內嵌原生 PNG |
| 正常資源擷取 | PASS | Windows ANGLE 最新 64 圖、資源 SHA 與真實存檔不變 |
| 使用者美術接受 | NOT RUN | 待使用者評價面罩、護框及整體風格 |
| 手機效能 | NOT RUN | 未進行實機 profiler 或量測 |

草稿只有斜視圖，側後方深度由原頭殼推測。新局部圓弧仍受遊戲原比例與 35% 計數上限約束，不宣稱完全還原概念或已達成使用者美術接受。系列比對頁目前 after 已更新為正式 v4。原 v2 首版另保存 [固定 15 圖及舊索引](../armor_style_unification_v1/revisions/titan_v2_before_helmet_refinement_v4/snapshot.json)；[v4 after15 索引](../armor_style_unification_v1/titan_helmet_refinement_v4_after_snapshot.json) 綁定當前 SCN／貼圖／capture SHA，original15 沒有替換。

Lossless 引擎匯入使正式 GLB 頭圖 30 個 RGB 取樣誤差為 0；早期壓縮取樣 0.06667 曾超過 0.05，改用高保真匯入後通過，沒有提高容差。仍保留低面數冠頂與耳殼及原遊戲短比例；只有斜視概念，側後方為推定，不宣稱逐像素還原成人概念。

- [最新 64 圖與存檔／資源綁定](review/helmet_v4_final/capture.json)
- [頭盔切分與五項防護](review/helmet_v4_contract_and_guards_test.json)
- [五圖 GLB](review/helmet_v4_glb_test.json)、[packed master](review/helmet_v4_master_test.json)、[lossless 匯入](review/helmet_v4_lossless_import.json)
- [四向灰模](review/helmet_v4_proportion_test.json)、[正面玻璃覆蓋](review/helmet_v4_visor_coverage.json)
