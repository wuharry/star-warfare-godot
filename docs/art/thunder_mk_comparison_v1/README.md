# Thunder mk1 / mk2 配色與硬甲對照

2026-09-14。B 新頭盔方向已獲使用者核准，並完成首版 3D 套用；先看 [runtime.html](runtime.html) 的原版／概念／實際遊戲角色對照。

[index.html](index.html) 保留概念階段的 A／B 比較、舊／新頭盔切換、灰階和放大互動。該頁的「尚未套用」等文字是當時候選階段紀錄，不代表目前 runtime 狀態；頁首已連到實際套用頁。兩頁都不需要網路服務或外部套件。

## 目前首版 3D

- 新場景在 `assets/armors/thunder/thunder.scn`，由 `armor_visuals.gd` 的 `REWORKED_SCENES[6]` 載入，角色與商店／裝備預覽使用同一組部位。
- 沿用原 Thunder 網格、UV 和骨架，改造額脊與臉部硬甲，保留原比例與動作。金橙 visor 由原貼圖區域的 shader mask 調整；不是用概念圖做平面看板。
- 首版仍看得出原低多邊形輪廓，連續曲面、耳部凹凸與細接縫較概念簡化，並非精準完整重建。
- 裝備 ID、玩法數值、存檔格式、其他套裝和原素材不變。四張 set06 部位縮圖已依新模型渲染；原 `armor_06.scn` 留作 before 基準。
- 重建、編譯、測試、截圖和縮圖命令見 [Thunder 模型 README](../../../assets/armors/thunder/README.md)；實際三角形數與來源雜湊以 [build_report.json](../../../assets/armors/thunder/build_report.json) 為準。
- `runtime/` 的五張圖複製自 `test_output/thunder_runtime/`，使用真正 `WarfarePlayer` 裝備載入流程、固定 1000 × 1200 視口、OpenGL Compatibility。原版與概念圖光照不同，不作精準像素比較。

## 概念階段已交付（歷史）

- A：mk2 的實際網格灰模作造型參考，套用目前 mk1 深鋼藍、暗色內襯、金黃標記、琥珀面罩。
- B：以目前 mk1 實際 Godot 截圖為目標，保留高頭冠、圓耳、面罩、胸腰特徵，增加 mk2 式分層肩甲、明確切面和厚邊。
- B 新頭盔：以使用者上傳的方形頭盔近照為參考，把高薄頭冠改成寬低中央額脊、下壓眉甲、V 形金橙面罩與短下顎護塊；A 沒改。
- 三張候選使用內建 imagegen，各一個請求；逐圖 prompt、輸入路徑和生成來源保存於 prompts/ 與 manifest.json。新頭盔的上傳參考無可用本地路徑，以對話圖片機制傳入，manifest 有描述，未捏造附件檔案。
- 當時只交付概念候選，不是已改造完成的模型或可直接貼回的 UV；概念階段沒有修改 runtime、商店、舊素材、匯入設定或玩家存檔。後續已依核准方向新增首版 3D，詳見上節。

## 審查備註

- A 的眼眉、肩甲與胸板分界有局部生成重繪；不可稱為原網格精準重貼皮。
- B 的肩甲與胸膝切面確實改變，仍可辨認 mk1；前臂和靴面細紋稍多，甲片厚度與活動空間要在建模再驗。
- B 新頭盔概念的主體盔甲、姿勢與配色整體保留；頸肩接縫小金黃格有局部生成差異，並非頸部以下逐像素不變。沒有新增生成背面；runtime.html 的背面來自實際 3D 網格。
- 來源截圖的鏡頭、光源、姿勢不同，不作精準顏色／渲染效能比較。
- 此處 mk1 指 runtime armor_06，不是 redesigned_armors 裡未接入的藍青貼圖，也不是以前那批 AI 概念。
- 原作素材權利未清理，不把 AI 改作當成商用授權。

## mk2 來源限制

來源 commit：252aab1b38d0298994053ffaaec39677ef1ae4ee，README 稱 Star Warfare 2 Avatar06 / Storm / Thunder。

同名 OBJ 和 PNG 直接貼合、U 翻向、V 翻向、abs(U) 鏡像等診斷皆未得到正確對位。OBJ 有 UV 和有效索引，負 U 不足以判定錯誤；來源未附完整材質設定，尚無法確定根因。只採灰模作生成參考；diagnostics/ 保留失敗證據，未放進畫廊當原版外觀。

## 重跑來源截圖與 HTML 檢查

```sh
/opt/homebrew/bin/godot --path . --rendering-method gl_compatibility docs/art/thunder_mk_comparison_v1/render_mk1.tscn
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python docs/art/thunder_mk_comparison_v1/render_reference.py
node docs/art/thunder_mk_comparison_v1/check_preview.mjs
```

mk1 使用固定 1000×1200 SubViewport、Godot OpenGL Compatibility，現在固定載入原 `assets/equipment_refined/armors/armor_06.scn` 的四件 mesh、skin、transform 和 metadata，不呼叫會跟隨新 set06 接線的 `ensure_parts`，因此仍可重現 before。避免 fixture 中無關武器 class 的載入失敗；精修 PNG 在記憶體中載入，不手動更改引擎 metadata。

mk2 使用 1200×1400 Blender Cycles，四個 OBJ 的共同座標，灰色材質。render_reference.py 預設只產生灰模；--probe 與 --textured-diagnostic 僅作診斷。

Chrome 檢查使用新建的隔離臨時 profile，不存取日常瀏覽資料；完成後只關閉自己啟動的程序。臨時 profile 保留於命令輸出的路徑。

## 實際驗證結果

| 階段／檢查 | 結果 | 範圍與限制 |
| --- | --- | --- |
| 概念階段 Chrome | PASS（歷史） | 桌面 1440×1250、手機 390×844；七張圖、五個切換、prompt、灰階、三種放大與重設；無 JavaScript 錯誤／手機溢出。 |
| 概念圖與來源紀錄 | PASS（歷史） | 三張生成圖目視、manifest、prompt、HTML 連結、PNG 標頭與 git diff 檢查。 |
| 首版 compiler 輸入驗證 | PASS | 九種正常／錯誤輸入；錯誤資料不覆寫遊戲場景。 |
| 首版 Thunder 專用測試 | PASS | 實際角色裝備、骨架綁定、混裝、動畫資料和 Store／Customize 預覽。 |
| 既有裝備回歸 | PASS | 其他 27 套裝備回歸、`armor_system` 與 `menu_equipment` 測試。 |
| 首版遊戲截圖 | PASS（截取） | 十二張固定視口圖片；取樣姿勢不等於所有動作均無穿模，也不是使用者美術驗收。 |
| 首版商店縮圖 | PASS | 只渲染 Thunder 四個部位。 |
| 概念／runtime HTML 最新回歸 | PASS | 桌面寬 1440、手機寬 390；概念頁互動回歸、runtime 七張圖片（含五張實際模型圖）和連結載入，無橫向溢出。桌面實際效果已目視。 |
| 首版使用者視覺驗收 | 待確認 | runtime.html 提供原版、核准概念和真正遊戲畫面，仍可再調整。 |

HTML 最新回歸由 `check_preview.mjs` 執行；原版 before 截圖腳本改為固定舊場景後已通過 GDScript parse check，本次未重拍歷史 before 圖片。瀏覽器與邏輯檢查通過，不等於概念已一比一建模或所有動畫皆無穿模。

## 工作包交接

Objective: 保留兩種 Thunder 概念歷史，將使用者核准的 B 新頭盔套入目前遊戲，提供真實前後對照。Inputs: 指定 commit 的 mk2 灰模、原 mk1 網格／貼圖、使用者頭盔近照與核准 B 概念。Outputs: 原候選圖、獨立首版 3D 場景、實際遊戲截圖、概念與 runtime 兩個 HTML、prompt、manifest。Acceptance: 原骨架與部位相容、角色／商店接線、截圖與使用者美術驗收。Handoff: 先讀 runtime 限制與逐圖 review_notes；目前是原網格改造初版，下一輪是否完整重建曲面／耳部細節由 Harvey 看效果後決定，未擴及其他套裝。
