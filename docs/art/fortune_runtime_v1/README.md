# Fortune 可套用遊戲素材

2026-10-04 最新交付採用 head refinement v11；body style v3、shoulder／hand／foot style v2 保持前輪 bytes 不變。頭盔以使用者指定的 `approved_helmet_reference.png` 為設計依據，修正實際前眉 UV 的藍帶位置、側耳罩位置、去除中央藍鼻尖並保留連續紫面罩。模型同步壓薄眉沿、抬平面罩下緣、縮短前突下巴；頂冠中央為 1.886 m，既有兩側上環為 1.847545 m，採 v10 箱形與 28 mm 試稿尖拱之間的 14 mm 折衷。原低面數仍會呈現折角，不宣稱已完全還原概念的圓冠；後腦中央原有暗縫仍殘留，v11 bleed 嘗試未完全消除。

這次允許頭部造型修正，與前一輪純畫法調整的零改形契約分開。`review/helmet_refinement_invariants.json` 直接比較最新實際 SCN 與凍結 v7 SCN：只有 head positions／normals 可變，全部 UV、index、weights、bones、Skin、物件 transforms，以及 body／limb 全部 arrays 必須精確相同。相對真正原版逐點量算最大位移 .0748000 m（14.7363%），頭寬差 0%、高差 3.9667%、深度差 7.6826%；沒有反向面、零面積面或鏡像位置間隙。UV 沿用既有 22/157 個 chin 座標改動（14.0127%），本輪新增 UV 改動為零，不在前稿累加另一個 15% 額度。

新 head PNG 由內建 image_gen 編輯，native 1254² 輸出只複製 bytes，沒有縮放、調色或濾鏡。V8～V10 未採用稿、實際完整 prompt、輸入快照、時間與 SHA 均保留於 `generated/`、`prompts/`、`input_snapshots/helmet_refinement_v8/`、`generation_inputs.json`。本輪基底使用 [頭盔修正 prompt](../armor_style_unification_v1/helmet_refinement_prompt.txt)，實際採用提示詞為 `prompts/head_diffuse_refinement_v11.txt`；其 painting 階段仍鎖 UV／mesh，軟體局部改形另以真正原版總 15% 驗證。其他四張貼圖仍依 [畫法統一基底](../armor_style_unification_v1/base_prompt.txt)。所有 selected 只表示目前工程採用，使用者美術驗收仍待確認。

頭部新的 neck 邊緣在預設 VRAM 壓縮下，有兩個 GLB 取樣通道差超過原 .05 容差（.08627、.05098）；原始 FAIL 報告／log 保存於 `review/compression_before_lossless/`。頭圖與 GLB portable 副本改用 lossless＋mipmaps，透過 `reimport_head_lossless.gd` 的 temporary EditorImportPlugin／`append_import_external_resource` 由引擎正常重建 metadata，PNG bytes 與其他四圖不變。取樣位置／容差沒有放寬；lossless 下 34 個 head 樣本 RGB 差為零。這會取消頭圖 GPU block 壓縮，新增實際 VRAM 開銷 **NOT RUN／未量測**；沒有以估計數字冒充量測。

最終驗證資料位於 `review/runtime_test.json`（15 動作）、`roundtrip_test.json`（9 GLB 動作／34 head 樣本）、`glb_images_test.json`（五張內嵌 PNG 全圖 RGB）、`delivery_validate.json`（packed master）、`helmet_refinement_invariants.json`（實際 SCN 原版總限額／增量不變量）、`proportion_test.json`（四向同鏡頭灰模）、`engine/capture.json`（64 正常 resource 實機圖），並由 `manifest.json` 串接當前來源、SCN、GLB、master、target、貼圖及每張實機 SHA。工程結果與使用者美術驗收分開；待機／跑動／換彈沿用原骨架與動作，暫存 profile 不寫真實存檔。

重建時從真正原版 `build/source.json` 執行 Blender `build.py`，使用既有 Godot 正常 import → `compile.gd` → `glb_unique_joints.py` → GLB import → editor `reimport_head_lossless.gd`。再執行既有 runtime／roundtrip、`validate_glb_images.py`、Blender `validate_delivery.py`、Godot `validate_helmet_refinement.gd`，最後正常 ANGLE `capture.tscn` → `measure.py` → `provenance.py` → `review.py`。不可把 raw-atlas-preview 當作正常載入／匯出驗收，也不對最新頭部再跑舊 paint-only `validate_style_pass.py` 來冒稱零改形。

前輪純畫法版本及舊 reproduction 腳本已凍結於 `../armor_style_unification_v1/revisions/fortune_head_v7_before_refinement/`。以下全文為 **v7 及更早的歷史紀錄，零新增模型結論與舊數值不描述最新交付**。

## 歷史：純畫法調整與頭盔 v6

2026-10-04 本輪完成五張貼圖的畫法統一：head style v7、body style v3、shoulder／hand／foot style v2。新增 PNG 由內建 image_gen 逐張編輯，原始輸出直接以 bytes 複製到 canonical，沒有縮放、調色或濾鏡處理。頭盔保留已確認 v6 的連續紫面罩、橄欖綠頂冠、細藍眉帶、實心短綠面甲與兩側小槽；胸口保留 v2 的 U 形框。這輪收斂甲片細白邊與密集刮痕，改用較寬柔的手繪漸層。膝／脛與手臂的刻線減少最明顯，頭盔眉沿和胸框仍採較保守的邊緣高光；這是待使用者評價的一次畫法調整，不宣稱已達到某個風格相似百分比。

相對本輪前的不可變快照 `../armor_style_unification_v1/before/fortune/`，新增 UV／模型變動皆為 **0**。`review/style_pass_invariants.json` 精確核對兩份 packed master 的頂點、UV loops、polygon indices／材質分區、weights、rest bones 與物件 transforms；target／geometry JSON bytes 及 original source SHA 相同。既有相對原版的 15% 限制仍保留，沒有累加新的改形額度。

本輪重新完成正常資源匯入、SCN／GLB 編譯、15 個 runtime 動作、9 個 GLB 動作、五張 GLB 內嵌 PNG 全圖 RGB 一致性、packed master、零改形不變量、輪廓與 provenance 檢查。64 張正式比較圖使用同一 Compatibility＋ANGLE／Direct3D11；已查看四向全身、頭部正／側／背、待機、跑動、換彈中段和兩個實際關卡，連續面罩未恢復成雙亮柱／W 分裂，既有接縫位置與動作未新增偏差。後腦原有中央細縫仍保留，頭／胸部分高光仍較亮，後續由使用者判斷是否再收斂。

後續優化必須從 [共用基底 prompt](../armor_style_unification_v1/base_prompt.txt) 開始，並加上每個材質的專屬約束。本次實際完整提示詞為 `prompts/head_diffuse_style_v7.txt`、`body_diffuse_style_v3.txt`、`shoulder_diffuse_style_v2.txt`、`hand_diffuse_style_v2.txt`、`foot_diffuse_style_v2.txt`。`generation_inputs.json` 保存原始工具輸出、時間、輸入快照與 SHA、prompt／base SHA、目前選用狀態和歷史取代關係。不可只拿舊原版 atlas 當新版的造型權威，也不可將共用 base 的零 UV／模型變動契約誤解為新一輪 15% 改動。

以下保留造型開發與原版工程比較的歷史背景；v6／body v2 是本輪鎖定的造型基準，canonical 貼圖已更新為上述畫法統一版本。

`index.html` 提供 Fortune ID 01／C-02 的原版、核准概念與新版實機比較；包括四向、頭盔、灰模、待機、跑動、九個換彈進度、兩個關卡，以及五張原版／新版 UV 貼圖。新版已接到遊戲、混搭與商店使用的共用裝甲載入器，存檔裝備 ID 不變。

頭盔以本輪使用者原始附圖 `approved_helmet_reference.png` 為最高造型依據；`../fusion_v2_generated/c02_fortune_fusion.jpg` 保留作歷史參考。新版採橄欖綠圓冠、狹窄銀藍眉帶、連續紫色面罩、小藍下唇、實心綠色短面甲與兩側小縱槽，以及胸口完整 U 形框。概念轉成 head、body、shoulder、hand、foot 五張專用 diffuse，保留原短壯遊戲體型，透過原骨架帶動。

第一稿沿用原 atlas 的額徽、鼻甲和 Y 形胸線，已留在 `review/first_material/`。頭部貼圖後續全面改畫，去掉眉上兩孔、前額 V 暗線、舊鼻甲與中央橫 vent，頸部改成中性黑。紫色 atlas 左緣實際是正臉中央鏡像接縫；最終 v6 在此保留連續中紫主面，清除先前兩根亮柱和黑色 W 分界，深紫側折面移到右側區域。身體採 v2，肩、手、靴採 v1。每次生成的提示詞、未採用圖、不可變參考快照、輸入與輸出 SHA256 保存在 `prompts/`、`generated/`、`generation_inputs.json`。

生成位置以原模型投影的 `guides/*_front_regions.*`、最終改形的 `head_semantic_*_v4c.*` 和中央鏡像邊定位 `head_visor_neck_semantic_v6.*` 為準。技術色區、UV 線與文字只作生成參考，不畫進 canonical 貼圖；舊 guide 及各版 raw 試貼保留。

本套沿用原 720 tris、四個部件、五個材質、28 bones、673 個 UV 座標與 19 個 UV charts。原 skin、triangle indices、weights、關節與掛點保留。UV 與外形差異上限為 15%，逐材質核對改動 UV 座標占比，並核對部件尺寸、以原部件最小尺寸正規化的頂點位移、同鏡頭灰模輪廓。貼圖重畫面積和概念相似度不當成這個百分比。

頭盔將 22/157 個原下巴 UV 向右移 .085 atlas units（14.0127%），採樣封閉綠面甲；仍是原 4 charts／157 座標。全套改動 22/673（3.2689%），其餘四材質 UV 精確相同。`guides/head_uv_authored.*` 呈現真正套用的下巴 UV。形狀從真正原版基準計算，保留圓冠、壓薄前眉、弱化中央鼻突並縮短下顎；最大 rest 位移 .0727188 m（原最小頭尺寸的 14.3263%），頭寬差 0%、高度差 1.9987%、深度差 5.7286%。沒有反向三角面、零面積面或鏡像接縫位置間隙。其餘三部件頂點位置與尺寸完全相同。原低面數切面和四肢輪廓仍保留；比較頁呈現實際套用結果，供逐套美術評價。

交付包含 `assets/armors/fortune_v1/fortune.scn`、帶原 skin 的 `fortune.glb`、五張 diffuse 和 `build/fortune_master.blend`。Master 內嵌五張 PNG，驗證其 packed bytes 與 canonical 貼圖一致。GLB 的 portable 圖片副本由 Godot 匯出產生。

`review/runtime_test.json` 驗證共用載入器、混搭、商店、原 weights／skin、十五個動作樣本；`roundtrip_test.json` 驗證 GLB 重新匯入後九個動作，並從真正頭部材質取樣 34 處 canonical v6 色彩。匯入貼圖的邏輯尺寸是 1254²，VRAM block 壓縮解碼為 1256²；取樣使用邏輯尺寸，最大 RGB 通道差 .04314，低於 .05 壓縮容差。`glb_images_test.json` 獨立循實際 node／mesh／primitive／material／texture／image 索引鏈解碼 GLB 五張內嵌 PNG，各 1,572,516 個像素全圖 RGB 與 canonical 完全相同，通道差為零。

`proportion_test.json` 只量相同鏡頭灰模輪廓，四向差異最大 2.8841%；`delivery_validate.json` 核對 packed master 的拓撲、權重、UV、位置與五張貼圖 bytes。十五個遊戲動作、九個 GLB 動作、master 與 canonical／SCN／GLB／target／生成來源 SHA 一致性均通過。runtime、roundtrip 與 capture 使用各自的暫存 profile，真實存檔 SHA 均未改動。這些檢查不代替使用者對造型的評價。

最終 64 張正常 resource 實機截圖全數重新使用 Compatibility＋內建 ANGLE（Direct3D11），原版與新版同一 driver。此次 NVIDIA 原生 OpenGL 在 renderer 初始化前於 `nvoglv64.dll` 發生 `0xc00000fd`，失敗啟動紀錄 `review/head_v6_preview_startup.log` 保留；ANGLE 實測 PASS 紀錄為 `review/final_angle_capture.log`。這次素材捕捉以命令列選擇 ANGLE；後續 2026-10-04 啟動修正將 Windows 預設 driver 設為 ANGLE，見 [啟動故障排查](../../GODOT_EDITOR_STARTUP.md)。使用者已開啟的 editor 未關閉或修改。manifest 保存最終 banner、log SHA 和 64 張圖片 SHA；Godot 會從 `OS.get_cmdline_args()` 濾掉 engine flags，因此 driver 證據取自本次啟動 banner。

重建順序，在 repo 根使用既有 Godot／Blender：

1. Godot `--headless --path . --script res://tools/fortune_runtime_v1/inspect.gd`。
2. Blender `--background --python-exit-code 1 --python tools/fortune_runtime_v1/build.py`。腳本從原版 source 重做局部 head shape 與 22 個 chin UV 位移，不會在前稿累加；產出 target、geometry 與 packed master。
3. 套用已選生成 PNG，Godot `--headless --editor --path . --import`。
4. Godot `--headless --path . --script res://tools/fortune_runtime_v1/compile.gd`；`python tools/fortune_runtime_v1/glb_unique_joints.py`；再讓引擎匯入 GLB。
5. Godot `--headless --path . --script res://tools/fortune_runtime_v1/render_uv.gd`；`python tools/fortune_runtime_v1/head_semantic_v4.py`、`python tools/fortune_runtime_v1/visor_neck_semantic_v5.py --revision v6` 可重建技術 SVG，再以 Godot `render_regions.gd -- --visor-neck-v6` rasterize。既有 generation guide 必須相同，否則另開 guide 版本，不覆寫輸入快照。
6. 執行 `tests/fortune_v1_test.tscn`、`tests/fortune_v1_roundtrip.tscn`；`python tools/fortune_runtime_v1/validate_glb_images.py`。Blender `--background docs/art/fortune_runtime_v1/build/fortune_master.blend --python-exit-code 1 --python tools/fortune_runtime_v1/validate_delivery.py`。
7. Godot `--rendering-method gl_compatibility --rendering-driver opengl3_angle --path . --log-file docs/art/fortune_runtime_v1/review/final_angle_capture.log res://tools/fortune_runtime_v1/capture.tscn` 產出正常 resource 64 張圖。
8. `python tools/fortune_runtime_v1/measure.py`；最後 `python tools/fortune_runtime_v1/provenance.py`、`python tools/fortune_runtime_v1/review.py` 更新 manifest 與比較頁。頁面預設頭盔近照，圖片 URL 使用最終 head SHA 前綴作 cache revision。

本輪畫法重建另需在步驟 8 前執行 Blender `--background --python-exit-code 1 --python tools/fortune_runtime_v1/validate_style_pass.py`，驗證目前 master 對本輪前快照完全沒有新增形狀或 UV 差異。`provenance.py` 會要求這份報告及最新 master／target／geometry SHA 一致，再接受最終交付。

`capture.tscn -- --raw-atlas-preview --preview-revision=...` 僅作生成稿快速試貼，不當成最終載入或匯出驗收。最終圖片必須由正常匯入與編譯後的 resource 產生。`.import`／`.uid` 均由引擎產生；沒有改動 Claude hooks。
