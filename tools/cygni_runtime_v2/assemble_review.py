"""Assemble same-camera evidence from Godot captures, without editing textures."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/cygni_runtime_v2'
ENGINE = WORK / 'review/engine'


def font(size):
    for name in ['/System/Library/Fonts/STHeiti Medium.ttc',
                 '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
                 'C:/Windows/Fonts/msjh.ttc']:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    print('Review labels: CJK font unavailable; use existing committed sheets.')
    return ImageFont.load_default(size=size)


def sheet(images, labels, target):
    height = images[0].height
    out = Image.new('RGB', (sum(im.width for im in images), height+44), (12,16,19))
    draw = ImageDraw.Draw(out)
    x = 0
    for im, label in zip(images, labels):
        out.paste(im, (x,44))
        draw.text((x+18,9), label, font=font(22), fill=(220,230,235))
        x += im.width
    out.save(WORK/'review'/target)


def main():
    old = Image.open(ENGINE/'original_diffuse_front.png').convert('RGB')
    new = Image.open(ENGINE/'new_diffuse_front.png').convert('RGB')
    sheet([old,new], ['原版 Cygni','原模型局部改造＋新貼圖'], 'comparison_front.png')
    sheet([Image.open(ENGINE/'family_original_10_front.png').convert('RGB'),new,
           Image.open(ENGINE/'family_original_12_front.png').convert('RGB')],
          ['原版 Phoenix','新版 Cygni','原版 Andromedae'], 'family_comparison.png')
    previous = Image.open(WORK/'generation_records/continuous_head/previous_checkpoint/comparison_front.png').convert('RGB').crop((640,44,1280,764))
    # Identical camera and identical crop window; no per-head size alignment.
    crop = (160,35,480,320)
    sheet([im.crop(crop) for im in [old,previous,new]],
          ['原版','上一版：碎片化','這次：局部改造'], 'head_before_after.png')
    out = Image.new('RGB', (1280,760), (12,16,19))
    draw = ImageDraw.Draw(out)
    for i in range(8):
        pic = Image.open(ENGINE/f'new_reload_{i:02d}.png').convert('RGB')
        pic.thumbnail((320,340))
        x,y = (i%4)*320,(i//4)*380
        out.paste(pic,(x,y+32))
        draw.text((x+12,y+5),f'換彈 {i+1}/8',font=font(16),fill=(220,230,235))
    out.save(WORK/'review/reload_sheet.png')
    print('CYGNI_REVIEW_SHEETS_PASS identical camera/crop, no texture editing')


if __name__ == '__main__':
    main()
