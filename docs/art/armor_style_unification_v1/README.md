# 裝甲畫法統一與頭盔修正

Tank 的 [三版比較頁](index.html#tank) 已進入最新頭盔修正 v6。Viper／Fortune 各自既有的 15% 契約不變；Tank 按真正原版總 20% 上限驗收，上限不是必須達到的改動量或美術相似度。前一輪五張畫法版的結果獨立保留為歷史，不能用純貼圖的零新增模型结論描述這次頭盔造型修正。

## Tank 最新頭盔修正 v6：形狀與貼圖分開驗收

使用者指出畫法 v2 的頭盔與最新附圖仍有差異，因此本次調整頭部主 surface 的位置／法線並重新生成頭部 atlas。[最新頭盔參考](../tank_runtime_v1/approved_helmet_reference.png) 原樣保存；四張身甲 atlas、頸襯與其他部件、所有 UV／索引／骨架／權重及材質參數保持 v2。這版的耳盤以既有側板與貼圖表現，沒有另外新增獨立耳罩網格。

第二欄是 [Tank v2 修正前獨立快照](revisions/tank_style_v2_before_helmet_refinement/snapshot.json)，保存 52 筆固定檔：15 張實機圖（含兩張灰模）、五張 atlas、SCN／GLB／packed master／來源及 target、報告、完整實送提示詞、歷史共用 PASS 等。完整 runtime 另凍結 [73 檔](../tank_runtime_v1/revisions/before_helmet_refinement_v3/snapshot.json)。更早的 shared46、runtime319、Viper／Fortune 等快照均保持不可變。

v6 相對真正原版的頭部最大位移為 11.8456%，三軸尺寸差約 0／2.42184／0%，四向整體灰模差最大 2.15383%；均在原版總 20% 上限內。相對 v2 有 86 個頭部位置紀錄改動、新增 UV 0。頭部主 surface 原有 4／149（2.68456%）UV 調整、胸主 surface 12／210（5.71429%）均沿用；全套座標及 chart 數量不增加。

15 個 runtime 姿勢、9 個 GLB 姿勢、五圖 SCN／GLB／packed master 一致性與 64 張 normal imported resources 擷取已通過。正式第二次 v6 擷取的實際存檔前後 SHA 相同；[第一次擷取](../tank_runtime_v1/review/failed_capture_v6_savecheck/capture.json) 的 save_unchanged 失敗仍保留，不能當作正式通過證據。[本輪 after15 索引](tank_helmet_refinement_after_snapshot.json) 記錄每張正式圖與當前 SCN／貼圖／capture SHA；Tank 嚴格來源 helper 已通過，第三欄顯示 v6 正式图；全六套當前 strict 來源與工程驗證已通過；美術仍待逐套評價。

[最新完整 head prompt](../tank_runtime_v1/prompts/head_diffuse_helmet_refinement_v6.txt) 與 [v3–v6 生成歷程](../tank_runtime_v1/helmet_refinement_v3_generation.json) 保留原始生成檔及未採用候選。後腦大面積黑色空白侵入已由原生生成補齊鋼藍 chart 覆蓋；薄暗描邊、低模冠頂折角與部分偏亮接觸邊仍可見。工程 PASS 不表示已完全還原參考或使用者認可美術。

## Tank 畫法第一輪歷史：保留設計、獨立驗收

Tank 保留使用者已確認的大金色面罩、中央下緣尖折、藍綠分節頭冠、厚眉、圓耳罩、實心中央護片、短橫進氣口，以及藍甲／綠邊／黑棕內襯。目標是與 Viper／Fortune 使用同一套寬柔高光、克制接縫和稀疏磨損，不將面罩縮成被否定的平下緣版本，也不藉由貼圖畫出模型沒有的新增厚度。

本輪前的 Tank 在 [tank_baseline_snapshot.json](tank_baseline_snapshot.json) 獨立凍結：26 個 `before/tank` 素材及實機檔案、15 張原版圖和 5 份歷史報告，共 46 筆 SHA 記錄。原先 Viper／Fortune 的 52 筆與 Fortune v7 的 56 筆不可變快照均不擴寫、不覆蓋。另有 [完整 runtime 凍結索引](../tank_runtime_v1/revisions/before_style_unification_v2/snapshot.json) 保存管線所需資料。

修改前的 Tank 實測為頭部最大位移 2.97859%、三軸尺寸差 0；頭部主 surface 的 UV 改動為 4／149（2.68456%），胸主 surface 為 12／210（5.71429%），其餘 surface 為 0。本輪工程檢查確認這些模型與 UV 數值保持；新增形狀及 UV 改動皆為 0。使用者允許 20% 上限，實際仍通過既有更嚴格的 15% 管線條件。五張 atlas 供六個材質 surface 使用，頭盔第二個 surface 的深色頸襯取樣自手臂 atlas 上區，必須單獨確認其 14 個 UV 與貼圖連續。

五張原始 PNG 已原樣套入 SCN／GLB／packed master，來源及 SHA 收錄在 [生成記錄](../tank_runtime_v1/style_unified_v2_generation.json)。新圖的密集白裂網收斂、藍甲高光更寬柔，並保留橙金大面罩中央尖折、雙綠冠條、耳盤、綠 U 領與上翹肩。部分接觸邊仍較亮，冠頂低模角面沒有改動；這是具體美術觀察，沒有客觀相似度分數。歷史 v2 正式圖取正常資源重新擷取的 15 張图，SHA 保存在 [v2 after 索引](tank_style_unified_after_snapshot.json)，候選預覽不作為正式交付。

歷史 v2 的 15 個 runtime 姿勢、9 個 GLB 姿勢、五張 master／GLB 貼圖與實際 SCN／packed master 不變量、四向灰模和 64 張正式擷取均通過。共用 [validate.json](validate.json) 核對新擷取對應目前模型、五張貼圖及報告，分開保存 20% 使用者上限與實際 15% 管線條件。

Tank 各張 [head](../tank_runtime_v1/prompts/head_diffuse_style_unified_v2.txt)、[body](../tank_runtime_v1/prompts/body_diffuse_style_unified_v2.txt)、[shoulder](../tank_runtime_v1/prompts/shoulder_diffuse_style_unified_v2.txt)、[hand](../tank_runtime_v1/prompts/hand_diffuse_style_unified_v2.txt)、[foot](../tank_runtime_v1/prompts/foot_diffuse_style_unified_v2.txt) 提示詞含完整畫法基底及該部件補充。新輸出必須先套回原模型，確認原版／本輪前／新版三欄、四向頭盔與全身、待機／跑動／換彈、兩個關卡，以及實際 SCN／GLB／packed master 的來源一致。歷史 PASS 不會當作新版本結果；每套裝甲的上限及實際改動分開標示。

## 下一套首版素材：Hydra → Strike → Titan

本輪接續製作 Hydra ID3、Strike ID4、Titan ID5，到 Thunder ID6 前停止。本輪開始時三套沿用遊戲的原版 refined fallback，尚無已採用的新設計專用 runtime；被拒絕的 `concept_runtime` 平塗場景屬歷史。比較頁因此使用「原版／首版遊戲素材」兩欄，另有清楚標示的設計參考入口，不填假的修改前新模型。正式圖片未完成時，兩欄按實際檔案顯示等待。

Hydra 以 [已確認的 C-04 概念](../original_armors_v1/images/c04_concept.png) 為權威：黃綠大面罩、短下護邊、小中央護片與單方額頭裝置。Strike 身甲沿用 [C-05 概念](../original_armors_v1/images/c05_concept.png)，頭盔優先 [最新指定 JPG](../fusion_v2_generated/c05_strike_fusion.jpg)：雙青冠線、小點、收口青玻璃與短下巴，不能把概念圖尚未同步的大冠圓環當最新頭盔。Titan 以 [C-06 概念](../original_armors_v1/images/c06_concept.png) 及三視作目前施工方向：大包覆金面窗、厚頰封閉下顎、金肩緣與兩側前臂各三黃點；兩張早期使用者頭盔附件沒有本地檔案，本地 EVA 候選已被取代。各套首版仍待人工美術評價。

Hydra 已接入正式 v2 首版遊戲素材：頭部最大 rest 位移 14.74399%、三軸尺寸差近零、四向整體灰模差最大 1.88081%；全套 UV 0／726 修改、760 三角面與 28 骨架保持。這是 current manifest／packed master 的量測，不能將先前候選數字當正式結果。原肩部兩個 v=-0.0021 UV 原樣繼承並保存 [範圍檢查歷史](../hydra_runtime_v1/review/failed_legacy_uv_range_history.json)。15 runtime／9 GLB／五張原生與 packed 圖完整 RGB0、64 normal ANGLE 擷取及 [嚴格來源 helper](hydra_first_integration_validate.json) 均通過；[本頁30圖來源索引](hydra_first_runtime_snapshot.json) 保存原版與首版的相同相機 PNG。v2 已收成單中央額前鏡頭與短下巴；仍有低面數切面、部分較亮接觸邊及玻璃中央鏡像反光，人工美術驗收待完成。Strike正式版本已完成；Titan已進入v4，最新結果與歷史來源分開列在下文。

Strike 正式 v3 的頭部最大 rest 位移 9.29106%、四向整體灰模差最大 1.19545%；UV 0／709 改動，722 三角面、28 骨架保持。最新 JPG 的兩條縱向青冠線及兩小點已依 [真實 UV 技術導引](../strike_runtime_v1/guides/strike_crown_longitudinal_v2.json) 定位，並收平前額冠面階差。原冠片暗描邊、少量低模折面及正面玻璃的明亮鏡像反光仍可見。完整 [最新 head prompt](../strike_runtime_v1/prompts/head_diffuse_original_integration_v3_head.txt)、[30圖索引](strike_first_runtime_snapshot.json) 與 [獨立嚴格 helper](strike_first_integration_validate.json) 可追溯實際採用版本。

Titan 目前為 [v4 圓弧面罩](../titan_runtime_v1/revisions/helmet_refinement_v4/index.html)：原版總頭部位移19.2932%、四向整體灰模差最大3.6761%，形狀上限20%；正面可見琥珀玻璃／整個頭盔mesh投影54.8105%，達到50%門檻。頭部164 tris／334 UV，對原版124／294增長32.2581%／13.6054%，另按35%計數上限；10/294原UV修正承襲v3，新增40中點繼承父面UV與原綁定，3 charts／28骨架保持。四張非頭部圖與模型保留v3，每側前臂三金點仍成立。15 runtime／9 GLB、五圖RGB0／master5／SCN／guards5、64 Windows ANGLE正常資源與save_unchanged均正式PASS。美術接受／手機效能仍NOT RUN；低面數冠頂與耳殼、推定側後方及原遊戲短比例保留，不宣稱逐像素還原成人概念。[原生attempt2完整prompt](../titan_runtime_v1/revisions/helmet_refinement_v4/head_diffuse_prompt_attempt_02.txt)、[目前after15索引](titan_helmet_refinement_v4_after_snapshot.json)、[v2歷史15圖與舊30圖index](revisions/titan_v2_before_helmet_refinement_v4/snapshot.json)、[v3本輪前完整快照](../titan_runtime_v1/revisions/before_helmet_refinement_v4/snapshot.json)分開保存；original15沒有替換。

[validate.json](validate.json) 的共享來源驗證須在Titan v4頁面與metadata完成後重新核對；此前六套PASS屬歷史，不能自動當作v4。比較頁共有90張after圖，其中Titan15張已更新為v4；比較頁另有原版與需要的歷史修改前圖，共 225 張。這是工程與來源驗證，不是風格相似度或人工美術接受。Thunder ID6 不在本輪範圍。

三套按真正原版總 20% 工程上限，先凍結目前原版模型、材質與 UV／骨架，再生成並確認貼圖落點。Titan 身體材質順序與 Tank 相反，肩為 surface0、胸為 surface1；不能照抄標籤順序。原版 glTF 與材質需重新取樣並核對當前 SHA，歷史 inventory 提供定位而不替代最新基準。裝甲玩法 ID、背包與能力保持原狀。

## Fortune 頭盔修正與已完成的畫法階段

Fortune 第一輪畫法調整後，使用者指出頭盔設計仍不理想，因此另進入「頭盔造型修正」階段。這一階段允許在原版總 15% 工程預算內調整頭部頂點；UV、面索引、骨架、權重及其餘身甲保持目前配置。不得沿用第一輪的「新增模型改動為零」結論描述這次修正。Viper 仍是純貼圖調整。

頭盔修正須使用 [helmet_refinement_prompt.txt](helmet_refinement_prompt.txt)：使用者認可的概念提供設計，現有 atlas／區域 guide 提供位置，原版提供畫法。被否定的實機稿只用來定位問題，不能當成所有特徵都必須保留的設計權威。軟體改形和圖片生成分開驗收；圖片生成保留現有 UV 排列，不以畫出假凸起取代模型修正。

送出頭盔圖像生成前先讀 [UV 定位注意事項](helmet_mapping_notes.md)，由原模型和區域 guide 確認正面、耳側與鏡像邊。Fortune 的實際前眉在 atlas 左上斜帶；不得再依貼圖外觀猜前後而畫反。

Fortune 被評價前的 v7 已完整凍結於 [修正前快照](revisions/fortune_head_v7_before_refinement/snapshot.json)，包括實機圖、五張貼圖、模型與 PASS 報告。下方「零新增模型／UV」規則描述第一輪畫法階段；後續頭盔修正依上方契約及最新 `validate.json` 的獨立量測。

最新版 Fortune 已採用 [v11 完整提示詞](../fortune_runtime_v1/prompts/head_diffuse_refinement_v11.txt) 產生的原始頭部 PNG，並套入 SCN／GLB／packed master。這輪只改頭部位置與法線，UV 沿用 v7；相對真正原版的頭部最大位移為 14.7363%，四向灰模差最大 3.81494%，都在既有 15% 限制內。15 個 runtime 動作、9 個 GLB 動作、貼圖／master 一致性與 64 張正常資源擷取已通過。頭圖使用引擎 importer 的 lossless 匯入，解決原壓縮兩處色彩取樣超差；原始 PNG 沒有修改，驗收容差沒有放寬。

這版修正薄藍眉位置、取消藍鼻三角、收回面罩及下巴前突，並收斂粗側後藍帶與增加現有側面板的耳罩陰影。頂冠仍有原低面數折角，後腦中央暗縫仍可見；這些是明列的美術落差，工程 PASS 不表示使用者已認可。

第一輪先調整 Viper／Fortune 的貼圖畫法，保留當時採用的新版頭盔及甲片配置。目標是讓高光、邊線、黑縫和磨損屬於同一套手繪科幻風格，不以增加細節或縮小百分比代替美術驗收。

## 後續優化的必要提示詞

[base_prompt.txt](base_prompt.txt) 是後續裝甲「貼圖畫法統一」階段的必用基底。每張實際生成提示詞必須包含完整基底，再附該裝甲、材質與 UV 接縫的具體補充，不能只寫「按照通用風格」。完整實送提示詞保存在各自 runtime 目錄的 `prompts/`。

參考責任固定：使用者最新決定 → 已確認的新設計 → 目前模型及 UV 的實際位置 → 原版貼圖的畫法。原版只提供高光、筆觸與磨損尺度，不得把新頭盔改回舊額徽、鼻甲或下巴。`legacy_armor_base_v2/base_prompt.txt` 保留為概念轉遊戲的歷史基底，本輪補上更具體的畫法與新設計保存要求。

每次送出前填寫：

- 遊戲名稱、visual ID、材質標籤及已確認的特徵。
- 輸入圖實際路徑及用途：編輯目標、原版畫法參考、模型／頭盔定位參考。
- 必須保留的 UV 島位置、方向、鏡像接縫與大色塊邊界。
- 本次只調整哪一種畫法；不得順便新增頭盔、甲片、孔洞或機械結構。

每次送出後保存完整 prompt、不可變輸入快照、SHA256、原始輸出、時間和採用／未採用原因。生成圖片必須在模型上核對，不能只憑 atlas 精細就採用。

## 第一輪畫法階段的製作邊界與驗收

相對於 `before/` 快照，頂點位置、UV、索引、骨架、權重、skin 與掛點均不再調整。沿用先前已驗證的原版 15% 局部改動預算，不把它當成貼圖重畫面積或風格相似度。本輪新增 UV／模型改動量應為零。

Viper 保留黑眉、連續紫色切面面甲、斜削下巴、雙胸窗、層疊腹甲、大腿分色及四片背甲。Fortune 保留橄欖綠圓冠、薄銀藍眉帶、連續紫面罩、短實心下巴、兩側小槽及 U 形胸框。

寬而柔和的高光、克制的深色接縫、少量接觸邊磨損與連續面甲反光，是共同畫法。例如 Fortune 不得再出現兩根亮柱或中央黑色 W 分界；Viper 每片甲板不得都有同樣亮的細白框。

核對同相機四向、灰模，再看正常遊戲距離、待機、跑動及換彈。工程通過只證明可用與相容，最終畫法仍待使用者評價。未來若必須改成立體甲片，另開造型修正階段，不在這個階段偷偷移 UV 或畫假厚度。

## 比較與追溯

[index.html](index.html) 提供原版、修改前新設計與最新調整的實機比對，各裝甲欄位標明實際階段。Fortune 頭盔修正的前版為凍結 v7；`baseline_snapshot.json` 與 `before/` 另外保留第一輪畫法開始前的資料，不會因後續修正而覆寫。調整後畫面取正常匯入與編譯資源，不以 raw atlas 試貼代替正式交付。

較早的 [新舊風格分析](../armor_style_comparison_v1/index.html) 已固定為修改前快照，避免舊結論對到新圖片。

第一輪十張 PNG 透過內建 imagegen 生成並原樣套用至遊戲資源。當輪每套十五個 runtime 姿勢、九個 GLB 姿勢、packed master 和貼圖一致性均通過；各六十四張正常資源實機圖完成。當時頭盔眉沿、下巴、胸框或扣具仍保留部分亮邊，屬保守第一輪。之後 Fortune 頭圖已由上述 v11 修正版取代；第一輪的結果與報告保存在 v7 快照，本頁顯示最新正常資源圖。

從 repo 根執行 `python tools/armor_style_unification_v1/validate.py` 核對不可變輸入、必要 prompt、原始 PNG、實際 SCN 與新增模型／UV 改動量；執行 `python tools/armor_style_unification_v1/review.py` 重建比較頁。`validate.json` 保存最新交付結果，區分 Viper 純貼圖不變量、Fortune 原版總 15% 頭部修正、Tank 原版總 20% 頭部修正，以及三套首版素材的原版總 20% 範圍；最後的瀏覽器檢查在 `review_browser/`。
