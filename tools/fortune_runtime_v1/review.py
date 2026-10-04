"""Generate the Fortune runtime review page from local delivery evidence.

This tool does not rewrite the armor gallery or claim artistic approval.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/fortune_runtime_v1"


def main() -> None:
    source = json.loads((WORK / "build/source.json").read_text())
    labels = {"ArmorHead_01": ["head"], "ArmorBody_01": ["body", "shoulder"],
              "ArmorHand_01": ["hand"], "ArmorFoot_01": ["foot"]}
    maps = {labels[name][surface]: "../../../" + row["texture"].removeprefix("res://")
            for name, part in source["parts"].items()
            for surface, row in enumerate(part["surfaces"])}
    reports = {}
    for label, filename in [("proportion", "proportion_test.json"),
                            ("runtime", "runtime_test.json"),
                            ("roundtrip", "roundtrip_test.json"),
                            ("master", "delivery_validate.json")]:
        path = WORK / "review" / filename
        reports[label] = json.loads(path.read_text()) if path.exists() else {"status": "NOT RUN"}
    template = Path(__file__).with_name("review_template.html").read_text(encoding="utf-8")
    revision = hashlib.sha256((ROOT / "assets/armors/fortune_v1/head_diffuse.png").read_bytes()).hexdigest()[:12]
    page = template.replace("__SOURCE_MAPS__", json.dumps(maps)).replace("__REPORTS__", json.dumps(reports)).replace("__REVISION__", json.dumps(revision))
    (WORK / "index.html").write_text(page, encoding="utf-8")
    print("FORTUNE_REVIEW_PASS focused comparison page generated; gallery untouched")


if __name__ == "__main__":
    main()
