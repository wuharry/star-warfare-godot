"""Render the offline comparison page from the reviewed analysis data."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/armor_style_comparison_v1"
TEMPLATE = Path(__file__).with_name("review_template.html")


def main() -> None:
    data = json.loads((WORK / "analysis.json").read_text(encoding="utf-8-sig"))
    if {armor["id"] for armor in data["armors"]} != {"viper", "fortune"}:
        raise ValueError("Comparison must contain the current Viper and Fortune.")
    template = TEMPLATE.read_text(encoding="utf-8")
    if template.count("__ANALYSIS_JSON__") != 1:
        raise ValueError("Expected one embedded analysis data marker.")
    embedded = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    embedded = embedded.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    output = WORK / "index.html"
    output.write_text(template.replace("__ANALYSIS_JSON__", embedded), encoding="utf-8")
    print(f"Comparison page written: {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
