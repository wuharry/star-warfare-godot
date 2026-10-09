"""Prepare exact original-atlas imagegen prompts and immutable image inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt'
ADDENDA = {
    'atom': {
        'identity': 'ATOM / C-08 / gameplay visual ID7. Violet-purple panels, muted steel blue secondary armor, cyan glass and cyan status lamps. Keep the original stocky game body proportions. Approved C08 concept provides design details only, not adult body proportions.',
        'head': 'The input is a mirrored HALF-HEAD SIDE atlas. Front is LEFT, crown TOP. TRUE EAR is the middle steel-blue polygon, UV center (.5796,.4972), rim u.465-.700,v.442-.540; far RIGHT is rear helmet, not the ear. Separate lower-right dark piece is a separate original chart. Keep the original continuous visor UV boundary at lower-left. Paint it cyan/teal with one broad reflection, no separate eyes or black center seam. Reinterpret original tall projecting violet mouthpiece as a restrained steel-blue short cheek/chin guard within the same chart; do not invent a new mouth grille. Round segmented violet brow and steel-blue crown strip, exactly THREE cyan lamps in assembled helmet: the one central crown lamp is mirrored/shared at top-left join, the two side lamps use the one existing left-side brow lamp mirrored. Do not draw three lamps on this half-atlas. Keep compact round steel-blue ear fitting; use original rear separate cyan panel conservatively. No extra visor at rear. Latest C08 shallow visor and short chin guide the paint, but do not move original UV boundaries.',
        'body': 'Maintain exact original torso chart placement. Convert broad violet/blue panels to the C08 serviceable chest armor language with a small CYAN vertical rectangular service window on the actual mirrored center-front chest join (LEFT near center, not on the BACK panel at top/right). Keep center seam color continuous, do not outline mirror join in black. Preserve black cloth and actual openings. Keep major violet flank/steel-blue front color blocks distinct, no helmet details on torso.',
        'shoulder': 'Maintain original shoulder atlas silhouette with upper-left swept plate and large central shoulder plate. Violet shoulder shell, steel-blue edge cap, one restrained circular cyan lamp in existing center position. Use compact layered plating inspired by C08, no additional islands or fake extra fins beyond model. Upper-right dark charts remain understated cloth.',
        'hand': 'Original arm/hand atlas layout is locked: top black rectangular strip remains dark inner joint/cloth, center large steel-blue forearm plate retains original cyan circular point, violet side wrist panels and restrained dark glove charts remain in place. Reinterpret a few blue panel subdivisions following C08 without moving joint boundaries. Keep cloth matte and sparse wear.',
        'foot': 'Original leg/boot atlas is locked, including cyan circular leg markers and central black joint chart. Violet outer thigh/knee caps, muted steel-blue shin and toe guards, cyan hip/heel points exactly where original uses them. Match C08 segmented leg palette with broad low contrast paint, no random added lamps, no new plates across bend regions.'
    },
    'pegasus': {
        'identity': 'PEGASUS / C-09 / gameplay visual ID8. All helmet and body armor shells are matching OFF-WHITE / LIGHT GRAY with sparse muted steel-blue accents; dark navy-black visor and cloth. The latest C09 white helmet correction is authoritative; absolutely no red helmet. Keep original stocky game proportions.',
        'head': 'Use original half-head atlas positions. Repaint ALL original colored/red shell regions OFF-WHITE LIGHT GRAY, same as body, including top crown, cheek, rear and chin. Preserve continuous dark charcoal/navy shallow V visor with a single restrained gray-blue reflection, no bright eye pair or metallic gold. Suggest the latest C09 paired low crown rails within original crown panels, replacing decorative paint without extending silhouette or adding islands. Layered off-white cheek guards and short tucked jaw are softly shaded, not a robot snout. Preserve dark neck and existing plate boundaries. White helmet and white body must have same value family.',
        'body': 'Reinterpret the original broad white torso panels into C09 angled chest and collar plate language with sparse blue seam accents, within every existing chart boundary. Dark navy-black rib/waist cloth remains. Keep mirrored chest joining edge continuous, no invented central black split or glowing service box. Do not paint broad blue areas: main chest remains off-white/light gray.',
        'shoulder': 'Keep original broad pale shoulder layers and exact chart positions. Match C09 off-white angular shoulder armor with only small muted blue seam/corner blocks. Maintain readable low-poly plane shading and soft cloth in dark regions. No new fins, no purple or gold trim.',
        'hand': 'Maintain original forearm/glove atlas chart layout, off-white wide arm plates, sparse steel-blue wrist trims, dark navy-black elbows/gloves. C09 clean layered cheek-like panel language applies only as subtle arm panel shapes, no new hand or islands. Avoid heavy black outlines on all shell borders.',
        'foot': 'Maintain original leg/boot chart layout. Off-white hip/knee/shin armor with sparse muted blue knee/toe seam blocks, dark navy-black inner thigh and joints. Match C09 pale layered leg identity; retain original boot/toe silhouettes and all fold positions. No added cyan lamps or gold trim.'
    }
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=ADDENDA, required=True)
    slug = parser.parse_args().armor
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    if (work / 'generation_inputs.json').exists():
        raise FileExistsError('Registered generation history already exists; prepare a new uniquely named attempt instead of rewriting attempt_01 prompts.')
    cid = '08' if slug == 'atom' else '09'
    ref = ROOT / f'docs/art/original_armors_v1/images/c{cid}_concept.png'
    records = []
    for label in ['head', 'body', 'shoulder', 'hand', 'foot']:
        target = work / f'revisions/original_source_v1/atlases/{label}.png'
        style = ROOT / f'assets/armors/viper_v2/{label}_diffuse.png'
        guide = work / f'guides/{label}_uv.png'
        references = []
        for index, (path, role) in enumerate([(target, 'edit_target'), (ref, 'helmet_design_authority' if label == 'head' else 'approved_body_design'), (style, 'approved_surface_style_only'), (guide, 'technical_uv_guide')]):
            snapshot = work / f'input_snapshots/{label}_{index}_{path.name}'
            if snapshot.exists():
                assert sha(snapshot) == sha(path), 'Frozen input changed'
            else:
                shutil.copyfile(path, snapshot)
            references.append({'path': path.relative_to(ROOT).as_posix(), 'snapshot': snapshot.relative_to(ROOT).as_posix(), 'sha256': sha(snapshot), 'role': role})
        addendum = '\n\nREQUIRED PER-ASSET ADDENDUM\n' + ADDENDA[slug]['identity'] + '\nMaterial: ' + label + '\n' + ADDENDA[slug][label]
        addendum += '\nInput order: Image1 EDIT TARGET true original atlas; Image2 latest approved design reference only; Image3 Viper shared painted STYLE ONLY, never copy its purple visor or blue identity; Image4 exact original UV technical wire guide only. Technical cyan lines must NEVER appear in the output. All actual source shape and UV positions remain unchanged in this pass. Keep original opaque gray unused padding. Only output a flat opaque square atlas registered to Image1.\n'
        prompt = work / f'prompts/{label}_attempt_01.txt'
        prompt.write_text(BASE.read_text(encoding='utf-8') + addendum, encoding='utf-8')
        records.append({'label': label, 'prompt': prompt.relative_to(ROOT).as_posix(), 'prompt_sha256': sha(prompt), 'base_prompt': BASE.relative_to(ROOT).as_posix(), 'base_prompt_sha256': sha(BASE), 'references': references, 'reference_images': [row['snapshot'] for row in references]})
    (work / 'generation_plan.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(slug.upper() + '_PROMPTS_PREPARED 5 exact prompts and frozen inputs, no generation claimed')

if __name__ == '__main__':
    main()
