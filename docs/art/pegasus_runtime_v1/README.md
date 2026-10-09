# Pegasus · C-09 runtime v1

Pegasus以真正原版四部件與五張UV貼圖為基底，轉譯C-09白灰裝甲、深色V面甲及藍色細節；依核准草稿修正頭盔與身甲／肩甲輪廓，UV0與原骨架精確保留。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 8，原節點 {'ArmorHead_08': 62, 'ArmorBody_08': 63, 'ArmorHand_08': 64, 'ArmorFoot_08': 65}；不改裝甲數值、技能、存檔ID或背包。

1128 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 1096原UV，0改動 · ArmorBody_08 位移10.71%／尺寸3.84% · ArmorFoot_08 位移0.00%／尺寸0.00% · ArmorHand_08 位移0.00%／尺寸0.00% · ArmorHead_08 位移19.29%／尺寸13.92% · 各部件由真正原版累積量算上限20%。幾何來自真正原版skin-space source；允許改形的原部件：ArmorHead_08、ArmorBody_08；只調整位置、重新計算法線與切線，其餘部件及全部UV0／原拓撲／skin／權重／transform保持原值。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/pegasus_v1/pegasus.scn、pegasus.glb與五張原生1254² diffuse；build/pegasus_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://pegasus_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：中央上額板已由分層 V 改成較連續白面，但最低眉下仍留一個小 V 片／黑影；雙外額翼仍是尖厚楔形，未等同草稿低窄鈍雙軌與單一簡潔額面。；冠上黑通風孔仍較靠屋頂面，未精準落在真正 rail strip；側耳外殼在正側面仍是大塊多邊白板／黑直縫，沒有草稿明確圓耳輪廓。；面窗讀成一片連續深黑玻璃，下頜較短；厚眉沿、護唇及淺 V 窗形仍占臉較多，沒有宣稱與草稿逐形一致。；body06 的共享白中隔在無武器前面近照已消失，胸槽讀成一個黑開口；仍可見極細暗中線，槽框／槽體偏高長收腰，槽下白件仍較長五角形，未形成草稿較短矩形服務槽和胸腹比例。；外大腿白殼下緣稍延長，但正面仍露出較多黑布、仍有原版髖大腿分區；未達草稿較大白甲覆蓋。原短壯比例保留。；白甲磨邊與細線較銳利；是否足夠接近 Viper／Fortune 的共同手繪風格仍待使用者評價。草稿沒有背面，後腦、背甲與腳跟僅驗收連貫性。；待機、跑動及九個換彈時間點與區域01／08畫面未見新增甲片飛離或明顯破洞；槍會遮住胸口，未檢查完整連續動畫全角度、手機螢幕與 GPU 效能。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=pegasus → Blender build.py -- --armor=pegasus → Godot正常import → compile.gd -- --armor=pegasus → glb_unique_joints.py --armor=pegasus → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=pegasus → Blender載入 build/pegasus_master.blend 後执行validate_delivery.py -- --armor=pegasus，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=pegasus → measure.py／provenance.py／review.py。禁止手改engine import metadata。
