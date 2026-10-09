# Thunder／Atom／Pegasus · 原版基底遊戲素材

本頁集中比對三套已整合的實際遊戲素材，列出「真正原版 → 3ed1c291 上一版遊戲素材 → draft_refinement_v3 草稿再修版」。三套最終工程檢查及逐圖目視紀錄已完成：Thunder 45 張、Atom 與 Pegasus 各 64 張，外觀仍待使用者評價。設計概念另列，所有模型圖片引用 Godot 原始 PNG，不重繪擷取，也不把概念圖當成已完成模型。

- Thunder：C-07，遊戲 ID 6。以目前圖集 `user_review.preferred_art` 選定的 B 新頭盔舊稿為外形與配色目標，在真正原版頭部基底上調整模型和貼圖；原版 UV、拓撲、骨架與權重保留，身甲維持 3ed。新交付由 `../thunder_draft_v3/` 記錄，上一輪 `../thunder_original_v2/` 完整保留。
- Atom：C-08，遊戲 ID 7。草稿目標包括短下巴、圓耳盤、前額三點、厚短肩鰭與上胸直式服務盒。這輪從真正原版頂點出發調整頭部、胸肩模型與貼圖，保留遊戲比例與骨架。來源與實際改動由 `../atom_runtime_v1/` 記錄。
- Pegasus：C-09，遊戲 ID 8。草稿目標包括低鈍雙冠軌、短下巴、低白領與黑色胸槽；頭盔與身甲保持白灰色。這輪調整頭部、胸肩模型與貼圖，來源與實際改動由 `../pegasus_runtime_v1/` 記錄。

相對真正原版的最大累積位移：Thunder 頭部 19.451%；Atom 頭部 12.641%、胸肩 19.789%；Pegasus 頭部 19.290%、胸肩 10.711%。三套原版 UV 座標均精確保留。Thunder 身甲維持 3ed，不能將頭部限制推定為整套原版差異；其他兩套輪廓比例驗證分別為最大 3.363% 與 8.111%，也不是概念還原率。所有數字以各套實際 manifest 和檢查報告為準。

`build_review.py` 讀取各套實際 manifest、正式 SCN、擷取 PNG 與檢查報告，核對 SHA256 後才加入頁面。Atom、Pegasus 的上一輪圖片讀自各套 `revisions/before_draft_refinement_v3/`，每套凍結 96 檔；Thunder 的上一輪完整生產資料凍結於 `thunder_draft_v3/revisions/before_draft_v3/`，共 126 檔，並從該凍結場景重新擷取同相機的 before 畫面。三套來源都是完整 commit `3ed1c2911e1eea5162e30d0bab331fd41a1d29f9`；圖片、場景與歷史擷取紀錄須相互綁定。Thunder 頭部、Atom 與 Pegasus 頭部及胸肩都須有實際頂點位移，且正式場景不同於上一版，才能發布。沒有完整證據時顯示待完成，不產生假圖或假 PASS。`review_data.json` 為可讀資料；`page_validate.json` 記錄頁面與資料 SHA、已完成套數，以及瀏覽器互動和使用者美術接受的獨立狀態。

最終模型、擷取、逐圖目視與 manifest 全部完成後，才在專案根目錄執行 `python docs/art/armor_original_based_v2/build_review.py` 重建頁面。三套正式素材與工程紀錄均通過後，可加 `--update-gallery` 同步 C07、C08、C09 的 `original_based_runtime`，包含本輪版本與上一輪快照來源。圖集其餘 43 條資料須保持相同；這三套的 `user_review`、既有圖與其他非交付資料也須保持。此欄位不改技能提案、裝備數值、背包、存檔 ID 或既有概念圖歷史。

發布後執行 `python docs/art/armor_original_based_v2/validate_review.py`，實際以 Node `--check` 檢查本頁、原裝甲圖集、Atom 與 Pegasus 獨立頁的 JavaScript。工具另核對嵌入資料與 `review_data.json`、所有遞迴本機資源 SHA、C07/C08/C09 metadata 和 CATALOG、相對 3ed1c291 的其餘 43 條資料與三套非交付欄位，以及 `page_validate.json` 的本頁與資料 SHA。結果寫入 `static_validation.json`；失敗以非零退出碼回報。工具不啟動瀏覽器、不改圖片或工程報告，語法通過不代表互動或美術驗收。

UV 與模型差異是工程限制，不是畫風相似度，也不能代表美術接受。中性擷取可對照面甲、輪廓與筆觸，遊戲畫面可看遮擋與辨識；遊戲中的敵人、粒子與環境時間不是逐像素控制實驗。完整動畫、手機 GPU 效能與使用者評價，只有真正執行後才可標示通過。

f94323e4 僅貼圖版及其 `before_draft_refinement_v2/` 快照完整保留，3ed1c291 是已改模但使用者要求繼續貼近草稿的版本。本輪以灰模檢查輪廓是否實際改形，再看面罩、燈件與胸甲大色塊；逐圖報告保留實際差距，不宣稱與草稿完全一致。概念只有斜正面，背面是連貫設計與工程驗收，不能推定完全還原。Atom 首稿胸匣錯位與雙盒的歷史證據另存其 `review/iterations/body_attempt_01/`。Thunder 先前的 25f11d9 頭盔圖保留歷史來源，不再作本輪頭盔權威。

Thunder 本輪第 1 稿的棚頂尖冠／粗眉沿與第 2 稿的後頸灰 padding 問題，連同當時 45 張原始擷取及工程資料保留於 `thunder_draft_v3/review/iterations/attempt_01/` 和 `attempt_02/`。最終比較頁只讀本輪最新且實際逐張看過的正式畫面，不把先前工程檢查通過當作已修正美術問題。

瀏覽器互動為 NOT RUN：本輪 CUA 拒絕 `file://` 協定，未用 HTTP 或其他介面繞過安全政策。JavaScript 語法與本機檔案 SHA 由最終靜態驗證獨立檢查；這些結果不代表瀏覽器操作驗收。
