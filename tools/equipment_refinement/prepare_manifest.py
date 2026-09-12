"""Inventory original assets and persist resumable, per-texture art instructions."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/equipment_refined'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'textures').mkdir(exist_ok=True)
data = json.loads((ROOT / 'test_output/equipment_refinement/sources.json').read_text())
names = {item['key']: item['name'] for item in data['entries']}
effects = {'Bag09_Float_LA_01.png', 'c02.png', 'gong_1.png', 'guiji-0657.png',
           'gun_up_1_gzqgj_l.png', 'jjq.png', 'joke_01.png', 'joke_L.png',
           'lg_002.png', 'shandian_003.png'}
jobs = []
for source, metadata in data['textures'].items():
    identity = hashlib.sha256(source.encode()).hexdigest()[:12]
    output = 'res://assets/equipment_refined/textures/' + identity + '.png'
    owner_names = ', '.join(str(names[key]) for key in metadata['owners'])
    prompt = (
        'Use case: precise-object-edit. Asset type: production game UV albedo texture. '
        f'Primary request: subtly refine the original Star Warfare {owner_names} texture. '
        'The input is the EXACT original UV atlas, NOT a design sketch. Keep every island contour, '
        'position, seam, panel shape, silhouette, emblem and original color at precisely the same '
        'normalized coordinates. Preserve baked hand-painted lighting and the original stylized '
        'sci-fi art. Improve only clarity of existing edges and restrained painted metal or cloth '
        'surface detail. Keep cloth soft; keep painted armor matte; visor colors unchanged. '
        'Output the same flat UV layout, full bleed, same aspect ratio, no margin, labels or '
        'perspective. No new details, panels, rivets, lights, scratches or plastic 3D gloss. '
        'Preserve alpha/transparency when present. This must still unmistakably look like the '
        'original asset when wrapped on its unchanged game mesh.'
    )
    jobs.append({'source': source, 'output': output, **metadata,
                 'status': 'preserve_effect_mask' if Path(source).name in effects else 'pending',
                 'prompt': prompt, 'tool': 'built-in image_gen'})
manifest_path = OUT / 'manifest.json'
if manifest_path.exists():
    previous = {job['source']: job for job in json.loads(manifest_path.read_text())['textures']}
    jobs = [previous.get(job['source'], job) for job in jobs]
manifest = {'direction': 'preserve original identity; refine existing surfaces and edges',
            'concept_reference': '068f4785eee8542217b2e0a3ab4f72b16056f5bf',
            'viper_reference': '415d800', 'status': 'in_progress',
            'entries': [{k:v for k,v in entry.items() if k != 'parts'} for entry in data['entries']],
            'textures': jobs}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'MANIFEST entries={len(data["entries"])} textures={len(jobs)}')
