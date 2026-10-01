# Andromedae：封閉面甲修正

本次將 Andromedae／ID 12／C-13 的寬玻璃面窗改成不透明鋼藍面甲，保留圓冠、分節中槽與青色 T／Y 細光槽；概念、三視與拆解已同步。使用者要求重新生成，尚未對新圖逐張驗收。

[查看頭盔前後比較](index.html) · [回到圖集](../../index.html#C-13)

## 修正原因與參考

使用者更正 Andromedae 和 Draco 都是無玻璃面罩的頭盔。先前 brief 卻要求把原版實心面部換成玻璃，這一設計判斷已取消。恢復模型截圖保留作輪廓與配色證據；本輪沒有重新分析原遊戲材質。

本次選用 [Warframe 官方 Vauban Prime 主視](https://www.warframe.com/en/news/vauban-prime-access-here-fr) 作封閉臉部／縱向分片參考。只取分片方向，省略高冠、金飾、長尖下巴與身甲。實際新圖中的參考變化較克制，以原版 Andromedae 身分為主。Oceanic 只繼續作既有身甲、壓力護領及接合結構參考，不再决定頭盔面窗。

## 實際交付與生成輸入

全部使用 built-in image_gen。輸出原樣複製至專案，沒有裁切、上色或合成；比較頁頭盔放大只改 CSS 顯示。來源、提示詞與 SHA-256 記在正式生成紀錄及 C-13 設計資料。

| 圖稿 | 新版 | 修改前 | 實際圖像輸入 | 完整提示词 |
| --- | --- | --- | --- | --- |
| 概念 | [新版](../../images/c13_concept.png) | [舊稿](images/c13_concept.png) | 舊概念、原版正面截圖、官方 Vauban Prime 主視 | [提示詞](../../prompts/c13_concept.txt) |
| 三視 | [新版](../../images/c13_turnaround.png) | [舊稿](images/c13_turnaround.png) | 舊三視、新概念 | [提示詞](../../prompts/c13_turnaround.txt) |
| 拆解 | [新版](../../images/c13_construction.png) | [舊稿](images/c13_construction.png) | 舊拆解、新概念 | [提示詞](../../prompts/c13_construction.txt) |

本資料夾保存三张舊圖、實送提示詞、舊生成紀錄及修改前設計／來源規則。舊紀錄的輸入路徑已指向對應封存圖，原路徑另保留為 `historical_reference_images`，避免正式圖更新後指到不同圖片。舊稿標示為被無玻璃要求取代，不計入正式三圖。

## 目視與限制

三圖均已逐張目視：新面甲為鋼藍塗裝與淺分面，正側和拆件都沒有大玻璃窗；圓冠與青色細線一致，短下巴、身甲和獨立 B-13 三筒背包方向延續。生成會重繪局部紋理，不宣稱頸下逐像素不變。各視角光槽長度、縫線及甲片厚度仍需在建模統一，拆解不是已驗裝配尺寸。

本輪只改美術文件、圖稿與預覽，Godot runtime、數值、骨架與動畫未變。圖片與資料檢查通過；全圖集驗證仍有既有錯誤，已與 HEAD 原內容比對。

| 檢查 | 結果 |
| --- | --- |
| 三圖目視：不透明面甲、鋼藍配色、細光槽 | PASS |
| 新舊 PNG 完整性、圖檔／提示詞／實際輸入 SHA-256 | PASS |
| C-13 設計／生成紀錄／manifest／圖集同步；其他圖集項目保持原資料 | PASS |
| 比較頁本地連結與 JavaScript 語法 | PASS |
| `git diff --check`、harness integrity | PASS |
| 全圖集 `validate_delivery.py` | FAIL：與 HEAD 相同的 39 項既有錯誤，本次新增 0 項 |
| 瀏覽器互動、Godot 應用驗證 | NOT RUN |

本機完整檢查與基準比較保存在 `test_output/andromedae_closed_helmet_delivery.json` 和 `test_output/andromedae_closed_helmet_baseline.json`，不列入美術交付圖稿。
