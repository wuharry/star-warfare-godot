"""Same-height review layout; crop/resize only, never repaint source assets."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "docs/art/armor_runtime_v1/style_base_v1"


def main() -> None:
    inputs = [
        (BASE / "references/original_cygni_front.png", (126, 70, 514, 680), "ORIGINAL GAME / raw mesh + diffuse"),
        (BASE / "cygni_style_trial_v1.png", (131, 72, 522, 744), "BASE PROMPT v1 / proportion drift"),
        (BASE / "cygni_style_trial_v2.png", (130, 44, 522, 737), "CORRECTED v2 / style reference only"),
    ]
    sheet = Image.new("RGB", (1140, 635), "#0c1013")
    draw = ImageDraw.Draw(sheet)
    provenance = []
    for i, (path, crop, label) in enumerate(inputs):
        with Image.open(path) as source:
            tile = source.convert("RGB").crop(crop)
            width = round(tile.width * 550 / tile.height)
            tile = tile.resize((width, 550), Image.Resampling.LANCZOS)
            sheet.paste(tile, (i * 380 + (380 - width) // 2, 48))
        draw.text((i * 380 + 14, 16), label, fill="#dce2e9")
        draw.line((i * 380 + 20, 598, (i + 1) * 380 - 20, 598), fill="#536071")
        provenance.append({"source": str(path.relative_to(ROOT)), "crop": crop,
                           "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    draw.text((14, 612), "Equal full-character display height; bitmap v2 is NOT a skinned 3D asset. No lighting or pixels repainted.", fill="#c5ced9")
    sheet.save(BASE / "cygni_same_height_comparison.png")
    (BASE / "comparison_record.json").write_text(json.dumps({
        "inputs": provenance, "display_character_height": 550,
        "operations": "manual review crops, uniform resize preserving aspect, layout and labels only",
        "limitations": "Image-plane silhouette comparison only; no geometric / animation acceptance",
    }, indent=2) + "\n")
    print("STYLE_REVIEW_COMPOSITION_PASS")


if __name__ == "__main__":
    main()
