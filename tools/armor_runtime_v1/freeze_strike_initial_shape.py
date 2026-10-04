"""Freeze the actual mapped v3 head before its crown-only shape refinement."""
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/strike_runtime_v1'
OUT = WORK / 'revisions/head_v3_before_crown_shape_refinement'
assert not (OUT / 'snapshot.json').exists(), 'Existing immutable revision is never replaced'
paths = [
    'assets/armors/strike_v1/strike.scn', 'assets/armors/strike_v1/strike.glb',
    *[f'assets/armors/strike_v1/{label}_diffuse.png' for label in ['head', 'body', 'shoulder', 'hand', 'foot']],
    *[f'docs/art/strike_runtime_v1/build/{name}' for name in ['source.json', 'target.json', 'geometry.json', 'strike_master.blend']],
    'tools/armor_runtime_v1/shapes/strike.py',
    'docs/art/strike_runtime_v1/runtime_config.json', 'docs/art/strike_runtime_v1/generation_inputs.json',
    *[f'docs/art/strike_runtime_v1/review/head_v3_preview/{version}_head_{view}.png'
      for version in ['original', 'new'] for view in ['front', 'side', 'rear', 'quarter']],
]
records = {}
for relative in paths:
    source = ROOT / relative
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    data = target.read_bytes()
    records[relative] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
record = {'stage': 'mapped_head_v3_initial_shape_before_crown_refinement',
          'created_at_utc': datetime.now(timezone.utc).isoformat(),
          'files': records, 'count': len(records),
          'note': 'Actual native v3 mapped preview and initial geometry; not final-engineering PASS.'}
(OUT / 'snapshot.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
print('STRIKE_PRE_CROWN_FREEZE_PASS', len(records), hashlib.sha256((OUT / 'snapshot.json').read_bytes()).hexdigest())
