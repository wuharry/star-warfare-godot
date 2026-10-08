# Atom / Pegasus 原版素材整合

這兩款共用既有五貼圖管線，首版只換材質。來源是 `assets/models/player/animated/player.gltf` 的 Atom ID 7（節點 58–61）與 Pegasus ID 8（節點 62–65）；不能使用 SW2、已優化款或成人比例概念模型代替原版基準。`preserve_all_geometry: true` 會額外要求所有實際 SCN mesh arrays 與原版完全相同，包含頭部位置、法線、切線、UV、索引及骨架權重。20% 是後續總預算，首版實際幾何與 UV 目標皆為 0。

先用 Godot 匯出實際原版 skin-space 數據，再凍結來源，順序不可交換。以下將 `$armorSlug` 設為 `atom` 或 `pegasus`；工具路徑使用本 repo 已有版本，不安裝新依賴。

```powershell
$armorSlug = 'atom'
$armorEngine = '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$armorBlender = 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe'
& $armorEngine --headless --path . --script res://tools/armor_runtime_v1/inspect_sources.gd -- "--armor=$armorSlug"
python tools/armor_runtime_v1/prepare_sources.py "--armor=$armorSlug"
& $armorEngine --headless --path . --script res://tools/armor_runtime_v1/render_guides.gd -- "--armor=$armorSlug"
```

`prepare_sources.py` 拒絕覆寫既有 `revisions/original_source_v1`。該目錄含不可變 source、原 runtime_config、inspect 腳本、五張原 atlas 和五張精確 UV SVG，共 13 個原檔；補充索引另外記錄 glTF 節點及 buffer SHA。`guides/head_semantics` 是以原版三維座標分區的技術輔助，標為 `TECHNICAL_POSITION_BINS_REQUIRES_3D_VIEW_REVIEW`，必須在原模型核對面甲、頭頂及後腦後才可據此繪製。

五張生成編輯目標固定使用 `revisions/original_source_v1/atlases/head.png`、`body.png`、`shoulder.png`、`hand.png`、`foot.png`。每張同時提供對應 `guides/*_uv.png`、所選 C-08/C-09 概念及 Viper/Fortune 統一風格參照；頭盔若有較晚的指定稿，以頭盔稿為面甲與冠頂權威。Pegasus 頭殼依已確認更正與白灰身甲同色。Atom 的原 body surface 順序是 `shoulder, body`，不可套用其他裝甲的 `body, shoulder` 假設。

生成只使用內建 image_gen；保存完整實送 prompt 和原生 PNG。禁止重排 atlas、旋轉 UV islands、裁切、縮放、拼接或以程式重畫生成貼圖。`generation_inputs.json` 必須記錄全部嘗試（含未採用稿），每項沿用既有欄位：`label`、`variant`、`tool`、`selected`、`generated_file`、`archive`、`archive_sha256`、`output_size`、`output`、`prompt`、`prompt_sha256`、`base_prompt`、`base_prompt_sha256`、`user_authorized_engineering_limit: 0.20`、`reference_images` 與包含 `path/snapshot/sha256/role` 的 `references`。第一參照 role 為 `edit_target` 並綁原 atlas；重試以 `edit_target_previous_attempt` 綁保留的未採用原生稿。頭部的設計參照 role 必須含 `design_authority`，body 使用 `approved_design` 或 `approved_body_design`。完整 prompt 必須包含既有 `docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt` 原文。

完成五張圖與真實 provenance 後，才執行採用、建模與編譯。`adopt.py` 只複製逐 byte 相同的原生生成 PNG。`build.py` 在 Blender 數據證明沒有移動後，保留 Godot JSON 原數值，避免 float32 與 JSON 末位小數差被誤記為幾何修改。`compile.gd` 對此兩款不重算法線；SCN 沿用全部原 mesh buffers，只替換五個材質。

```powershell
python tools/armor_runtime_v1/adopt.py "--armor=$armorSlug"
& $armorBlender --background --python-exit-code 1 --python tools/armor_runtime_v1/build.py -- "--armor=$armorSlug"
& $armorEngine --headless --path . --editor --quit
& $armorEngine --headless --path . --script res://tools/armor_runtime_v1/compile.gd -- "--armor=$armorSlug"
python tools/armor_runtime_v1/glb_unique_joints.py "--armor=$armorSlug"
& $armorEngine --headless --path . --editor --quit
```

根節點正式 loader 加入 ID 7/8 路由後，跑原有實際裝備和動作 fixture。原三款的歷史 validator 不改；Atom/Pegasus 使用獨立 `first_integration_contract.py`，核對真正原版 13 檔、glTF buffers、五 native PNG、UV0、860/1128 原三角及量化權重。所有報告都綁當次 source/target/SCN/map SHA。引擎 import 成功只算匯入，不算這些驗收已通過。

```powershell
python tests/armor_runtime_next_pipeline_test.py
& $armorEngine --headless --path . --script res://tools/armor_runtime_v1/validate_scene.gd -- "--armor=$armorSlug"
& $armorEngine --headless --path . res://tests/armor_runtime_v1_test.tscn -- "--armor=$armorSlug"
& $armorEngine --headless --path . res://tests/armor_runtime_v1_roundtrip.tscn -- "--armor=$armorSlug"
& $armorBlender --background "docs/art/${armorSlug}_runtime_v1/build/${armorSlug}_master.blend" --python-exit-code 1 --python tools/armor_runtime_v1/validate_delivery.py -- "--armor=$armorSlug"
python tools/armor_runtime_v1/validate_glb_images.py "--armor=$armorSlug"
& $armorEngine --path . --rendering-method gl_compatibility --rendering-driver opengl3_angle --log-file "docs/art/${armorSlug}_runtime_v1/review/original_integration_angle_capture.log" res://tools/armor_runtime_v1/capture.tscn -- "--armor=$armorSlug"
python tools/armor_runtime_v1/measure.py "--armor=$armorSlug"
python tools/armor_runtime_v1/provenance.py "--armor=$armorSlug"
python tools/armor_runtime_v1/review.py "--armor=$armorSlug"
```

擷取需正常 ANGLE/Direct3D11、64 張原版與新版固定視角、待機/跑動/換彈及關卡畫面，確認圖片後才可標視覺已看。真實存檔必須前後 SHA 相同。`provenance.py` 在六份實際報告和全部擷取通過前會拒絕產出交付 manifest；美術仍標 `pending_user_art_review`，不能把數值 0% 當概念還原度。
