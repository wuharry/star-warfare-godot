"""Compose actual engine captures; estimate fixed-camera silhouette overlap."""
from pathlib import Path
import json

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "test_output/armor_concept_runtime"
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"


def main() -> None:
    font = ImageFont.truetype(FONT, 26)
    small = ImageFont.truetype(FONT, 18)
    canvas = Image.new("RGB", (1440, 920), (22, 28, 39))
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 14), "Cygni · 同一遊戲內的新舊風格比對", font=font, fill="white")
    labels = [("rejected_flat_v1/armor_11_concept_quarter.png", "上一輪：簡化模型（已停用）"),
              ("armor_11_concept_quarter.png", "這一輪：原比例＋手繪貼圖"),
              ("armor_11_original_quarter.png", "原版：同鏡頭、同骨架、同姿勢")]
    for i, (file, label) in enumerate(labels):
        image = Image.open(WORK / file).convert("RGB")
        image.thumbnail((470, 620))
        canvas.paste(image, (i * 480 + (480 - image.width) // 2, 80))
        draw.text((i * 480 + 18, 52), label, font=small, fill=(220, 225, 236))
        if i:
            tag = "original" if i == 2 else "concept"
            low = Image.open(WORK / f"armor_11_{tag}_quarter_small.png").convert("RGB")
            canvas.paste(low, (i * 480 + 22, 710))
            draw.text((i * 480 + 205, 744), "引擎低解析度\n約 125 px 角色高度", font=small, fill=(200, 208, 224))
    draw.text((24, 880), "風格試稿：金色玻璃、白灰漆面；身體沿用原有 UV 細節。美術風格尚待確認。", font=small, fill=(177, 187, 205))
    canvas.save(WORK / "cygni_painted_comparison.jpg", quality=94)
    results = {}
    for view in ["front", "quarter", "rear"]:
        candidate = Image.open(WORK / f"armor_11_concept_{view}.png").convert("RGB")
        original = Image.open(WORK / f"armor_11_original_{view}.png").convert("RGB")
        assert candidate.size == original.size

        def mask(image: Image.Image) -> set:
            background = image.getpixel((0, 0))
            return {i for i, c in enumerate(image.getdata())
                    if max(abs(c[k] - background[k]) for k in range(3)) > 4}

        a, b = mask(candidate), mask(original)
        results[view] = {"silhouette_iou_estimate": len(a & b) / len(a | b), "viewport": candidate.size}
    report = {"method": "Fixed-camera background difference >4; dark cloth can merge with background. No realignment. Screenshot estimate, not exact mesh geometry.",
              "views": results, "does_not_measure": "Artist style, texture craft or exact concept fidelity"}
    (WORK / "painted_silhouette.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(results))


if __name__ == "__main__":
    main()
