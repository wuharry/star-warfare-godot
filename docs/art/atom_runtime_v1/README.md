# Atom · C-08 runtime v1

Atom以真正原版四部件與五張UV貼圖為基底，轉譯C-08身甲及指定新版頭盔；初版保持原幾何。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 7，原節點 {'ArmorHead_07': 58, 'ArmorBody_07': 59, 'ArmorHand_07': 60, 'ArmorFoot_07': 61}；不改裝甲數值、技能、存檔ID或背包。

860 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 772原UV，0改動 · 頭部最大局部位移 0.00% · 各軸尺寸差最大 0.00% · 真正原版總上限20%。幾何來自真正原版skin-space source；身體手腳保持原數據。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/atom_v1/atom.scn、atom.glb與五張原生1254² diffuse；build/atom_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://atom_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：原幾何／UV 全保留，所以 Atom 長下巴、平多角耳蓋及長肩刺仍在；概念短頜、圓耳與較收斂肩部尚未完整形成。；青玻璃中心為亮 V 反射，未見黑色拼接裂縫；其亮度與對稱高光較概念硬，仍待使用者美術評價。；前胸已是單一直立青窄窗，但尺寸與高度受原短壯胸部 UV 面積限制，外框形狀較概念成人版狹長。；後背雙盒已移除，中央改為不發光鋼藍板；不是原圓燈的完全恢復。；部分白色磨邊及紫色裂紋較概念密，和 Viper/Fortune 的柔和大色塊仍有細節密度差異。；動畫只核對待機／跑動各一張與換彈九張固定取樣；未見新增破裂，不代表完整連續動畫或手機效能全面驗收。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=atom → Blender build.py -- --armor=atom → Godot正常import → compile.gd -- --armor=atom → glb_unique_joints.py --armor=atom → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=atom → Blender載入 build/atom_master.blend 後执行validate_delivery.py -- --armor=atom，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=atom → measure.py／provenance.py／review.py。禁止手改engine import metadata。
