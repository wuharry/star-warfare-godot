# Thunder · 真正原版頭盔素材 v2

這輪恢復真正原版 SW1 的高後掠單冠、V 形壓眉、圓耳盤、金橙單片面窗與短藍下框，再以原版 atlas 原位重生成頭圖。正式入口是 `assets/armors/thunder/thunder.scn`；不是上一輪被退回的成人低冠頭盔。

頭部維持真正原版 196 三角形、147 UV 座標、28 Skin binds；幾何、UV、拓撲、蒙皮與 transform 的改動皆為 0。身甲／手／腳繼承恢復後 `bef5b833` 的原 buffer、材質、Skin 與 transform；整套目前 6574 三角形。這兩個基準不同，不能說整套對真正原版也只有 0% 或已驗證低於 20%。`thunder_sw2.scn` 與 `thunder_prototype.scn` 保持原值。

本輪只有一個原生生成嘗試，1254 × 1254 PNG；未進行影像後製、重排 UV、裁圖或重新縮放。完整實送 Prompt 在 `prompts/head_attempt_01.txt`，真正原版 atlas 與僅作身甲配色參考的圖在 `generation_references/` 固定保存，原生工具路徑與 SHA 由 `generation_inputs.json` 記錄。Godot 建立 portable `ImageTexture`，compile_report 核對解碼像素相同。

`review/engine/` 保存真正原版、修改前已還原版本與本輪正式素材各 15 張，共 45 張原始 Godot PNG。頭部四向、全身四向、灰模兩向、待機、跑動、換彈與區域 01／03 可在 [集中比對頁](../armor_original_based_v2/index.html#thunder) 查看。三版使用同攝影機；遊戲關卡是實際世界，粒子與時間不作逐像素量測。

`build/compile_report.json` 與 `review/runtime_test.json` 驗證正式場景、原頭部 buffer、UV／Skin／transform、保留身甲、替代場景、重複裝備、混裝、商店／自訂與九個實際動畫取樣。`visual_review.json` 記錄逐張查看的 45 個 PNG SHA 與觀察；美術仍待使用者評價。

目前高冠與原面甲風格成立；新頭圖比舊版更乾淨、明亮，局部亮邊磨損及 V 形玻璃反光仍較強。身甲原有的切面與白邊保持，並非這次頭圖新增。完整動畫影片、手機效能、使用者美術接受及頁面瀏覽器互動未由工程 PASS 推定。

只有 Root 重新跑引擎後才更新證據。`python docs/art/thunder_original_v2/build_manifest.py` 只讀取並核對已存在的 compile／runtime／capture／原生 PNG，再寫 manifest 與製作紀錄；不執行引擎，也不生成或編輯圖片。
