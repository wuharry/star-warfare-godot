# Titan v7 · 縮短可見頸部

上一版 v6 修正原頸圈與不透明內襯，仍讓圓面罩下緣離衣領太遠。這一輪將已確認圓面罩的外殼整體向下貼合固定頸圈，並把「可見脖子只能像既有裝甲般少量」納入後續標準。

外殼採整體下收與下緣小幅延伸，保留金色圓面罩的形狀；24 個真原版頸圈 UV 頂點固定，全部 UV、面、骨骼、權重與五張 PNG 完全繼承 v6。這次沒有呼叫 imagegen，也沒有修改貼圖像素。整體下收量與下緣各組偏移以 `../titan_runtime_v1/runtime_config.json` 的 `shell_fit` 明列，新增弧面中點只繼承兩個原父點的平均偏移；完整形狀仍須通過真正原版 20% 上限。

- [目前預覽](index.html)：發布工具從真報告產生，包含 v6/v7 正常材質近拍、29 個身甲×3 動作×4 視角共348組露頸量與五個家族參考。固定修改前僅有4身甲48組，沒有舊取樣的列標示 `NOT RUN`，不製造 v6 前圖或數字。
- [必要露頸標準 prompt 附錄](prompts/mandatory_limited_neck_exposure.txt)：追加至既有基底及原頸圈附錄，不改寫歷史 prompt。
- [原 v6 固定快照](revisions/before_shell_fit_v7/snapshot.json)：175 檔，固定於 `bd71a0e5357790959a2d563556885a71ddfb4129`。
- [上一版接口修復](../titan_neck_mix_v1/index.html)：保留原報告；它的工程 PASS 不代替本輪露頸比例驗收。
- [正式發布紀錄](review/published_delivery.json)：發布後列出報告路徑與 SHA；缺少這份檔案代表尚未完成正式發布。

露頸量只採已裝備頭盔、身甲、手甲、腳甲四件裝甲的遮擋結果；待機、跑動、換彈都在套用姿勢後隱藏武器、背包與換彈殘片，避免槍械替頭盔擋住脖子。以原頸部連通元件的紅色診斷遮罩計數，再除以完整頭部的投影像素。家族門檻取修改 Titan 前固定的目前已優化 ID 0–4（Viper／Fortune／Tank／Hydra／Strike）同鏡頭參考，不能為了通過新模型而放寬。21 個 legacy 頭盔僅展示，不參與門檻。正式 baseline 為 `review/before_final/capture.json`；較早完整性失敗的調查報告保留歷史，不用來批准門檻。

量測完整性、露頸風格門檻、原接口不變、29 身甲×9 動作矩陣、正常材質目視與使用者美術接受必須分開記錄。短頸封口仍可以看見；取樣通過不代表每一動畫影格、所有鏡頭都沒有露布或穿插。瀏覽器互動、手機實機效能與產品匯出煙霧測試另行標示，不使用舊版 PASS 冒充本輪驗收。

發布使用 `tools/armor_runtime_v1/publish_titan_shell_fit.py`，明確傳入正式 baseline、修改後露頸報告與配對引擎日誌（`--coverage-log`）、35 張混搭報告、261 姿勢測試與本輪 64 張正常資源擷取。348 組診斷必須逐一證明已裝備模型與完整頭部的所有 surface／三角形皆實際繪出，包含沒有索引的原生模型；日誌出現腳本或解析錯誤即拒絕發布。發布工具會先核對當前素材 SHA、真原版形狀、原生生成繼承與全部報告，再同步 Titan manifest、C06、系列 after15 及內嵌 HTML；不修改模型或圖像像素。

上一交付的系列 after15 沿用 v5 圖片，雖然系列文字曾標為 v6。發布前會另存原 bytes 與舊頁面於 `../armor_style_unification_v1/revisions/titan_v6_before_shell_fit_v7/`；本輪 after15 必須直接複製真正 v7 正常資源擷取並建立新的 SHA 索引，不回溯改寫舊 v5/v6 報告。

失敗或已被取代的調查擷取已逐檔核對 SHA 後完整存入 `revisions/investigation_archives/*.zip`，包含原 PNG 與 JSON 的相同 bytes；[封存索引](review/investigation_archive_index.json) 記錄原目錄、各檔 SHA 與 ZIP SHA。它們不是本輪正式 PASS 證據。正式 baseline、無武器348組及35張混搭近拍仍保留為可直接讀取的檔案。
