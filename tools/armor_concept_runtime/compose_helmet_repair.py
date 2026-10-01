"""Review composition of actual engine screenshots; never paints textures."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "test_output/armor_concept_runtime"
REVIEW = ROOT / "docs/art/armor_runtime_v1/armor_11/repair_shell_v4/review"
FONT = "/System/Library/Fonts/STHeiti Medium.ttc"


def main() -> None:
    REVIEW.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(FONT, 24)
    small = ImageFont.truetype(FONT, 19)
    canvas = Image.new("RGB", (1320, 390), (22, 28, 39))
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), "Cygni · 3D 頭盔結構比對（灰模仍未完成美術）", font=font, fill="white")
    panels = [
        (ROOT / "docs/art/original_armors_v1/revisions/c12_helmet_fusions_20260929/images/anubis_gold_t_swept.png",
         (310, 15, 670, 320), "已選草稿：造型參考"),
        (WORK / "rejected_floating_v3/armor_11_concept_side.png", (175, 45, 465, 278), "上版側面：已拒絕／停用"),
        (WORK / "repair_armor_11_concept_front.png", (175, 45, 465, 278), "重建灰模：正面"),
        (WORK / "repair_armor_11_concept_side.png", (175, 45, 465, 278), "重建灰模：側面"),
    ]
    for index, (path, region, label) in enumerate(panels):
        frame = ImageOps.contain(Image.open(path).convert("RGB").crop(region), (310, 267))
        x = index * 330 + (330 - frame.width) // 2
        canvas.paste(frame, (x, 85 + (267 - frame.height) // 2))
        draw.text((index * 330 + 15, 56), label, font=small, fill=(220, 225, 236))
    draw.text((20, 362), "新鏡片與外殼共用邊緣；本輪只驗 3D，正式貼圖與其餘裝甲尚未完成。", font=small, fill=(190, 201, 216))
    canvas.save(REVIEW / "helmet_structure_comparison.png")
    # Proportion context uses identical engine cameras, skeleton and pose.
    canvas = Image.new("RGB", (1240, 660), (22, 28, 39))
    draw = ImageDraw.Draw(canvas)
    for i, (tag, label) in enumerate([("concept", "頭盔灰模＋原版身體"), ("original", "原版：相同骨架、鏡頭與姿勢")]):
        frame = Image.open(WORK / f"repair_armor_11_{tag}_quarter.png").convert("RGB")
        canvas.paste(frame, (i * 620, 48))
        draw.text((i * 620 + 20, 14), label, font=font, fill="white")
    canvas.save(REVIEW / "game_proportion_comparison.png")
    print("HELMET_REPAIR_REVIEW_COMPOSED")


if __name__ == "__main__":
    main()
