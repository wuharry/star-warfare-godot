"""Publish byte-identical Godot captures, rejecting stale runtime resources."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / 'test_output/thunder_helmet_comparison'
DEST = ROOT / 'docs/art/thunder_helmet_comparison_v5'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--annotation', type=Path, help='User-supplied marked concept PNG')
    args = parser.parse_args()
    captures = {}
    records = {}
    for variant in ['sw2', 'prototype']:
        folder = SOURCE / variant
        manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        scene = ROOT / f'assets/armors/thunder/thunder_{variant}.scn'
        assert manifest['runtime_scene_sha256'] == sha(scene), f'{variant}: stale scene'
        assert manifest['save_unchanged'] and not manifest['failures'], f'{variant}: failed capture'
        assert len(manifest['frames']) == 30, f'{variant}: incomplete capture'
        for resource, expected in manifest['runtime_resource_sha256'].items():
            assert sha(ROOT / resource.removeprefix('res://')) == expected, f'Stale {resource}'
        captures[variant] = manifest
        records[variant] = {'scene': str(scene.relative_to(ROOT)), 'sha256': sha(scene),
                            'frames': {frame['file']: sha(folder / frame['file']) for frame in manifest['frames']}}
    # Creating .gdignore first keeps documentation PNGs/native art out of Godot imports.
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / '.gdignore').write_text('', encoding='utf-8')
    for variant, manifest in captures.items():
        target = DEST / variant
        target.mkdir(exist_ok=True)
        for name in ['manifest.json'] + [frame['file'] for frame in manifest['frames']]:
            shutil.copyfile(SOURCE / variant / name, target / name)
    reference = ROOT / 'docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png'
    shutil.copyfile(reference, DEST / 'reference.png')
    if args.annotation:
        shutil.copyfile(args.annotation, DEST / 'annotated.png')
    assert (DEST / 'annotated.png').is_file(), 'Provide --annotation on first publication'
    html = (HERE / 'preview.html').read_text(encoding='utf-8').replace('__CAPTURES__', json.dumps(captures, ensure_ascii=False))
    (DEST / 'index.html').write_text(html, encoding='utf-8')
    checks = {}
    for name, marker in {
        'validation_v5': 'THUNDER_COMPILER_VALIDATION_PASS',
        'test_sw2_v5': 'THUNDER_ARMOR_PASS',
        'test_prototype_v5': 'THUNDER_ARMOR_PASS',
        'test_default_v5': 'THUNDER_ARMOR_PASS',
        'equipment_v5': 'EQUIPMENT_REFINEMENT_TEST_PASS',
        'menu_v5': 'MENU_EQUIPMENT_TEST_PASS',
    }.items():
        log = ROOT / f'test_output/armor_rework/{name}.log'
        text = log.read_text(encoding='utf-8', errors='replace')
        assert marker in text and 'SCRIPT ERROR' not in text, f'Failed validation: {log}'
        checks[name] = next(line for line in text.splitlines() if marker in line)
    (DEST / 'verification.json').write_text(json.dumps({
        'status': 'ENGINE_CHECKS_PASS', 'checks': checks, 'variants': records,
        'reference_sha256': sha(reference), 'image_processing': 'none; byte-identical native Godot PNGs',
        'visual_review': 'Inspected front, three-quarter, side, rear, low-front, visor, respirator and level captures. Artistic preference remains for user comparison.',
        'known_warning': 'Existing game/fixture font and CanvasItem resource cleanup warnings at capture process exit.',
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'THUNDER_HELMET_PREVIEW_PASS images=60 output={DEST / "index.html"}')


if __name__ == '__main__':
    main()
