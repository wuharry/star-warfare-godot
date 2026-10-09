"""Create a mesh-only UV placement diagram, never paint the game atlas.

The image generator receives this new technical diagram as a third reference.
Selected diffuse PNGs are always untouched native imagegen outputs.
"""
import argparse
import json
import shutil

from PIL import Image, ImageDraw

from prepare_generation import BASE, ROOT, sha


def prepare_atom(guide_revision=2):
    slug = 'atom'
    work = ROOT / 'docs/art/atom_runtime_v1'
    config = json.loads((work / 'runtime_config.json').read_text())
    source = json.loads((ROOT / config['source']).read_text())
    row = source['parts']['ArmorBody_07']['surfaces'][1]
    # Entirely new technical drawing from coordinates. No diffuse image pixels
    # are read, composited, tinted, cropped or otherwise modified here.
    size = 1254
    guide = Image.new('RGB', (size, size), (28, 33, 41))
    draw = ImageDraw.Draw(guide)
    for start in range(0, len(row['indices']), 3):
        points = [tuple(round(c * size) for c in row['uv'][i]) for i in row['indices'][start:start + 3]]
        draw.line(points + [points[0]], fill=(110, 120, 135), width=2)
    rect = (round(.0288 * size), round(.55 * size), round(.065 * size), round(.615 * size))
    draw.rectangle(rect, fill=(0, 240, 240), outline=(245, 250, 255), width=3)
    draw.line([(rect[2] + 5, sum(rect[1::2]) // 2), (310, 735)], fill=(0, 240, 240), width=3)
    draw.text((315, 725), 'CYAN BOX ONLY HERE - FRONT CHEST', fill=(0, 240, 240))
    draw.text((315, 750), 'left join u .0288; v .55 to .615', fill=(245, 250, 255))
    # Later diagrams deliberately show only the desired destination. An
    # orange erase marker in v2 was mistaken for the output destination.
    if guide_revision == 2:
        draw.rectangle((30, 440, 85, 620), outline=(250, 110, 65), width=3)
        draw.text((95, 475), 'ERASE OLD BOX ABOVE', fill=(250, 110, 65))
    guide_path = work / f'guides/body_chest_placement_v{guide_revision}.png'
    assert not guide_path.exists()
    guide.save(guide_path)
    history = json.loads((work / 'generation_inputs.json').read_text())
    parent = next(item for item in history if item['label'] == 'body' and item['selected'])
    attempt = sum(item['label'] == 'body' for item in history) + 1
    references = []
    for index, (path, role) in enumerate([
        (ROOT / parent['archive'], 'edit_target_previous_attempt'),
        (ROOT / 'docs/art/original_armors_v1/images/c08_concept.png', 'approved_body_design'),
        (guide_path, 'technical_uv_placement_guide_not_output_colors'),
    ]):
        snapshot = work / f'input_snapshots/body_retry{attempt}_{index}_{path.name}'
        assert not snapshot.exists()
        shutil.copyfile(path, snapshot)
        references.append({'path': path.relative_to(ROOT).as_posix(),
                           'snapshot': snapshot.relative_to(ROOT).as_posix(),
                           'sha256': sha(snapshot), 'role': role})
    prompt_path = work / f'prompts/body_attempt_{attempt:02}.txt'
    assert not prompt_path.exists()
    prompt = BASE.read_text(encoding='utf-8') + '''

ATOM FRONT CHEST WINDOW - SINGLE PRECISE PLACEMENT FIX
Image1 is the exact atlas edit target. Image2 the Atom design authority. Image3 is a NEW TECHNICAL UV diagram, NOT output colors or art. Its cyan filled rectangle marks the EXACT desired position on Image1. Match the rectangle location in Image3 precisely; do not copy its wireframe, labels, arrows, orange lines or background into the output.
Erase the existing cyan window at the left edge UPPER third of Image1 completely, restore the blue armor plate and black cloth beneath the old bezel. Draw ONE narrow cyan rectangular half-window and graphite frame ONLY at the filled cyan rectangle of Image3: normalized x .0288 to .065, y .55 to .615; native 1254 pixels x36..82, y690..771. Touch the left shared join so the mirror makes ONE center-front window. Its middle is about halfway down the atlas, considerably LOWER than the current window. The desired panel is the LARGE BLUE HEXAGON at the left edge, BETWEEN two diagonal PURPLE stripes: replace the LEFT HALF of this blue hexagon with a framed CYAN WINDOW, leave its right half blue. The window is INSIDE the large blue hexagon, not above it. Keep the long horizontal blue lower-chest strip below it. Add a small steel connector immediately below the window. Keep every other chart, thigh lamp, cloth region, outline, padding and color exactly as Image1. Only move this one cyan chest window to the diagram's desired position; no extra front boxes, no cyan on collar/back/crotch. Output only the complete edited opaque diffuse atlas, no diagram marks.
'''
    prompt_path.write_text(prompt, encoding='utf-8', newline='\n')
    plans_path = work / 'generation_plan.json'
    plans = json.loads(plans_path.read_text())
    plan = next(item for item in plans if item['label'] == 'body')
    plan.update(prompt=prompt_path.relative_to(ROOT).as_posix(), prompt_sha256=sha(prompt_path),
                references=references, reference_images=[item['snapshot'] for item in references])
    plans_path.write_text(json.dumps(plans, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'ATOM_BODY{attempt:02}_PLACEMENT_PREPARED technical drawing only')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--guide-revision', type=int, default=2)
    args = parser.parse_args()
    prepare_atom(args.guide_revision)
