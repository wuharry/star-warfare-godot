# Hydra · C-04 runtime v1

Hydra保留黃綠大型面甲與藍綠装甲，中央單鏡頭相機、縮短藍色下巴。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 3，原節點 {'ArmorHead_03': 42, 'ArmorBody_03': 43, 'ArmorHand_03': 44, 'ArmorFoot_03': 45}；不改裝甲數值、技能、存檔ID或背包。

760 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 726原UV，0改動 · 頭部最大局部位移 14.74% · 各軸尺寸差最大 0.00% · 真正原版總上限20%。幾何來自真正原版skin-space source；身體手腳保持原數據。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/hydra_v1/hydra.scn、hydra.glb與五張原生1254² diffuse；build/hydra_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://hydra_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：中央單鏡頭已映射；金綠大面甲與短下巴仍保留原低模折面和少量亮色接觸邊，待使用者美術評價。；原肩甲兩個UV樣本超出0–1邊界，與true original逐值相同，沒有新增越界座標或UV改動。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=hydra → Blender build.py -- --armor=hydra → Godot正常import → compile.gd -- --armor=hydra → glb_unique_joints.py --armor=hydra → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=hydra → Blender載入 build/hydra_master.blend 後执行validate_delivery.py -- --armor=hydra，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=hydra → measure.py／provenance.py／review.py。禁止手改engine import metadata。
