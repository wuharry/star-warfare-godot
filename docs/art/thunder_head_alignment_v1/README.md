# Thunder · 新版頭盔正式整合

**新版頭盔已套用至遊戲預設 Thunder A，身甲保持先前採用的 B 舊稿與已整合模型。** 本輪依較晚 C07 頭盔調整冠脊、金圈圓耳、連續金面窗與下框，採用原生 atlas attempt 2。較晚 JPG 的成年身甲、胸肩與四肢沒有一併替換；裝甲 ID6、技能、購買、存檔與獨立背包對應保持。

**本輪工程與30組正常資源擷取 PASS；使用者美術接受、手機效能與瀏覽器互動仍為 NOT RUN。** 下護頰兩側仍較尖、中央保留原 A 的通氣插片，黑眉沿比指定 C07 概念厚。側後方由目前頭殼推定，不宣稱完美或逐像素還原。

[開啟前後模型與兩份概念比對](index.html)。27組受控棚拍／動作使用相同相機、姿勢、光照與視口；3組 live 關卡的 NPC／時間有差，只作遊戲可讀性預覽。可切全部30個視角，點擊原圖放大，前後60張PNG均綁定各自原檔SHA。

## 外觀來源

- [較晚 C07 fusion JPG](../fusion_v2_generated/c07_thunder_fusion.jpg)是本輪頭盔設計方向：後掠冠、金框圓耳、窄金面窗、短護頰。原檔直接引用，沒有合成；該指定 commit 未記錄 JPG 的生成 prompt，不補造其來源。
- [B 新頭盔舊稿](../thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png)的身甲方向保持；其中舊頭盔屬歷史。本輪遊戲採用前已在 default A 的模型／材質，比較頁的 before 是該固定 A。
- C07 原始概念、三視與拆解保留歷史；它們尚未同步本輪頭盔。技能資料仍為提案，背包是另一件獨立裝備。

## 修改前基準與實測

**本輪20%形狀預算只相對固定 current A 計算；UV、三角形索引、skin與28具名綁定逐項保持。** 這個 A 已包含先前 SW2 來源頭部重建，不能把 current A 當 untouched classic SW1 原版。本輪沒有新增UV／頂點／三角形，非頭部三件的 arrays、材質、skin 與掛點完全相同。

| 實測 | 本輪前 A | 本輪新版頭盔 |
| --- | ---: | ---: |
| 頭部三角形 | 6284 | 6284 |
| 整套三角形 | 12662 | 12662 |
| 頭部拆分surface座標 | 18852 | 18852 |
| UV 座標修改／新增 | — | 0／0 |
| 三角形索引與skin | 固定前版 | 逐項相同 |
| 具名原骨架綁定 | 28 | 28 |
| 最大局部位移／前版最短邊 | — | 18.1759% ＜20% |
| 頭部寬／高／深尺寸差 | — | 0／+5.6267%／0 |
| 接縫最大間隙 | — | 0 m |
| 反轉／新增退化面 | — | 0／0 |

[完整幾何與來源檢查](geometry_validate.json)另列 raw SW2 頭部974三角形及先前整合後6284三角形（約6.4517倍）。這個增幅已存在於本輪前 A，不能宣稱相對該原來源的總計數變化僅15–20%；classic SW1頭部幾何等同性仍為NOT RUN，沒有以換基準假裝通過。

本輪對變形後頭部重算法線與實際使用法線貼圖的 tangent frame。未使用法線貼圖的非頭部既有 tangent 缺陷分開記錄，非頭部 arrays 保持；不把來源問題隱藏為全數無缺陷。

## 原生生成與後續 prompt

**採用原生 atlas attempt 2 與遊戲PNG位元組相同，未經程式重畫、改色、縮放或合成。** 未採用 attempt 1 原圖與實送 prompt 保留；生成來源、參考輸入與 raw SHA 在 [generation.json](generation.json)。法線、shader及其他材質來源由正式場景與報告記錄。

- [採用 attempt 2 完整實送 prompt](prompts/helmet_atlas_attempt_02.txt)
- [未採用 attempt 1 完整實送 prompt](prompts/helmet_atlas_attempt_01.txt)
- [後續必要 prompt](armor_head_alignment_prompt.txt)：頭盔／身甲參考分工、current A預算、原來源差異、UV保留與真正遊戲驗收。

## 本輪驗證與擷取

**所有PASS均為本輪最新SCN／素材／報告；不沿用前輪A的PASS。** [交付驗證](validate.json)記錄預設runtime、prototype回歸、compiler防護、正常資源擷取、actual SCN、Blender建置與head compile七項結果；compiler12項及checker8項故意破壞驗證亦通過。prototype場景保持前版，沒有修改其他頭盔候選。

| 檢查 | 狀態 | 範圍 |
| --- | --- | --- |
| 實際SCN與幾何 | PASS | current A總20%、UV／拓撲／skin與非頭部保持 |
| 預設與prototype裝備回歸 | PASS | 實際角色、部位、骨架與商店／裝備路徑 |
| compiler／checker防護 | PASS | 12／8項輸入與故意破壞檢查 |
| 最新正常引擎擷取 | PASS | Windows ANGLE Compatibility；27棚拍／姿勢與3 live關卡 |
| 正式PNG／資源／存檔 | PASS | 30張after與固定before原圖；current SHA，真實存檔不變 |
| 使用者美術接受 | NOT RUN | 待評價面窗、冠脊、圓耳與下框 |
| 手機效能 | NOT RUN | 沒有GPU／幀率／記憶體實機量測 |
| 瀏覽器互動 | NOT RUN | 尚未驗證DOM、手機viewport或互動；語法／檔案檢查不能代替 |

棚拍／姿勢為1200×1440，關卡為1600×900；27對取景／姿勢一致，3對live NPC／時間非決定性，不作像素差異評分。動作擷取包含持槍待機與換彈，不代表所有動畫或關卡皆無穿模。

- [固定本輪前112筆來源](before/snapshot.json)與[固定SCN arrays](before/scene_arrays.json)
- [actual SCN檢查](scene_test.json)、[目前完整arrays](scene_arrays.json)、[建模量測](build_measure.json)、[完整幾何／來源](geometry_validate.json)
- [最新after30圖與素材綁定](after/manifest.json)、[固定before30](before/resources/test_output/thunder_helmet_comparison/sw2/manifest.json)
- [交付驗證與日誌](validate.json)、[C07圖庫](../original_armors_v1/index.html#C-07)

本次修改不新增原素材授權證明。

## 重建與後續修改

從專案根目錄執行 `tools/armor_rework/build_thunder_head_alignment.py`（Blender Python），再用 Godot `--script res://tools/armor_rework/compile_thunder_head_alignment.gd` 寫入正式場景。建置固定讀本輪凍結 A；不要對已變形的模型再累加 helper。改形狀時須重算原平滑／硬邊群組的法線及切線，保留 UV 與原具名骨架。

接著執行 `tests/thunder_head_alignment_test.gd`、`tools/armor_rework/validate_thunder_head_alignment.py` 和既有 `tests/thunder_armor_test.tscn`；視覺仍使用正常引擎 `tools/thunder_helmet_comparison/capture.tscn`。任何新模型、貼圖或法線變更，都要刷新 after 擷取及 SHA。

[本輪逐圖目視紀錄](visual_review.json)已檢查最終30張，保留尖折下框、通氣插片及眉框等設計差異。[頁面資料檢查](page_validate.json)核對60張原圖、來源連結、圖庫資料與 JavaScript 語法，沒有執行瀏覽器互動。

資料夾的 `.gdignore` 避免引擎重新匯入凍結的重複資源／UID；測試以原生 SCN 和原始 bytes 直接載入，已實際確認可運作。
