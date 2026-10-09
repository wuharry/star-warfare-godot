"""Freeze the delivered Titan v5 resources before the mixed-neck repair."""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/art/titan_neck_mix_v1/revisions/before_neck_fix'


def main():
    assert not (OUT / 'snapshot.json').exists(), 'Never overwrite a completed before snapshot'
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    candidates = list((ROOT / 'assets/armors/titan_v1').glob('*'))
    candidates += list((ROOT / 'docs/art/titan_runtime_v1/build').glob('*'))
    candidates += [ROOT / 'docs/art/titan_runtime_v1' / name for name in ['runtime_config.json', 'manifest.json', 'README.md']]
    candidates += list((ROOT / 'docs/art/titan_runtime_v1/revisions/helmet_refinement_v5').rglob('*'))
    candidates += list((ROOT / 'docs/art/titan_runtime_v1/review').glob('helmet_v5*'))
    candidates += [ROOT / 'tools/armor_runtime_v1' / name for name in ['shapes/titan.py', 'build.py', 'update_titan_helmet.gd', 'validate_titan_helmet.py']]
    files = set()
    for candidate in candidates:
        files.update(candidate.rglob('*') if candidate.is_dir() else [candidate])
    rows = []
    for source in sorted(p for p in files if p.is_file() and '__pycache__' not in p.parts):
        relative = source.relative_to(ROOT).as_posix()
        raw = source.read_bytes()
        before = subprocess.check_output(['git', 'show', f'{commit}:{relative}'], cwd=ROOT)
        if before.startswith(b'version https://git-lfs.github.com/spec/v1'):
            digest = hashlib.sha256(raw).hexdigest()
            assert re.search(rb'oid sha256:([a-f0-9]{64})', before).group(1).decode() == digest
        else:
            # Use the immutable commit blob, independent of checkout EOLs or
            # concurrent authoring of source scripts. Live assets are unchanged.
            raw = before
            digest = hashlib.sha256(raw).hexdigest()
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        assert target.read_bytes() == raw
        rows.append({'original_path': relative, 'snapshot_path': target.relative_to(ROOT).as_posix(),
                     'sha256': digest, 'bytes': len(raw)})
    snapshot = {'status': 'FROZEN_TITAN_V5_BEFORE_NECK_MIX_FIX', 'source_commit': commit,
                'scope': 'Original delivered resources and engineering reports; no art reconstruction or postprocessing.',
                'files': rows}
    (OUT / 'snapshot.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'status': 'PASS', 'source_commit': commit, 'files': len(rows),
                      'snapshot_sha256': hashlib.sha256((OUT / 'snapshot.json').read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
