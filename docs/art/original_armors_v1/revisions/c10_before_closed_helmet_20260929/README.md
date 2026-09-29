# Draco：Reverie Dawn 頭盔試稿

2026-09-29：Draco 頭盔改參考 Destiny 2 **Reverie Dawn Helm**，目前待使用者評價。

使用者先更正「Draco 的頭盔是沒有護目鏡那種的面罩的」，再針對 Iron Symmachy 試稿回覆「不太對換一個天命的頭盔參考」。本輪由助理另選 Reverie Dawn；不把要求換參考視為已接受這一版。

## 新方向

寬額與一道細窄水平視孔，搭配盾形不透明金屬面甲。將參考圖的下臉收短，換成 Draco 煤灰／鐵灰，保留小圓耳座、厚肩甲與原有身體輪廓。大玻璃護目鏡、上一稿中央深色縱條、參考圖白金裝飾均不採用。

| 圖稿 | 新版 | 修改前 | 完整提示詞 |
| --- | --- | --- | --- |
| 全身概念 | [主圖](../../images/c10_concept.png) | [舊稿](images/c10_concept.png) | [提示詞](../../prompts/c10_concept.txt) |
| 三視圖 | [主圖](../../images/c10_turnaround.png) | [舊稿](images/c10_turnaround.png) | [提示詞](../../prompts/c10_turnaround.txt) |
| 結構拆解 | [主圖](../../images/c10_construction.png) | [舊稿](images/c10_construction.png) | [提示詞](../../prompts/c10_construction.txt) |

## 參考與未採用版本

- [Reverie Dawn Helm 來源頁](https://destinytracker.com/destiny-2/db/items/99549082-reverie-dawn-helm)：[Bungie 官方物品圖片](https://www.bungie.net/common/destiny2_content/screenshots/99549082.jpg)，[本地參考](../../references/destiny2/c10_reverie_dawn_helm.jpg)。只取頭盔形體。
- CQC 繼續作既有身甲結構參考，沒有用來決定新頭盔面部。
- [未採用的 Iron Symmachy 版](../c10_rejected_iron_symmachy_20260929/README.md)：保留長面甲、縱條草稿與當時提示詞；不作本版頭盔依據。

## 製作與檢查

使用內建 image_gen，沒有後製拼貼。概念圖實際輸入為修改前全身稿與 Reverie Dawn 原圖；三視及拆解各輸入修改前圖稿與新版概念。精確輸入、提示詞、SHA-256 與目視紀錄見 [角色資料](../../c10_lodestone.json) 及 [生成紀錄](../../generation_records/c10_concept.json)。

已逐圖目視：新頭盔在三張圖一致，拆解為外殼、面甲與軟內襯；煤灰身甲與獨立 B10 的藍／紫／金／青配色保留。生成會重繪表面紋理，沒有宣稱像素完全不變。三視與拆解是概念參考，視孔、接縫、厚度與跨視尺寸仍需在建模時統一。

本資料夾保存換頭盔前的圖片、提示詞、生成紀錄、design_before.json 與 source_rules_before.json。歷史 JSON 原有相對路徑以當時 original_armors_v1 為根；generation_records 的舊輸入應按當時雜湊理解，不是今日同名主圖。

來源分析保留原擷取觀察，另列使用者取消玻璃的設計要求；沒有重新驗證原遊戲材質。此次只有美術文件與預覽，Godot 模型、骨架、動畫及玩法未更動。
