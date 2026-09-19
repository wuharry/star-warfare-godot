"""Decode source game tables and compile the mapped CoM armor baseline.

No inferred SW2 column labels: preserve table names, row order and cell strings.
CoM's executable explicitly loads Config/, not the unused Config_Android copy.
"""
from __future__ import annotations

import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

import UnityPy

from extract_unity_tables import read_tables
from reconstruct_sources import ROOT, WORK, REPORT, digest, save_json

COM_MODELS = {21: "Role04", 22: "Role02", 23: "Role09", 24: "Role05",
              25: "Role06", 26: "Role03", 27: "Role07", 28: "Role10"}


class Reader:
    def __init__(self, data: bytes, position: int = 0):
        self.data = data
        self.position = position

    def integer(self) -> int:
        value, = struct.unpack_from("<i", self.data, self.position)
        self.position += 4
        return value

    def text(self) -> str:
        count = self.integer()
        if not 0 <= count <= len(self.data) - self.position:
            raise ValueError(f"Invalid string at {self.position - 4}: {count}")
        value = self.data[self.position:self.position + count].decode("utf-8")
        self.position = (self.position + count + 3) & ~3
        return value


def sw2_tables() -> dict:
    env = UnityPy.load(str(WORK / "sw2/raw/assets/bin/Data"))
    manager = next(o.read() for o in env.objects if o.type.name == "ResourceManager")
    game_object = next(p.read() for name, p in manager.m_Container if name == "data/datatable")
    obj = next(pair.component.deref() for pair in game_object.m_Component if pair.component.type.name == "MonoBehaviour")
    header = obj.read(check_read=False)
    assert header.m_Script.read().m_ClassName == "DataTableScript"
    raw = obj.get_raw_data()
    reader = Reader(raw, 32)
    count = reader.integer()
    tables = {}
    for _ in range(count):
        name = reader.text()
        row_count = reader.integer()
        assert 0 <= row_count < 100000 and name not in tables
        rows = []
        for _ in range(row_count):
            columns = reader.integer()
            assert 0 <= columns < 1000
            rows.append([reader.text() for _ in range(columns)])
        tables[name] = rows
    assert reader.position == len(raw) and count == 227
    return {"source": {"game": "sw2", "resource": "data/datatable", "file": obj.assets_file.name,
                       "path_id": obj.path_id, "sha256": digest(raw), "consumed_bytes": reader.position},
            "column_semantics": "Raw ordered strings; names/units require consumer-code evidence before gameplay use.",
            "tables": tables}


def xml_record(element: ET.Element) -> dict:
    record = {"tag": element.tag, "attributes": element.attrib}
    if element.text and element.text.strip():
        record["text"] = element.text.strip()
    if len(element):
        record["children"] = [xml_record(child) for child in element]
    return record


def com_tables() -> tuple[dict, dict]:
    inventory = json.loads((REPORT / "com/inventory.json").read_text(encoding="utf-8"))
    configs = {}
    primary = {}
    for record in inventory["objects"]:
        if record["type"] != "TextAsset":
            continue
        for resource in record["resources"]:
            if not resource.startswith(("config/", "config_android/")) or record["name"] in {"EncryptKeys", "ConfigMD5"}:
                continue
            payload = (ROOT / record["export"]).read_bytes()
            if not payload.lstrip().startswith(b"<"):
                configs[resource] = {"source_file": record["file"], "path_id": record["path_id"],
                                     "sha256": digest(payload), "tsv_rows": [line.split("\t") for line in payload.decode("utf-8-sig").splitlines()]}
                continue
            element = ET.fromstring(payload)
            configs[resource] = {"source_file": record["file"], "path_id": record["path_id"],
                                 "sha256": digest(payload), "xml": xml_record(element)}
            xml_path = REPORT / "com/xml" / (resource + ".xml")
            xml_path.parent.mkdir(parents=True, exist_ok=True)
            xml_path.write_bytes(payload)
            if resource.startswith("config/"):
                primary[record["name"]] = element
    rows = {element.attrib["Model"]: element.attrib for element in primary["AvatarConfig"].iter("Avatar")}
    mapped = {}
    for set_id, model in COM_MODELS.items():
        row = rows[model]
        mapped[str(set_id)] = {
            "source_type": int(row["Type"]), "source_model": model, "name": row["TextName"],
            "hp": float(row["HP"]), "shield": float(row["Shield"]),
            "shield_delay": float(row["ShieldRestoreTimeLimit"]),
            "shield_recovery_fraction": float(row["ShieldRestorePercent"]),
            "unlock_level": int(row["UnlockLevel"]),
            "credits": int(row["BuyMoney"].split(";")[0]),
            "premium": int(row["BuyCrystal"].split(";")[0]),
            "icon": row["IconName"], "description": row["Desc"],
            "weakness_source": row["WeaknessDesc"], "level_description_source": row["LevelDesc"],
            "raw": row,
        }
    level_rows = [[int(e.attrib["Level"]), int(e.attrib["Exp"])] for e in primary["LevelExp"].iter("Exp")]
    return ({"game": "com", "selection": "Config/ is loaded by Assembly-CSharp DataConfig.Load*; Config_Android preserved separately.",
             "configs": configs}, {"armor_sets": mapped, "level_exp": level_rows})


def equipment_atlas() -> dict:
    # UIAtlas / UISpriteData field order verified in the supplied managed assembly.
    env = UnityPy.load(str(WORK / "com/raw/assets/bin/Data/f39890c58c894b345a00b8f6890a3dfe"))
    obj = next(o for o in env.objects if o.type.name == "MonoBehaviour")
    header = obj.read(check_read=False)
    assert header.m_Script.read().m_ClassName == "UIAtlas"
    reader = Reader(obj.get_raw_data(), 44)  # MonoBehaviour header + Material PPtr.
    count = reader.integer()
    frames = {}
    for _ in range(count):
        name = reader.text()
        values = [reader.integer() for _ in range(12)]
        x, y, width, height = values[:4]
        assert x >= 0 and y >= 0 and x + width <= 2048 and y + height <= 2048
        frames[name + ".png"] = {"frame": dict(zip(["x", "y", "w", "h"], values[:4])),
                                  "border": values[4:8], "padding": values[8:]}
    assert count == 222 and len(frames) == count
    return {"frames": frames, "meta": {"image": "Equipments.png", "source_pixel_scale": 1,
            "size": {"w": 2048, "h": 2048}, "source": "CoM UIAtlas, f39890c58c894b345a00b8f6890a3dfe"}}


def main() -> None:
    sw1_inventory = json.loads((REPORT / "sw1/inventory.json").read_text(encoding="utf-8"))
    source = next(r for r in sw1_inventory["objects"] if r["type"] == "TextAsset" and r["name"] == "resDataSets")
    binary = ROOT / source["export"]
    assert binary.read_bytes() == (ROOT / "assets/starwarfare_data/resDataSets_raw.bin").read_bytes()
    tables = read_tables(binary)
    save_json(REPORT / "sw1/data_verification.json", {"status": "BYTE_IDENTICAL_ALREADY_APPLIED", "source": source,
              "existing": "assets/starwarfare_data/resDataSets_raw.bin", "table_count": len(tables),
              "runtime": "scripts/core/recovered_game_data.gd"})
    sw2 = sw2_tables()
    save_json(REPORT / "sw2/tables.json", sw2)
    configs, mapped = com_tables()
    save_json(REPORT / "com/tables.json", configs)
    save_json(REPORT / "com/mapped_armor.json", mapped)
    gd = '# Generated by tools/build_source_catalogs.py from supplied CoM Infinity 2.6.\nextends RefCounted\n\n'
    gd += 'const ARMOR_SETS := ' + json.dumps({int(k): v for k, v in mapped["armor_sets"].items()}, ensure_ascii=False, indent=2) + '\n\n'
    # JSON object keys are strings; consumers use str(set_id).
    gd += 'const LEVEL_EXP := ' + json.dumps(mapped["level_exp"]) + '\n'
    (ROOT / "scripts/core/recovered_com_data.gd").write_text(gd, encoding="utf-8")
    save_json(REPORT / "com/equipment_atlas.json", equipment_atlas())
    print(f"SOURCE_TABLES_PASS sw1={len(tables)} sw2={len(sw2['tables'])} com_configs={len(configs['configs'])} mapped_armor=8")


if __name__ == "__main__":
    main()
