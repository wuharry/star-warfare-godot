"""Record the rejected chest/back placement and prepare one exact atlas correction."""
import json
import argparse
from pathlib import Path
import shutil
from prepare_generation import ROOT, BASE, sha

WORK = ROOT/'docs/art/atom_runtime_v1'
parser = argparse.ArgumentParser()
parser.add_argument('--attempt', type=int, choices=[2, 3], default=2)
attempt = parser.parse_args().attempt
history = WORK/'revisions/body_wrong_position_attempt_01'
if attempt == 2:
    assert not history.exists(), 'Do not replace the rejected-attempt evidence'
    history.mkdir()
    shutil.copytree(WORK/'review/engine', history/'engine')
    shutil.copyfile(ROOT/'assets/armors/atom_v1/atom.scn', history/'atom.scn')
    shutil.copyfile(WORK/'build/target.json', history/'target.json')
refs = [
    (WORK/f'generated/body_attempt_{attempt-1:02}.png', 'edit_target_previous_attempt'),
    (ROOT/'docs/art/original_armors_v1/images/c08_concept.png', 'approved_body_design'),
    (WORK/('guides/body_uv.png' if attempt==2 else 'guides/body_placement.png'), 'technical_original_uv_guide'),
    (history/'engine/new_diffuse_front.png', 'runtime_mapping_front_check_only'),
    (history/'engine/new_diffuse_rear.png', 'runtime_mapping_back_check_only'),
]
references = []
for number, (path, role) in enumerate(refs):
    snapshot = WORK/f'input_snapshots/body_retry{attempt}_{number}_{path.name}'
    shutil.copyfile(path, snapshot)
    references.append({'path':path.relative_to(ROOT).as_posix(), 'snapshot':snapshot.relative_to(ROOT).as_posix(), 'sha256':sha(snapshot), 'role':role})
prompt = WORK/f'prompts/body_attempt_{attempt:02}.txt'
addendum = '''

REQUIRED PER-ASSET ADDENDUM — ATOM BODY CORRECTION ONLY
Image1 EDIT TARGET is the retained first native body atlas. Image2 is approved C08 concept (design only). Image3 exact ORIGINAL UV wire guide (technical only). Image4 actual current front mapping, Image5 actual current back mapping (diagnostics only, never render characters into atlas).
Fix only the misplaced chest service window. The original atlas is a MIRRORED HALF-BODY layout. UV coordinates below are normalized atlas coordinates, u from LEFT and v from TOP. Do NOT flip v. Every original UV/chart/panel outline stays locked.
FRONT location: the actual center-front mirrored seam is u=0.0288, from v=0.3766 to0.7677, on the LEFT edge of the large left-side torso chart. Paint ONE HALF of the small cyan vertical service window touching this front seam. Its RIGHT HALF frame occupies u=0.0288..0.072, v=0.52..0.62; its cyan glass occupies u=0.0288..0.052, v=0.54..0.60. At u=0.0288 the cyan glass must meet its mirrored partner with no black border. Do NOT paint a complete rectangular box offset from the seam, which would become two boxes. The model mirrors this half into ONE centered full rectangular upper-chest window. The leftmost padding u<0.0288 is not the center of the box.
Remove the OLD front cyan diamond at u=0.0288..0.10, v=0.64..0.71: fill that old diamond and its black rim with continuous muted steel-blue breastplate shading, matching adjacent blue armor. This lower area must no longer contain a glowing diamond. Keep the connected chest panels, violet trim and cloth exactly where they are.
BACK location: the long narrow middle atlas strip is BACK, NOT FRONT. Its mirrored seam is u=0.552, v=0.3676..0.7357. Remove the wrongly placed COMPLETE cyan rectangular window around u=0.51..0.55,v=0.41..0.51. Paint blue/violet service armor there, with at most ONE HALF of a small restrained cyan circular lamp touching u=0.552 centered around v=0.447, so its mirrored copy becomes one rear circle. No pair of cyan rear rectangles. Original other small circular markers may remain at their existing positions.
Preserve all remaining armor planes, palette, chart silhouettes, original openings, broad hand-painted shading and sparse wear. No new border at any mirrored joining edge. Do not increase white edge wear. Return ONLY the complete opaque square flat atlas registered to Image1, no overlay guides, captions, character, UI or text. This is a texture placement repair; actual model and UV remain identical to the true original source.
'''
if attempt == 3:
    addendum += '''
CRITICAL VISUAL PLACEMENT OVERRIDE: Image3 is now a SIMPLE COLOR PLACEMENT DIAGRAM at precisely the same square framing, not the wireframe. The MAGENTA rectangle shows the ONLY correct new chest window location. Repaint Image1 exactly in the corresponding MAGENTA rectangle; its inner CYAN strip touches the LEFT center-front mirror seam. The nearby RED rectangle BELOW it shows the OLD cyan diamond which MUST be ERASED to steel blue, including every cyan pixel there. The RED rectangle in the middle strip marks the wrong rear box to REMOVE. Do not place the new chest window on that middle strip. Never output these magenta/red guide colors or text. Actual art there is a dark framed cyan half-window, and continuous steel-blue armor over the old lower diamond. Merely removing the rear box without adding the front half-window and erasing the lower diamond is an INCOMPLETE EDIT. Keep the rest of Image1 unchanged.\n'''
prompt.write_text(BASE.read_text(encoding='utf-8')+addendum, encoding='utf-8')
plans = json.loads((WORK/'generation_plan.json').read_text())
row = next(row for row in plans if row['label']=='body')
row.update(prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=sha(prompt), references=references, reference_images=[ref['snapshot'] for ref in references])
(WORK/'generation_plan.json').write_text(json.dumps(plans,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if attempt == 2:
    (history/'rejection.json').write_text(json.dumps({'status':'REJECTED_WRONG_FRONT_BACK_UV_PLACEMENT', 'reason':'Front retained old diamond; rectangular cyan box mirrored into two on rear. Must repair atlas against actual original source coordinates.', 'map_sha256':sha(WORK/'generated/body_attempt_01.png'), 'scene_sha256':sha(history/'atom.scn'), 'capture_summary_sha256':sha(history/'engine/capture.json')},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('ATOM_BODY_RETRY_PREPARED immutable first-attempt evidence and exact source UV coordinates')
