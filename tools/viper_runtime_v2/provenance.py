"""Record generated inputs, archived attempts and validated runtime outputs."""
import hashlib
import json
from copy import deepcopy
from pathlib import Path
from struct import pack
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/viper_runtime_v2'
GEN=Path('C:/Users/whw88/.codex/generated_images/01a0d34a-7c78-72d0-b7ae-7c134c979b6f')
SOURCE='assets/models/player/animated/armor_textures/head_22f92a18e5f8_2x.png'
ART='docs/art/fusion_v2_generated/c01_viper_fusion.jpg'
V8_INPUTS=WORK/'revisions/concept_match_v8/generation_inputs.json'
V8_VARIANT='concept_match_v8'
LABELS={'head','body','shoulder','hand','foot'}

def describe(path):
    path=(ROOT/path).resolve()
    row={'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
    if path.suffix.lower() in {'.png','.jpg','.jpeg'}:
        with Image.open(path) as image:
            row['dimensions']=list(image.size)
    return row

def concept_match_records(previous):
    """Keep prior attribution, then verify all five selected v8 outputs."""
    inputs=json.loads(V8_INPUTS.read_text(encoding='utf-8'))
    entries=inputs['entries'] if isinstance(inputs,dict) else inputs
    if len(entries)!=len(LABELS) or {entry['label'] for entry in entries}!=LABELS:
        raise ValueError('concept_match_v8 requires exactly one entry per material label')
    attempts=inputs.get('archived_attempts',[]) if isinstance(inputs,dict) else []
    described=[]
    snapshots={}
    for label in LABELS:
        before=WORK/f'revisions/concept_match_v8/before/{label}_diffuse.png'
        if before.exists():
            reference=describe(before)
            snapshots[reference['sha256']]=reference
    for entry,selected in [(entry,True) for entry in entries]+[(entry,False) for entry in attempts]:
        if entry['label'] not in LABELS:
            raise ValueError(f"Unknown material label: {entry['label']}")
        if entry['generator']!='image_gen':
            raise ValueError('Only actual image_gen outputs are supported by this manifest')
        if not entry['generated_at'] or not entry['notes'] or not entry['input_paths']:
            raise ValueError('Generation time, notes and actual input paths are required')
        row=describe(entry['output_path'])
        canonical=describe(f"assets/armors/viper_v2/{entry['label']}_diffuse.png")
        if selected and row['sha256']!=canonical['sha256']:
            raise ValueError(f"Selected {entry['label']} output differs from runtime canonical texture")
        references=[describe(path) for path in entry['input_paths']]
        actual_paths=entry.get('actual_input_paths')
        if actual_paths is not None:
            if len(actual_paths)!=len(references):
                raise ValueError('actual_input_paths must correspond one-to-one with input_paths')
            for reference,actual_path in zip(references,actual_paths):
                reference['actual_input_path']=actual_path
        for reference in references:
            snapshots[reference['sha256']]=reference
        row.update({'label':entry['label'],'variant':entry.get('variant',V8_VARIANT),
                    'source_revision':V8_VARIANT,
                    'tool':'image_gen.imagegen','generator':entry['generator'],
                    'generated_at':entry['generated_at'],'notes':entry['notes'],
                    'prompt':describe(entry['prompt_path']),'references':references,
                    'selected':selected,'status':'runtime_integrated_pending_user_art_review' if selected else 'superseded_concept_match_attempt'})
        if selected:
            row['canonical_output']=canonical
        generated_path=entry.get('original_generation_path',entry.get('generated_source_path'))
        if generated_path:
            row['original_generation_path']=generated_path
        described.append(row)
    records=[]
    for previous_row in previous:
        if previous_row.get('source_revision')==V8_VARIANT or previous_row.get('variant')==V8_VARIANT:
            continue  # Re-running the recorder must not duplicate the same revision.
        row=deepcopy(previous_row)
        archived_path=ROOT/row['path']
        if not archived_path.exists() or hashlib.sha256(archived_path.read_bytes()).hexdigest()!=row['sha256']:
            snapshot=snapshots.get(row['sha256'])
            if snapshot is None:
                raise ValueError(f"Missing immutable snapshot of prior generated output: {row['path']}")
            row['superseded_runtime_path']=row['path']
            row.update(snapshot)
        if row.get('selected'):
            row['selected']=False
            row['status']='superseded_by_concept_match_v8'
        records.append(row)
    return records+described

def legacy_records(previous):
    records=previous[:5]
    # Initial calls saw the pre-texture render at this original path. Preserve
    # its exact bytes in a stable snapshot after later captures reuse the path.
    snapshot=describe('docs/art/viper_runtime_v2/review/pretexture/new_diffuse_front.png')
    for row in records:
        old=row['references'][4]
        assert old['sha256']==snapshot['sha256']
        row['references'][4]={**snapshot,'actual_input_path':old.get('actual_input_path',old['path'])}
        if row['label']=='head':
            original=row['sha256']; saved=describe('docs/art/viper_runtime_v2/rejected/head_diffuse_v1.png')
            assert saved['sha256']==original
            row.update(saved);row['status']='rejected_brow_mapped_to_rear';row['selected']=False
        else:row['selected']=True;row['status']='runtime_integrated_pending_user_art_review'
    variants=[
        ('v2','exec-0e51e198-a1e5-4ea1-b86b-d888ecdc4bb0.png','head_diffuse_correction.txt',
         ['docs/art/viper_runtime_v2/rejected/head_diffuse_v1.png','docs/art/viper_runtime_v2/guides/head_regions.png',SOURCE,ART,'docs/art/viper_runtime_v2/rejected/head_trial_front.png'],False),
        ('v3','exec-19fdd381-649a-42c9-aa59-1d3bdef11a02.png','head_diffuse_correction_v3.txt',
         [SOURCE,'docs/art/viper_runtime_v2/guides/head_regions.png',ART],False),
        ('v4','exec-6edbe1fb-876d-4683-a6d4-08ca56975958.png','head_diffuse_correction_v4.txt',
         ['docs/art/viper_runtime_v2/rejected/head_diffuse_v3.png',ART,'docs/art/viper_runtime_v2/guides/head_uv.png'],False),
        ('v5','exec-b850e6a7-b4b5-4077-a5c2-d5bc9b865ccd.png','head_diffuse_correction_v5.txt',
         ['docs/art/viper_runtime_v2/rejected/head_diffuse_v4.png',ART,'docs/art/viper_runtime_v2/guides/head_regions.png',SOURCE,'docs/art/viper_runtime_v2/review/face_geometry/new_clay_front.png'],False),
        ('v6','exec-115e1afa-2faf-4885-aef9-fd03fcfb4355.png','head_diffuse_correction_v6.txt',
         ['docs/art/viper_runtime_v2/rejected/head_diffuse_v5.png','docs/art/viper_runtime_v2/guides/user_helmet_reference.png','docs/art/viper_runtime_v2/guides/head_regions_v6.png','docs/art/viper_runtime_v2/rejected/head_v5_front.png'],False),
        ('v7','exec-5b8cfa2c-5955-476f-8228-abbad73737a6.png','head_diffuse_correction_v7.txt',
         ['docs/art/viper_runtime_v2/rejected/head_diffuse_v6.png','docs/art/viper_runtime_v2/guides/user_helmet_reference.png','docs/art/viper_runtime_v2/guides/head_regions_v7.png','docs/art/viper_runtime_v2/rejected/head_v6_front.png'],True)]
    for version,generated,prompt,refs,selected in variants:
        path='assets/armors/viper_v2/head_diffuse.png' if selected else f'docs/art/viper_runtime_v2/rejected/head_diffuse_{version}.png'
        row=describe(path)
        original=GEN/generated
        expected=hashlib.sha256(original.read_bytes()).hexdigest() if original.exists() else next(r['sha256'] for r in previous if r.get('variant')==version)
        assert row['sha256']==expected
        row.update({'label':'head','variant':version,'tool':'image_gen.imagegen','original_generation_path':str(GEN/generated),
                    'prompt':describe('docs/art/viper_runtime_v2/prompts/'+prompt),'references':[describe(p) for p in refs],
                    'selected':selected,'status':'runtime_integrated_pending_user_art_review' if selected else 'superseded_local_texture_attempt'})
        if version=='v6':row['references'][1]['actual_input_path']='C:/Users/whw88/AppData/Local/Temp/codex-clipboard-5878ab43-ee47-44d5-8b52-bd18807601b3.png'
        records.append(row)
    return records

def measured_uv_budget():
    """Derive count percentages from the current authored coordinates."""
    source=json.loads((WORK/'build/source.json').read_text(encoding='utf-8'))
    target=json.loads((WORK/'build/target.json').read_text(encoding='utf-8'))
    geometry=json.loads((WORK/'build/geometry.json').read_text(encoding='utf-8'))
    materials={}
    parts={}
    for name,original in source['parts'].items():
        authored=target['parts'][name]
        if len(original['surfaces'])!=len(authored['surfaces']):
            raise ValueError(f'{name}: material surface count changed')
        part_count=0
        part_changed=0
        geometry_exact=True
        for original_surface,authored_surface in zip(original['surfaces'],authored['surfaces']):
            original_uv=original_surface['uv']
            authored_uv=authored_surface['uv']
            if len(original_uv)!=len(authored_uv):
                raise ValueError(f'{name}: UV coordinate count changed')
            changed=sum(any(abs(a-b)>1e-7 for a,b in zip(old,new)) for old,new in zip(original_uv,authored_uv))
            count=len(original_uv)
            original_positions=original_surface['positions']
            authored_positions=authored_surface['positions']
            if len(original_positions)!=len(authored_positions):
                raise ValueError(f'{name}: vertex count changed')
            # Godot's JSON text rounds float32 positions to fewer decimal digits.
            # Compare their actual float32 values rather than that serialization.
            exact=all(pack('3f',*old)==pack('3f',*new) for old,new in zip(original_positions,authored_positions))
            label=authored_surface['label']
            if label in materials:
                raise ValueError(f'Duplicate authored material label: {label}')
            materials[label]={'uv_coordinate_count':count,'uv_changed_coordinates':changed,
                              'uv_changed_fraction':changed/count,'uv_exact':changed==0,
                              'geometry_exact':exact}
            if changed/count>.20:
                raise ValueError(f'{label}: changed UV coordinate fraction exceeds 20%')
            part_count+=count
            part_changed+=changed
            geometry_exact=geometry_exact and exact
        measured=geometry['parts'][name]
        if measured['uv_changed_count']!=part_changed or measured['uv_coordinate_count']!=part_count:
            raise ValueError(f'{name}: geometry.json is stale relative to source/target coordinates')
        if measured['uv_charts']!=measured['original_uv_charts']:
            raise ValueError(f'{name}: original UV chart count changed')
        parts[name]={'uv_coordinate_count':part_count,'uv_changed_coordinates':part_changed,
                     'uv_changed_fraction':part_changed/part_count,'geometry_exact':geometry_exact,
                     'uv_charts':measured['uv_charts'],'original_uv_charts':measured['original_uv_charts']}
    if set(materials)!=LABELS:
        raise ValueError('The authored material labels must match the five runtime diffuse maps')
    unchanged_labels={'shoulder','hand','foot'}
    if not all(materials[label]['uv_exact'] for label in unchanged_labels):
        raise ValueError('Shoulder, hand and foot UV coordinates must remain original')
    if not all(materials[label]['geometry_exact'] for label in LABELS-{'head'}):
        raise ValueError('Body, shoulder, hand and foot geometry must remain original')
    total_count=sum(row['uv_coordinate_count'] for row in materials.values())
    total_changed=sum(row['uv_changed_coordinates'] for row in materials.values())
    return {'materials':materials,'parts':parts,'total_count':total_count,'total_changed':total_changed,
            'total_changed_fraction':total_changed/total_count}

def current_delivery_report(budget):
    """Reject a prior packed-master report after the master or maps change."""
    path=WORK/'review/delivery_validate.json'
    report=json.loads(path.read_text(encoding='utf-8'))
    if report['status']!='PASS' or report['errors']:
        raise ValueError('Current focused delivery validation did not pass')
    for report_key,file_path in [('master_sha256','docs/art/viper_runtime_v2/build/viper_master.blend'),
                                 ('source_sha256','docs/art/viper_runtime_v2/build/source.json'),
                                 ('target_sha256','docs/art/viper_runtime_v2/build/target.json')]:
        if report[report_key]!=describe(file_path)['sha256']:
            raise ValueError(f'delivery_validate.json is stale: {report_key}')
    if report['changed_uv_coordinate_count']!=budget['total_changed']:
        raise ValueError('Focused delivery report has a stale changed UV count')
    for label in LABELS:
        if report['images'][label]['canonical_sha256']!=describe(f'assets/armors/viper_v2/{label}_diffuse.png')['sha256']:
            raise ValueError(f'delivery_validate.json has a stale {label} texture hash')
    return report

def main():
    previous=json.loads((WORK/'build/generation.json').read_text(encoding='utf-8'))
    is_v8=V8_INPUTS.exists()
    records=concept_match_records(previous) if is_v8 else legacy_records(previous)
    if is_v8:
        uv=measured_uv_budget()
        delivery=current_delivery_report(uv)
    (WORK/'build/generation.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    outputs=[describe(p.relative_to(ROOT)) for p in sorted((ROOT/'assets/armors/viper_v2').iterdir()) if p.suffix in ['.png','.glb','.scn']]
    outputs.append(describe('docs/art/viper_runtime_v2/build/viper_master.blend'))
    base=describe('docs/art/viper_runtime_v2/prompts/base_prompt_snapshot.txt')
    assert base['sha256']=='de445a88ca6c06ae90c567e188461f9b823157f767b46145fbb4eb8901f6c7e2'
    manifest={'revision':'viper_runtime_v2','date':'2026-10-03','legacy_name':'Viper','visual_id':0,'design_id':'C-01',
              'status':'runtime_integrated_pending_user_art_review','runtime_scene':'assets/armors/viper_v2/viper.scn',
              'base_prompt':base,'base_prompt_commits':['13d6836708418208a2d5c8318fb0e3260c4a2bfc','48f0a12adba5c71abde2ac9c9d7513edfabdc20e'],
              'selected_helmet_reference':{**describe(ART),'source_commit':'25f11d9a52ab1bc2c4f63dc509f1fcb0943589f5','scope':'full_armor_and_helmet' if is_v8 else 'helmet_only'},
              'source_mesh':describe('assets/models/player/animated/player.gltf'),
              'source_buffer':describe('assets/models/player/animated/player.bin'),
              'construction':'Original indexed continuous cages; local head reshape only. Four modular parts, five material surfaces, original indices/bones/weights/Skin binds; original four head UV charts and130 coordinates retained,18 visor coordinates locally changed with whole-face projection; body UV exact.',
              'budget':{'triangles':682,'bones':28,'surfaces':5,'local_geometry_change_limit':.20,'head_uv_coordinate_count':130,'original_head_uv_coordinate_count':130,'head_uv_changed_coordinates':18,'head_uv_changed_fraction':18/130,'uv_chart_count_change_limit':.20},
              'selected_generations':[r['path'] for r in records if r['selected']],
              'generation_records':'build/generation.json','outputs':outputs,
              'verification':{'runtime':'review/runtime_test.json','engine_roundtrip':'review/roundtrip_test.json','geometry':'review/proportion_test.json','blender':'review/blender_validate.json','blender_roundtrip':'review/blender_roundtrip/roundtrip.json'},
              'visual_review':'Compared actual front/side/rear/quarter, closeup, idle/run/reload and two game levels. V7 follows the user-selected helmet: continuous purple visor, central lower polygon bevel seam, dark angled lens edges, blue framed cheek recesses. Only18 of130 headUVs moved inside the original visor chart, whole-face mapping avoids mirrored reflections. Front black brow/blue center and blue crown channels retained. Original low-poly side ear mass and source shell construction retained. User art approval remains pending.',
              'inferred':'Local chin/cheek/brow depth from a perspective helmet concept; original hidden rear/neck/joints/bodyUV authoritative; user explicitly allowed local helmetUV changes with20% tolerance.'}
    if is_v8:
        head=uv['materials']['head']
        body=uv['materials']['body']
        body_part=uv['parts']['ArmorBody_00']
        head_part=uv['parts']['ArmorHead_00']
        outputs.append(describe('docs/art/viper_runtime_v2/review/delivery_validate.json'))
        manifest.update({
            'current_variant':V8_VARIANT,
            'generation_inputs':V8_INPUTS.relative_to(WORK).as_posix(),
            'selected_armor_reference':{**describe(ART),'source_commit':'25f11d9a52ab1bc2c4f63dc509f1fcb0943589f5','scope':'full_armor_and_helmet'},
            'construction':f"Full-concept diffuse repaint on the existing Viper v2 indexed cages. Four modular parts, five material surfaces, original indices/bones/weights/Skin binds. Body, shoulder, hand and foot geometry remain exact to the original. Front chest and abdomen UV remap {body['uv_changed_coordinates']} of {body['uv_coordinate_count']} body-material coordinates; shoulder, hand and foot UVs remain exact. The inherited v7 helmet retains {head['uv_changed_coordinates']} locally changed visor coordinates out of {head['uv_coordinate_count']}. Original UV chart and coordinate counts remain unchanged.",
            'visual_review':'The complete steel-blue and charcoal armor in the user-selected concept is the design authority. The new five diffuse outputs are attributed to their actual prompts and immutable image inputs; the previous v7 outputs remain archived. The latest continuous purple faceplate is retained. See the comparison page and capture/test reports for actual runtime results; user art approval remains pending.',
            'inferred':'Original hidden rear/neck/joint construction and game proportions remain authoritative. Perspective art does not establish exact hidden surface depth. Front chest and abdomen UV corrections sample the regenerated blue plates, black chest insets and longer abdominal core while retaining original mesh topology. Original chunky proportions and chest-window width remain constrained by the existing low-poly mirrored cage. The 20% limit is the cap on changed source UV coordinate count fraction, measured independently for head and body material, not a per-point UV distance bound.',
            'verification':{'runtime':'review/runtime_test.json','engine_roundtrip':'review/roundtrip_test.json','geometry':'review/proportion_test.json','delivery':'review/delivery_validate.json','historical_blender':'review/blender_validate.json','historical_blender_roundtrip':'review/blender_roundtrip/roundtrip.json'},
            'verification_scope':{'delivery':delivery['scope'],'historical_blender':'Previous source-geometry warning checks retained for context; not a freshly rerun general validator for this revision.','historical_blender_roundtrip':'Prior Blender roundtrip evidence; current packed images and authored UVs are checked by delivery_validate.json.'}})
        manifest['budget'].update({
            'head_uv_coordinate_count':head['uv_coordinate_count'],
            'original_head_uv_coordinate_count':head['uv_coordinate_count'],
            'head_uv_changed_coordinates':head['uv_changed_coordinates'],
            'head_uv_changed_fraction':head['uv_changed_fraction'],
            'body_material_uv_coordinate_count':body['uv_coordinate_count'],
            'body_material_uv_changed_coordinates':body['uv_changed_coordinates'],
            'body_material_uv_changed_fraction':body['uv_changed_fraction'],
            'body_including_shoulder_uv_coordinate_count':body_part['uv_coordinate_count'],
            'body_including_shoulder_uv_changed_coordinates':body_part['uv_changed_coordinates'],
            'body_including_shoulder_uv_changed_fraction':body_part['uv_changed_fraction'],
            'total_uv_coordinate_count':uv['total_count'],
            'total_uv_changed_coordinates':uv['total_changed'],
            'total_uv_changed_fraction':uv['total_changed_fraction'],
            'head_uv_chart_count':head_part['uv_charts'],
            'original_head_uv_chart_count':head_part['original_uv_charts'],
            'uv_changed_coordinate_fraction_limit':.20,
            'body_uv_exact':body['uv_exact'],
            'shoulder_hand_foot_uv_exact':True,
            'body_shoulder_hand_foot_geometry_exact':True,
            'additional_uv_coordinates_changed_this_revision':sum(row['uv_changed_coordinates'] for label,row in uv['materials'].items() if label!='head'),
            'uv_material_measurements':uv['materials'],
            'uv_part_measurements':uv['parts'],
            'uv_tolerance_definition':'Fraction of original UV coordinates that changed, independently capped at 20% per head/body material; not a normalized per-point displacement limit.'})
    (WORK/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('VIPER_PROVENANCE_PASS generations=%d selected=%d outputs=%d'%(len(records),len(manifest['selected_generations']),len(outputs)))

if __name__=='__main__':main()
