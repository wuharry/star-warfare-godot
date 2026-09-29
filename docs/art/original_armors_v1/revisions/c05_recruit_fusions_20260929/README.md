# Strike：B／Atom 與 Recruit 的頭盔融合預覽

日期：2026-09-29。狀態：使用者偏好前輪 B，要求這兩個融合方向都製作供參考；本輪尚未選定正式版本。

## 兩案皆套回遊戲原始 Strike 的大頭短身比例

本次把「原版」解讀為 references/legacy/c05_front.png 的原始 Strike，而非目前較寫實的全身重設概念。保留大頭、短身、粗四肢及既有藍甲，僅探索頭盔。

| 方案 | 特徵 | 圖片 | 完整提示詞 |
| --- | --- | --- | --- |
| B＋Recruit | B 的淺 V 金色窄窗，搭配 Recruit 分片圓頂、頰甲與側殼銜接 | [全身與頭部比較](b_recruit_original_fit.png) | [prompt_b_recruit.txt](prompt_b_recruit.txt) |
| Atom＋Recruit | Atom 青色連續玻璃、下緣收窄的輪廓，融合 Recruit 弧形眉框與頰甲；套在 Strike 上 | [全身與頭部近照](atom_recruit_original_fit.png) | [prompt_atom_recruit.txt](prompt_atom_recruit.txt) |

## B＋Recruit

![B＋Recruit](b_recruit_original_fit.png)

已目視：身體保留原始短身厚肢特徵，金色玻璃較窄，圓頂與前後雙額燈一致。左側 ORIGINAL 也是模型重新繪製的比較圖，並非原圖直接拼貼；左腳外緣略貼圖邊。新方案人物雙腳完整。

## Atom＋Recruit

![Atom＋Recruit](atom_recruit_original_fit.png)

已目視：原始 Strike 身甲、雙額燈及短身比例保留，玻璃改青色，下側邊向中央收窄。實際生成的玻璃仍較大；下中央護片形成小凹口。這一案同時變更形狀與顏色，不能把兩案的辨識差異全歸因於輪廓。

## 原始參考

以下連結直接指向既有來源圖片，不是生成的來源重繪。

| 用途 | 來源 |
| --- | --- |
| 原始 Strike 的比例、身甲及站姿 | [正面](../../references/legacy/c05_front.png)、[側面](../../references/legacy/c05_side.png) |
| 使用者偏好的 B 面罩 | [B 方案](../c05_helmet_alternatives_20260929/strike_b.png) |
| 原始 Atom 面罩 | [正面](../../references/legacy/c08_front.png)、[側面](../../references/legacy/c08_side.png) |
| Atom 目前重設面罩輪廓的補充參考 | [概念圖](../../images/c08_concept.png) |
| Halo 4 Recruit (GEN2) 頭盔結構 | [近照及模型](../../references/halo/c05_recruit_halo4_model.jpg)、[另一張遊戲造型參考](../../references/halo/c05_recruit_halo4_render.png) |

本輪使用內建 image_gen，各案獨立生成。兩圖均為概念合成，尚未接入 Godot、修改原始模型或替換正式素材；不代表精確比例量測或可直接建模的正投影圖。
