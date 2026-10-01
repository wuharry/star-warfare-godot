# Cygni 頭盔融合試稿 · 2026-09-29

使用者以「好偏T字這種」選定 `images/anubis_gold_t.png` 為正式頭盔方向；主圖採用同一張原圖，三視與拆解已同步。較寬的金色大面罩原圖保留。

[開啟前後比較](index.html) · [完整來源與逐圖生成紀錄](study.json)

## 本輪結果

| 圖片 | 用途／狀態 | 已目視的變化 |
| --- | --- | --- |
| [baseline.png](images/baseline.png) | 原稿快照 | 白灰殼、紫面罩、銅橙 U 框、圓形頰接點。 |
| [anubis.png](images/anubis.png) | A 初稿；使用者偏好方向 | 分層眉甲與斜收頰板，仍是紫面罩，白色中央下巴較高。 |
| [anubis_gold.png](images/anubis_gold.png) | 使用者喜歡並要求保留 | 金色反光玻璃向兩側和下頰延伸，頰框及中央下巴縮小；原圖未再更動。 |
| [anubis_gold_t.png](images/anubis_gold_t.png) | 使用者已選定並採用 | 上眼帶維持寬度，頰板輕微內收，下半部金色玻璃較集中於中央。 |
| [moonfang.png](images/moonfang.png) | B 比較稿；未採用 | 中央額脊、冠槽，紫面罩向下收尖，形成較長 V 形。 |

各稿延續白灰頭盔與身甲、深綠內板、銅橙細節、後掠短翼與站姿。這些是概念圖，表面紋理會重繪；不是精確尺寸圖或遊戲模型。

## 參考與融合

- **[Halo 5 Anubis 製作渲染](https://www.halopedia.org/File:Anubis-armor-render-02.jpg)**：借用分層眉甲、斜收護頰和短中央呼吸護塊；保留 Cygni 側翼與身甲。金色大面罩依使用者後續要求加入，並非宣稱參考原圖是金色。
- **[Destiny 2 Moonfang-X7 Mask 原圖](https://www.bungie.net/common/destiny2_content/screenshots/2623956730.jpg)**：借用中央額脊、冠槽及收尖玻璃形狀；省略參考中的青藍塗裝、粉色零件與額頭符號。
- 來源圖片、SHA-256、實際生成輸入及逐圖目視紀錄收在 `study.json`；參考用途不代表授權已完成。

## 生成方式

使用 **built-in image_gen**；輸出直接複製至此資料夾，沒有另外裁切、上色或合成。比較頁的頭盔放大只改 CSS 顯示範圍。

| 輸出 | 實際輸入 | 完整提示詞 |
| --- | --- | --- |
| A 初稿 | 原稿快照 + Anubis 製作渲染 | [anubis.txt](prompts/anubis.txt) |
| B 試稿 | 原稿快照 + Moonfang-X7 官方物品圖 | [moonfang.txt](prompts/moonfang.txt) |
| A 金色修訂 | A 初稿 | [anubis_gold.txt](prompts/anubis_gold.txt) |
| 略偏 T 字版 | A 金色修訂 | [anubis_gold_t.txt](prompts/anubis_gold_t.txt) |

正式圖集已採用 T 字概念原圖，並依此同步三視／拆解；[採用紀錄與舊稿](../c12_before_t_adoption_20260929/README.md)可回看。大面罩及[前一輪對照頁](index_before_t.html)留作歷史參考，未接入 runtime。

## 試稿階段檢查（正式採用前）

- PASS：輸出、提示詞及實際輸入 SHA-256 一致；頁面本地連結都有對應檔案。
- PASS：既有 C-12 概念／三視／拆解內容未變，其餘圖集項目資料未變。
- PASS：in-app browser 目視窄版頭盔放大；圖片均載入、全身切換與金色圖放大有效；主圖集入口可到達本頁。
- PASS：新增 T 字版後重新目視並排頭盔；兩張圖載入、全身切換及 T 字原圖放大有效；大面罩原檔 SHA-256 與前一 commit 相同。
- PASS：harness integrity。Godot 應用測試 NOT RUN，本輪只有美術試稿、資料及 HTML 圖集變更。

## 2026-10-01：收窄雙頰的 T 字修訂

新增 [收窄 T 字試稿](images/anubis_gold_t_narrow.png)，白灰護頰往內、往上延伸，讓寬金色眼帶與窄中央直條的交界更清楚。完整提示詞在 [anubis_gold_t_narrow.txt](prompts/anubis_gold_t_narrow.txt)。使用 built-in image_gen，實際輸入僅為目前正式 `images/c12_concept.png`；原始輸出直接複製，沒有裁切、重塗或合成。

這是待選候選稿；2026-09-29 採用的微 T 原圖、正式三視與拆解保留，遊戲模型未更新。本頁較早的採用紀錄指的是微 T 版，不代表新稿已獲同意。[新版並排比較](index.html)提供頭盔放大與全身切換；[前一輪比較頁](index_before_narrow_t.html)亦保留。

### 本次驗證

本次候選圖、來源紀錄與連結檢查通過；全圖集驗證仍有既有失敗，已用 HEAD 內容在記憶體中重跑比較，錯誤清單完全相同。

| 檢查 | 結果 |
| --- | --- |
| 新圖目視：收窄下頰、金色 T 字、白灰外殼與身甲延續 | PASS |
| 新圖／提示詞／實際輸入 SHA-256、頁面本地連結 | PASS |
| 原正式三圖保持原樣、其他圖集項目未變 | PASS |
| `git diff --check`、harness integrity | PASS |
| `validate_delivery.py` 全圖集一致性 | FAIL：與 HEAD 相同的 39 項既有錯誤，涉及歷史狀態、來源與提示詞雜湊；本次新增 0 項 |
| 瀏覽器互動、Godot runtime | NOT RUN：本輪未改頁面互動程式或遊戲內容 |

本機檢查報告位於 `test_output/cygni_narrow_t_delivery.json` 與 `test_output/cygni_narrow_t_baseline.json`（不提交的測試輸出）。

## 2026-10-01：修正護頰太方

方頰收窄版被使用者以「臉頰的裝甲太方了，感覺還是不對」否定，已標示為未採用並保留原圖。新版 [斜收護頰稿](images/anubis_gold_t_swept.png) 把矩形大平面改成朝下巴斜收的折面，寬通風格柵改為細長斜口。金色面窗仍有寬眼帶與中央下伸直條；轉角更柔和，中央上段略變寬，未宣稱完整保留前稿面罩形狀。

使用 built-in image_gen，唯一圖像輸入是前稿 `images/anubis_gold_t_narrow.png`，完整實送提示保存在 [anubis_gold_t_swept.txt](prompts/anubis_gold_t_swept.txt)。輸出原樣複製，沒有另行裁切或上色。現行正式概念／三視／拆解及遊戲模型未變，新稿尚待使用者評價；比較页更新為方頰版與斜收版，上一頁保存在 [index_before_swept_cheeks.html](index_before_swept_cheeks.html)。

### 前前稿直接比較

依使用者要求，比較頁預設改為「前前稿金色微 T 原稿」對「最新斜收護頰版」。左側可切换成未採用的方頰版；右側保持最新版，頭盔／全身與原圖放大仍可用。這次只調整比較頁，沒有重新生成或修改任何圖片。
