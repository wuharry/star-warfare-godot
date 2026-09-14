# Thunder B — 首版 3D 套用

2026-09-14。使用者核准 B 新頭盔後，將方向套入既有 Thunder set06；這是沿用原網格／UV 的首版 3D 改造，並非概念圖的精準完整重建。

- 核准參考：[B 新頭盔概念](../../../docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png)。
- 實際對照：[原版／概念／遊戲模型](../../../docs/art/thunder_mk_comparison_v1/runtime.html)。
- 改造包含寬低中央額脊、眉甲、金橙面罩、短下顎與硬甲切面；曲面、耳部和細接縫仍比概念簡化。
- 保留原 Thunder 比例、網格與 UV 基底、骨架綁定、動畫和混裝部位。新增殼體以真正幾何呈現厚度，原貼圖區域仍保留 baked 色彩；材質設定以 compiler 與 shader 為準。

## 遊戲接線

`scripts/game/armor_visuals.gd` 的 `REWORKED_SCENES[6]` 指向 `res://assets/armors/thunder/thunder.scn`。角色與商店／裝備預覽共用這條替換流程。

- 輸出保留 `ArmorHead_06`、`ArmorBody_06`、`ArmorHand_06`、`ArmorFoot_06`，以原具名 Skin binds 接回原骨架；metadata 為 `thunder_mk1_helmet_v2`。
- 不變更裝備 ID、玩法數值、存檔格式、其他套裝或原素材。原版 `assets/equipment_refined/armors/armor_06.scn` 留存；改造前截圖腳本固定讀它，不跟隨新的 set06 接線。
- 四張商店縮圖由目前實際模型重新渲染至 `assets/ui/armor_thumbnails/armor_{head,body,arms,legs}_06.png`。
- 三角形數量、範圍和來源雜湊以 [build_report.json](build_report.json) 為準；不要在其他文件另維護一份容易失真的數字。

## 重建與驗證

以下命令從 repo 根目錄執行。Blender 與 Godot 必須已安裝；不需要安裝新依賴。先完成引擎正常資源匯入，勿手改 `.import`、`.uid` 或 `.godot`。

```sh
# 產生骨架相容的網格資料與 build_report.json。
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/armor_rework/build_thunder.py

# 編譯前先測輸入拒絕路徑；此命令不覆寫遊戲模型。
godot --headless --path . --log-file /tmp/thunder-compiler-validation.log --script tools/armor_rework/compile_thunder.gd -- --self-test

# 由 test_output/armor_rework/thunder_meshes.json 產生 thunder.scn。
godot --headless --path . --log-file /tmp/thunder-compile.log --script tools/armor_rework/compile_thunder.gd

# 實際角色、混裝、Skin binds、材質、動畫與商店預覽斷言。
godot --headless --path . --log-file /tmp/thunder-armor-test.log res://tests/thunder_armor_test.tscn

# 必須使用真正 renderer；headless 邏輯測試不能驗收畫面。
godot --path . --rendering-method gl_compatibility --log-file /tmp/thunder-art-capture.log res://tests/thunder_art_capture.tscn

# 只更新 Thunder 四部位的商店縮圖。
godot --path . --rendering-method gl_compatibility --log-file /tmp/thunder-thumbnails.log --script res://tools/render_armor_thumbnails.gd -- --set-id=6
```

構建輸入／中間資料在 `test_output/armor_rework/`；檢查 `build_report.json` 後再接受模型。正式 shader 色彩由 `compile_thunder.gd` 決定，Blender 材質僅方便編輯，不拿 Blender 截圖冒充遊戲效果。

遊戲截圖輸出到 `test_output/thunder_runtime/`，包含 `capture_manifest.json`；視口固定 1000 × 1200。HTML 使用其中的全身、頭盔近照、背面、持槍和換彈中段圖片。測試使用隔離的測試存檔路徑，不應覆寫玩家平常的裝備存檔。

上述是重跑方法，不代表每次重建已通過驗收。判斷結果須看當次 `THUNDER_COMPILE_*`、`THUNDER_COMPILER_VALIDATION_*`、`THUNDER_ARMOR_*`、`THUNDER_ART_CAPTURE_*` 輸出；capture 成功只代表截圖完成，仍需看圖和檢查動作。

本次已通過 compiler、輸入錯誤路徑、Thunder 專用角色／混裝／Store／Customize 測試、其他 27 套裝備回歸及 `armor_system`／`menu_equipment` 測試，並完成十二張真實角色截圖和四張縮圖。概念頁及 runtime 頁的桌面／手機圖片、連結與溢出檢查通過，桌面實際畫面已目視；最終美術滿意度仍由使用者確認。

## 來源與後續

原 Thunder 網格來自 `assets/models/player/animated/player.gltf`，原貼圖來自 `assets/equipment_refined/textures/`；沿用原素材的部分仍未取得商用權利清理。AI 概念和新增幾何不能自動消除原素材的授權限制。

下一輪應由使用者先看遊戲效果，決定是否再重建更貼近概念的連續外殼、耳部凹凸和細接縫。不要把這個首版記成已完成全套原創商用資產。
