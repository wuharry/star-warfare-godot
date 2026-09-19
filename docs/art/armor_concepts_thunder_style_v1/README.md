# 全裝甲新一輪草稿：Thunder 風格

[開啟 HTML 圖集與原版對照](index.html)。共 28 套新草稿，包含 Viper、Fortune 與追加裝甲；Thunder 提供風格參考。

每套依自己的原配色、頭盔和胸肩特徵生成，統一為 Thunder 理想圖的厚甲、稜角、短壯比例與細緻手繪表面。風格來源是 [使用者選定的 Thunder 全身圖](references/thunder_style.png)，不是較早的三格概念圖。

| 內容 | 位置 |
| --- | --- |
| 28 張新概念草稿 | `images/armor_NN.png` |
| 原裝甲全身、頭盔、背面 | `references/NN_original.png`、`NN_helmet.png`、`NN_rear.png` |
| 完整實際提示詞 | `prompts/` |
| 逐套來源、配色、保留特色、檢視記錄與 SHA256 | `entries/`、`manifest.json` |
| 檔案核對結果 | `verification.json` |
| HTML 互動與圖片載入檢查 | `browser_report.json` |

使用內建 `image_gen` 逐套生成並檢視。圖片直接複製原始生成結果，沒有裁切、放大、壓縮或程式後製。實際原生尺寸記錄於各套 entry，頁面僅用 CSS 等比例顯示。Andromedae 初版誤加的黃色點綴已透過 imagegen 局部修正，修正提示詞亦保留。

參考裝甲畫面取自既有同模型、同燈光的擷取資料；Viper 與 Fortune 是已接受的高清版本，其他套使用本輪高清重繪前的配色畫面。貼圖畫面上的光影不作新的裝甲色塊。所有新草稿已檢視原配色、辨識特徵、完整頭腳與整體風格；使用者美術選定仍待確認。

這一輪只交付單張正面三分之四視角概念圖，遊戲模型、UV、貼圖、數據與動畫未變更。頁面的背面圖是原裝甲參考，新版背面與建模細節尚未定稿。

重新組合離線頁面：

```powershell
python docs/art/armor_concepts_thunder_style_v1/build_gallery.py
```

頁面不依賴網路、伺服器或生成快取，直接開啟 `index.html` 即可使用。`build_gallery.py` 會核對 28 張圖片、SHA、尺寸及提示詞是否完整，再輸出 manifest 與 HTML；若原生成快取仍在，也核對檔案是否完全一致。
