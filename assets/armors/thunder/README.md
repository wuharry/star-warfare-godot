# Thunder 頭盔 v5：兩個修訂方案

本次依使用者圈選的概念圖，將金色面罩下端收窄，讓藍色頰甲向內包覆，取代 v4 的寬面罩方向。兩版保留各自頭盔基底、配對刻紋與貼合呼吸器，沿用 v4 身甲及原 28 個具名骨骼綁定。

| 方案 | 實作 | 遊戲場景／可編輯來源 |
| --- | --- | --- |
| A：SW2 修訂（預設） | 在原 SW2 相連網格上變形下方面罩與內頰邊界，保留 UV、刻紋、耳部與後腦；壓低冠頂並調整眉甲深度 | `thunder.scn`（預設）、`thunder_sw2.scn`（明確選 A）；[thunder.blend](../../../docs/art/armor_rework/thunder.blend) |
| B：雛形修訂 | 保留 V3 圓頂、寬脊甲與後腦；新建梯形面罩、分段倒角頰甲、斜眉甲，補齊側面包覆 | `thunder_prototype.scn`；[thunder_prototype.blend](../../../docs/art/armor_rework/thunder_prototype.blend) |

A 的後續修訂已將冠頂修圓，呼吸器縮薄並沿下巴斜面嵌入；遊戲材質的藍／深藍基色對齊身甲，金色面甲不調色。原始點陣貼圖不變，配色由 `helmet_detail.gdshader` 套用；Blender 檔提供最新幾何，實際遊戲配色以 HTML 擷取為準。

`ArmorVisuals.reworked_scene_path(6)` 供遊戲與商店共用；啟動參數 `--thunder-helmet=prototype` 選 B，`--thunder-helmet=sw2` 選 A。省略參數使用 A，不把方案寫入存檔。商品縮圖使用預設 A。

[離線 HTML 對照](../../../docs/art/thunder_helmet_comparison_v5/index.html) 包含兩版各 30 張 Godot 實際擷取、概念圖、細節、換彈與關卡畫面；可點擊放大與切換角度。兩版使用相同燈光、姿勢與固定取景，未補畫或合成角色。概念圖自身的姿勢與光線不同，不宣稱像素級還原。

## 素材與可重建性

[SW2 來源紀錄](source_sw2/README.md) 記錄使用者提供的 OBB 中模型、材質與貼圖配對。新版頭盔使用 `sw_06_head_d/n/l`，不是舊版 `Avatar06_head.png`。B 的外殼基於原 V3 建模腳本，面罩重新對應原金色島；本次沒有重新生成或縮放點陣貼圖。

1254 × 1254 的 [頭盔貼圖](textures/helmet_detail_albedo.png) 與 [生成提示](helmet_texture_prompt.txt) 沿用 v4；原法線貼圖為 256 × 256、發光圖為 512 × 512。新增頰甲、斜角與面罩輪廓屬於模型幾何，刻紋保留貼圖與配對法線。

原 Unity 貼圖的 alpha 含材質遮罩，透明像素仍有必要的 RGB。編譯器直接解碼 PNG，再透過 Godot 儲存可攜式、無損 `ImageTexture` `.res`，避免預設 alpha 邊界修補破壞法線。沒有新增 mipmap 或有損像素壓縮，測試逐像素比對來源。`.res` 的 `FLAG_COMPRESS` 是無損資源封裝，並非有損圖像壓縮。

`build_report_sw2.json`、`build_report_prototype.json` 記錄各自幾何與素材雜湊；`build_report.json` 對應預設 A。版本標記為 `thunder_helmet_v5_sw2`／`thunder_helmet_v5_prototype`。

## 建置、檢查及啟動

在專案根目錄執行；將 `sw2` 換成 `prototype` 即可重建 B：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python-exit-code 1 --python tools/armor_rework/build_thunder.py -- --helmet=sw2
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/armor_rework/compile_thunder.gd -- --helmet=sw2
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/thunder_armor_test.tscn -- --thunder-helmet=sw2
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_helmet_comparison/capture.tscn -- --thunder-helmet=sw2
powershell -ExecutionPolicy Bypass -File tools/thunder_helmet_comparison/launch.ps1 -Helmet prototype
```

完成 A、B 擷取及對應測試後，`python tools/thunder_helmet_comparison/build_preview.py` 會檢查場景、材質雜湊，再更新離線 HTML，拒絕使用過期擷取。初次建立文件可用 `--annotation` 指定使用者紅圈圖片。詳細驗證紀錄在 HTML 附錄。

擷取使用隔離的測試裝備資料，並核對實際存檔前後雜湊，不修改使用者裝備、階級或貨幣。關卡擷取退出仍有既有 font／CanvasItem 資源清理警告，與模型解析或載入失敗分開記錄。

[V4 對照](../../../docs/art/thunder_detail_v4/index.html) 與 [V3 雛形](../../../docs/art/thunder_concept_v3/index.html) 保留作為歷史版本。
