# Titan 最新版檢查與輪廓試作 · 2026-10-06

**目前 v4 素材與動作檢查通過；本次另做收小耳甲、收回下護框的獨立試作。** [前後對照](index.html)使用 macOS Godot 4.7.2／Compatibility／Apple M4 的同相機擷取。正式 `assets/armors/titan_v1/titan.scn`、GLB、五圖、模型目標、master 與既有 Windows 報告都保留。

## 判斷與實作

**目前主要落差在耳側的大三角片、下框尖端與柔霧玻璃反光。** 試作只調整前兩者的現有頂點；玻璃與冠頂貼圖沿用 v4。草稿的小圓扣、較清楚的玻璃主反光仍是後續可改善處，不把本次稱為完全貼合草稿。

| 項目 | v4 | 試作 |
| --- | ---: | ---: |
| 頭盔三角形／UV 座標／連續區域 | 164／334／3 | 164／334／3 |
| 原骨架 | 28 bones | 28 bones |
| 最大位移／原最短邊 | 19.2932% | 19.4967% |
| 翻面／退化面 | 0／0 | 0／0 |
| 原生貼圖變更 | — | 0 |

移動是由單張斜視概念推測的小幅調整；不是正交圖量測或草稿相似率。`adjustments.json` 保留原來源代表頂點、Godot rest-space 位移及輸入 SHA。鏡像與共用位置一起移動，新切分中點跟隨父邊，UV 與權重維持 v4。

## 工程結果

**最新正式素材與獨立試作的檢查分開保存。** Mac 新結果在此目錄；既有 Windows 15／9 姿勢報告未覆寫。

| 檢查 | 結果 | 證據 |
| --- | --- | --- |
| 最新正式來源／GLB／五圖 | PASS | `current_asset_test.json`；包含固定 glTF 節點與 raw binary buffer |
| 正式遊戲動作 | PASS | `current_runtime_test.json`：15 姿勢、混搭、配裝、真實存檔不變 |
| 正式 GLB 回讀 | PASS | `current_roundtrip_test.json`：9 姿勢、頭圖 RGB 取樣、真實存檔不變 |
| 換行判定回歸 | PASS | `tests/test_titan_provenance_eol.py`：LF／CRLF、未登記 hash、內容改動、active-file 拒絕共 4 個案例 |
| 試作 SCN | PASS | `candidate_scene_test.json`：原 UV／權重／非頭部 arrays／skin／貼圖、逐頂點目標 |
| 試作 master | PASS | `candidate_master_test.json`：已儲存模型、UV、原骨架名稱、5 張內嵌 PNG |
| 試作引擎畫面 | 完成擷取與選定視圖檢視 | `../draft_alignment_20261006_poses/capture.json`：64 圖，含待機／跑動／換彈與場景，存檔不變 |
| 試作 GLB／正面覆蓋重測 | NOT RUN | 本次是獨立輪廓試作；正式 v4 原檢查保留 |
| 使用者美術接受／手機效能 | NOT RUN | 待人工評價；本次未量測手機 |
| 對照頁瀏覽器操作與排版 | NOT RUN | 瀏覽器安全政策拒絕本機 `file://` 頁面；使用靜態連結與 JavaScript 語法檢查，不能代替瀏覽器驗收 |

`candidate.scn` 可由 Godot 載入，`candidate_master.blend` 可在 Blender 繼續編輯；沒有把它登記為正式裝備。動作圖由擷取工具把同一試作 mesh 套到原角色骨架。遊戲場景擷取時停止戰鬥，不能當作效能量測。

## 修正的跨平台問題

**原檢查把 LF／CRLF 換行差異誤認為原模型內容變更。** 凍結的原 glTF SHA 是 Windows CRLF；Mac checkout 的 LF 可以精確重建為同一既定 SHA。修正只對這個已經由固定快照核對的 glTF 啟用既有歷史文字規則，仍檢查完整文字、原節點、buffer 長度與原二進位 SHA；沒有改門檻或重寫來源紀錄。

## 重現試作

**此流程輸出到本 review 目錄，不覆蓋正式 SCN 或 GLB。** 使用專案已安裝的工具：

```sh
python3 tests/test_titan_provenance_eol.py
python3 tools/armor_runtime_v1/review_titan_alignment.py
godot --headless --path . --script res://tools/armor_runtime_v1/update_titan_helmet.gd -- --preview-target=res://docs/art/titan_runtime_v1/review/draft_alignment_20261006/candidate_target.json --preview-output=res://docs/art/titan_runtime_v1/review/draft_alignment_20261006/candidate.scn
/Applications/Blender.app/Contents/MacOS/Blender -b docs/art/titan_runtime_v1/build/titan_master.blend --python-exit-code 1 --python tools/armor_runtime_v1/review_titan_alignment.py -- --master
/Applications/Blender.app/Contents/MacOS/Blender -b docs/art/titan_runtime_v1/review/draft_alignment_20261006/candidate_master.blend --python-exit-code 1 --python docs/art/titan_runtime_v1/review/draft_alignment_20261006/check_master.py
godot --headless --path . --script res://tests/titan_alignment_review_test.gd
godot --path . --rendering-method gl_compatibility res://tools/armor_runtime_v1/capture.tscn -- --armor=titan --preview-revision=draft_alignment_20261006_poses --candidate-scene=res://docs/art/titan_runtime_v1/review/draft_alignment_20261006/candidate.scn --candidate-target=res://docs/art/titan_runtime_v1/review/draft_alignment_20261006/candidate_target.json
```
