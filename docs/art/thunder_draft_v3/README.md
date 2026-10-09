# Thunder · B 草稿頭盔整合 v3

本輪已將目前圖集選定的 `docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png` 轉譯為真正原版頭部基底的改形模型與專用貼圖。採用第 2 輪形狀及第 3 稿原生貼圖；正式 compile、172 項 runtime 檢查與 45 張 ANGLE 實機擷取完成，45 張已逐張目視，未有未解阻擋問題。外觀仍待使用者評價，保留原拓撲折面、微小後尖、眉沿、下巴與頸環等差距，不宣稱草稿完全還原。

頭部保留原版 147 個 UV 座標、196 個三角形、28 個 skin binds、原索引、權重、骨架與節點 transform；頂點位置可在真正原版最小軸尺寸的累積 20% 內調整，各軸尺寸變化也限制 20%。這些是工程限制，不是概念圖相似度。身甲、手腳保持 3ed 版的 native buffers、材質、skin 與 transform；身甲來自更早的改模歷史，不宣稱整套相對真正原版符合頭部的 20% 限制。

本次頭部最大累積位移為 19.451%，最大軸尺寸變化為 14.131%，UV 座標變更為 0。數字與原生圖、模型及擷取 SHA 由 `manifest.json` 綁定；最終觀察及殘差在 `review/visual_review.json`。後頸灰 padding 已修正，工程與目視結果不能代表所有連續動畫、使用者美術接受或手機效能都已通過。

上一版完整交付凍結於 `revisions/before_draft_v3/`，來源 commit 為 `3ed1c2911e1eea5162e30d0bab331fd41a1d29f9`，共 126 檔。`snapshot.json` SHA256 是 `8ef68f9c7d9e67b32d01c1632bdf765debc527117f872e1a56c8ab00c02c09fb`。快照包括 Thunder 的舊模型、原生 PNG／portable RES、original_v2 製作與擷取資料、工具／測試、真正原版 glTF／buffer／head atlas，以及選定 B 稿與其 prompt／provenance。快照逐檔驗證，不遞迴複製本輪目錄，不覆寫歷史。

`generation_inputs.json` 保存所有實際生成嘗試及其完整 prompt、參照、原生輸出與 SHA，包含未採用稿。只有選中的原生 PNG 可以逐 byte 複製到 `assets/armors/thunder/textures/draft_head_v3.png`；不裁切、縮放、拼圖或程式重畫。原生貼圖生成不等於已套用遊戲，後續仍需以下完整流程。

第 1 稿的後冠尖棚頂與粗 V 眉沿、第 2 稿後頸被原 UV 採樣到的灰色 padding 都是已發現的美術問題。兩稿各 45 張原始擷取及當時的 compile／runtime／config／capture 資料分別保存在 `review/iterations/attempt_01/` 與 `attempt_02/`；它們不作最終目視通過證據。後續只修正後頸貼圖時，仍須重新編譯、驗證並擷取整套 45 張，不能用上一稿畫面代表新原生圖。

從專案根目錄執行，既有 `$armorEngine` 指向專案使用的 Godot console 程式：

```powershell
# 先完成 head_target.json、選中原生 PNG 與 runtime_config 的實際 SHA。
python tools/thunder_draft_v3/head_contract.py
python tools/thunder_draft_v3/test_head_contract.py
& $armorEngine --headless --path . --editor --quit
& $armorEngine --headless --path . --script res://tools/thunder_draft_v3/compile.gd
& $armorEngine --headless --path . --editor --quit
& $armorEngine --headless --path . res://tests/thunder_draft_v3_test.tscn
& $armorEngine --path . --rendering-method gl_compatibility --rendering-driver opengl3_angle --log-file docs/art/thunder_draft_v3/review/draft_v3_angle_capture.log res://tools/thunder_draft_v3/capture.tscn
# 逐張實看 45 張 PNG，寫當前 review/visual_review.json，保留殘差與 SHA。
python docs/art/thunder_draft_v3/build_manifest.py
# Thunder、Atom、Pegasus 的所有最終交付完成後，才同步圖集。
python docs/art/armor_original_based_v2/build_review.py --update-gallery
python docs/art/armor_original_based_v2/validate_review.py
```

正式擷取包含真正原版、凍結的 3ed 上一版、本輪模型各 15 個視角，共 45 張原始 PNG。頭部四向、全身四向、灰模正側面、待機、跑動、換彈與兩關實機畫面使用同一固定比對管線；live gameplay 的粒子與環境不是逐像素控制實驗。所有擷取都綁當前模型、target、原生圖與 before 場景 SHA；真實存檔前後必須相同。

`build_manifest.py` 僅在實際 compile／runtime 檢查通過、正常 ANGLE／Direct3D11 擷取完整、當前逐圖目視無未解 blocker 時才產生 manifest；它不改貼圖、模型、target、生成紀錄或快照。外觀仍標 `pending_user_art_review`，完整動畫影片、手機效能與使用者美術接受只在實際執行後記錄。

正式比較頁位於 `../armor_original_based_v2/index.html#thunder`。本輪只更新 C07／C08／C09 的 `original_based_runtime`；圖集其餘 43 條資料及三套原有 `user_review`、概念圖與歷史保持。先前 `../thunder_original_v2/` 完整保留。Browser 為 NOT RUN：先前本機 `file://` 預覽遭工具拒絕，未以其他介面繞過；Node 語法及本機 SHA 檢查不能代表瀏覽器操作或美術驗收。
