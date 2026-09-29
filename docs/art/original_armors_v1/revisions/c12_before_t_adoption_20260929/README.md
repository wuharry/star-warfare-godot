# Cygni 採用金色微 T 面罩前的版本

2026-09-29 使用者回覆「好偏T字這種」，正式方向採用 Anubis 融合、金色微 T 面罩。

## 本次同步

- 主圖直接採用 [已選 T 字原圖](../c12_helmet_fusions_20260929/images/anubis_gold_t.png)，未重新生成。
- [三視圖](../../images/c12_turnaround.png)與[拆解圖](../../images/c12_construction.png)透過 built-in image_gen 同步金色微 T 玻璃、分層眉甲、內收護頰及短下巴。
- 白灰頭盔、短後掠翼、深綠／白灰／銅橙身甲及獨立 B-12 背包延續。
- 使用者已選定概念方向；配套三視與拆解由助理目視核對，未宣稱逐張獲使用者驗收。

## 可回看的版本

| 視角 | 採用前圖 | 採用前提示詞 | 目前提示詞 |
| --- | --- | --- | --- |
| 主圖 | [舊紫面罩](images/c12_concept.png) | [舊提示詞](prompts/c12_concept.txt) | [金色 T 字](../../prompts/c12_concept.txt) |
| 三視 | [舊三視](images/c12_turnaround.png) | [舊提示詞](prompts/c12_turnaround.txt) | [同步提示詞](../../prompts/c12_turnaround.txt) |
| 拆解 | [舊拆解](images/c12_construction.png) | [舊提示詞](prompts/c12_construction.txt) | [同步提示詞](../../prompts/c12_construction.txt) |

[寬面罩／T 字比較](../c12_helmet_fusions_20260929/index.html)保留；寬金色面罩原檔未修改。`design_before.json`、`source_rules_before.json` 及 `generation_records/` 保留採用前的設計與來源紀錄。

本輪只更新設計圖集，未製作或接入遊戲模型。三視玻璃轉折、護頰厚度、拆件裝配縫仍需在建模時統一；概念圖不作精確尺寸或 UV 分區依據。

## 驗證

- PASS：主圖與使用者選定原圖完全相同；寬金色面罩未變；採用前三張圖完整封存。
- PASS：圖片、提示詞及實際輸入 SHA-256、逐圖紀錄、manifest 和內嵌圖集資料一致；其他裝甲資料及玩法數值未變。
- PASS：in-app browser 已顯示「已採用頭盔方向」與金色 T 主圖，三視、拆解、修改前切換均載入對應圖片。
- PASS：harness integrity、`git diff --check`。Godot 應用測試 NOT RUN；這次不涉及遊戲程式或執行期素材。
