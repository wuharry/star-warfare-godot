# Pegasus · C-09 runtime v1

Pegasus以真正原版四部件與五張UV貼圖為基底，轉譯C-09白灰裝甲、深色V面甲及藍色細節；初版保持原幾何。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 8，原節點 {'ArmorHead_08': 62, 'ArmorBody_08': 63, 'ArmorHand_08': 64, 'ArmorFoot_08': 65}；不改裝甲數值、技能、存檔ID或背包。

1128 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 1096原UV，0改動 · 頭部最大局部位移 0.00% · 各軸尺寸差最大 0.00% · 真正原版總上限20%。幾何來自真正原版skin-space source；身體手腳保持原數據。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/pegasus_v1/pegasus.scn、pegasus.glb與五張原生1254² diffuse；build/pegasus_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://pegasus_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：原頂點／UV 全保留，所以雙冠較概念高、前頜較尖長，概念低冠與短頜未完整形成；目前是原遊戲比例的貼圖轉譯。；前胸仍保留原五角中央件和藍領區，與概念黑色矩形胸槽不同；這輪 body prompt 以原胸板重整為範圍，沒有要求新增發光服務盒。；藍色外緣線與磨損比原版更清楚，部分仍有亮白磨邊。全身大色塊與深色關節符合共同方向，細節密度是否足夠接近 Viper/Fortune 仍待使用者美術評價。；後腦與腳跟保留原深藍技術紋理，概念只展示斜正面，背面做法屬原版基底延伸。；區域 08 雪地降低白灰外殼背景對比；目前沒有手機螢幕與效能實測，不將實機擷取視為行動裝置驗收。；動畫是待機／跑動各一張與換彈九張固定取樣，未見新增破裂，不代表完整連續動畫所有角度皆已驗證。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=pegasus → Blender build.py -- --armor=pegasus → Godot正常import → compile.gd -- --armor=pegasus → glb_unique_joints.py --armor=pegasus → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=pegasus → Blender載入 build/pegasus_master.blend 後执行validate_delivery.py -- --armor=pegasus，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=pegasus → measure.py／provenance.py／review.py。禁止手改engine import metadata。
