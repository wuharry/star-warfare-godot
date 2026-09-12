"""Copy visually inspected imagegen outputs; do not alter their pixels."""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
manifest_path = ROOT / 'assets/equipment_refined/manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
selected = json.loads((ROOT / 'test_output/equipment_refinement/selected_images.json').read_text())
by_source = {item['source']: item for item in selected}
for job in manifest['textures']:
    if job['source'] not in by_source:
        continue
    item = by_source[job['source']]
    target = ROOT / job['output'].removeprefix('res://')
    shutil.copyfile(item['generated'], target)
    job['status'] = 'approved'
    job['generated_source'] = item['generated']
    if item.get('prompt'):
        job['prompt'] = item['prompt']
    job['review'] = 'UV layout and original identity inspected; in-game review tracked separately'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('SAVED', len(selected), 'reviewed textures')
