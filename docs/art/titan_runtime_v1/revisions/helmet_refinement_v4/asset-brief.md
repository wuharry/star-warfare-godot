# Titan 圓罩頭盔製作約束

本輪以 approved_concept.png 的圓形金色壓力面罩為方向，已進入實際遊戲素材流程；使用者美術驗收仍待確認。不要把工程 PASS 寫成與概念圖完全一致。

## 後續必要 prompt 與模型基底

保留 Titan 的短身、大頭與原骨架。頭部要是包覆式圓弧金色面罩，正面投影可見面罩至少占整個 ArmorHead_05 輪廓 50%。藍色冠、兩側護框與下巴要形成連續框線，黑色密封圈保持窄；不要畫兩個對稱反光橢圓、兩個銀色中央扣件或使兩片面罩看似分裂。斜視圖不能有主玻璃弧面之外另凸出的玻璃翼。維持 Viper、Fortune 目前共用的厚甲、手繪 diffuse 與低多邊形遊戲風格。

編輯貼圖必須使用這輪的原生 atlas 和 UV 語意圖作參照，保留島的位置、朝向、三個 charts 與鏡像共用區域。整張概念圖不能直接當 UV atlas。頭部貼圖是 titan_head_diffuse.png；身體、肩、手、腳沿用前一輪四張圖，不重畫。

當前頭部 334 UV 座標、164 三角形，原版 294／124。新增 40 個點只能是原邊中點，具有原父邊與父面記錄；前 294 個原點索引與權重保持身份，只承襲既有 10 個 UV 編輯。計數上限為原版的 1.35 倍，這是此輪 Titan 的明確實作預算，不能套用為其他裝甲的一般授權。實際為 UV 1.1361 倍、三角形 1.3226 倍。

對真正原版的最大局部位移與各軸尺寸差仍限 20%，原 UV 座標變更比例按每個 surface 分別限 20%。不能逐輪累加 20%。其他部位 raw arrays、原 skin binds 與 28 骨架保持原值。前弧玻璃／框線新增切分提高圓度；側返回面的新增中點收向內 12mm、向後 40mm，以免 quarter 出現獨立金翼。不得因此造成翻面、零面積或可見裂縫。

## 實際圖片與重建流程

完整實送 prompt：head_diffuse_prompt.txt、head_diffuse_prompt_attempt_02.txt。第一稿未採用，第二稿是目前原生 canonical；generation_record.json 與 generation_record_attempt_01.json 保留來源、原生輸出 SHA 與 ancestry。PNG 以原生位元組複製，未額外手繪、重採樣或合成。

1. Blender build.py -- --armor=titan，生成 master、target、geometry。
2. Godot update_titan_helmet.gd 更新實際 SCN／GLB，再做 glb_unique_joints.py 和正常匯入。不要使用 first-integration compile/adopt/provenance/review 流程蓋回舊頭盔。
3. 實際 scene invariants、15 個動作姿勢、9 個 GLB 回讀姿勢、全五圖 GLB RGB 與 Blender packed PNG 驗證。
4. 必要時使用 reimport_titan_head_lossless.gd 的引擎 importer callback；不手改 .import／.uid。
5. 正常 renderer 擷取 helmet_v4_final 的 64 張圖。另隔離整個頭部擷取面罩覆蓋率，再執行 measure_titan_visor.py；覆蓋率分母包括 ArmorHead_05 內所有可見幾何，不是只取面罩附近裁切框。
6. 執行 test_titan_helmet_guards.py、titan_refinement_manifest.py，更新比較頁／after15 後執行共用六套 validator 與原創系列交付 validator。

20%／35% 與覆蓋率都不是美術相似度評分。只有 quarter 參考可用，側後面仍含推定；目前保持原版比例與有限面數，尚未達到概念圖的逐像素完全一致。實機效能、手機記憶體與使用者美術確認未完成。
