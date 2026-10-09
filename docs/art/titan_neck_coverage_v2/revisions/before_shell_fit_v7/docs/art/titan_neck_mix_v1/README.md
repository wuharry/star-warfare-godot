# Titan 混搭頸部修正

Titan 頭盔的頸管被面罩變形一起帶動，而且頸部貼圖偏灰，配低領身甲時會露出不連續的接合。本輪保留已指定的圓面罩，修復頸部接口與黑色內襯，並將混搭納入後續頭盔製作的必要驗收。

- [修正前後預覽](index.html)：同身甲、動作、角度並排，共 35 組；直接開啟本機 HTML 即可，不依賴網路載入 JSON。
- [修正前來源契約](review/before_neck_contract.json)：8 個頸管 UV 頂點被移動，最大 15.799 mm；原 UV、權重與頸管三角形仍相同。
- [修正前實際引擎報告](review/before/capture.json)：29 個身甲、261 個動作取樣、35 張擷取；已重現頸管位移與灰色內襯失敗。
- [修正後實際引擎報告](review/after/capture.json)：`PASS`，29 個身甲、261 個動作取樣、35 張擷取；保護頸管最大位移為 0。
- [修正後混搭與負面測試](review/after_test/capture.json)：`PASS`，261 個姿勢與 10 個獨立拒絕情境；真實存檔未變，GameState 已還原。
- [追加共享編譯防護實測](review/after_test_shared/capture.json)：`PASS`，保留 261 個姿勢與 10 個獨立拒絕情境，另含 24 項共享 gate 檢查；原 `after_test` 保留不覆寫。
- [最終有限值與共享防護實測](review/after_test_shared_finite/capture.json)：`PASS`，261 個姿勢、20 個獨立拒絕情境與 24 項共享 gate 檢查；前兩份測試保留歷史。
- [最新編譯前頸部 gate](../titan_runtime_v1/review/neck_contract_gate.json)：`PASS`，以正式 updater 同一程式碼執行隔離 preview 保存驗證，輸出 `helmet_v6_compile_check.scn`；這次 preview 未改正式 SCN／GLB。
- [修正前固定快照](revisions/before_neck_fix/snapshot.json)：固定於 `46e449993fa7767e95324ca1aa0ae81b6cc40736`，不得用修正後資源改寫歷史。
- [後續必要 prompt 附錄](prompts/mandatory_neck_interface.txt)：附加至既有固定基底 prompt，不修改基底本身。

## 修正與防範範圍

頸管必須由真原版模型的連通部件與實際骨骼名稱推導，包含共用實體位置的 UV 接縫重複頂點。Titan 的來源為 12 個實體位置、24 個 UV 頂點、12 個三角形，上下分別連到 `Bip01 Head` 與 `Bip01 Spine1`。這些來源結果不可被面罩的外形調整、對齊或輸出步驟改動。

共享 `compile.gd` 與 Titan 專用 `update_titan_helmet.gd` 已接入正式保存前的來源接口 gate。共享流程會搜尋所有 source mesh surfaces，例如 Tank 的頸管位於第二個 surface；幾何、UV、骨架／權重、頸管面與不透明為硬條件。接近黑色的色調限制依各套設計由 `neck_charcoal_required` 啟用，Titan 專用流程始終嚴格檢查黑布，其他套裝不會因核准布料底色不同就被共享流程誤拒。

追加的 24 項實測包含 21 個原版頭部正控制、未啟用黑布限制時允許不同不透明底色、透明像素必須拒絕，以及真正 production writer 在接口失敗時保留既有檔案、也不建立原本不存在的輸出。失敗 writer 的內層報告為 `FAIL` 且 `wrote_scene=false`，外層測試因成功阻止寫入而通過。其餘自訂 compiler 尚未全部接入；這是共享製作流程與 Titan 的防護，不代表所有現存資產都已重新驗收。

最後一輪另將非有限值檢查放在 `ArrayMesh` 上傳之前，直接拒絕 `NaN`／無窮大，不能只依賴位移大小的比較。20 個負面情境包含原 10 項與 10 項真正保留非法值的 NaN 回歸：頂點、UV、權重、安裝 transform、Skin bind、材質 tint／UV／像素及真原版頂點／UV。production writer 也真正注入並讀回 NaN 頂點，確認不覆寫既有目的檔、不建立缺少的目的檔；parts 與三角形數量檢查已移到寫入之前。

Titan 頸部內襯必須在原生貼圖中畫成不透明、接近黑色的布料；不能用材質染黑、透明、加深燈光或擴大身甲衣領掩蓋失敗。既有整體形狀或 UV 百分比上限不授權移動這個混搭接口。

建置與編譯必須執行來源接口檢查，正式 SCN／GLB 與實際裝備後的材質、權重和動作也必須檢查。負面測試須用獨立記憶體副本，分別移動接口、改 UV／綁骨、破壞頸管面、改成灰色／透明內襯並確認會被拒絕；包括「正確原幾何＋真正修正前灰圖」的獨立回歸情境。

## 驗收證據與限制

混搭矩陣涵蓋全部 29 個身甲 ID，各自取樣待機、跑步、換彈各三次，共 261 個實際姿勢。35 張正常資源擷取涵蓋 Viper、Fortune、Strike、Titan、Phoenix、Cygni、Assault Armor、Training Suit 的正／斜／側／背面，以及 Viper 身甲三個持槍動作。

實際接口與內襯檢查通過後，仍須逐圖檢視背景穿透、頸管與衣領分離、穿插及貼圖斷裂。頸管回到原版只是工程條件；若實際畫面仍有空洞，需修正真正的蒙皮幾何並重跑驗收。不能以原版座標相同宣稱視覺問題已解決。

預覽頁只顯示嵌入的真報告狀態。缺少修正後報告時顯示 `NOT RUN`；工程 `PASS`、人工畫面檢視、使用者美術接受與手機效能分開記錄。使用者美術接受與手機實機效能目前仍待確認。擷取和測試須記錄資源 SHA、renderer、尺寸及真實存檔未變／狀態已還原。

已逐張查看全部 35 張修正後近景，另查看 Training Suit 正／斜面及 Viper 背面三張修正前對照。這些 720 × 720 黑底、有限角度的靜態圖中未見明顯頸部背景穿洞或脫離頭身的浮片；換彈近景有部分頸部被槍遮住，不能代表所有動畫時間與視角。

低領身甲背面仍看得出原頸管下緣的方形黑布輪廓。Viper 背面的細藍楔與 Training Suit 正／斜面下緣的深色三角布紋，在修正前對照也存在，屬仍可見的衣領重疊痕。本輪不宣稱所有混搭沒有任何穿插或已達完美外觀。新版內襯原圖／有效材質平均亮度為 0.113814，仍比原版約 0.032 亮；材質門檻通過不等於色調完全相同。

預覽頁的 JavaScript 語法、內嵌報告 SHA 及全部前後 70 張 PNG SHA 已靜態核對；瀏覽器操作仍為 `NOT RUN`。最新 gate 是隔離 preview 的同程式碼驗證，正式素材的混搭畫面與 261 姿勢證據仍以 `after` 及最終防護報告分別記錄。

本頁不把舊 v5 同套裝甲驗收當成本輪混搭通過證據。完整來源與既有圓面罩設計仍可在 [Titan v5 歷史頁](../titan_runtime_v1/revisions/helmet_refinement_v5/index.html) 追溯。
