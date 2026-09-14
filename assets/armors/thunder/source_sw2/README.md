# Thunder 原始網格與配對材質參考

此目錄保存本機使用者提供的《Star Warfare 2》新版 Thunder（Avatar06）資料，供重建使用。`.gdignore` 防止 Godot 將原始輸入誤當作遊戲材質匯入；實際遊戲模型由 Thunder 建置工具輸出。

## 來源與修正

- 檔案：`E:/05_Assets/godot遊戲素材/com.ifreyr.sw2.zip`。
- 容器：`com.ifreyr.sw2/main.29.com.ifreyr.sw2.obb`，Unity `2017.4.40c1`。
- 來源 ZIP SHA-256：`746fd686388cff23b5225a1677b7c9bf7eafdc3415919997ac2d7d9795a6d63e`。
- 同資料夾的 `StarWarfare2.xapk` 也包含真正遊戲 APK 與 OBB。`uptodown-com.ifreyr.sw2.apk` 是下載器，沒有 Unity 遊戲資料。
- 遊戲內同時存在舊版 `Avatar06_head-head2` 與新版 `Avatar06_head-Material #43`。舊的 `Avatar06_head.png` 不適用新版 `head` 網格；兩者 UV 不同。此前錯配的 OBJ/PNG 不能當作 UV 判斷依據。

新版頭盔的實際鏈結：

| 項目 | 原始名稱 / 檔案識別 |
| --- | --- |
| Renderer prefab | `124d64a8e6b606e48b340e549ea6d15e`，`head` |
| Mesh | `9cb1ea6de74a23344a8ccd8c97cd240a`，`head`，775 頂點、974 三角面 |
| Material | `Avatar06_head-Material #43` |
| `_RGBA` | `sw_06_head_d.png`，512 × 512 |
| `_normalmap` | `sw_06_head_n.png`，256 × 256 |
| `_lightTex` | `sw_06_head_l.png`，512 × 512 |

三張 PNG 是原始 Unity Texture2D 解碼後的未修改內容。配對來自材質的 PPtr 鏈結，沒有按檔名猜測、重繪或換 UV。甲片邊緣與凹刻主要由原始法線貼圖補足；帽脊、耳罩、面罩輪廓與頰甲厚度則有實際網格。

## JSON 座標與骨架

- `positions_raw`：原 Mesh 頂點，Z 向上、面向 -Y。
- `positions` / `normals`：原 Unity 物件旋轉後 `(x, z, -y)`，Y 向上、面向 +Z。
- `positions_game` / `normals_game`：供現有 Godot 模型比較的 `(-x, z, y)`，Y 向上、面向 -Z，保持三維座標手性。
- `uv`：原始 UV0；V=0 位於圖片底部。轉到 Godot 所用 UV 慣例時只在建置流程統一處理一次。
- `submeshes`：每個材質的三角頂點索引。原始法線與繞序均保留；匯入 Blender 時依引擎慣例處理面方向。
- `bone_names`、`bone_indices`、`bone_weights`、`bind_poses_raw`、`transforms`：保留原始綁定資訊，不直接假設兩代遊戲骨架休息姿勢完全相同。

焊接相同座標作診斷後，頭盔包含一個主殼（673 原始頂點）與兩個独立耳罩（各 51 頂點）；面甲、帽脊與呼吸器是主殼的一部分，並非可任意拆移的獨立元件。這個診斷未修改保存的拓撲。

## 重現

```powershell
py -3.13 tools/armor_rework/audit_sw2_thunder.py --source E:/05_Assets/godot遊戲素材/com.ifreyr.sw2.zip
```

輸出位於 `test_output/thunder_v4_source_audit`。工具會透過實際材質鏈結找齊新舊四件網格，輸出原始頂點、UV、法線、骨架、材質與配套 PNG；不改寫來源容器或正式遊戲資產。

已用新版四件原始網格、正確 UV、原 diffuse/normal/light 貼圖在 Blender 製作 `full_front`、`full_3q`、`full_back`、`full_back_3q`、`head_front`、`head_3q`、`head_back`、`head_back_3q` 診斷圖。它們是 SW2 原始資產的工作室參考渲染，不是目前 Godot 遊戲實拍。
