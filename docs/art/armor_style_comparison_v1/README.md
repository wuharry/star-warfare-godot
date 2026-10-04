# Viper／Fortune 新舊裝甲風格比較

開啟 `index.html`，切換裝甲、四個視角及全身／頭盔／灰模／第三人稱畫面。支援原新並排、滑動重疊與點圖放大。頁面離線運作，圖片引用同一個儲存庫的正式素材驗收目錄。

此頁已固定為本輪畫法統一前的快照，圖片放在 `snapshots/`，資產來源指向封存的修改前交付。最新調整見 [畫法統一前後比較](../armor_style_unification_v1/index.html)；此頁保留當時判讀，不跟隨後續貼圖替換。

比較的是原版 `player.gltf` 的 Viper（ID 0）、Fortune（ID 1），以及目前採用的 Viper `concept_match_v8`、Fortune `head_v6 / body_v2`。這次只新增比較資料與展示，沒有修改裝甲素材。

## 判讀結果

兩套新版仍屬於同一系列的短壯科幻厚甲，但全身辨識仍偏向原裝甲改款。

- Viper：黑眉、面甲、腹甲、大腿和四片背甲已有差異；相同的雙胸窗、肩部配色與體積，仍容易被認作同款。
- Fortune：大面積紫面甲、短下巴與 U 形胸框形成較清楚的正面差異；肩甲、四肢與背甲仍接近原版，背面辨識最弱。
- 兩套新版的細白邊、強黑縫及高光比原版更硬、更亮。後續宜統一貼圖高光的畫法，再調整一至兩個主要甲片配置，增加遠距與背面辨識度。

以上為同圖目視判讀，沒有玩家盲測或風格相似度評分。完整十個部位的觀察、保留項目及調整優先順序在 `analysis.json` 與展示頁中。

## 量測口徑

中性全身和頭盔圖使用同相機、白色材質 tint、UN_SHADED，以比較貼圖；灰模比較幾何，第三人稱圖保留遊戲的材質與場景。

UV 百分比是修改座標數／原座標總數；頭部局部位移除以原完整頭部（含頸部）包圍盒最短邊；灰模輪廓差異是 `(1 − 交集／聯集) × 100%`。分母不同，不能合併成裝甲相似度。15% 工程限制也不限制貼圖重畫面積。

Fortune 擷取紀錄含啟動時 SCN／貼圖 SHA，且匹配當前資產。Viper 既有擷取沒有啟動 SHA；目前資產可核對，但擷取追溯證據較弱。

## 產生與驗證

從儲存庫根目錄執行 `python tools/armor_style_comparison_v1/review.py`，以 `analysis.json` 重建 HTML。

- `source_validate.json`：72 個圖片路徑、目前 SCN／頭部貼圖 SHA、HTML／Canvas 資料一致性通過。
- `browser_validate.json`：隔離的 headless Chrome 渲染與 31 項操作／窄版檢查通過；展示截圖為 `preview_*.png`。
- `canvas_typecheck.json`：本機 Canvas SDK 型別檢查通過，尚未驗證 Canvas 宿主內的實際渲染。
- `canvas_snapshot_sources.json`：獨立 Canvas 的位置、檔案 SHA 與 20 張內嵌圖來源；圖片保持原始 PNG 位元組，沒有重畫、裁切或調色。
