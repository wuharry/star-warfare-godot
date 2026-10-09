"""Prepare an exact native-image retry; keep the preceding runtime evidence."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/thunder_draft_v3'
sys.path.insert(0, str(ROOT / 'tools/armor_runtime_v1'))
from prepare_generation import BASE
from first_integration_contract import BASE_PROMPT_SHA256


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(attempt=2):
    history = json.loads((WORK / 'generation_inputs.json').read_text(encoding='utf-8'))
    assert attempt in (2, 3) and len(history) + 1 == attempt
    assert sha(BASE) == BASE_PROMPT_SHA256
    old_review = WORK / f'review/iterations/attempt_{attempt - 1:02}'
    assert not old_review.exists(), 'Do not overwrite previous iteration evidence'
    old_review.mkdir(parents=True)
    shutil.copytree(WORK / 'review/engine', old_review / 'engine')
    for path in [WORK / 'build/compile_report.json', WORK / 'review/runtime_test.json',
                 WORK / 'runtime_config.json']:
        shutil.copyfile(path, old_review / path.name)
    refs = [
        ('assets/models/player/animated/armor_textures/09_head_1d5d05de7b53_2x.png', 'true_original_uv_layout_authority'),
        (f'docs/art/thunder_draft_v3/generated/head_attempt_{attempt - 1:02}.png', 'previous_native_atlas_material_mapping_only'),
        ('docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png', 'current_gallery_preferred_art_design_authority'),
        (f'docs/art/thunder_draft_v3/review/iterations/attempt_{attempt - 1:02}/engine/new_head_{"front" if attempt == 2 else "rear"}.png', 'actual_previous_runtime_mapping_diagnostic'),
    ]
    snapshots = WORK / f'generation_references/attempt_{attempt:02}'
    snapshots.mkdir(parents=True, exist_ok=True)
    rows = []
    for i, (relative, role) in enumerate(refs):
        source = ROOT / relative
        snapshot = snapshots / f'{i}_{source.name}'
        assert not snapshot.exists()
        shutil.copyfile(source, snapshot)
        rows.append({'path': relative, 'snapshot': snapshot.relative_to(ROOT).as_posix(),
                     'sha256': sha(source), 'role': role})
    addendum = '''

THUNDER C07 — SECOND NATIVE ATLAS PASS AFTER ACTUAL MODEL REVIEW
The references in order are: (1) TRUE ORIGINAL SW1 side/half-head UV atlas, sole immutable layout authority; (2) previous native generated atlas, working material mapping only; (3) user-confirmed CURRENT GALLERY B DRAFT, the sole helmet design authority; (4) actual prior model front, diagnostic only. Return only the entire edited flat opaque square atlas using exactly Image1's original charts. Preserve UV outlines, normalized layout, orientation, scale, padding and mirror continuity. No repacking, chart additions or perspective render.
Improve Image2 toward Image3, using Image4 to avoid recreating its visible mistakes. Keep the integrated STEEL/NAVY BLUE broad central crown band and adjacent blue crown panels. The geometry is separately being rounded into a low continuous crown; paint the upper chart as one attached structural rib, no swept razor fin or floating thin wing. Preserve the original small gold service insets, rear accents and blue ear with restrained gold ring. Reduce long white scratch seams and uniform white edge tracing: broad quiet painted blue planes, soft shading, sparse tiny corner chips.
The actual model's golden glass currently has a huge sharp bright V reflection and looks like two deep diagonal eye grooves. Replace this with ONE coherent warm amber-orange visor, softly shaded, broad restrained gold reflection, no white V, no double columns, no eye cavities, no inset diagonal grooves, no dark center seam. Keep a readable gold-orange midtone like Image3. Keep the original actual glass/chart sampling region and its boundary: do not move glass onto the ear, forehead or neck. The forehead/brow remains blue but should read as a subtle structural band with a central downward taper rather than two aggressive deep brow ridges. The newly fitted mesh separately controls the brow outline.
The atlas's small bottom-left central chin currently reads as a huge BLACK BLOCK when mirrored on Image4. Repaint this existing chin exterior STEEL BLUE to connect continuously into the blue cheek guards, matching Image3's compact blue lower face frame. Retain only ONE small rectangular GRAPHITE vent/inset centered across the shared joining edge. Use a narrow soft shadow around it; do not paint both mirrored sides as independent boxes or exterior black borders. Preserve black neck cloth and opaque padding. Do not add teeth, respirator tubes, skulls, large nose or new lower visor panes.
This is a head-only native repaint on original UVs; original-based cumulative position/dimension limit20% is enforced separately and inherited body/hands/feet are frozen. Use broad softly shaded Viper/Fortune hand-painted game texture language, with Thunder's distinct blue/gold identity. Output a complete game-ready atlas, no text, guide marks, labels, character rendering or watermark. Selected native PNG bytes must be usable unchanged, no postpaint, tint, crop or resampling.
'''
    if attempt == 3:
        addendum = '''

THUNDER C07 — TARGETED BLACK NECK CHART COVERAGE REPAIR
References: Image1 is the immutable TRUE ORIGINAL SW1 atlas and exact UV-layout authority. Image2 is the selected recent native atlas; preserve its blue crown, blue ear/gold service accents, warm orange visor, blue cheeks and compact chin unchanged. Image3 is the user-confirmed current-gallery B draft. Image4 is the actual rear model diagnosing a mapped-texture defect. Output only the complete square flat opaque atlas. Keep all original normalized UV charts, outlines, locations, orientations, scale, mirrored joins and padding. Do not crop, repack, move charts or render a character.
Make one precise material correction to Image2: its bottom-right BLACK neck/underside rectangular chart is too short. The source chart's lower vertices reach normalized V=0.989; Image2's black ends around V=0.92 and leaves gray padding which becomes the BIG GRAY PANEL below the helmet on Image4. Restore the COMPLETE original black rectangle coverage: the entire lower-right region from normalized U=0.46 through 1.00 and V=0.84 through 1.00 must be opaque very dark charcoal/black like Image1, including the bottommost edge. This is an actual sampled black under-helmet/neck surface, not unused padding. Paint the whole rectangle with a continuous near-black charcoal base, only a subtle broad black cloth shadow if needed. No gray bottom strip, gray exposed gaps, blue or gold outlines, labels or background canvas inside this rectangle. Original neighboring left chin/cheek charts must remain unchanged.
Keep Image2's rest of the blue/gold head atlas and its material sampling boundaries unchanged: do not repaint the crown, add fins, rearrange the visor or increase scratches. The geometry is already separately fitted and bounded. Gold glass remains ONE continuous warm orange-gold pane without two eye grooves or a center dark seam. Crown stays navy/steel blue, quiet softly shaded hand-painted planes in Viper/Fortune language. Keep original black padding opaque. Final image must be usable as game diffuse unchanged, with the exact original bottom-right rectangle fully black to avoid the visible gray-neck artifact. No technical marks, watermark, text or postprocessing required.
'''
    prompt = WORK / f'prompts/head_attempt_{attempt:02}.txt'
    assert not prompt.exists()
    prompt.write_text(BASE.read_text(encoding='utf-8') + addendum, encoding='utf-8', newline='\n')
    plan = [{'label': 'head', 'attempt': attempt, 'variant': 'thunder_draft_v3',
             'base_prompt': BASE.relative_to(ROOT).as_posix(), 'base_prompt_sha256': sha(BASE),
             'prompt': prompt.relative_to(ROOT).as_posix(), 'prompt_sha256': sha(prompt),
             'references': rows, 'reference_images': [r['snapshot'] for r in rows]}]
    (WORK / 'generation_plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'prompt': prompt.read_text(encoding='utf-8'),
                      'referenced_image_paths': [str(ROOT / r['snapshot']) for r in rows],
                      'transparent_background': False}, ensure_ascii=False))


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--attempt', type=int, default=2)
    prepare(parser.parse_args().attempt)
