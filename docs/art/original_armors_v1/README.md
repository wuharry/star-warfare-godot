# 裝甲與背包融合設計

本輪重做 **21 套裝甲與 25 個獨立背包**，把實際原版特色與指定 Halo 非士官長設計融合成新的人體科幻裝甲。從 [圖集 index.html](index.html) 看「原版 → Halo 參考 → 新稿」，並用 [runtime_mapping.json](runtime_mapping.json) 查遊戲裝備對應。

- C-01 是 Viper（armor ID 0）的外觀替換提案；B-01 是 VB-03-II（bag ID 0），不是 Viper 的固定背包。
- 每套 C 有概念、三視及結構拆解三種交付；每個 B 有包含主視、外面、側面、貼背面及維修拆解的獨立設計稿。同序配搭只是三視展示，裝甲與背包仍可各自選擇。
- 本輪舊的白綠通用外形與機械臉稿已由新方向取代。暫名和可用的玩法草案保留；配色、頭盔與裝置依本輪來源、prompt 及目視紀錄重寫。

新機器 clone 後先執行 `git lfs pull`，PNG 才會是完整圖片，而非 LFS 指標文字。下列整理與驗證工具使用 Python 3.9 以上，不需額外套件。

逐套評價保存在各款 JSON 的 `user_review`，圖集目錄與標籤會顯示保留決定。2026-09-28：C-01／Viper 已評價「沒有問題」，保留目前頭盔與身甲；背包仍各自評價。這與下方的生成、目視和遊戲製作狀態分開記錄。

Fortune／C-02 已依「頭盔太像原版」的回饋修改面罩與下顎：取消額前黑徽槽、鼻部凸塊及方形下巴缺口，改為連續藍眉框、較低的紫色面罩、斜切寬護頰與中央綠色護片。三張概念／三視／拆解均以內建 imagegen 編輯並同步，身甲與 B-02 設計延續，局部繪製細節不保證逐像素相同。使用者已評價「好，很好」，圖集標為「保留目前設計」；各視圖可按「查看修改前」切換；原圖、提示與來源紀錄保存在 `revisions/c02_previous_helmet_20260928/`。本次是概念美術修改，Fortune 遊戲模型尚未套用。

Tank／C-03 依最新回饋保留原大橙金面罩、中央尖折與分節頭冠，只修改下方護頰和呼吸器：中央護片保留向上尖起的輪廓，改成實心鋼藍切面及底部短橫進氣口，兩側增加斜向分件護頰。概念／三視／拆解已以內建 imagegen 同步，身甲與 B-03 設計延續；局部繪製細節可能改變。原圖、提示與來源紀錄在 `revisions/c03_previous_helmet_20260928/`，圖集各視圖可切換修改前後。縮小面罩、寬平下顎的中間稿因失去 Tank 特色被使用者否定，完整保存在 `revisions/c03_flat_visor_rejected_20260928/`。使用者已評價「ok；不錯」，圖集標為「保留目前設計」；Tank 遊戲模型尚未套用。

Thunder／C-07 恢復先前核准的 [B 新頭盔概念](../thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png)。圖集優先顯示此舊稿，原 C-07 融合概念、三視與拆解明確標示「未採用版本」，不當成舊稿的配套三視。`user_review.preferred_art` 保存選圖、SHA256、原提示與生成紀錄；本輪 88 張生成紀錄保留作歷史交付，採用方向以 `user_review` 為優先。具體舊圖依歷史核准紀錄辨認，已提出檔名確認。遊戲 Thunder 面罩另已移除兩道深黃色刻槽，見 [實際模型前後對照](../thunder_helmet_comparison_v5/index.html)；其美術驗收仍待回覆。

## 本次刷新狀態

2026-09-25 刷新時，46／46 款的全部要求圖種已有目視紀錄，仍需使用者選稿。以下數字只計正式圖檔和生成紀錄都存在的輸出；未採用版本另留在歷史紀錄。

| 圖種 | 已生成 | 已目視 |
|---|---:|---:|
| concept | 21 | 21 |
| turnaround | 21 | 21 |
| construction | 21 | 21 |
| design_sheet | 25 | 25 |

完整狀態在每款 JSON 的 `images`、`production_status` 和 `generation.records`；可攜的實際生成紀錄保存在 `generation_records/`。`null` 是尚未交付，不顯示虛構圖片連結；`generated_pending_visual_review` 不代表目視合格。後續修改各款 JSON、圖片及生成紀錄後，可執行正式的 [tools/build_gallery.py](tools/build_gallery.py) 更新 manifest 與圖集，再用 [tools/validate_delivery.py](tools/validate_delivery.py) 檢查交付一致性。這些工具不依賴本機 scratch 或 `.codex` 原始路徑。

## 從美術圖到遊戲

本輪已執行的資料、圖檔與瀏覽器檢查見 [validation.json](validation.json)；檢查通過不等於使用者已選定造型或遊戲素材已完成。

概念／三視／拆解 → 製作新 3D 模型 → UV 展開 → 專用貼圖 → 綁骨架與裝配 → 遊戲內混搭及動作測試。

模型決定頭盔、肩甲與背包的立體輪廓；UV 指定每塊表面使用貼圖的哪個位置。整張人物概念圖不能直接捲到現有模型上；只換貼圖也不會得到新輪廓。這批圖是建模參考，尚未交付 mesh、UV、runtime 紋理或骨架。

## 資料與来源

- [series_plan.md](series_plan.md)：21 套装甲與 25 個背包的原版、Halo、暫名與技能方向對照。
- [art_direction.md](art_direction.md)：人穿裝甲、來源融合、C-06 附件例外，以及三視與獨立背包的製作規則。
- `cNN_*.json`、`bNN_*.json`：共同保留 C-01 schema 的 root 欄位；新技能一律 `proposal_only`，背包不承接裝甲技能。C-10～C-21 的 HP／盾尚未指定。
- `prompts/`：完整提示詞內容；檔案換行統一為 LF、檔尾單一換行。`generation.records` 指向實際輸入與目視結論；未採用稿和輸入錯誤版本亦保留。提示詞存在不等於生成完成。
- `references/` 保存原遊戲恢復模型截圖與 Halo 來源圖，`sources/` 保存逐款觀察及來源。來源圖路徑以本資料夾為基準；`historical_reference_paths` 另保留擷取時的本機路徑，無需在新機器重建。這些參考圖不是本輪生成成品，也不是可直接發布的原創遊戲素材。
- C-06／Titan 的概念僅將使用者兩張頭盔附件作圖像輸入；Titan 原圖僅用文字觀察。先前 EVA 候選不是此次概念呼叫的圖像輸入。後續三視／拆解的輸入另依各自紀錄。
- C-14／Perseus 依使用者修正，以原版高封閉硬面殼、中央折面、下收白分叉線和窄橘冠條為主，沒有護目鏡、水平玻璃帶或露眼窗；EOD 只保留身體與頸胸穿戴結構參考。
- C-17／Knight 依使用者修正，以原版外翻寬帽沿、中央尖冠、雙短角與大綠面罩為主；Halo 不再主導頭盔造型。
- 這兩套的前一版三圖、實送提示詞與生成紀錄分別封存於 `revisions/c14_previous_fusion/`、`revisions/c17_previous_fusion/`，標記為已被使用者新方向取代。正式 `images/c14_*.png`、`images/c17_*.png` 才是目前選用稿；封存稿不計入 88 張交付。

## 未改動的遊戲內容

本輪只製作美術與提案資料，未改現有裝甲 ID、物品、能力值、背包容量、購買升級、存檔或裝備規則。來源融合與重畫不等於已完成授權或發布審查。

[com_consolidation.json](com_consolidation.json) 保持原檔；CoM ID 21～28 的整理仍是另案提案。本輪保留原版少量外觀的要求已更新，因此舊檔中 C-01「不沿用外形」的歷史語句不作本輪美術依據；其中已核對的數值與未實作技能區分仍保留。
