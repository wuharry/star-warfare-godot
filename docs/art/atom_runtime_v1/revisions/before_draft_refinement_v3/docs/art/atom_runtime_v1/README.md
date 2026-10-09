# Atom · C-08 runtime v1

Atom以真正原版四部件與五張UV貼圖為基底，轉譯C-08身甲及指定新版頭盔；依核准草稿修正頭盔與身甲／肩甲輪廓，UV0與原骨架精確保留。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 7，原節點 {'ArmorHead_07': 58, 'ArmorBody_07': 59, 'ArmorHand_07': 60, 'ArmorFoot_07': 61}；不改裝甲數值、技能、存檔ID或背包。

860 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 772原UV，0改動 · ArmorBody_07 位移15.84%／尺寸8.08% · ArmorFoot_07 位移0.00%／尺寸0.00% · ArmorHand_07 位移0.00%／尺寸0.00% · ArmorHead_07 位移15.66%／尺寸3.90% · 各部件由真正原版累積量算上限20%。幾何來自真正原版skin-space source；允許改形的原部件：ArmorHead_07、ArmorBody_07；只調整位置、重新計算法線與切線，其餘部件及全部UV0／原拓撲／skin／權重／transform保持原值。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/atom_v1/atom.scn、atom.glb與五張原生1254² diffuse；build/atom_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://atom_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：原頭部已縮短下巴、壓低冠頂，六點耳蓋側視比例從約1.96:1改為1.19:1；金屬耳盤已畫回真正耳蓋，仍保留低多邊形外殼輪廓。；紫頂／鋼藍冠燈、三額燈與青玻璃已呈現；中央鋼藍冠區較草稿短，玻璃的V形對稱反光較強，缺少草稿的獨立青色頰窗。；長肩刺改成較短厚的楔形鰭，前面青燈可見但小且靠根，仍較草稿外張，未宣稱草稿肩部逐形一致。；body10實機是一個高胸青服務模組，已非舊領口燈或低胸燈；相對理想UV標示仍偏高，胸甲放射分片與下方五角板保留較多原版特色。；前臂圓燈改為矩形窗；白色磨邊與紫裂紋仍較草稿密。背面沿原版推定，概念未展示隱藏側背，不能稱完全還原。；15裝備姿勢／9GLB姿勢及64張ANGLE擷取通過；未做完整連續動畫全角度或手機效能實測，美術仍待使用者審閱。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=atom → Blender build.py -- --armor=atom → Godot正常import → compile.gd -- --armor=atom → glb_unique_joints.py --armor=atom → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=atom → Blender載入 build/atom_master.blend 後执行validate_delivery.py -- --armor=atom，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=atom → measure.py／provenance.py／review.py。禁止手改engine import metadata。
