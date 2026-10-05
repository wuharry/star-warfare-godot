# 工蟲外觀風格統一 · 2026-10-05

目前工蟲已改成較柔和的手繪甲殼，降低密集刮痕、金色硬亮邊與霓虹紫縫；[比較頁](index.html) 提供修改前後與原版敵人同畫面。原版 `bug01`、`bug03` 貼圖決定畫法，現有工蟲 atlas 決定 UV 位置，六眼／雙鐮臂／四足設計繼續保留。

## 修改範圍

這次交付只改外觀，遊戲仍透過 `MonsterCatalog.visual_scene_path("crawler")` 載入 `warrior.gltf`。

| 項目 | 本次做法 |
| --- | --- |
| 畫法 | 用內建 imagegen 編修兩輪；去除細碎刮痕，將切面筆觸與硬金邊改成大面積柔和漸層 |
| 新貼圖 | `assets/models/enemies/concept/warrior/warrior_anatomy_v6.png`；1024×1536、六部位 atlas、完全不透明 |
| 稜邊 | 線性基色改為 `[0.075, 0.030, 0.013]`，移除自發光 |
| 紫色甲縫 | 線性基色改為 `[0.080, 0.016, 0.100]`，移除自發光 |
| 甲殼基本亮度 | `painted_fill` 從 0.45 改為 0.65，保留原有柔和漫反射與色彩空間轉換 |
| 幾何／UV／骨架／動畫 | 交付的 `warrior.bin` 與修改前 SHA256 相同；glTF 只更新材質和貼圖 URI |
| 眼睛 | 沿用六眼薄環與頂點漸層 |

這樣處理是因為風格落差集中在表面畫法與材質：例如同一個頭罩原本佈滿裂痕與金色亮邊，現在用較大的褐色甲面與柔和反光表現弧面。沒有重新切 UV 或增加小甲片。

## 重現

生成器的兩次實際 prompt、原始輸出與參考 hash 見 [generation_record.json](generation_record.json)。第一次輸出刮痕已減少，但筆觸仍偏硬，第二次專門柔化。這些是 diffuse 成品貼圖，包含原版遊戲的手繪明暗；不套用一般 PBR 的「禁止畫光影」規則。

```sh
# 重建材質與模型；不會重新付費生成貼圖。
/Applications/Blender.app/Contents/MacOS/Blender --background --python-exit-code 1 --python tools/enemy_concept/build_warrior.py
# 先匯入新 PNG，再經 Godot ConfigFile API 設定 mipmaps／3D 壓縮。
godot --headless --editor --path . --quit
godot --headless --path . --script tools/enemy_concept/configure_import.gd
godot --headless --editor --path . --quit
godot --headless --path . res://tests/enemy_concept_test.tscn
godot --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/enemy_concept_visual_capture.tscn -- --family --player-view
```

Blender 重建通過，但與先前匯出版本相比有很小的跨平台浮點差異；初次嚴格比對因法線差異超過 0.0001 失敗，未採用該次幾何輸出。本次只取回重建後的材質設定，再保留既有二進位幾何資料。[rebuild_comparison.json](rebuild_comparison.json) 列出實測差異，不把重建結果稱為逐位元相同。

## 驗證與限制

本次檢查結果見 [validation.json](validation.json)，畫面由 Godot 4.7.2 / GL Compatibility 直接擷取；未修圖。

| 檢查 | 狀態 |
| --- | --- |
| Blender 材質重建 | PASS；30 骨、8 動畫、12,256 三角形，未增加部件 |
| Godot 概念素材與命中 | PASS；131 checks、27 條射線，含新貼圖及稜邊／紫縫不自發光 |
| 敵人動畫回歸 | PASS；4 種敵人 |
| 畫面擷取 | PASS；23 張，包含敵人同畫面與玩家鏡頭 |
| 目視檢查 | 已檢視正面、側面、頭部、跑步、攻擊、死亡、關卡及敵人並排；風格是否符合你的偏好待你確認 |
| harness | PASS；只代表入口同步完整 |
| 比較頁 | 靜態引用與 JavaScript 語法 PASS；瀏覽器 NOT RUN（本機伺服器未啟動，file URL 被瀏覽器政策拒絕） |
| 大量敵人效能／手機實機 | NOT RUN；既有面數未降低，不宣稱效能改善 |

「關卡近景」隱藏角色與 HUD 並另設相機，屬美術檢查；「玩家鏡頭」使用原本玩家相機、角色與 HUD，只凍結動作。兩者在比較頁分開標示。其他敵人與你正在修改的 AI 資料沿用現有工作內容。
