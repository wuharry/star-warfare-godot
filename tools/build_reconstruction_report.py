"""Build an offline source -> rules -> runtime report from recovered evidence."""
from __future__ import annotations

import json
from pathlib import Path
import shutil

from reconstruct_sources import ROOT, REPORT, WORK, save_json


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def xml_rows(root: dict) -> list[dict]:
    result = []
    def walk(node: dict, ancestors: list[str]) -> None:
        if node.get("attributes"):
            result.append({"_path": "/".join(ancestors + [node["tag"]]), **node["attributes"]})
        for child in node.get("children", []):
            walk(child, ancestors + [node["tag"]])
    walk(root, [])
    return result


def main() -> None:
    sources = read(REPORT / "sources.json")
    inventories = {g: read(REPORT / g / "inventory.json") for g in ["sw1", "sw2", "com"]}
    media = read(REPORT / "media_mapping.json")["records"]
    datasets = []
    sw1 = read(ROOT / "docs/data/recovered_data_v1/tables.json")
    for table in sw1["tables"]:
        datasets.append({"game": "sw1", "name": f"Table {table['index']:02d}", "rows": table["data"],
                         "note": "表 0 怪物；1–11 攻擊；13 武器；14 裝甲；15 套裝；16 道具；17 軍階；18 升級；19–72 生成；73–75 技能。已接入範圍見 SYSTEMS.md。"})
    sw2 = read(REPORT / "sw2/tables.json")
    for name, rows in sw2["tables"].items():
        datasets.append({"game": "sw2", "name": name, "rows": rows,
                         "note": "完整解碼的原始字串欄位；尚未證明的欄位意義不猜測，也不覆蓋 SW1 同名裝備。"})
    com = read(REPORT / "com/tables.json")
    for name, record in com["configs"].items():
        if "xml" in record:
            rows = xml_rows(record["xml"])
            columns = list(dict.fromkeys(key for row in rows for key in row))
            values = [[row.get(key, "") for key in columns] for row in rows]
        else:
            columns, values = [], record["tsv_rows"]
        datasets.append({"game": "com", "name": name, "columns": columns, "rows": values,
                         "note": "Config/ 是原 DLL 實際載入的本機版本；Config_Android 保留供比較。沒有連線取得伺服器熱更新。"})
    mapped = read(REPORT / "com/mapped_armor.json")["armor_sets"]
    dataset = {"game": "com", "name": "已套用的 8 套裝甲", "columns": ["目前 ID", "名稱", "原模型", "整套 HP", "整套護盾", "恢復延遲（秒）", "每秒恢復比例", "來源等級", "整套點數", "整套秘銀"],
               "rows": [[key, row["name"], row["source_model"], row["hp"], row["shield"], row["shield_delay"], row["shield_recovery_fraction"], row["unlock_level"], row["credits"], row["premium"]] for key, row in mapped.items()],
               "note": "原作金幣／水晶對應本作點數／秘銀。HP／護盾平均分到四個可混搭部件；整套僅收費一次。人物等級 HP 與既有背包加成另計。"}
    datasets.insert(0, dataset)
    summary = read(REPORT / "media_summary.json")
    overview = []
    for source in sources:
        game = source["id"]
        inventory = inventories[game]
        overview.append({"id": game, "name": source["manifest"]["name"], "version": source["manifest"]["version_name"],
                         "sha256": source["sha256"], "objects": len(inventory["objects"]), "counts": inventory["object_counts"],
                         "errors": len(inventory["errors"]), "table_count": len([d for d in datasets if d["game"] == game and d is not dataset])})
    payload = {"overview": overview, "datasets": datasets, "media": media, "summary": summary}
    template = (ROOT / "tools/templates/reconstruction_report.html").read_text(encoding="utf-8")
    (REPORT / "index.html").write_text(template.replace("__REPORT_DATA__", json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")), encoding="utf-8")
    capture = WORK / "store_applied.png"
    if capture.exists():
        shutil.copyfile(capture, REPORT / "store_applied.png")
    save_json(REPORT / "summary.json", {"games": overview, "datasets": len(datasets) - 1, **summary})
    print(f"RECONSTRUCTION_REPORT_PASS games=3 datasets={len(datasets) - 1} media={len(media)}")


if __name__ == "__main__":
    main()
