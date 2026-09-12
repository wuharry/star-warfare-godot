# U.F.O 原版材質還原（2026-09-12）

`gun45` 發白是舊 MTL 遺漏貼圖。從 Unity `Resources/weapon/gun45.prefab`
重新匯出的 OBJ 與目前檔案 SHA256 相同：
`be1d8bcd763a63ee9e42f09e5bddc66cbc23d976a04c250df2d10e8bb3f70765`。

原始 `Material/HotWing-Material #25.mat` 使用 `iPhone/SolidAndAlphaTexture`，
公式為 `_texBase + _tex2 * _TintColor`，不受場景燈光影響。
`HotWing_D.png`、`HotWing_L.png` 均直接複製原版 Texture2D；保留原模型 UV。

目前 converter 已能讀取此材質格式，重新產生 `gun45.mtl` 即可補回七個主貼圖連結。
OBJ/MTL 無法表示雙貼圖 shader，所以 `UnityMaterialRestorer.restore_ufo_body`
在玩家與商店共用原有 `unity_solid_overlay.gdshader` 還原疊圖。
材質依名稱匹配，兼容 `gun45_body.obj`、`gun45_reload.obj` 的不同表面編號。
明確載入主貼圖也避免既有 OBJ 匯入快取保留空白材質。

重建 MTL 的命令（輸出到暫存目錄，核對模型一致後複製 MTL 與主貼圖）：

```powershell
python tools/yaml_mesh_converter/convert.py prefab E:/Star-Warfare-1.0.2/Assets/Resources/weapon/gun45.prefab test_output/gun45_fix/gun45.obj --assets-root E:/Star-Warfare-1.0.2/Assets
```

原生 OBJ 編輯器預覽若沿用舊材質，需在 Godot 重新匯入上述三個 OBJ。
裝填目錄的青色仍是刻意標記；側面供彈艙的換彈設計不代表原版動畫。

驗證：模型截圖（Compatibility、1280×720）已檢視，商店與換彈新增雙貼圖斷言通過，
拆件 `--check` 通過。換彈全套斷言通過，但快速重複換裝時引擎仍輸出
`Parameter "material" is null`，因此不視為無錯誤日誌的驗收。
