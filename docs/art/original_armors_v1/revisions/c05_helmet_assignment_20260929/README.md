# Strike／Atom 頭盔方向採用

2026-09-29：使用者選 Atom＋Recruit 為 Strike 正式頭盔方向，並要求 B＋Recruit 套用 Atom 頭盔。兩套沿用既有全身比例與身甲；本次替換正式概念、三視及拆解圖，Godot 素材尚未變更。

| 角色 | 採用特徵 | 概念 | 三視 | 拆解 | 修改前 |
| --- | --- | --- | --- | --- | --- |
| Strike／C-05 | 青色面罩向下收窄、中央小凹口、短下巴；鋼藍圓冠與雙冠環 | [概念](../../images/c05_concept.png) | [三視](../../images/c05_turnaround.png) | [拆解](../../images/c05_construction.png) | [封存](../c05_before_helmet_swap_20260929/README.md) |
| Atom／C-08 | B＋Recruit 淺 V 窄窗、短下巴；紫藍殼、青玻璃、三顆額燈與圓耳 | [概念](../../images/c08_concept.png) | [三視](../../images/c08_turnaround.png) | [拆解](../../images/c08_construction.png) | [封存](../c08_before_helmet_swap_20260929/README.md) |

## 採用依據

使用者原話：「Atom 版 當正式的好了／但是B＋Recruit。的設計我希望你把它用到atom的頭盔上」。前輪選案見 [兩款預覽](../c05_recruit_fusions_20260929/README.md)。使用者確認的是方向；本輪衍生圖由助理目視核對，尚未逐張獲使用者確認。

## 生成與修正

全部使用內建 image_gen，以既有全身稿／配套圖和已選頭盔作編輯參考，沒有後製裁切或拼貼。逐圖提示詞、實際參考圖、輸出來源與雜湊見 [Strike 資料](../../c05_breachline.json)、[Atom 資料](../../c08_prism.json)和 `generation_records`。圖像生成會重繪畫面，身甲沿用是設計意圖，不表示像素完全不變。

Strike 拆解初稿殘留舊額前方形燈及較多通風槽，已修成不發光藍甲與簡化通風槽。此處的 [初稿](construction_initial.png)、[初稿提示詞](construction_initial_prompt.txt)及 [生成紀錄](construction_initial_record.json)僅保留修正來源；正式拆解以主圖庫版本為準。

## 驗收界線

已逐張檢視頭盔輪廓、指示燈、面罩配色、完整站姿及背包分離。三視與拆解仍是概念參考，跨視接縫、遮擋、尺寸及機構須在建模時統一；未執行遊戲模型、骨架、碰撞或動畫驗收。

| 檢查 | 結果 |
| --- | --- |
| 六張主圖、提示詞與參考圖雜湊；設計 JSON、manifest、圖庫資料一致性 | PASS |
| 修改前封存與 HEAD 原始內容比對；圖片依 Git LFS SHA-256 核對 | PASS |
| 其餘圖庫項目未變更 | PASS |
| 本機瀏覽器切換兩套各三種視圖及修改前版本，共十二張圖片載入 | PASS |
| `git diff --check`、`python3 .harness/verify.py` | PASS（harness 僅檢查投遞完整性） |
| Godot 執行期與角色動畫 | NOT RUN；本次只修改美術文件與概念圖片 |
