"""Prepare targeted C08/C09 edits; never paint or resample diffuse pixels."""
import argparse
import json
import shutil
from pathlib import Path

from prepare_generation import BASE, ROOT, sha


ADDENDA = {
    ('pegasus', 'head'): '''PEGASUS C09 — V3 DESIGN FIDELITY CORRECTION
Image1 is the HALF-HEAD SIDE diffuse atlas EDIT TARGET. Image2 is the approved concept and design authority. Image3 is the actual current model for mapping diagnosis only. Output ONLY Image1's complete edited flat atlas, with precisely the same outer silhouettes, island edges, placement, padding and scale. The separately corrected mesh will narrow the broad brow plates and flatten the central V; do not reproduce the current model's excessive V stair decoration in the paint.
Repaint the entire forehead as simple, softly shaded OFF-WHITE armor with a shallow central brow, matching Image2. REMOVE the current thick black stacked V-chevron outlines and multiple false layered triangular forehead plates: the roof should be broad continuous quiet white planes. REMOVE the large blue outline that frames the huge broad brow plate, and remove all decorative blue cheek diamonds and squares. Keep a few small pale-blue seams only, as in Image2. Remove the wrongly placed three vents near the top center of Image1 (v approximately .14); fill them with uninterrupted white armor.
The actual narrow raised crown RAIL TOP is the slanted polygon with normalized corners (.6127,.2359),(.6473,.1933),(.3010,.2259),(.3097,.2724). Put THREE SMALL black rectangular vent recesses ONLY inside this narrow strip, centers (.390,.240),(.470,.232),(.550,.224), each about .030 wide and .016 high, aligned with its shallow slope. Mirroring makes the two concept rails; never draw extra roof rails or a centered vent bank. The broad plate below this narrow strip remains WHITE and visually quiet, not a separate blue framed wing.
Keep the existing one continuous graphite-black face window in the lower-left, but remove the giant central bright V reflection: use dark glass and ONE restrained soft broad gray reflection. Keep chin and cheek white, with small black vents and sparse pale-blue accents matching Image2. Reduce the white edge scratching, stippled noise and outlined panel maze throughout the entire helmet to the concept's broad matte hand-painted planes with a few small corner chips. Quiet white rear shell and black ribbed rear neck stay in their exact charts. No colored guide marks, text, render, new objects or atlas rearrangement.''',
    ('atom', 'head'): '''ATOM C08 — CROWN SPINE, CHEEK WINDOW AND CALM GLASS
Image1 is the exact native half-head SIDE UV atlas EDIT TARGET. Image2 is the approved Atom concept/design authority. Image3 is the previous actual model for mapping diagnosis only. Image4, when provided, is a new mesh-derived technical placement diagram. Output ONLY the whole edited Image1 diffuse atlas; every original island outline, location, scale, sampled boundary and padding remains exact.

Repaint the entire following original-mesh crown band (the BLUE filled band in Image4 when provided) as a continuous STEEL-BLUE CROWN SPINE in Image1. This strip runs all the way over the helmet, following the original chart's curved TOP boundary from the front center (.234,.107) through (.364,.058),(.593,.038) to the rear center (.791,.143). It must extend along that entire curve with the full width of the actual continuous band; it is NOT just the current tiny blue lamp badge at the top left. The full normalized UV band outline is (.13183,.207),(.20617,.25557),(.21591,.26639),(.28927,.1954),(.31366,.18621),(.48683,.1474),(.56062,.14087),(.66185,.18604),(.73164,.22311),(.82498,.35277),(.83617,.34347),(.87533,.33256),(.93013,.3148),(.921,.2906),(.7905,.1434),(.5925,.0382),(.3642,.0584),(.2341,.1074), then close. Repaint that entire sampled band steel blue, not just a left badge. Blue band areas must lose their old purple paint. The remaining dome sides stay muted violet purple. Keep the ONE central cyan crown lamp and ONE side-brow cyan lamp at their existing original centers in this half-head atlas. The assembled mirrored head has precisely three forehead lamps.

Paint ONE short bright CYAN CHEEK WINDOW at the actual UV destination (the filled cyan rectangle in Image4 when provided), centered (u=.365,v=.555), width .075,height .022. Add a slim graphite/steel-blue bezel. This is the lower cheek panel immediately BELOW the visor's outer edge and LEFT of the ear; the existing correctly placed metal EAR RING centered (.5796,.4972) must remain metal, dark centered and unchanged. No cyan inside the ear ring or on the rear shell.

Calm the lower-left cyan glass: REMOVE the giant sharp pale V reflection. Use one continuous blue-cyan window with broad softly shaded glass and a single restrained off-center reflection like the concept. No bright central seam, mirrored white triangles or two bright columns. EXPAND the cyan glass UPWARD into ALL of this connected original-mesh UV polygon (the large cyan polygon in Image4 when provided), from the current upper edge v about .478 to the new upper edge near v .37-.43 across u .04-.23, with the outer taper reaching (.337,.447). Erase the old purple brow paint and its seam INSIDE this cyan destination. The new cyan glass joins the existing lower window as ONE continuous large face window; retain a slim dark upper rim. The exact extension polygon is (.0407,.4234),(.054631,.366313),(.100852,.386404),(.189869,.401649),(.226988,.414969),(.337174,.446795),(.336899,.448607),(.335037,.454445),(.32533,.469319),(.307525,.485075),(.29502,.521246),(.219306,.504305),(.169093,.495805),(.044073,.478505),(.043979,.478502),(.044,.4783), then close. This is an intentional repaint boundary change inside the SAME UV chart, not a UV change. Do not preserve the previous painted glass boundary. Keep the side forehead lamp near (.28,.39) untouched because it is outside this new glass region. The narrow separate cyan rectangle below the outer visor remains the cheek lamp. The blue crown spine and three forehead lamps remain above the enlarged glass.

Paint broad matte purple and steel-blue armor planes matching Image2. Remove the dense white crack maze, bright continuous white edge outlining and uniform speckled wear; retain only sparse dark seams, soft broad bevel shading and a few small corner chips. Lower cheek/chin armor remains steel blue, cloth remains dark. The far-right rear shell stays quiet steel blue, with no new ring or extra visor. Do not copy diagram wireframe, labels, padding color or arrows. No render, character, new islands, captions or watermark.''',
    ('atom', 'body'): '''ATOM C08 — V3 FRONT CHEST REPAINT
Image1 is the exact native BODY UV atlas EDIT TARGET. Image2 is the approved Atom full-body concept. Image3 shows the current model for mapping diagnosis. Preserve every chart outline, sampled area, padding and UV placement, black cloth, round thigh lamps and all back-side islands. Substantially REPAINT the FRONT CHEST design inside its original chart to match Image2; do not retain the old radiating purple-striped shield pattern.
The front chest is the LEFT chart mirrored on the LEFT vertical edge u=.0288. Paint TWO broad STEEL-BLUE chest cheeks with violet side armor and a clearly readable GRAPHITE vertical central service spine. Remove the diagonal purple stripes that currently cross the main blue chest cheeks and remove their bright white surrounding outlines. One or two broad plate seams suffice; use the concept's simple serviceable bevels.
Move the existing front cyan service window LOWER from its current high collar-adjacent location. Draw exactly HALF of ONE compact cyan vertical rectangle touching u=.0288 on the left shared seam, from u=.0288 to .065 and v=.555 to .605, centered at v=.580 (source Y=1.12667m), inside the actual main steel-blue chest plate. Mirror continuity yields ONE full center-front module. Surround with a compact graphite steel frame and a small metal connector directly below. Erase the previous high cyan window completely and restore blue/graphite plating there. Do not move the back round lamp and do not add cyan on the neck, waist, crotch or back. The main design change is to replace the legacy radiating chest paint with broad blue cheeks around this one mid-chest service module. All remaining charts stay coherent with the concept, with sparse wear, no white crack maze. Output only the complete opaque atlas.''',
    ('atom', 'shoulder'): '''ATOM C08 — V3 THICK UPRIGHT FIN AND SHOULDER PAINT
Image1 is the exact native SHOULDER atlas EDIT TARGET. Image2 is the approved design. Image3 is the actual current model, showing the existing too-small fin lamp. All island boundaries, sampled areas, scale, placement and padding must stay exact. The geometry is separately reshaped to shorter, more upright thick shoulder fins, not long outward antennae.
The genuine fin FRONT FACE is exactly original surface0 triangles 54/55, with normalized UV quad corners (.2659,.1004),(.5269,.1777),(.5245,.1937),(.2641,.1231) in boundary order. Repaint most of this strip as a clearly readable long narrow CYAN indicator with a dark graphite rim — one lamp spanning approximately u=.30 to .49, following this strip's slope and staying between its actual upper and lower borders. Near u=.40 those borders are approximately v=.140 and v=.160; the painted indicator must stay inside them, never on the adjacent upper wedge. Its UV shape is slanted but it becomes the upright fin face on the 3D model. Make this front indicator substantially longer than the current tiny root light, stopping before the strip edges. The broad adjacent sloping surface remains steel-blue with one quiet dark inset, NO cyan window outside the genuine front strip.
The main shoulder is violet purple, its original one circular cyan lamp remains at the exact original center, with a dark restrained inset and broad steel-blue upper rim. Remove dense branching scratches, radiating white line decorations and the original-looking concentric shield divisions. Use large soft painted planes, a few dark plate joins and sparse small corner chips matching Image2. Keep all cloth and other charts unchanged. No technical lines, colored guide rectangles, words or rearranged atlas.''',
    ('pegasus', 'body'): '''PEGASUS C09 — V3 CONCEPT CHEST AND THIGH REPAINT
Image1 is the complete native BODY UV atlas EDIT TARGET. Image2 is the approved concept; Image3 is the actual current model for mapping diagnosis. Preserve exact chart outlines, placement, padding, sampling and black cloth. Redesign the PAINT inside the front chest chart to match Image2, with broad WHITE-GRAY paired chest plates, a LOW white collar around BLACK ribbed neck cloth, and restrained pale-blue edge traces.
The front shared mirror join is the LEFT vertical chart edge u=.0288. Move the one GRAPHITE vertical service recess lower into the main chest: paint HALF of one compact dark rectangle from u=.0288 to .065,v=.55 to .615, with a slim white bevel. Mirroring yields one complete narrow service slot. Fill the previous high black slot near the collar with quiet white plate; the neck remains its separate ribbed cloth. Replace the long white lower central pentagon's dark exterior outlining with a short compact lower chest plate and soft off-white shading, so it no longer reads as a long pointed hanging bib. Remove radiating stacked chevron paint across the front chest; broad paired plates and a small low connector follow Image2. Never paint a black seam across the mirrored join above or below the slot.
Keep the existing outer thigh chart boundaries but paint their full sampled armor panels WHITE-GRAY, with restrained pale-blue accents and broad shading matching the larger white thigh plates in Image2. Do not paint cloth on sampled thigh armor merely to imitate legacy undersuit gaps. Rear technical parts and real black cloth islands stay intact. Reduce bright white edge outlines and noisy wear to a few small corner marks. No added islands, text, technical colors or separate character render.''',
}


def prepare(slug, label, spec=None, guide=None):
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    history = json.loads((work / 'generation_inputs.json').read_text())
    parent = next(row for row in history if row['label'] == label and row['selected'])
    attempt = sum(row['label'] == label for row in history) + 1
    concept = ROOT / f"docs/art/original_armors_v1/images/c{'08' if slug == 'atom' else '09'}_concept.png"
    view = 'new_head_quarter.png' if label == 'head' else 'new_painted_quarter.png'
    diagnostic = work / 'revisions/before_draft_refinement_v3' / f'docs/art/{slug}_runtime_v1/review/engine/{view}'
    references = []
    inputs = [
        (ROOT / parent['archive'], 'edit_target_previous_attempt'),
        (concept, 'helmet_design_authority' if label == 'head' else 'approved_body_design'),
        (diagnostic, 'previous_runtime_mapping_diagnostic_not_design_authority'),
    ]
    if guide:
        inputs.append((ROOT / guide, 'technical_uv_placement_guide_not_output_art'))
    for ordinal, (path, role) in enumerate(inputs):
        snapshot = work / f'input_snapshots/{label}_v3_{attempt}_{ordinal}_{path.name}'
        assert not snapshot.exists(), f'Input already exists: {snapshot}'
        shutil.copyfile(path, snapshot)
        references.append({'path': path.relative_to(ROOT).as_posix(), 'snapshot': snapshot.relative_to(ROOT).as_posix(), 'sha256': sha(snapshot), 'role': role})
    prompt = work / f'prompts/{label}_attempt_{attempt:02}.txt'
    assert not prompt.exists(), 'Actual sent prompts are immutable'
    addendum = (ROOT / spec).read_text(encoding='utf-8') if spec else ADDENDA[(slug, label)]
    if guide:
        addendum += '\nImage4 is a newly drawn TECHNICAL UV placement diagram, not art. Its filled regions mark the exact sampled destinations on Image1. Use their locations; never copy wireframe, labels, arrows or diagram background. Output only the edited Image1 atlas.\n'
    prompt.write_text(BASE.read_text(encoding='utf-8') + '\n\nDRAFT REFINEMENT V3 — TARGETED DESIGN CORRECTION\n' + addendum + '\n', encoding='utf-8', newline='\n')
    plan_path = work / 'generation_plan.json'
    plans = json.loads(plan_path.read_text())
    plan = next(row for row in plans if row['label'] == label)
    plan.update(prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=sha(prompt), references=references, reference_images=[ref['snapshot'] for ref in references], variant='draft_refinement_v3')
    plan_path.write_text(json.dumps(plans, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'{slug.upper()}_{label.upper()}_V3_PROMPT_PREPARED attempt={attempt}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=['atom', 'pegasus'], required=True)
    parser.add_argument('--label', choices=['head', 'body', 'shoulder'], required=True)
    parser.add_argument('--spec', type=Path)
    parser.add_argument('--guide', type=Path)
    args = parser.parse_args()
    prepare(args.armor, args.label, args.spec, args.guide)
