# 裝甲高清細節化：Viper／Fortune 基準

依 `af01d8a9a6c76afff0b2e461a0d1b1992ffa40b1` 的 Fortune 重繪方式，補強其餘 26 套裝甲的 119 張貼圖。保留各套原有輪廓、配色、面罩、UV 配置與辨識特徵，重新刻畫模糊的接縫、細邊高光、金屬表面與布料。Viper、Fortune 保留既有完成版本；Thunder 維持獨立新版，未納入此次修改。

`ea55de4c9e8441e2256176db9804d255d87f6ea5` 已完成的無損匯入、停用 mipmap 與自動 3D 壓縮設定沿用。這次改的是美術內容；貼圖仍採原生 1254 × 1254，沒有用程式放大或銳化濾鏡替代重繪。

[開啟逐套 HTML 對照](armor_hd_refinement_v1/index.html)。可選各套裝甲、全身／近景、正／側／背面，點圖片放大；Viper 與 Fortune 提供相同燈光下的品質參考。修改前欄使用本次開始前備份的貼圖，與新版共用相同模型、材質設定及鏡位。畫面直接由 Godot 實際玩家換裝後擷取。

## 範圍對應

| 部分 | 處理 |
| --- | --- |
| Viper、Fortune | 保留已完成版本，作為手繪材質與細節品質參考 |
| Tank、Hydra、Strike、Titan、Atom、Pegasus、Draco、Phoenix | 每套五張貼圖分別重繪 |
| Cygni、Andromedae、Perseus、Chaos、DEC.24、Knight、R.O.M.E、Black Hole | 每套五張貼圖分別重繪 |
| X-Field、Wrath | 每套五張貼圖，保留各自特殊發光區與複雜板件配置 |
| Assault Armor | 八張材質圖；其中兩張來源與 Viper 完全相同，直接使用已完成的對應 Viper 貼圖 |
| Combat Suit、Drillmaster、Heavy Battlesuit、Mark-6 117R、Recon Suit、Sanguine Chaos、Training Suit | 每套三張；完全相同的原始內襯／共用頭盔依來源 SHA 共用同一份已檢視成果 |
| Thunder、武器、其他遊戲數據 | 未修改 |

模型沿用上一輪已完成的微小銳邊修整，未再增加倒角或變更骨骼、UV、碰撞與動畫。新版貼圖直接替換既有執行時路徑，遊戲與商店共用；商品部位縮圖另外重新渲染。

## 製作記錄與驗證

使用內建 `image_gen`，以每張原 UV 圖為編輯目標，對應 Viper 部位僅作畫工參考。生成結果經查看後直接複製，未修改像素。小區塊誤色、非物理鏡像接縫與背景問題以工具局部修正；Assault／Recon 的額頭中央亮白接縫已在實際模型上複查。

完整提示詞、來源、參考、生成路徑、輸出雜湊與逐張檢視記錄在 [製作工具資料夾](../../tools/armor_hd_refinement/)。`provenance_legacy_a.json`、`provenance_legacy_b.json`、`provenance_extended.json`、`provenance_com.json` 合計對應 119 張目標圖。`approved` 是製作端圖集檢視，使用者美術驗收仍獨立；實際遊戲畫面檢視另記於 HTML 附件。

既有 `equipment_refinement_test` 驗證裝甲材質映射、骨骼權重、待機／跑步／換彈形變及混搭，並核對實際載入貼圖的尺寸、無損／無 mipmap 設定與匯入快取。HTML 發布會核對擷取時的場景、貼圖與程式雜湊，拒絕過期圖片；擷取使用隔離測試存檔並比對真實存檔雜湊。

此輪沒有進行手機實機效能量測。部分舊 OBJ 的 UID 路徑回退及既有測試退出時的資源清理警告與裝甲檢查結果分開記錄。

## 重建預覽

```powershell
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility res://tools/armor_hd_refinement/capture.tscn
python tools/armor_hd_refinement/build_preview.py
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --script tools/render_armor_thumbnails.gd -- --exclude-set-ids=0,1,6
```

修改前貼圖位於本機忽略追蹤的 `test_output/armor_hd_refinement/baseline/textures`。缺少備份時，可從本次修改前的 `9a70bc586d86fc4dc4118038bedcd346fb22c59c` 取回相同檔名至該目錄；已發布的 HTML 與圖片可直接離線開啟，不依賴生成快取或該備份。
