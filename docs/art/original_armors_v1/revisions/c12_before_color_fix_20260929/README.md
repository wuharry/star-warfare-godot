# Cygni：頭盔與身甲統一白灰

2026-09-29 使用者更正：「Cygni 也是頭盔跟身體顏色應該一致」。本輪將粉珊瑚頭盔外殼改為身甲相同的白灰；保留暗紫面罩、銅橙 U 形框、黑色內襯及既有造型。新輸出仍待使用者逐圖評價。

| 圖稿 | 更正後 | 更正前 | 完整提示詞 |
| --- | --- | --- | --- |
| 全身概念 | [新版](../../images/c12_concept.png) | [舊稿](images/c12_concept.png) | [提示詞](../../prompts/c12_concept.txt) |
| 三視圖 | [新版](../../images/c12_turnaround.png) | [舊稿](images/c12_turnaround.png) | [提示詞](../../prompts/c12_turnaround.txt) |
| 結構拆解 | [新版](../../images/c12_construction.png) | [舊稿](images/c12_construction.png) | [提示詞](../../prompts/c12_construction.txt) |

## 製作範圍

使用內建 image_gen，第一輪各以對應的更正前圖稿為唯一圖片輸入，要求只更正粉色硬殼。冠殼、頰殼、下巴、圓形接點、側翼與後腦都應統一白灰；拆解的獨立零件、穿戴小圖及肩部小圖中的頭盔邊緣亦在範圍內。B-12 背包保留獨立白橘殼、藍頂、中央金屬筒及下方橫接頭。

拆解另作局部修正：第一稿的肩部小圖邊緣仍殘粉色，拆開的面罩框也少了一段銅橙色。修正輸入為[第一稿](construction_initial.png)與[更正前拆解](images/c12_construction.png)；[第一輪提示詞](construction_initial_prompt.txt)及[紀錄](construction_initial_record.json)保留可追溯來源。

角色資料、融合規格與圖集同步取消「保留粉盔與身甲反差」要求。來源分析保留原擷取觀察，另記使用者更正；未重畫原遊戲參考圖，也未宣稱重新驗證原遊戲材質。

## 版本與限制

本目錄保存更正前圖片、提示詞、生成紀錄、design_before.json 與 source_rules_before.json。歷史 JSON 原有相對路徑以 original_armors_v1 為根；舊輸入按當時雜湊理解。當次新輸出的精確來源、提示詞與目視紀錄見 [角色資料](../../c12_spur.json) 及 [生成紀錄](../../generation_records/c12_concept.json)。

已逐圖目視：三張圖的頭盔外殼及小視圖均已改白灰，紫面罩、銅橙框和獨立背包配色保留。拆解圖右側銅橙邊仍較組裝示意窄，色塊邊界需建模統一。

此次為配色修正，不是造型重設。生成會重繪表面紋理，不宣稱像素完全不變；三視與拆解仍是概念參考，機構尺寸及活動間隙須於建模階段確認。Godot 模型、動畫與玩法未更動。
