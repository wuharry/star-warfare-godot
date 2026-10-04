# Tank runtime 製作契約

目標是將使用者確認的 `approved_parts_reference.png` 與最新 Tank 頭盔融入原遊戲短壯比例。大橙金面甲與中央尖折、鋼藍厚板、雙鼠尾草綠冠條、肩上翹綠護唇是辨識重點；中央下護片改成實心藍護片、低部短橫進氣。

原版權威是 `assets/models/player/animated/player.gltf` 的 `ArmorHead_02`、`ArmorBody_02`、`ArmorHand_02`、`ArmorFoot_02`。`build/source.json` 保存 rest-space 與原 bind-space 頂點、UV、索引、權重、骨架名稱、normal 及完整 Skin bind matrix；`build/texture_sources.json` 記錄五張原 atlas 的路徑、共享區域與原用途。

UV 座標和 chart 數量維持不變。每材質改動 UV 座標占比最多 15%；本版頭盔中央改 4／149（2.68%）、前胸綠領改 12／210（5.71%），其餘材質完全使用原值，總共 16／731（2.19%）。中央進氣口必須跨過鏡像縫連成單槽，綠色 U 領必須在可見胸甲上方。局部頂點位移除以該原部位的最小尺寸、各軸尺寸變化、同相機灰模輪廓差異亦各不超過 15%。本版只有下護頰微收與下護片補厚，原四肢、骨架、索引和權重維持原值。

生成輸入使用原 atlas、確定的美術、原 UV guide 與實機模型。`guides/body_front_regions.png` 的 cyan 表示真正的前半胸 plate，白虛線是 `u≈.029` 鏡像縫；前胸主要取樣於 `u=.029–.247, v=.415–.694`。完整雙側胸板若畫在 atlas 內部會重複，必須只畫半面與正確接縫。線圖和技術區域色不能畫進 diffuse。

肩部、頭盔、手臂、身體和靴子的 diffuse 不得用全身展示圖取代。手臂 atlas 上方區域另供頭盔頸襯取樣；維持深色布料。五張圖共用 original-compatible UV，但美術可按本輪參考重畫，原版後方未明確顯示的細節依原模型和三視參考統一。

本版採用 head v2、body v4、shoulder v2、hand／foot v1。`*_uv` guide 與生成輸入記錄不可覆寫；最終局部取樣另存 `*_authored_uv` guide。所有非退化 UV 三角形方向保持，沒有折疊。舊 0% 驗收位於 `review/drafts/uv0_head1_body2/`，最終報告必須與目前 SCN／GLB／master／canonical PNG 的 SHA 對應。

驗收包含原版／新版全身、頭部、待機、跑動、換彈與兩個真實關卡，使用同相機與原骨架。Root 負責遊戲 loader 和系列 gallery；本套 build、交換模型、貼圖來源紀錄及比較頁保存於本目錄。
