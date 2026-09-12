"""Create the offline animation viewer and per-weapon correspondence table."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "test_output/reload_catalog"
CATEGORIES = {"rifle":"步槍", "shotgun":"散彈槍", "rocket":"火箭筒", "sniper":"狙擊槍", "grenade":"榴彈發射器"}
MOTIONS = {
    "rifle": ["肩前直插", "抬槍斜插", "胸前側收"],
    "shotgun": ["側翻逐顆裝填", "抬槍逐顆裝填"],
    "sniper": ["微抬側轉換匣", "平收換匣"],
    "grenade": ["側轉抽換", "斜抬抽換"],
    "rocket": ["胸前側收", "立筒裝填"],
}
REFERENCES = '''
| 遊戲參考 | 抽樣位置 | 借用的動作 |
| --- | --- | --- |
| [Fortnite OG](https://www.youtube.com/watch?v=H9eEc6LJqo8) | 0:45–1:25 散彈槍、5:20–5:50 狙擊槍、6:04 起發射器 | 側轉露出装填區、分開取彈／插入／復位 |
| [GTA Online 第三人稱換彈](https://www.youtube.com/watch?v=g6oDZf93eys) | 1:40–3:18 步槍／散彈／狙擊槍 | 肩前換匣、抬槍與平收姿勢的差異 |
| [The Division 2](https://www.youtube.com/watch?v=FaAZPqJZuTg&t=270s) | 4:30–5:50 實際射擊與換彈片段 | 操作時收槍並側轉，之後恢復射擊姿勢 |

以上是公開影片抽樣畫面的姿勢比較，未完整播放或量測動作角度。科幻槍的供彈方式是配合本專案原模型設計，沒有宣稱是參考遊戲的相同武器結構。
'''


def main() -> None:
    manifests = {mode: json.loads((OUTPUT / filename).read_text(encoding="utf-8")) for mode, filename in [("stationary", "manifest.json"), ("moving", "manifest_moving.json")]}
    verification = json.loads((OUTPUT / "verification.json").read_text(encoding="utf-8"))
    movement = json.loads((OUTPUT / "movement_verification.json").read_text(encoding="utf-8"))
    models = json.loads((ROOT / "tools/yaml_mesh_converter/reload_parts.json").read_text(encoding="utf-8"))
    if verification["failures"] or movement["failures"]:
        raise ValueError("Resolve reload verification failures before publishing the comparison")
    weapons = {}
    rows = []
    notes = []
    for key, entry in manifests["stationary"]["weapons"].items():
        profile = entry["profile"]
        category = profile["reload_category"]
        motions = MOTIONS[category][:profile["reload_variants"]]
        if key == "gun30":
            motions = ["胸前換艙", "側抬換艙"]
        weapon = {"id": key, "name": entry["name"], "category": CATEGORIES[category], "part": profile["reload_part_label"],
                  "capacity": profile["magazine_size"], "motions": motions, "note": profile["reload_design_note"], "modes": {}, "status": "PASS"}
        for mode, manifest in manifests.items():
            variants = manifest["weapons"][key]["variants"]
            views = {}
            for variant_key, variant in variants.items():
                captures = [c for c in variant["captures"] if mode == "moving" or "frame" in c]
                if not captures:
                    raise ValueError(f"No animation frames for {key}; capture with --sequence")
                for capture in captures:
                    if not (OUTPUT / capture["path"]).is_file():
                        raise FileNotFoundError(capture["path"])
                    view = views.setdefault(capture["view"], {})
                    frame = view.setdefault(capture["time"], {"time": capture["time"]})
                    frame[variant_key] = capture["path"]
            weapon["modes"][mode] = {"duration": next(iter(variants.values()))["duration"], "views": {v: sorted(frames.values(), key=lambda f: f["time"]) for v, frames in views.items()}}
        for view_frames in weapon["modes"]["stationary"]["views"].values():
            if any(len(frame) != len(motions) + 1 for frame in view_frames):
                raise ValueError(f"Incomplete synchronized variant set: {key}")
        if not (OUTPUT / "models" / (key + "_part.png")).is_file():
            raise FileNotFoundError(key + " part inspection image")
        weapon["exploded"] = "faces" in models[key] or models[key].get("existing_parts", False)
        weapons[key] = weapon
        names = "／".join(chr(65+i) + " " + name for i, name in enumerate(motions))
        rows.append(f"| {entry['name']} (`{key}`) | {CATEGORIES[category]} | {weapon['part']} | {weapon['capacity']} | {names} | PASS |")
        if "設計" in weapon["note"] or key == "gun35":
            notes.append(f"- **{entry['name']}**：{weapon['note']}")
    payload = {"weapons": weapons, "viewport": manifests["stationary"]["viewport"], "fps": manifests["stationary"]["fps"]}
    template = (ROOT / "tools/templates/reload_catalog.html").read_text(encoding="utf-8")
    (OUTPUT / "reload_catalog.html").write_text(template.replace("__DATA__", json.dumps(payload, ensure_ascii=False)), encoding="utf-8")
    doc = """# 全武器換彈對應表

24 把武器已接入遊戲，共 55 套換彈動作。每次開始換彈等機率隨機選擇該槍的 A/B 或 A/B/C；散彈槍一次連續裝填只選一次。`reload_variant_override = -1` 是隨機，設為 0/1/2 可固定方案供檢視。

| 武器 | 分類 | 個別彈匣／裝填結構 | 容量 | 動作 | 行為驗證 |
| --- | --- | --- | --- | --- | --- |
""" + "\n".join(rows) + "\n\n## 模型處理\n\n" + "\n".join(notes) + r"""

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
""" + REFERENCES
    (ROOT / "docs/WEAPON_RELOAD_CATALOG.md").write_text(doc, encoding="utf-8")
    print("RELOAD_CATALOG_PREVIEW_PASS weapons=24 variants=55", OUTPUT / "reload_catalog.html")

if __name__ == "__main__":
    main()
