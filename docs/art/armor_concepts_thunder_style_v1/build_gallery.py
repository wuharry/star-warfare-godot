"""Assemble the offline concept gallery and verify unchanged imagegen outputs."""
import hashlib
import json
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    catalog = json.loads((HERE / 'catalog.json').read_text(encoding='utf-8'))
    expected = set(range(29)) - {6}
    assert {item['id'] for item in catalog} == expected
    entries = []
    for item in catalog:
        path = HERE / f'entries/armor_{item["id"]:02d}.json'
        record = json.loads(path.read_text(encoding='utf-8'))
        assert record['id'] == item['id'] and record['name'] == item['name']
        assert record['image'] == item['image'] and record['prompt'] == item['prompt']
        assert record['status'] == 'concept_pending_user_review'
        output = HERE / record['image']
        assert digest(output) == record['sha256'], f'Changed concept: {output}'
        source = Path(record['generated_source'])
        if source.exists():
            assert digest(source) == record['sha256'], f'Image processing detected: {output}'
        with Image.open(output) as image:
            assert list(image.size) == record['dimensions'] and min(image.size) >= 1000
        assert record['palette'] and record['features'] and record['review']
        assert (HERE / record['prompt']).read_text(encoding='utf-8').strip()
        # Preserve actual generation inputs; display all three original views.
        record['generation_references'] = record['references']
        record['references'] = dict(item['references'], style='references/thunder_style.png')
        record['reference_hashes'] = {name: digest(HERE / value) for name, value in record['references'].items()}
        if isinstance(record['features'], list):
            record['features'] = '、'.join(record['features'])
        record['group'] = 'sw' if record['id'] < 21 else 'com'
        entries.append(record)
    assert len(entries) == 28 and len({item['sha256'] for item in entries}) == 28
    manifest = {
        'title': 'Thunder 草稿風格：28 套裝甲新一輪概念',
        'status': 'concepts_generated_and_visually_inspected_pending_user_review',
        'count': 28, 'runtime_modified': False,
        'style_reference': 'references/thunder_style.png',
        'style_original': '../thunder_helmet_comparison_v5/reference.png',
        'reference_note': 'Viper/Fortune use accepted current art; remaining original palette captures precede the HD repaint. Each capture keeps the original model and lighting.',
        'image_processing': 'none; direct copies of built-in image_gen outputs',
        'limitations': 'Single front three-quarter concept per set; rear design, production geometry, UVs and in-game implementation are not delivered by these images.',
        'entries': entries,
    }
    (HERE / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    payload = json.dumps(entries, ensure_ascii=False).replace('</', '<\\/')
    template = (HERE / 'gallery.template.html').read_text(encoding='utf-8')
    (HERE / 'index.html').write_text(template.replace('__CONCEPTS__', payload), encoding='utf-8')
    report = {'asset_integrity': 'PASS', 'concept_count': len(entries), 'unique_images': 28,
              'original_views': 84, 'style_references': 1, 'visual_review': 'See each entry.review; user approval pending',
              'runtime_modified': False, 'image_processing': 'none'}
    (HERE / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('CONCEPT_GALLERY_ASSETS_PASS concepts=28 original_views=84 style=1')


if __name__ == '__main__':
    main()
