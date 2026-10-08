"""Copy selected native imagegen PNG bytes, after validating full provenance."""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=['hydra', 'strike', 'titan', 'atom', 'pegasus'], required=True)
    slug = parser.parse_args().armor
    work = ROOT / 'docs/art' / f'{slug}_runtime_v1'
    config = json.loads((work / 'runtime_config.json').read_text())
    if config.get('head_refinement'):
        raise SystemExit('First-integration adoption would restore the old head PNG. Use the active helmet generation_record.json and README workflow.')
    records = json.loads((work / 'generation_inputs.json').read_text())
    selected = [r for r in records if r['selected']]
    assert len(selected) == 5 and {r['label'] for r in selected} == {'head', 'body', 'shoulder', 'hand', 'foot'}
    for row in selected:
        archive = ROOT / row['archive']
        assert sha(archive) == row['archive_sha256'] == sha(Path(row['generated_file']))
        raw=archive.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n'
        size=list(struct.unpack('>II',raw[16:24]))
        assert size[0] == size[1] and size[0] >= 512
        assert row.get('output_size',size) == size
        row['output_size']=size
        prompt = ROOT / row['prompt']
        base = ROOT / row['base_prompt']
        assert sha(prompt) == row['prompt_sha256'] and sha(base) == row['base_prompt_sha256']
        assert base.read_text() in prompt.read_text()
        for ref in row['references']:
            assert sha(ROOT / ref['snapshot']) == ref['sha256']
        output = ROOT / row['output']
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, output)
        assert sha(output) == row['archive_sha256']
        row['status'] = 'native_adopted_pending_runtime_visual_review'
    (work / 'generation_inputs.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')
    print(slug.upper() + '_NATIVE_ADOPT_PASS 5 native PNG bytes unchanged')


if __name__ == '__main__':
    main()
