# Thunder／Atom／Pegasus · 原版基底遊戲素材

本頁集中比對三套實際遊戲素材；真正原版、這輪正式素材與設計概念分開列出。所有模型圖片引用 Godot 原始 PNG，不重繪擷取，也不把概念圖當成已完成模型。

- Thunder：C-07，遊戲 ID 6。撤回上一輪 `d73922d1` 頭盔修改後，從真正原版頭部 UV 與貼圖重新製作；修改前身甲保持。來源、生成與驗收由 `../thunder_original_v2/` 記錄。
- Atom：C-08，遊戲 ID 7。既有紫色／灰藍身甲與青色大面窗、圓形設備點方向，以原版四部件與五張 UV atlas 製作。來源與驗收由 `../atom_runtime_v1/` 記錄。
- Pegasus：C-09，遊戲 ID 8。依使用者更正，頭盔與身甲同為白灰色，配深色 V 面窗與藍色細節；來源與驗收由 `../pegasus_runtime_v1/` 記錄。

`build_review.py` 讀取各套實際 manifest、正式 SCN、擷取 PNG 與檢查報告，核對 SHA256 後才加入頁面。沒有完整證據時顯示待完成，不產生假圖或假 PASS。`review_data.json` 為可讀資料；`page_validate.json` 記錄頁面與資料 SHA、已完成套數，以及瀏覽器互動和使用者美術接受的獨立狀態。

在專案根目錄執行 `python docs/art/armor_original_based_v2/build_review.py` 重建頁面；三套正式素材與工程紀錄均通過後，才可加 `--update-gallery` 同步 C07–C09 的 `original_based_runtime`。此欄位不改技能提案、裝備數值、背包、存檔 ID 或既有概念圖歷史；圖集其他 43 條資料須保持相同。

UV 與模型差異是工程限制，不是畫風相似度，也不能代表美術接受。中性擷取可對照面甲、輪廓與筆觸，遊戲畫面可看遮擋與辨識；遊戲中的敵人、粒子與環境時間不是逐像素控制實驗。完整動畫、手機 GPU 效能與使用者評價，只有真正執行後才可標示通過。

2026-10-09：三套正式素材、逐張目視紀錄與原版來源已完整綁定；美術狀態為工程候選，等待使用者評價。Atom 胸匣採第 5 稿，首稿錯位與雙盒的歷史證據另存其 `review/iterations/body_attempt_01/`。Thunder 先前的 25f11d9 頭盔圖保留歷史來源，不再作本輪頭盔權威。

瀏覽器互動為 NOT RUN：本輪 CUA 拒絕 `file://` 協定，未用 HTTP 或其他介面繞過安全政策。JavaScript 語法與本機檔案 SHA 已獨立檢查；這些靜態結果不代表瀏覽器操作驗收。
