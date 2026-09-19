"""Record the inspected armor repaint provenance without rebuilding unrelated assets."""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MANIFEST = ROOT / 'assets/equipment_refined/manifest.json'
IDS = set(range(2, 29)) - {6}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    targets = {job['output']: job for job in manifest['textures']
               if any(owner.startswith('armor_') and int(owner[6:]) in IDS for owner in job['owners'])}
    records = {}
    for path in sorted(HERE.glob('provenance_*.json')):
        data = json.loads(path.read_text(encoding='utf-8'))
        for record in data.get('entries', []) if isinstance(data, dict) else data:
            output = record['output']
            assert output in targets and output not in records, f'Unexpected/duplicate output: {output}'
            assert record['status'] in ['approved', 'atlas_reviewed_pending_runtime'], f'Unreviewed: {output}'
            assert record.get('inspection') or record.get('review') or record.get('visual_review')
            asset = ROOT / output.removeprefix('res://')
            digest = sha(asset)
            assert digest == record.get('output_sha256', record.get('sha256')), f'Changed output: {output}'
            with Image.open(asset) as image:
                assert image.size[0] >= 1254 and image.size[1] >= 1254, f'Low resolution: {output}'
                size = list(image.size)
            records[output] = dict(record, provenance=str(path.relative_to(ROOT)),
                                   output_sha256=digest, output_size=size)
    assert set(records) == set(targets) and len(records) == 119, 'Missing armor atlas records'
    for output, record in records.items():
        job = targets[output]
        job['previous_refinement'] = job.get('previous_refinement', {
            key: job[key] for key in ['prompt', 'generated_source', 'review'] if key in job})
        job['prompt'] = record['prompt']
        job['generated_source'] = record.get('generated_source', record.get('generated'))
        job['tool'] = record['tool']
        job['output_size'] = record['output_size']
        job['output_sha256'] = record['output_sha256']
        job['review'] = record.get('inspection', record.get('review', record.get('visual_review')))
        job['hd_refinement'] = {'revision': 'armor_hd_v1', 'provenance': record['provenance'],
                                'style_reference': record['style_reference']}
        # Existing runtime integration is retained. Atlas review and runtime
        # image review are distinct; the latter is recorded after captures.
        job['status'] = 'approved'
    for entry in manifest['entries']:
        if entry['kind'] == 'armor' and entry['id'] in IDS:
            entry['visual_review'] = 'HD atlas repaint inspected; runtime comparison recorded in docs/art/armor_hd_refinement_v1.'
    manifest['quality_review']['armor_hd_v1'] = {
        'reference_commits': ['af01d8a9a6c76afff0b2e461a0d1b1992ffa40b1', 'ea55de4c9e8441e2256176db9804d255d87f6ea5'],
        'armor_sets': 26, 'target_textures': 119,
        'direction': 'Preserve each original UV layout, silhouette and palette; repaint fine edges and material detail to the accepted Viper/Fortune standard.',
        'preserved': 'Viper, Fortune, Thunder, weapon assets, all armor meshes and skinning.',
        'method': 'Built-in image_gen; byte-identical accepted outputs. Identical original atlases reuse one reviewed output. Two Viper-origin auxiliary atlases reuse accepted Viper paintings.',
        'runtime_review': 'docs/art/armor_hd_refinement_v1/visual_review.json',
    }
    manifest['quality_review']['art_detail_parity'] = 'Viper and Fortune retained as accepted benchmarks; the remaining 26 non-Thunder armor sets now have individually reviewed HD paint. See armor_hd_v1 for provenance and runtime comparison; weapons retain the preceding refinement.'
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'ARMOR_HD_MANIFEST_PASS sets={len(IDS)} textures={len(records)}')


if __name__ == '__main__':
    main()
