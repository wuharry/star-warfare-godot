"""Freeze the delivered v6 before changing helmet coverage, never rewrite it."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/art/titan_neck_coverage_v2/revisions/before_shell_fit_v7'


def main():
    assert not (OUT / 'snapshot.json').exists(), 'Completed before snapshots are immutable'
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', commit], cwd=ROOT, text=True).splitlines()
    prefixes = ('assets/armors/titan_v1/', 'docs/art/titan_runtime_v1/build/',
                'docs/art/titan_runtime_v1/revisions/helmet_refinement_v6/',
                'docs/art/titan_runtime_v1/review/helmet_v6',
                'docs/art/titan_neck_mix_v1/review/after/',
                'docs/art/titan_neck_mix_v1/review/after_test_shared_finite/')
    exact = {'docs/art/titan_runtime_v1/' + p for p in ('runtime_config.json', 'manifest.json', 'README.md', 'index.html')}
    exact |= {'docs/art/titan_runtime_v1/review/' + p for p in ('original_scene_invariants.json', 'runtime_test.json', 'roundtrip_test.json', 'neck_contract_gate.json')}
    exact |= {'tools/armor_runtime_v1/' + p for p in ('shapes/titan.py', 'build.py', 'update_titan_helmet.gd', 'validate_titan_helmet.py', 'neck_contract.gd')}
    exact |= {'docs/art/titan_neck_mix_v1/' + p for p in ('README.md', 'index.html', 'prompts/mandatory_neck_interface.txt')}
    rows = []
    for relative in paths:
        if relative not in exact and not relative.startswith(prefixes):
            continue
        data = subprocess.check_output(['git', 'show', f'{commit}:{relative}'], cwd=ROOT)
        if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
            expected = re.search(rb'oid sha256:([a-f0-9]{64})', data).group(1).decode()
            data = (ROOT / relative).read_bytes()
            assert hashlib.sha256(data).hexdigest() == expected, relative
        target = OUT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        rows.append({'original_path': relative, 'snapshot_path': target.relative_to(ROOT).as_posix(),
                     'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    snapshot = {'status': 'FROZEN_TITAN_V6_BEFORE_SHELL_FIT', 'source_commit': commit,
                'scope': 'Exact delivered v6 shell, original neck interface and exposed-neck evidence; no image editing.',
                'files': rows}
    path = OUT / 'snapshot.json'
    path.write_text(json.dumps(snapshot, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'status': 'PASS', 'source_commit': commit, 'files': len(rows),
                      'snapshot_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
