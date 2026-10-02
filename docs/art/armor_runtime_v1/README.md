# 裝甲遊戲素材：回到原版建立 base prompt

Cygni 的 v4 灰模已被使用者指出比例與外型不對；目前改為研究原版模型、貼圖及設定，建立共通 prompt 後再做新裝甲。

## 目前方向

- [原版研究與 base prompt](style_base_v1/README.md)：九套原始 mesh 量測、原版 rest-pose 實機視圖、材質與貼圖來源。
- [base_prompt.txt](style_base_v1/base_prompt.txt)：大頭短身、每套獨有剪影、少量大甲片、手繪 diffuse 明暗與細節密度。
- [Cygni 新風格參考 v2](style_base_v1/cygni_style_trial_v2.png)：已用 base prompt 生成，再校正長窄主殼及短頸；這是 bitmap 施工參考，尚未通過使用者驗收，也不是已套用遊戲的 3D 模型。
- 原 Cygni 主殼寬 0.4606，v4 主殼寬 0.6000；含側翼的總寬卻同為 0.6832。這是外框對齊仍然看起來怪的實際原因之一，後續須分開檢查主殼與附件。

## 歷史嘗試

- v3 的圓殼、眉甲、面罩、護頰各自向前堆疊，側面像漂浮貼片。使用者於 2026-10-01 指出 **3D 模型結構壞掉**；v3 已停用，舊 `--cygni-new-helmet` 不再載入它。
- v4 用同一個連續網格建構冠甲、眉線、護頰、下巴與 T 字鏡片。鏡片和白色外殼共用邊緣，沒有往前貼上的整片面罩。
- 大頭短身、骨架、skin binds 與裝備 ID 沿用遊戲尺度。身體恢復原 Cygni 幾何及既有精修貼圖，不使用前一版增加的薄層。
- v4 頭盔刻意使用灰模；UV 只是技術用暫存座標，**尚未製作生產用 UV／貼圖**。
- 前側深度、背面與側翼厚度仍有推定；灰模外形需要人工確認，未宣稱「100% 對齊」。

## 版本狀態

| 版本 | 結果 | 用途 |
| --- | --- | --- |
| v1 平塗批次 | 使用者拒絕，停用 | 歷史失敗樣本 |
| v2 舊 UV 貼圖編輯／薄層 | 沒有真正重建草稿，已被新方向取代 | 歷史材質實驗 |
| v3 新圖集／獨立甲片頭盔 | 使用者拒絕，停用 | 錯誤結構的比對證據 |
| v4 連續外殼灰模 | 使用者拒絕比例與外型，停止優化 | 幾何失敗的比對證據 |
| 原版 base prompt／Cygni v2 三視圖 | 風格參考待人工驗收 | 新一輪建模的施工參考 |

## v4 檔案與驗證

- 建模程式：`tools/armor_concept_runtime/repair_cygni_helmet.py`。
- Native master：`armor_11/repair_shell_v4/master.blend`（頭盔與原骨架）。
- Godot 試看場景：`assets/armors/concept_runtime/painted/repaired_cygni_helmet.scn`。
- 模型報告：`armor_11/repair_shell_v4/asset-manifest.json`、`validate.json`。
- 實機圖片：`test_output/armor_concept_runtime/repair_armor_11_*`。動畫／混搭檢查另見 `repair_runtime_test.log`。

Blender topology／UV／weights 檢查沒有 failures 或 warnings；主外殼沒有開放邊緣或非流形邊緣。側翼與內部領口是個別閉合部件，根部埋入外殼。原骨架、動畫、混搭、商店／配裝載入的 Godot 測試 PASS，實際存檔未改動。這些檢查不代表造型已獲接受。

## 套用範圍

最終目標是 Viper 到 Cygni，Phoenix 保留原版，Thunder 沿用既有採用模型。Andromedae 之後所有套裝及 Call of Mini 套裝保留現有素材。

2026-10-02 起，Cygni 的預設外觀已改用 [cygni_runtime_v2](../cygni_runtime_v2/README.md)，本目錄的灰模／試貼圖仍為歷史試作。`--cygni-helmet-repair` 僅保留重現被拒絕的 v4 灰模，不能作為正式採用旗標；其他套裝不替換。全批次尚未完成，新的 prompt 圖沒有直接掛進遊戲 loader。

## 重現 v4

```bash
godot --headless --path . --script res://tools/armor_facets/export.gd
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/armor_concept_runtime/repair_cygni_helmet.py
godot --headless --path . --script res://tools/armor_concept_runtime/compile_painted.gd -- --repaired-head
godot --headless --path . res://tests/concept_armor_test.tscn -- --cygni-helmet-repair
godot --path . --rendering-method gl_compatibility res://tools/armor_concept_runtime/preview.tscn -- --capture --ids=11 --cygni-helmet-repair
```

去掉 `--capture` 可操作比對窗口，切換正面、側面、背面、跑步與換彈。
