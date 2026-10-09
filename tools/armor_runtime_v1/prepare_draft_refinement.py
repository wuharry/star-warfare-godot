"""Prepare revision prompts from the selected native atlas, without painting it.

Each edit keeps an immutable native parent and the approved C08/C09 concept.
Generation and engine verification remain separate explicit pipeline steps.
"""
import argparse
import json
import shutil

from prepare_generation import BASE, ROOT, sha


ADDENDA = {
    'atom': {
        'head': """ATOM C08 draft refinement. Image1 is the existing native HALF-HEAD SIDE atlas, the edit target. Image2 is the approved design authority. Keep Image1's exact island outlines, padding and coordinates. The mesh has separately acquired a shorter chin and more circular ear; do not draw a different atlas or a full helmet render.
Repaint the broad TOP dome currently steel blue as predominantly violet-purple, with a narrow steel-blue CENTRAL crown strip at the far LEFT shared crown join (approximately x0.05..0.23 of atlas). Keep the existing ONE central cyan crown lamp and ONE side-brow lamp at their exact centers; mirroring assembles three lamps, never add three lamps on this half atlas. Keep the lower-left continuous cyan glass, one broad soft reflection. Repaint the tall purple lower-left mouthpiece and purple lower cheek as restrained STEEL-BLUE short cheek/chin guard. TRUE EAR UV is the MIDDLE steel-blue polygon, center (.5796,.4972), rim approximately u.465.. .700,v.442.. .540: paint a horizontally elliptical steel-blue concentric ring with a dark center, which becomes round on the fitted 3D ear. No cyan window on this ear plate. The far-right chart is REAR helmet, not the ear; keep it quiet steel-blue without a ring or extra visor. All rear separate charts remain dark and restrained. Reduce dense scratches and mottled speckles; use broad softly shaded planes, sparse corner wear. Preserve image1's physical silhouette and island boundaries exactly.""",
        'body': """ATOM C08 draft chest correction. Image1 is the selected native body atlas, Image2 the approved full-body design. Keep all atlas outlines and placement, black cloth charts, thigh lamp centers, and padding EXACT. The actual mirrored FRONT chest join is the far LEFT vertical edge at u=.0288; this is shared by both chest halves. Rebuild its chest paint as separate steel-blue broad chest cheeks, violet side plates, and a graphite vertical center service spine.
MOVE the one existing cyan front service window from the LOWER left (current center v approximately .69) UP to the middle-left chest at u=.0288.. .060, v=.55.. .615, continuous across the left shared join. Paint HALF of one narrow cyan rectangle at that LEFT border, so the mirror yields one complete vertical box centered on the UPPER CHEST. Steel-blue/graphite rectangular bezel, small lower metal connector beneath it. Remove the old low cyan window completely and fill with steel-blue plate. Only one front cyan service rectangle; do not place cyan boxes on the top-left black collar, back at upper-right, waist or crotch. Keep round cyan thigh lamps. Broader chest cheeks should read as serviceable beveled plates like Image2, not concentric radiating legacy shields. Reduce white scratches and noisy crack patterns to sparse edge wear. Do not move UV islands, draw guides or text.""",
        'shoulder': """ATOM C08 draft shoulder refinement. Image1 is the native shoulder atlas edit target. Image2 fixes design only. Keep exact outlines and island positions. The upper-left triangular island is the short thick wedge fin after separate mesh fitting: retain steel-blue fin, add ONE small cyan service indicator with a thin dark bezel inside the actual front-facing UV strip, parallel to the upper sloping edge (u.38.. .49, v.14.. .18). This slanted UV bar becomes vertical on the 3D fin; do not put a big window in the broad sloping face around u.47,v.24. The large lower shoulder shell should be predominantly violet-purple, with a steel-blue narrow upper cap, dark central inset and its existing ONE circular cyan lamp in exactly the same place. Keep dark cloth upper-right charts. Simplify radiating panel divisions into broad beveled violet plates matching the draft; sparse corner wear, no dense scratches or white outlining. Do not repack charts or add extra islands.""",
        'hand': """ATOM C08 draft forearm refinement. Image1 is the native hand/forearm atlas; Image2 approved concept. Preserve exact island layout and outline, fingers, black glove and steel-blue palm plate. On the main forearm purple outer service panel, replace the existing round cyan status lamp with one compact vertical rectangular cyan service window with graphite bezel, following Image2. Keep its center inside the same original sampled panel, not across chart seams. Steel-blue inner forearm, violet outer forearm, a few broad plate breaks and sparse edge wear. No extra cyan lamps, no glow on glove. Preserve every chart and its padding.""",
    },
    'pegasus': {
        'head': """PEGASUS C09 draft helmet correction. Image1 is a mirrored HALF-HEAD SIDE native atlas, the exact edit target; Image2 the approved helmet/body design authority. Keep every existing island outline, coordinate and padding. The mesh is separately fitted to LOWER blunt parallel front-to-back crown rails and a shorter, shallower chin; do not draw a different atlas.
Repaint the upper crown strip regions as restrained WHITE-GRAY low rail plating with a FEW BLACK rectangular recessed vents along the raised rail, matching Image2. Remove the three conspicuous blue squares on the broad brow and extra blue ornamental cheek squares: these become quiet off-white plates, with only small restrained pale-blue edge accents. Keep one broad continuous near-black graphite visor in the lower-left glass chart; widen its painted reading within the current glass boundary with a broad soft gray reflection, no eyes, no bright center seam, no second visor. Lower guard and cheek are compact white-gray armor, dark rear neck remains black ribbed cloth. Simplify V-stair paint and remove the apparent extra pointed center forehead panel; broad crown surfaces and low rails should read clearly. Sparse corner wear instead of dense speckling. Preserve original UV layout and opaque background.""",
        'body': """PEGASUS C09 draft torso correction. Image1 exact native body atlas edit target, Image2 approved concept. Preserve chart outlines, locations, padding and actual black openings. The FRONT chest is the left chart, mirrored along u=.0288. Its top-left region from u=.0288.. .17,v=.30.. .47 currently reads as a large BLUE front neck bib: repaint its CENTER as BLACK ribbed neck cloth with a LOW WHITE outer collar, matching the draft. The adjacent mid-left chest should be broad WHITE-GRAY paired chest plates, with only restrained pale-blue edge accents, not a wide blue chest bib.
The actual central chest join is u=.0288: paint HALF of one DARK VERTICAL RECTANGULAR service recess from u=.0288.. .058,v=.55.. .615, so mirroring yields one complete narrow graphite slot between the two white chest plates. Remove the old WHITE central pentagon around u=.0288,v=.65; make the lower central panel quiet white-gray plating around the dark slot. Never draw a dark center seam above or below the actual slot. Do not put the service slot on the back top-right chart. Keep black abdomen and white thigh plates with restrained pale-blue insets. Reduce patterned radiating legacy ribs on the front; larger white panels, softer hand-painted shading and sparse edge wear. All UV chart geometry stays exact.""",
        'shoulder': """PEGASUS C09 draft shoulder refinement. Image1 exact native shoulder atlas; Image2 design reference. Keep all outlines, chart placement and padding exact. Reinterpret the large center white shoulder as broad layered WHITE-GRAY plates with a clearly readable STEEL-BLUE HORIZONTAL clasp/band crossing its upper-middle portion (atlas approximately x.20.. .56,y.49.. .56), following the concept's blue front shoulder clasp. The clasp is paint inside the existing sampled plate, not a new island or detached object. Keep the lower plate white and the upper-left smaller plate white, upper-right cloth black. Tone down the oversized arrow-chevron shading and sparse original blue line around the perimeter; broad bevels and restrained blue breaks instead. Soft hand-painted planes, sparse corner wear, no dense scratches, no text or guide colors.""",
    },
}


def prepare(slug, label):
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    history = json.loads((work / 'generation_inputs.json').read_text())
    parent = next(row for row in history if row['label'] == label and row['selected'])
    attempt = sum(row['label'] == label for row in history) + 1
    concept = ROOT / f"docs/art/original_armors_v1/images/c{'08' if slug == 'atom' else '09'}_concept.png"
    refs = []
    for index, (path, role) in enumerate([
        (ROOT / parent['archive'], 'edit_target_previous_attempt'),
        (concept, 'helmet_design_authority' if label == 'head' else 'approved_body_design'),
    ]):
        snapshot = work / f'input_snapshots/{label}_draft{attempt}_{index}_{path.name}'
        assert not snapshot.exists(), f'Prepared input already exists: {snapshot}'
        shutil.copyfile(path, snapshot)
        refs.append({'path': path.relative_to(ROOT).as_posix(),
                     'snapshot': snapshot.relative_to(ROOT).as_posix(),
                     'sha256': sha(snapshot), 'role': role})
    prompt = work / f'prompts/{label}_attempt_{attempt:02}.txt'
    assert not prompt.exists(), 'Never overwrite an actual generation prompt'
    text = BASE.read_text(encoding='utf-8') + '\n\nDRAFT REFINEMENT V2 — MATERIAL ADDENDUM\n' + ADDENDA[slug][label] + '\n'
    prompt.write_text(text, encoding='utf-8', newline='\n')
    plan_path = work / 'generation_plan.json'
    plans = json.loads(plan_path.read_text())
    plan = next(row for row in plans if row['label'] == label)
    plan.update(prompt=prompt.relative_to(ROOT).as_posix(), prompt_sha256=sha(prompt),
                references=refs, reference_images=[ref['snapshot'] for ref in refs],
                variant='draft_refinement_v2')
    plan_path.write_text(json.dumps(plans, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'{slug.upper()}_{label.upper()}_DRAFT_PROMPT_PREPARED attempt={attempt}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=list(ADDENDA), required=True)
    parser.add_argument('--label', choices=['head', 'body', 'shoulder', 'hand'], required=True)
    args = parser.parse_args()
    prepare(args.armor, args.label)
