# Atom · C-08 runtime v1

Atom以真正原版四部件與五張UV貼圖為基底，轉譯C-08身甲及指定新版頭盔；依核准草稿修正頭盔與身甲／肩甲輪廓，UV0與原骨架精確保留。 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID 7，原節點 {'ArmorHead_07': 58, 'ArmorBody_07': 59, 'ArmorHand_07': 60, 'ArmorFoot_07': 61}；不改裝甲數值、技能、存檔ID或背包。

860 triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · 772原UV，0改動 · ArmorBody_07 位移19.79%／尺寸6.70% · ArmorFoot_07 位移0.00%／尺寸0.00% · ArmorHand_07 位移0.00%／尺寸0.00% · ArmorHead_07 位移12.64%／尺寸3.90% · 各部件由真正原版累積量算上限20%。幾何來自真正原版skin-space source；允許改形的原部件：ArmorHead_07、ArmorBody_07；只調整位置、重新計算法線與切線，其餘部件及全部UV0／原拓撲／skin／權重／transform保持原值。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/atom_v1/atom.scn、atom.glb與五張原生1254² diffuse；build/atom_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://atom_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：head04 已有全頂鋼藍冠脊、真耳圓盤與獨立青頰窗，下巴也縮短；紫殼及冠脊仍受原低多邊形折面影響，輪廓較草稿扁平、圓潤度不同。；面罩仍是原有繪製上緣和較矮的青面窗，中央強 V 形對稱反光未完全消除。head05 的過度玻璃稿未採用；未完成上緣移到新 UV polygon 的美術目標。舊「可見玻璃增加35%」指標已撤回，不能用作還原證據。；肩鰭已由整片原頂點改成連續上斜寬楔、長青前燈可辨，沒有舊 L 形突然直立段；根底仍較外偏、末端仍比草稿短厚直立片更扁，未宣稱逐形一致。；body12 已消除舊紫色放射胸條，形成雙大藍胸面與胸甲中央下移青服務件；服務框仍比概念簡化、較小，中央紫領塊與下方五角腹甲保留原版構造，不將現在模組誤判為頸燈。；紫／鋼藍／青配色連續、前臂矩形窗與腿側圓燈保留辨識；白磨邊、硬板縫與腿甲折角仍比草稿密／銳，四肢及原短壯比例尚有明顯原版特徵。；概念沒有展示背面；後腦封閉後蓋、藍背板與背側青件只檢查连貫性，不宣稱隱藏側背完全還原。；64張固定取樣沒有顯見新增裝甲裂口或飛片，換彈外部長方物是原版也有的彈匣；武器與背包遮住部分胸背，未檢查完整連續動畫全角度、手機螢幕或GPU效能。

共用管線位於 tools/armor_runtime_v1：adopt.py --armor=atom → Blender build.py -- --armor=atom → Godot正常import → compile.gd -- --armor=atom → glb_unique_joints.py --armor=atom → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor=atom → Blender載入 build/atom_master.blend 後执行validate_delivery.py -- --armor=atom，以及validate_glb_images.py → ANGLE capture.tscn -- --armor=atom → measure.py／provenance.py／review.py。禁止手改engine import metadata。
