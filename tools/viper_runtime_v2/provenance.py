"""Record generated inputs, archived attempts and validated runtime outputs."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/viper_runtime_v2'
GEN=Path('C:/Users/whw88/.codex/generated_images/01a0d34a-7c78-72d0-b7ae-7c134c979b6f')
SOURCE='assets/models/player/animated/armor_textures/head_22f92a18e5f8_2x.png'
ART='docs/art/fusion_v2_generated/c01_viper_fusion.jpg'

def describe(path):
    path=ROOT/path
    row={'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
    if path.suffix.lower()=='.png':row['dimensions']=list(Image.open(path).size)
    return row

def main():
    previous=json.loads((WORK/'build/generation.json').read_text())
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
    (WORK/'build/generation.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    outputs=[describe(p.relative_to(ROOT)) for p in sorted((ROOT/'assets/armors/viper_v2').iterdir()) if p.suffix in ['.png','.glb','.scn']]
    outputs.append(describe('docs/art/viper_runtime_v2/build/viper_master.blend'))
    base=describe('docs/art/viper_runtime_v2/prompts/base_prompt_snapshot.txt')
    assert base['sha256']=='de445a88ca6c06ae90c567e188461f9b823157f767b46145fbb4eb8901f6c7e2'
    manifest={'revision':'viper_runtime_v2','date':'2026-10-03','legacy_name':'Viper','visual_id':0,'design_id':'C-01',
              'status':'runtime_integrated_pending_user_art_review','runtime_scene':'assets/armors/viper_v2/viper.scn',
              'base_prompt':base,'base_prompt_commits':['13d6836708418208a2d5c8318fb0e3260c4a2bfc','48f0a12adba5c71abde2ac9c9d7513edfabdc20e'],
              'selected_helmet_reference':{**describe(ART),'source_commit':'25f11d9a52ab1bc2c4f63dc509f1fcb0943589f5','scope':'helmet_only'},
              'source_mesh':describe('assets/models/player/animated/player.gltf'),
              'source_buffer':describe('assets/models/player/animated/player.bin'),
              'construction':'Original indexed continuous cages; local head reshape only. Four modular parts, five material surfaces, original indices/bones/weights/Skin binds; original four head UV charts and130 coordinates retained,18 visor coordinates locally changed with whole-face projection; body UV exact.',
              'budget':{'triangles':682,'bones':28,'surfaces':5,'local_geometry_change_limit':.20,'head_uv_coordinate_count':130,'original_head_uv_coordinate_count':130,'head_uv_changed_coordinates':18,'head_uv_changed_fraction':18/130,'uv_chart_count_change_limit':.20},
              'selected_generations':[r['path'] for r in records if r['selected']],
              'generation_records':'build/generation.json','outputs':outputs,
              'verification':{'runtime':'review/runtime_test.json','engine_roundtrip':'review/roundtrip_test.json','geometry':'review/proportion_test.json','blender':'review/blender_validate.json','blender_roundtrip':'review/blender_roundtrip/roundtrip.json'},
              'visual_review':'Compared actual front/side/rear/quarter, closeup, idle/run/reload and two game levels. V7 follows the user-selected helmet: continuous purple visor, central lower polygon bevel seam, dark angled lens edges, blue framed cheek recesses. Only18 of130 headUVs moved inside the original visor chart, whole-face mapping avoids mirrored reflections. Front black brow/blue center and blue crown channels retained. Original low-poly side ear mass and source shell construction retained. User art approval remains pending.',
              'inferred':'Local chin/cheek/brow depth from a perspective helmet concept; original hidden rear/neck/joints/bodyUV authoritative; user explicitly allowed local helmetUV changes with20% tolerance.'}
    (WORK/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('VIPER_PROVENANCE_PASS generations=%d selected=%d outputs=%d'%(len(records),len(manifest['selected_generations']),len(outputs)))

if __name__=='__main__':main()
