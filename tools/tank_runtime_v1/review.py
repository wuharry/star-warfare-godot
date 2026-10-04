"""Write Tank review page from current source and measured delivery."""
import json
import hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/tank_runtime_v1'

def main():
    source=json.loads((WORK/'build/source.json').read_text())
    labels={'ArmorHead_02':['head','hand'],'ArmorBody_02':['body','shoulder'],'ArmorHand_02':['hand'],'ArmorFoot_02':['foot']}
    maps={labels[name][sid]:'../../../'+row['texture'].removeprefix('res://') for name,p in source['parts'].items() for sid,row in enumerate(p['surfaces'])}
    template=Path(__file__).with_name('review_template.html').read_text(encoding='utf-8')
    revision=hashlib.sha256((ROOT/'assets/armors/tank_v1/head_diffuse.png').read_bytes()).hexdigest()[:12]
    template=template.replace('__REVISION__',revision)
    chosen=next(row for row in json.loads((WORK/'generation_inputs.json').read_text()) if row['selected'] and Path(row['output']).name=='head_diffuse.png')
    template=template.replace('__HEAD_PROMPT__',str(Path(chosen['prompt']).relative_to(WORK.relative_to(ROOT))).replace('\\','/'))
    (WORK/'index.html').write_text(template.replace('__SOURCE_MAPS__',json.dumps(maps)),encoding='utf-8')
    print('TANK_REVIEW_PASS offline engine / concept / UV comparison written')
if __name__=='__main__':main()
