"""Publish unchanged runtime screenshots and reject incomplete or stale captures."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / 'test_output/armor_hd_refinement'
DEST = ROOT / 'docs/art/armor_hd_refinement_v1'
EXPECTED_IDS = [index for index in range(29) if index != 6]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_captures(ids: list[int]) -> list[dict]:
    result = []
    for armor_id in ids:
        key = f'armor_{armor_id:02d}'
        folder = SOURCE / 'sets' / key
        data = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        assert data['id'] == armor_id and data['key'] == key
        assert data['save_unchanged'] and not data['failures'], f'Capture failed: {key}'
        assert data['status'] == 'CAPTURED_REQUIRES_VISUAL_REVIEW', f'Capture failed: {key}'
        versions = ['current'] if armor_id in [0, 1] else ['current', 'baseline']
        expected = {f'{version}_{framing}_{view}.png'
                    for version in versions for framing in ['full', 'close']
                    for view in ['front', 'side', 'rear']}
        assert {frame['file'] for frame in data['frames']} == expected, f'Missing frames: {key}'
        for resource, digest in data['resources'].items():
            assert sha(ROOT / resource.removeprefix('res://')) == digest, f'Stale resource: {resource}'
        for resource, digest in data['baseline_textures'].items():
            assert sha(ROOT / resource.removeprefix('res://')) == digest, f'Baseline changed: {resource}'
        for frame in data['frames']:
            assert sha(folder / frame['file']) == frame['sha256'], f'Capture changed: {key}/{frame["file"]}'
        result.append(data)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sample', help='Comma-separated ids; output stays in test_output, never publishes an incomplete set')
    args = parser.parse_args()
    ids = [int(value) for value in args.sample.split(',')] if args.sample else EXPECTED_IDS
    assert ids and all(value in EXPECTED_IDS for value in ids)
    captures = load_captures(ids)
    target = SOURCE / 'sample_preview' if args.sample else DEST
    target.mkdir(parents=True, exist_ok=True)
    # Keep portable documentation renders out of Godot imports.
    (target / '.gdignore').write_text('', encoding='utf-8')
    for data in captures:
        folder = target / 'sets' / data['key']
        folder.mkdir(parents=True, exist_ok=True)
        for name in ['manifest.json'] + [frame['file'] for frame in data['frames']]:
            shutil.copyfile(SOURCE / 'sets' / data['key'] / name, folder / name)
    payload = json.dumps(captures, ensure_ascii=False).replace('</', '<\\/')
    (target / 'index.html').write_text(
        (HERE / 'preview.html').read_text(encoding='utf-8').replace('__CAPTURES__', payload), encoding='utf-8')
    report = {
        'status': 'CAPTURE_INTEGRITY_PASS_REQUIRES_VISUAL_REVIEW',
        'armor_sets': len([data for data in captures if not data['reference']]),
        'reference_sets': len([data for data in captures if data['reference']]),
        'images': sum(len(data['frames']) for data in captures),
        'image_processing': 'none; byte-identical Godot screenshots',
        'save_unchanged': all(data['save_unchanged'] for data in captures),
        'resource_hashes_checked': True,
        'notes': 'Viper/Fortune are accepted references. Thunder is excluded. Baseline uses saved pre-task textures on identical current geometry and private material copies.',
    }
    (target / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'ARMOR_HD_PREVIEW_PASS images={report["images"]} output={target / "index.html"}')


if __name__ == '__main__':
    main()
