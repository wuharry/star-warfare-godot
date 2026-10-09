"""Archive native imagegen output bytes and attach the prepared exact prompt."""
import argparse
import json
import shutil
import struct
from pathlib import Path
from prepare_generation import ROOT, BASE, sha
from first_integration_contract import BASE_PROMPT_SHA256, verify_reference


def validate_plan(plan):
    """Read-only checks must finish before any archive/history is written."""
    base = ROOT / plan['base_prompt']
    assert base.resolve() == BASE.resolve(), 'Wrong required base prompt'
    assert sha(base) == plan['base_prompt_sha256'] == BASE_PROMPT_SHA256, 'Required base prompt bytes changed'
    prompt = ROOT / plan['prompt']
    assert sha(prompt) == plan['prompt_sha256'], 'Prepared prompt bytes changed'
    assert base.read_text(encoding='utf-8') in prompt.read_text(encoding='utf-8'), 'Prepared prompt omitted the required base'
    assert len(plan['references']) == len(plan['reference_images']) >= 2, 'Prepared reference order/count is invalid'
    for reference, actual_path in zip(plan['references'], plan['reference_images']):
        verify_reference(reference, actual_path, root=ROOT)


def register_generation(slug, label, native):
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    plan = next(row for row in json.loads((work/'generation_plan.json').read_text()) if row['label']==label)
    validate_plan(plan)
    path = work/'generation_inputs.json'
    records = json.loads(path.read_text()) if path.exists() else []
    attempt = sum(row['label']==label for row in records)+1
    archive = work/f'generated/{label}_attempt_{attempt:02}.png'
    assert not archive.exists()
    native = Path(native)
    raw = native.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    size = list(struct.unpack('>II', raw[16:24]))
    assert size[0] == size[1] and size[0]>=512
    shutil.copyfile(native, archive)
    for row in records:
        if row['label']==label:
            row['selected']=False
    record = {**plan, 'variant':plan.get('variant', 'original_based_v1'), 'tool':'builtin.image_gen', 'selected':True,
              'generated_file':str(native), 'archive':archive.relative_to(ROOT).as_posix(),
              'archive_sha256':sha(archive), 'output_size':size,
              'output':f'assets/armors/{slug}_v1/{label}_diffuse.png',
              'user_authorized_engineering_limit':.20, 'status':'native_generated_pending_runtime_visual_review'}
    records.append(record)
    path.write_text(json.dumps(records, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(slug.upper()+'_'+label.upper()+'_NATIVE_ARCHIVED '+sha(archive))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=['atom', 'pegasus'], required=True)
    parser.add_argument('--label', choices=['head', 'body', 'shoulder', 'hand', 'foot'], required=True)
    parser.add_argument('--native', type=Path, required=True)
    args = parser.parse_args()
    register_generation(args.armor, args.label, args.native)

if __name__=='__main__':
    main()
