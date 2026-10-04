# Titan · C-06 runtime v1

Titan保留大面積金色全罩、鋼藍護框與厚甲，依原UV映射金色識別元素。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 5，原節點 {'ArmorHead_05': 50, 'ArmorBody_05': 51, 'ArmorHand_05': 52, 'ArmorFoot_05': 53}；不改裝甲數值、技能、存檔ID或背包。

700 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 1607原UV，0改動 · 頭部最大局部位移 10.31% · 各軸尺寸差最大 0.00% · 真正原版總上限20%。幾何來自真正原版skin-space source；身體手腳保持原數據。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/titan_v1/titan.scn、titan.glb與五張原生1254² diffuse；build/titan_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://titan_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：Original low-poly facets and some bright hand-painted contact edges remain.

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=titan → Blender build.py -- --armor=titan → Godot正常import → compile.gd -- --armor=titan → glb_unique_joints.py --armor=titan → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=titan → validate_delivery.py（Blender）與validate_glb_images.py → ANGLE capture.tscn -- --armor=titan → measure.py／provenance.py／review.py。禁止手改engine import metadata。
