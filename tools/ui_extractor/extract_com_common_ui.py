"""Recover CoM CommonUI named regions from the supplied atlas XML; pixels unchanged."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "test_output/source_reconstruction/com/text/CommonUI_cfg__sharedassets18.assets_11.bytes"
OUTPUT = ROOT / "assets/recovered_sources/com/ui/CommonUI.json"


def recover() -> dict:
    data = SOURCE.read_bytes()
    root = ET.fromstring(data)
    atlas = root.find("./textureInfoHD/TextureInfo")
    assert atlas is not None and atlas.findtext("textureFile") == "CommonUI@2x"
    frames = {}
    for frame in atlas.findall("./frames/FrameInfo"):
        name = frame.findtext("frameName")
        x, y, w, h = (int(frame.findtext(key)) for key in ("x", "y", "width", "height"))
        assert name and name not in frames and min(x, y) >= 0 and min(w, h) > 0
        assert x + w <= 2048 and y + h <= 2048
        frames[name] = {"frame": {"x": x, "y": y, "w": w, "h": h}}
    return {"frames": frames, "meta": {"image": "CommonUI.png", "size": {"w": 2048, "h": 2048},
            "source_pixel_scale": 1, "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
            "source_sha256": hashlib.sha256(data).hexdigest()}}


def main() -> None:
    result = recover()
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Recovered {len(result['frames'])} named CommonUI regions; reused the existing PNG.")


if __name__ == "__main__":
    main()
