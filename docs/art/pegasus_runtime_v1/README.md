# Pegasus · C-09 runtime v1

Pegasus以真正原版四部件與五張UV貼圖為基底，轉譯C-09白灰裝甲、深色V面甲及藍色細節；依核准草稿修正頭盔與身甲／肩甲輪廓，UV0與原骨架精確保留。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 8，原節點 {'ArmorHead_08': 62, 'ArmorBody_08': 63, 'ArmorHand_08': 64, 'ArmorFoot_08': 65}；不改裝甲數值、技能、存檔ID或背包。

1128 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 1096原UV，0改動 · ArmorBody_08 位移4.83%／尺寸3.84% · ArmorFoot_08 位移0.00%／尺寸0.00% · ArmorHand_08 位移0.00%／尺寸0.00% · ArmorHead_08 位移17.53%／尺寸12.48% · 各部件由真正原版累積量算上限20%。幾何來自真正原版skin-space source；允許改形的原部件：ArmorHead_08、ArmorBody_08；只調整位置、重新計算法線與切線，其餘部件及全部UV0／原拓撲／skin／權重／transform保持原值。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/pegasus_v1/pegasus.scn、pegasus.glb與五張原生1254² diffuse；build/pegasus_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://pegasus_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：雙冠與下巴已由原頂點縮低、內收；冠頂仍是較寬側眉蓋與中央V階梯，和草稿窄鈍雙軌仍有差距。；深色面窗連續，前頜已縮短；厚眉與護唇仍佔較大比例，未宣稱草稿逐形一致。；白領／黑頸與中央黑直槽、藍肩橫帶已套用；胸槽較靠領口且保留共享中分線，槽下白件仍為原長五角輪廓。；外大腿白板稍延長，但正面黑布露出仍比草稿多；遊戲原短壯比例保留，未改成人比例。；側背是依原版與草稿延伸，概念只展示斜正面；保留原後腦與腳跟技術紋理。；15裝備姿勢／9GLB姿勢及64張ANGLE擷取通過；未做完整連續動畫全角度或手機效能實測，美術仍待使用者審閱。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=pegasus → Blender build.py -- --armor=pegasus → Godot正常import → compile.gd -- --armor=pegasus → glb_unique_joints.py --armor=pegasus → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=pegasus → Blender載入 build/pegasus_master.blend 後执行validate_delivery.py -- --armor=pegasus，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=pegasus → measure.py／provenance.py／review.py。禁止手改engine import metadata。
