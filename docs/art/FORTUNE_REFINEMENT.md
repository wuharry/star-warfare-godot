# Fortune：以 Viper 原版細修為基準

本次只重繪 Fortune 的頭盔、胸甲、肩甲、手臂與腿部五張貼圖。保留原藍綠分色、深色面罩、部件排列與整體輪廓，將上一輪模糊的板件邊線、布料與金屬表面重新刻畫成清楚的手繪細節。遊戲既有 Fortune 場景直接引用這五張貼圖，裝備／商店的四張縮圖也已更新。

使用者指定的 `998f8f1dbe2101d0195185ed5cf9b81ffc7e33c4` 快照中，Viper 的資源與現在相同；Viper 的原版細修資產最早由 `415d800` 引入。這次以該版本的五張 Viper 貼圖作清晰度與材質刻畫參考，並在相同遊戲鏡位直接比較。

模型沿用已完成的 Fortune 小幅銳邊修整。本次模型檔的 SHA-256 未改變，因此沒有再次增加倒角、改外形或改骨骼。其他裝甲與武器資源已用修改前後的檔案雜湊核對，均未改動。

## 檔案對應

| Fortune 部位 | 本次重繪貼圖 |
|---|---|
| 頭盔 | [24d26eb90e3d.png](../../assets/equipment_refined/textures/24d26eb90e3d.png) |
| 胸甲／背甲 | [c0beb4cb8ee2.png](../../assets/equipment_refined/textures/c0beb4cb8ee2.png) |
| 肩甲 | [7e29a9d3f24b.png](../../assets/equipment_refined/textures/7e29a9d3f24b.png) |
| 手臂／手部 | [e8fbfe34f4aa.png](../../assets/equipment_refined/textures/e8fbfe34f4aa.png) |
| 腿部／靴子 | [b38368733664.png](../../assets/equipment_refined/textures/b38368733664.png) |

使用內建 `image_gen` 編輯工具，原 Fortune UV 圖為編輯目標，對應的 Viper UV 圖僅作細節品質參考。五張圖均為原生 1254×1254；沒有用程式放大、濾鏡或修改像素代替美術重繪。完整提示詞、來源、參考與生成檔路徑記於 [texture_provenance.json](../../tools/fortune_refinement/texture_provenance.json)。肩甲另外做一次局部色彩修正，將右上背面 UV 區塊恢復深褐色。

## 實際畫面與驗證

[開啟 Fortune 對照 HTML](../../test_output/fortune_refinement/index.html)。左欄可切換上一輪／原始 Fortune，中欄是本次版本，右欄是 Viper。支援近景／全身、前／側／後及點圖放大。另含三個移動換彈階段與區域 01、03 的實際遊戲畫面，共 35 張截圖。

已目視檢查原版辨識特徵、三視角近景、全身輪廓、移動換彈與兩個關卡畫面。`equipment_refinement_test` 通過（28 套裝甲、85 個武器網格）；HTML 的 35 張圖片、視角選擇、版本切換與放大檢查通過；四張 Fortune 縮圖已重新渲染。測試仍可見舊 OBJ UID 回退警告，擷取場景退出時有既有資源清理警告。

這些是製作端的畫面檢查，最終美術喜好仍以使用者驗收為準。

重建目前版本與 Viper 比較：

```powershell
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tools/fortune_refinement/capture.tscn
python tools/fortune_refinement/build_preview.py
```

上一輪圖的本機備份位於 `test_output/fortune_refinement/baseline`；缺少備份時，工具會省略上一輪選項，仍能比較原始 Fortune、本次 Fortune 和 Viper。HTML 與擷取圖片為本機產物；產生工具、貼圖、縮圖與製作紀錄納入版本控制。
