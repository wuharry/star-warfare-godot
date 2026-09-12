"""Persist a generated candidate and its provenance without approving it."""
import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('source')
parser.add_argument('generated')
args = parser.parse_args()
manifest = json.loads((ROOT / 'assets/equipment_refined/manifest.json').read_text(encoding='utf-8'))
job = next(job for job in manifest['textures'] if job['source'] == args.source)
target = ROOT / job['output'].removeprefix('res://')
shutil.copyfile(args.generated, target)
record = {'source': args.source, 'generated': args.generated, 'output': job['output'],
          'prompt': job['prompt'] + ' Extremely restrained restoration: do not intensify wear or existing glow. Preserve exact original luminance.',
          'status': 'generated_pending_review'}
directory = ROOT / 'test_output/equipment_refinement/records'
directory.mkdir(exist_ok=True)
(directory / (target.stem + '.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
print('CANDIDATE_SAVED', target.name)
