# Cygni 頭盔融合試稿 · 2026-09-29

使用者偏好 Halo 5 Anubis 方向，並要求面罩改為金色、占比更大；最新圖為 `images/anubis_gold.png`，修訂效果待確認。

[開啟前後比較](index.html) · [完整來源與逐圖生成紀錄](study.json)

## 本輪結果

| 圖片 | 用途／狀態 | 已目視的變化 |
| --- | --- | --- |
| [baseline.png](images/baseline.png) | 原稿快照 | 白灰殼、紫面罩、銅橙 U 框、圓形頰接點。 |
| [anubis.png](images/anubis.png) | A 初稿；使用者偏好方向 | 分層眉甲與斜收頰板，仍是紫面罩，白色中央下巴較高。 |
| [anubis_gold.png](images/anubis_gold.png) | A 最新修訂；待確認 | 金色反光玻璃向兩側和下頰延伸，頰框及中央下巴縮小；面罩面積未作數值量測。 |
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

目前圖集主稿及既有三視／拆解保留，C-12 入口新增此比較頁連結。這次未製作新三視或拆解，也未接入 runtime；新修訂圖尚未獲使用者驗收。

## 檢查

- PASS：輸出、提示詞及實際輸入 SHA-256 一致；頁面本地連結都有對應檔案。
- PASS：既有 C-12 概念／三視／拆解內容未變，其餘圖集項目資料未變。
- PASS：in-app browser 目視窄版頭盔放大；圖片均載入、全身切換與金色圖放大有效；主圖集入口可到達本頁。
- PASS：harness integrity。Godot 應用測試 NOT RUN，本輪只有美術試稿、資料及 HTML 圖集變更。
