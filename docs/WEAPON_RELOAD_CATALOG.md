# 全武器換彈對應表

24 把武器已接入遊戲，共 55 套換彈動作。每次開始換彈等機率隨機選擇該槍的 A/B 或 A/B/C；散彈槍一次連續裝填只選一次。`reload_variant_override = -1` 是隨機，設為 0/1/2 可固定方案供檢視。

| 武器 | 分類 | 個別彈匣／裝填結構 | 容量 | 動作 | 行為驗證 |
| --- | --- | --- | --- | --- | --- |
| FR28a (`gun00`) | 步槍 | 前下方細彈匣 | 30 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| MA72 (`gun01`) | 步槍 | 前下方斜置彈匣 | 30 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| MS06 (`gun02`) | 步槍 | 前下方短斜彈匣 | 32 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| FR43C (`gun03`) | 步槍 | 前置寬斜彈匣 | 30 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| FL334AR (`gun04`) | 步槍 | 前下方嵌入式供彈匣 | 36 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| TB10-LW (`gun05`) | 步槍 | 前下方弧形供彈匣 | 40 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| TSG-03 (`gun06`) | 散彈槍 | 槍身左下裝填口／逐顆彈殼 | 6 | A 側翻逐顆裝填／B 抬槍逐顆裝填 | PASS |
| SD58 (`gun07`) | 散彈槍 | 機匣左側裝填口／逐顆彈殼 | 8 | A 側翻逐顆裝填／B 抬槍逐顆裝填 | PASS |
| WD03S (`gun08`) | 散彈槍 | 扳機前側裝填口／逐顆彈殼 | 6 | A 側翻逐顆裝填／B 抬槍逐顆裝填 | PASS |
| S92M (`gun09`) | 散彈槍 | 機匣側邊裝填口／逐顆彈殼 | 6 | A 側翻逐顆裝填／B 抬槍逐顆裝填 | PASS |
| T740 (`gun10`) | 散彈槍 | 槍身左下裝填口／逐顆彈殼 | 8 | A 側翻逐顆裝填／B 抬槍逐顆裝填 | PASS |
| RPG-21 (`gun11`) | 火箭筒 | 原 RPG-21 前端彈頭 | 1 | A 胸前側收／B 立筒裝填 | PASS |
| RPG-24 (`gun12`) | 火箭筒 | 原 RPG-24 細長彈頭 | 1 | A 胸前側收／B 立筒裝填 | PASS |
| RPG-31 (`gun13`) | 火箭筒 | 原 RPG-31 短錐彈頭 | 1 | A 胸前側收／B 立筒裝填 | PASS |
| Vox-07 (`gun14`) | 榴彈發射器 | 中央圓柱彈鼓與前後環 | 4 | A 側轉抽換／B 斜抬抽換 | PASS |
| M347 (`gun15`) | 榴彈發射器 | 寬型中央彈鼓與前後環 | 6 | A 側轉抽換／B 斜抬抽換 | PASS |
| Ge09x (`gun16`) | 榴彈發射器 | 上置圓柱彈鼓 | 6 | A 側轉抽換／B 斜抬抽換 | PASS |
| BLACK STARS (`gun30`) | 火箭筒 | 後上方火箭供彈艙 | 1 | A 胸前換艙／B 側抬換艙 | PASS |
| R100-RAILGUN (`gun34`) | 狙擊槍 | 前下方長形供彈匣 | 5 | A 微抬側轉換匣／B 平收換匣 | PASS |
| R700-AA (`gun35`) | 狙擊槍 | 機匣前下方淺型彈倉匣 | 5 | A 微抬側轉換匣／B 平收換匣 | PASS |
| AST-KK (`gun40`) | 步槍 | 前下方異形彈匣 | 36 | A 肩前直插／B 抬槍斜插／C 胸前側收 | PASS |
| J.O.K.E (`gun41`) | 榴彈發射器 | 右側圓形供彈模組 | 4 | A 側轉抽換／B 斜抬抽換 | PASS |
| Reflection (`gun43`) | 狙擊槍 | 前下方楔形供彈匣 | 5 | A 微抬側轉換匣／B 平收換匣 | PASS |
| U.F.O (`gun45`) | 榴彈發射器 | 左側方形供彈艙 | 5 | A 側轉抽換／B 斜抬抽換 | PASS |

## 模型處理

- **FL334AR**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。
- **TB10-LW**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。
- **BLACK STARS**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。
- **R100-RAILGUN**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。
- **R700-AA**：原模型彈倉與機匣共面；沿底部輪廓分割淺型彈倉，保留上方機匣。
- **J.O.K.E**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。
- **U.F.O**：原科幻模型未標明供彈機構；以此原有部件設計可拆供彈艙，屬本次動畫設計。

其餘可拆部件保留原始輪廓、UV、法線與材質；可見彈頭發射後隱藏。散彈槍依各自機匣設定入口與彈殼尺寸，沒有額外掛上方盒。`gun35` 的淺型彈倉從共用機匣表面切開；來源面積守恆，額外封口只用於取出的零件。

`gun30` 的來源握把座標偏移另行校正；`gun41`／`gun45` 依匯入網格方向校正模型旋轉。這些校正作用在武器模型，彈匣與槍身共用相同轉換。

## 預覽與重現

離線 HTML：`test_output/reload_catalog/reload_catalog.html`。可選武器、A/B/C 同步比較、前／側／後視角、慢速、逐幀拖曳，以及原部件標示和拆出圖。站立為完整序列，跑動為關鍵姿勢；青色僅為檢查標示，遊戲內仍用原貼圖。

```powershell
python tools/yaml_mesh_converter/split_reload_parts.py --check
python tools/build_reload_catalog.py
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --headless res://tests/reload_catalog_test.tscn
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --headless res://tests/reload_catalog_running_test.tscn
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/reload_model_capture.tscn
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 960x540 res://tests/reload_catalog_capture.tscn -- --sequence
& .\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 960x540 res://tests/reload_catalog_capture.tscn -- --moving
python tools/build_reload_catalog_preview.py
```

擷取輸出不提交；場景、工具、模型分割選擇與此對應表均保留。HTML 可直接從本機開啟，不需伺服器或網路。

## 驗證與限制

| 檢查 | 本次結果 |
| --- | --- |
| 逐把換彈／隨機方案／取消與切槍 | PASS |
| 實際跑動／飛行換彈 | PASS |
| FR28a 與 RPG-21 回歸 | PASS |
| 鏡頭／持槍／投射物／遊戲煙霧／設定 | PASS |
| 模型來源與分割 `--check` | PASS |
| Edge 離線 HTML：24 把切換、播放／暫停、拖曳、視角、跑動圖、放大 | PASS |
| `git diff --check`／Godot 編輯器匯入 | PASS |
| `.harness/verify.py` | FAIL：既有生成文件與來源不同步，這次未修改相關政策或入口文件 |

- `reload_catalog_test`：24 把／55 套、裝配位置與尺寸、雙手接觸、補彈、取消、隨機方案與散彈連續裝填。
- `reload_catalog_running_test`：55 套實際跑動與 24 把飛行換彈，使用正常物理更新與 AnimationTree。
- 視覺以預設盔甲、Compatibility renderer 擷取；未逐件驗收所有盔甲。原模型未提供手指骨骼與可動膛蓋，因此握持和單發裝填仍受原素材限制。
- 測試退出可能報 ObjectDB／resource 清理警告；斷言通過不代表清理警告已修復。

## 動作參考

| 遊戲參考 | 抽樣位置 | 借用的動作 |
| --- | --- | --- |
| [Fortnite OG](https://www.youtube.com/watch?v=H9eEc6LJqo8) | 0:45–1:25 散彈槍、5:20–5:50 狙擊槍、6:04 起發射器 | 側轉露出装填區、分開取彈／插入／復位 |
| [GTA Online 第三人稱換彈](https://www.youtube.com/watch?v=g6oDZf93eys) | 1:40–3:18 步槍／散彈／狙擊槍 | 肩前換匣、抬槍與平收姿勢的差異 |
| [The Division 2](https://www.youtube.com/watch?v=FaAZPqJZuTg&t=270s) | 4:30–5:50 實際射擊與換彈片段 | 操作時收槍並側轉，之後恢復射擊姿勢 |

以上是公開影片抽樣畫面的姿勢比較，未完整播放或量測動作角度。科幻槍的供彈方式是配合本專案原模型設計，沒有宣稱是參考遊戲的相同武器結構。
