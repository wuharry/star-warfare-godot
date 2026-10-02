# Cygni：一套可入遊戲的示範

**這版已用 Blender 局部改造原 Cygni 頭盔，保留原版的 238 tris 與 7 個 UV 連續區域；新貼圖、換裝場景與 GLB 可入遊戲，美術效果仍待使用者評價。** 先看 [原版／新版 3D 比較頁](index.html)，再決定是否修改這套，不擴到其他裝甲。交付底線是「並排像同一位美術製作的不同裝甲」；工程 PASS 不能代替這項美術判斷。

![原版／碎片化上一版／這次局部改造](review/head_before_after.png)

![相同相機、姿勢與高度的原版／新版比較](review/comparison_front.png)

這張比較使用原貼圖本色，取消原 glTF 額外的粉紅頭部染色；比較頁另保留原匯入色調。素材與遊戲預設均未因這個比較顯示而改寫。

![原版 Phoenix／新版 Cygni／原版 Andromedae](review/family_comparison.png)

## 實際交付

**頭盔改用原 cage 局部重塑，原 UV 座標與鏡像共用不變；其餘三件沿用上一個示範 checkpoint。** 新版需非常接近原版，僅接受局部改動；金 T、短下巴與內收頰甲融入原頭殼，不能把整個頭盔換成另一種製作風格。胸前新增 V 甲片仍為上輪示範，其他三件的 TargetUV 尚未改回原版，不假稱本輪已完成全部位的連續 UV 重製。

| 檔案 | 類型與用途 |
| --- | --- |
| [CH_Cygni_master.blend](CH_Cygni_master.blend) | 可編輯幾何、UV、原關節與參考；貼圖打包在母檔內 |
| [cygni.glb](../../../assets/armors/cygni_v2/cygni.glb) | 四件 mesh、骨架、內嵌貼圖；已做 Godot 重新匯入與動作比較 |
| [cygni.scn](../../../assets/armors/cygni_v2/cygni.scn) | 接到既有玩家與商店 loader 的四件 PackedScene |
| [head_diffuse.png](../../../assets/armors/cygni_v2/head_diffuse.png)、body／hand／foot | 四張 runtime diffuse；肩部包含在 body atlas |
| [generation_records/](generation_records/) | 完整實際 prompt、參考路徑／hash、生成原圖、處理紀錄 |
| [asset-manifest.json](asset-manifest.json) | 輸出 hash、狀態、原骨架及 GLB 綁定資訊 |

| 項目 | 這版 |
| --- | --- |
| 裝甲 | Cygni／ID 11／C-12，四件獨立換裝 |
| 三角形 | 1,110，全套；原型預算為 3,000 |
| 原關節 | 保留原骨架的 28 個名稱、rest 與槍／背包掛點 |
| GLB 輔助 joint | 29 個 identity child，用於保留重複 bind；不改原關節 |
| 生成輸出 | 四張原圖各為 1,254 × 1,254，原圖保留 |
| Runtime diffuse | 四張各為 512 × 512；Blender 僅縮放匯出，沒有將透視概念投影到 atlas |
| 材質 | Godot `SHADING_MODE_UNSHADED`；GLB `KHR_materials_unlit` |
| 預覽狀態 | `--cygni-v2` 比較入口，尚未採用為預設正式外形 |

## 已跑過的驗證

**遊戲換裝及 GLB 動作檢查通過；貼圖統計與美術選定分別記錄。** 所有視角來自同一套模型，動作使用實際玩家和既有 reload fixture。

| 檢查 | 狀態 | 證據／限制 |
| --- | --- | --- |
| 原 UV 頂點對應 | PASS | [source_uv_validation.json](review/source_uv_validation.json)；逐面檢查 1,006 個原 cage faces，避免反轉面的朝向時錯接 UV |
| 四件換裝、混搭、重複換裝 | PASS | [runtime_test.json](review/runtime_test.json)；沒有重複節點 |
| 商店及配裝共用 loader | PASS | 四件均載入新版本 |
| 原關節、原手腳 deformation、掛點 | PASS | 待機／跑動／換彈共 15 個取樣；原 cage 動作 bounds 與原件比對 |
| 真實存檔保護 | PASS | 測試與 capture 使用獨立暫存 profile，原檔 hash 未變 |
| GLB 重新匯入 | PASS | [roundtrip_test.json](review/roundtrip_test.json)；9 個動作取樣，包含換彈 IK 的最終 global pose |
| 正／側／背、灰模、持槍、跑動、換彈、兩張實際地圖 | 已擷取並檢視 | [capture.json](review/engine/capture.json)，共 54 張；檢視角度為有限取樣，不代表所有動作絕無穿插 |
| Capture 尺寸 | PASS | 審查為 640 × 720；實際地圖為 1,280 × 720；用固定 SubViewport，未將螢幕視窗尺寸冒充圖片尺寸 |
| 不透明、均值、p98、色相集中度 | PASS（數值） | 四張實際 runtime PNG，排除 GLB importer 自動抽出的副本 |
| 亮像素占比 | FAIL（原版 atlas 參考帶） | 27.5%，高於原五張 atlas 統計上緣 18.1%；白甲亮度仍待評價 |
| 互動頁的瀏覽器目視驗收 | NOT RUN | Browser 工具網址政策禁止 `file://`；未繞過限制。JS 語法及檔案引用已檢查，Godot 畫面另外檢視 |
| 使用者美術選定 | 本輪待評價 | 上一版碎片化頭盔已被否決；本輪採原模型局部改造，工程 PASS 不能代替同作者風格門檻 |

## 生成來源與推定

**本輪的下巴、頰部、頭冠和短翼調整為概念到遊戲比例的局部推定；主要頭殼與 UV 來自原件。** 生成的遊戲比例三視圖是輔助參考，沒有被標成使用者批准的新外形。

- 規則：[ARMOR_TEXTURE_STYLE_SPEC.md](../ARMOR_TEXTURE_STYLE_SPEC.md) 與 [legacy_armor_base_v2](../legacy_armor_base_v2/README.md)。
- 設計：[c12_concept.png](ref/c12_concept.png)；原圖決定角色比例的部分不沿用成人長腿。
- 原參考：[sources.json](ref/sources.json)、原模型正側背、原 diffuse 與原骨架。
- 真正生成：`image_gen.imagegen`。每次使用該模型的 UV placement guide；沒有用程式畫成品 diffuse。
- 最終選圖由 [selection.json](generation_records/selection.json) 指定：頭部 r4、身體／手腳 r2；生成被拒絕的版本仍保留與標示原因。原 r1 的 guide 已原樣封存到 `generation_records/inputs_r1/`，輸入 hash 不隨修正 guide 而失去對應。
- 上一版的六個側接片頂點上收屬已否決 checkpoint；完整母檔、原場景、GLB、UV guide 和比較圖存於 `generation_records/continuous_head/previous_checkpoint/`。本輪以原 cage 局部改造取代，不再執行 `taper_cheek.py`。
- 所有生成原圖均保留。Body guide 將原 diffuse 烘焙到新模型 UV；新甲片在模型內先有幾何與材質區域，再生成 painted diffuse。
- 本示範保留原肩甲、手套與靴子的主要輪廓；肩翼尖端收短，胸前新增 V 甲片，沒有宣稱所有局部都已一比一重建概念。
- 身體 atlas 合併了原肩圖，手腳沿用上輪較緊密版面；本輪頭部則恢復原始布局。空白比例會影響整張 atlas 統計；亮像素 FAIL 如實保留，未抬高門檻或調數據讓它通過。

## 原版頭盔與本次偏差

**本輪已回到原版的連續主頭殼與大片共用 UV；上一版的拆分方式作為失敗記錄保留。** 實測見 [original_head_method.json](review/original_head_method.json)；原始貼圖與原模型仍為製作依據，不能以本次失敗頭盔再生下一版當作風格基底。

| 項目 | 原版 Cygni | 已否決上一版 | 這次局部改造 |
| --- | ---: | ---: | ---: |
| 全頭盔 tris | 238 | 596 | 238 |
| 貼圖上連續 UV 區域（左右重疊合併） | 7 | 141 | 7 |

原主頭殼是 166 tris；側圓附件及薄翼另外做幾何，面罩與大量縫隙、亮邊由手繪 diffuse 表現。鏡像三角形的配對中，大部分共用相同 UV。這些是成品檔案證據，不能據此聲稱知道原作者當年的實際作業順序。本輪已按此方法局部改造。逐面檢查見 [method_validation.json](review/continuous_head/method_validation.json)：238 個來源 faces、TargetUV 與 OriginalUV 完全相同；最大單點改動約 0.136 game units，主要縮短舊下巴。這不是風格相似率，仍需看並排效果。

## 綁定與母檔的限制

**原素材的 inverse bind 並不全等於目前 bone rest 的反矩陣，靴子還有重複同名 bind；本輪頭部也保留原 legacy bind。** 把它們換成一般 inverse-rest 會令手腳在動作中偏移；這版保留原 cage 的原 bind，新增胸片另加 bind。

- 遊戲場景以原骨架播放既有動作；已驗證的是 Godot 的最終姿勢。Blender 母檔用於編輯形體與 UV，未另外在 Blender 驗收全部既有動作。
- 最終 GLB 從 Godot 的實際 Skin 匯出。glTF 的 `skin.joints` 要求唯一索引，因此重複 bind 改指向跟隨同一原 joint 的 identity child；inverse-bind、mesh、貼圖及原 joint 未改寫。規則來源：[Khronos skin schema](https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/skin.schema.json)，記錄見 [glb_bind_aliases.json](build/glb_bind_aliases.json)。
- 不直接以 Blender 普通 GLB 匯出覆蓋最終檔案；它不能完整表達這批舊資產的重複 bind 例外。
- GLB 內含四張貼圖。Godot 匯入時另外抽出的 `cygni_*_diffuse.png` 是匯入副本，沒有額外執行四次生成。

## 如何看遊戲效果

**加入 `--cygni-v2` 即可由既有玩家及商店載入本示範。** 使用比較頁先確認外形；遊戲中需裝備 Cygni，這個 flag 不改寫存檔中的裝備選擇。

```bash
godot --path . -- --cygni-v2
```

## 重建與驗證

**生成原圖已保存，重建不需要再付費生成。** 以下從原骨架檢查到遊戲資料匯出，最後才製作對照頁；新生成原圖與 prompt 應另存版本，不能覆蓋這次的來源紀錄。

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/cygni_runtime_v2/inspect_source.py
godot --headless --path . --script tools/cygni_runtime_v2/inspect_rig.gd
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/cygni_runtime_v2/build.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/cygni_runtime_v2/head_regions.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/cygni_runtime_v2/validate_head_method.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/cygni_runtime_v2/export.py
godot --headless --path . --script tools/cygni_runtime_v2/compile.gd
python3 tools/cygni_runtime_v2/glb_unique_joints.py
godot --headless --editor --path . --import
godot --headless --path . tests/cygni_v2_test.tscn -- --cygni-v2
godot --headless --path . tests/cygni_v2_roundtrip.tscn -- --cygni-v2
godot --path . --disable-render-loop tools/cygni_runtime_v2/capture.tscn -- --cygni-v2
godot --headless --path . --script tools/cygni_runtime_v2/viewer_data.gd
python3 tools/cygni_runtime_v2/assemble_review.py
python3 tools/cygni_runtime_v2/make_viewer.py
python3 tools/armor_texture_check.py assets/armors/cygni_v2/head_diffuse.png assets/armors/cygni_v2/body_diffuse.png assets/armors/cygni_v2/hand_diffuse.png assets/armors/cygni_v2/foot_diffuse.png
```

最後一項目前回報亮像素 `FAIL`，不可將非零退出寫成 PASS。`python3 .harness/verify.py` 另為規則投遞檢查，不能代替以上應用與視覺檢查。


## 回家後繼續的工作

**接續時先評價本輪 Cygni，再把同樣方法用到其他已授權裝甲；不要把這版自動視為正式採用。**

- 工作入口：[完整比較頁](index.html)，不是 `tools/cygni_runtime_v2/viewer.template.html`；模板沒有嵌入模型資料。
- 規則入口：[ARMOR_TEXTURE_STYLE_SPEC.md](../ARMOR_TEXTURE_STYLE_SPEC.md)、[base_prompt.txt](../legacy_armor_base_v2/base_prompt.txt)。已加入「新版非常接近各自原版、只做局部改動」與 Blender 建模／大片鏡像 UV 方法。
- 編輯母檔：`CH_Cygni_master.blend`；頭部現在是改造原拓撲，沒有浮動頰甲。`build.py::helmet` 可重現修改，原始資產未改。
- 其他裝甲：先讀各自的原模型與 atlas，再改指定局部。原版、上一版、新版用同相機比較；不以增加分片或提高解析度當成進步。
- 範圍維持前段至 Cygni；Phoenix、Cygni 後面套裝保留原版，Thunder 保留已選版本。本輪沒有把其他套裝換進遊戲。
- 待辦：使用者美術評價、整套亮度／材料一致性；若繼續改胸肩與手腳 UV，要用它們自己的原件並另生成相容貼圖，不能沿用碎片版 UV。
- 生成器未嚴格逐像素服從技術區域圖；已在正／側／背確認金色玻璃位於臉部、側頰為白甲，但不宣稱遮罩位置完全一致。來源原圖及偏差保留供下輪修改。
- 匯入注意：研究 `.blend` 必須放在 `.gdignore` 排除的 authoring 目錄。本輪一度因臨時 `.blend` 匯入提示阻斷 Godot 更新，載入了舊 GLB cache；排除後重新匯入，9 個動作取樣比較才通過。
