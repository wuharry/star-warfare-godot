# Pegasus 頭盔配色更正

2026-09-29：使用者更正「Pegasus 頭盔應該是同色不是紅色的」。正式方向改為頭盔硬殼與身甲一致的白灰色；保留深色 V 面罩、雙低冠軌、分層頰甲與現有全身造型。

| 圖稿 | 更正後 | 修改前 | 本次完整提示詞 |
| --- | --- | --- | --- |
| 全身概念 | [主圖](../../images/c09_concept.png) | [舊稿](images/c09_concept.png) | [提示詞](../../prompts/c09_concept.txt) |
| 三視圖 | [主圖](../../images/c09_turnaround.png) | [舊稿](images/c09_turnaround.png) | [提示詞](../../prompts/c09_turnaround.txt) |
| 結構拆解 | [主圖](../../images/c09_construction.png) | [舊稿](images/c09_construction.png) | [提示詞](../../prompts/c09_construction.txt) |

## 更正範圍

使用內建 image_gen 對既有三張圖分別進行局部改色；三視含前、側、後殼，拆解含完整頭盔及全部外殼分件。身甲、姿勢、比例與獨立背包沿用原設計。未進行後製拼貼；圖像生成可能有細節重繪，不宣稱像素完全不變。

舊規格把紅盔寫成保留條件，現已同步修正角色資料、融合規則與來源分析中的有效配色要求。原擷取圖不重繪，其紅色頭盔只保留作歷史觀察，不再作為後續配色依據。

## 封存與建模界線

本目錄的圖片、提示詞、生成紀錄、`design_before.json` 與 `sources` 保留更正前內容；歷史 JSON 相對路徑以當時 `original_armors_v1` 為根。新的逐圖紀錄見 [角色資料](../../c09_bulwark.json)。

本次只更正美術圖與文件，未修改 Godot 模型或材質。三視與拆解仍是概念參考，尺寸、接縫與機構須在建模時統一。

## 驗證

| 檢查 | 結果 |
| --- | --- |
| 三張圖片、提示詞、輸入圖雜湊與設計／manifest／圖庫紀錄一致 | PASS |
| 修改前封存與原始版本一致，圖片核對 Git LFS SHA-256 | PASS |
| 其餘圖庫角色與來源分析項目未變更 | PASS |
| 瀏覽器切換概念、三視、拆解及各自舊稿，共六張圖片載入 | PASS |
| `git diff --check`、`python3 .harness/verify.py` | PASS（harness 僅檢查投遞完整性） |
| Godot 模型、材質與動畫 | NOT RUN；此次未修改執行期素材 |
