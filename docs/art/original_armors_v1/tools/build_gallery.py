"""Build the offline review gallery and provenance manifest from inspected assets."""
import hashlib,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
ART=ROOT/'docs/art/original_armors_v1'
WORK=ART
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def formal_ref(path,kind='halo'): return 'references/'+kind+'/'+Path(path).name
def png_size(path):
    with path.open('rb') as stream: header=stream.read(24)
    assert header[:8]==b'\x89PNG\r\n\x1a\n',path
    return list(struct.unpack('>II',header[16:24]))
mapping_path=ART/'runtime_mapping.json'
mapping=read(mapping_path)
halo={}
for filename in ['halo_matches_01_07.json','halo_matches_08_14.json','halo_matches_15_21.json']:
    for match in read(ART/'sources'/filename)['matches']: halo[match['design_id']]=match
halo_bags={x['design_id']:x for x in read(ART/'sources'/'halo_backpack_matches.json')['matches']}
early={x['design_id']:x for x in read(ART/'sources'/'legacy_armor_audit.json')['armors']}
late={x['design_id']:x for x in read(ART/'sources'/'legacy_armor_later.json')['entries']}
bags={x['design_id']:x for x in read(ART/'sources'/'legacy_backpacks.json')['backpacks']}
assets=[]
for path in sorted((WORK/'generation_records').glob('*.json')):
    r=read(path)
    if 'not_selected' in r.get('status','') or '_v1' in path.stem: continue
    if not r.get('visual_review') or not (ART/r['path']).is_file(): continue
    if r.get('status')!='visually_reviewed_pending_user_selection': continue
    r['generation_record']='generation_records/'+path.name;r['sha256']=sha(ART/r['path']);r['dimensions']=png_size(ART/r['path'])
    r['bytes']=(ART/r['path']).stat().st_size;r['prompt_sha256']=sha(ART/r['prompt'])
    r['reference_sha256']={ref:sha(ART/ref) for ref in r.get('reference_images',[])}
    assets.append(r)
catalog=[]
for kind,entries in [('armor',mapping['armor_mappings']),('backpack',mapping['backpack_mappings'])]:
    for m in entries:
        did=m['design_id'];num=int(did.split('-')[1]);code=did.lower().replace('-','')
        candidates=list(ART.glob(code+'_*.json'))
        metadata=read(candidates[0]) if len(candidates)==1 else {}
        my_assets=[r for r in assets if r['design_id']==did]
        images={r['kind']:r['path'] for r in my_assets}
        if kind=='armor':
            h=halo[did];o=early.get(did,late.get(did,{}))
            raw_refs=h.get('images',h.get('references',[]))
            halo_info=dict(variant=h['variant'],game=h['game'],url=h.get('article_url',h.get('source_page_url','')),reference_images=[dict(path=formal_ref(x['local_path']),label=x.get('role',x.get('key','參考 '+str(i+1)))) for i,x in enumerate(raw_refs) if (ART/formal_ref(x['local_path'])).exists()])
            legacy_refs=[dict(path=f'references/legacy/{code}_{v}.png',label=label) for v,label in [('front','原模型：前方'),('side','原模型：側方'),('rear','原模型：背方')]]
            legacy_name=m['legacy_set_name']
            observed=h.get('observed',{})
            fusion=dict(retained=o.get('retain_in_fusion',o.get('retained_cues',[])),borrowed=[observed[k] for k in ('helmet','torso','chest') if k in observed],optimized=[o.get('optimization_direction',o.get('optimization',''))])
            if did=='C-06':
                halo_info=dict(variant='使用者指定的兩款全罩式頭盔',game='使用者提供的 Halo 參考',url='https://www.halopedia.org/Armor_customization',reference_images=[],reference_note='本稿直接使用對話中的兩張頭盔附件；附件沒有工作區檔案，因此不以其他款式冒充原參考。')
                fusion['borrowed']=['連續大面積曲面玻璃、厚頰框與封閉下顎；以使用者兩張頭盔圖為最高優先。']
        else:
            h=halo_bags[did];o=bags[did];legacy_name=m['legacy_name']
            halo_info=dict(variant=h['halo_name'],game=h['halo_game'],url=h['halo_source_page_url'],reference_images=[dict(path=formal_ref(x['local_path']),label=x.get('key','設備／背部參考')) for x in h['references'] if (ART/formal_ref(x['local_path'])).exists()])
            legacy_refs=[dict(path=formal_ref(path,'legacy'),label=label) for label,path in o['reference_views'].items()]
            fusion=dict(retained=[o['observed_silhouette'],o['retain_for_fusion']],borrowed=[h['observed_back_cue']],optimized=['重排外殼接縫、加入穿戴者側襯墊與可拆固定點；仍是獨立背包。'])
        recipe=metadata.get('fusion_recipe',{})
        for key in ['retained','borrowed','optimized']:
            if recipe.get(key):
                value=recipe[key]
                fusion[key]=value if isinstance(value,list) else [v for k,v in value.items() if k in ('helmet','torso','chest','back')] if isinstance(value,dict) else [value]
        if did in ('C-14','C-17'):
            halo_info['variant'] += '（身甲參考）'
            halo_info['reference_note'] = '頭盔以原版改造為主；此圖僅保留頸部與身甲結構參考。'
        item=dict(design_id=did,kind=kind,working_name_zh=metadata.get('working_name_zh',m.get('working_name_zh',legacy_name)),working_name_en=metadata.get('working_name_en',m.get('working_name_en','')),legacy_name=legacy_name,legacy_id=num-1,status=metadata.get('status','generation_in_progress'),images=images,_assets=my_assets,legacy_refs=legacy_refs,halo=halo_info,fusion=fusion,role=metadata.get('role',''),stats={},abilities=metadata.get('proposed_abilities',[]),source_file=candidates[0].name if len(candidates)==1 else '')
        if kind=='backpack':item['stats']={'capacity':o['current_bag_slots'],'basis':'目前遊戲背包欄位；新造型與技能尚未接入'}
        else:
            stats=metadata.get('proposed_stats',{});item['stats']={k:v for k,v in stats.items() if k in ['basis','per_part','four_piece_total','movement_modifier','damage_modifier','unlock']}
        catalog.append(item)
template=(ART/'tools/gallery.template.html').read_text(encoding='utf-8')
assert template.count('__CATALOG_JSON__')==1
embedded=json.dumps(catalog,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')
(ART/'index.html').write_text(template.replace('__CATALOG_JSON__',embedded),encoding='utf-8')
sources=[]
for path in sorted((ART/'references').rglob('*')):
    if path.is_file():
        sources.append(dict(path=path.relative_to(ART).as_posix(),sha256=sha(path),bytes=path.stat().st_size,purpose='source_reference_not_generated_delivery'))
archived=[]
for path in sorted((WORK/'generation_records').glob('*.json')) + sorted((ART/'revisions').rglob('*.json')):
    r=read(path)
    if isinstance(r,dict) and r.get('path') and r.get('prompt') and r.get('status') and r['status']!='visually_reviewed_pending_user_selection':
        r['record_path']=path.relative_to(ART).as_posix();archived.append(r)
expected_keys={(f'C-{i:02d}',kind) for i in range(1,22) for kind in ('concept','turnaround','construction')} | {(f'B-{i:02d}','design_sheet') for i in range(1,26)}
complete=len(assets)==88 and {(a['design_id'],a['kind']) for a in assets}==expected_keys
manifest=dict(schema_version=2,date='2026-09-25',scope={'armors':21,'backpacks':25,'expected_selected_images':88},status='complete_pending_user_review' if complete else 'generation_in_progress',runtime_changed=False,tool='built-in image_gen',postprocessing='none',reference_entrypoint='https://www.halopedia.org/Armor_customization',assets=assets,reference_assets=sources,rejected_iterations=archived,previous_delivery_reset={'previous_generated_art_removed':True,'note':'舊交付已重新生成；本輪未採用及使用者修訂前稿另存於 revisions/ 或 v1 圖與紀錄。'},notes=['選用圖是概念／建模參考，非UV貼圖或遊戲模型。','三視近似正交；比例、固定位置與微小接縫須在3D階段統一。','Halo和原遊戲圖是來源參考，來源權利不因融合生成而消失；未聲稱法律授權。','B編號對應獨立背包ID，與同序C同框僅為本轮展示搭配。'])
manifest['prompt_files']=[dict(path=p.relative_to(ART).as_posix(),sha256=sha(p)) for p in sorted((ART/'prompts').glob('*.txt'))]
(ART/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

print(json.dumps({'catalog':len(catalog),'selected_images':len(assets),'references':len(sources),'status':manifest['status']}))
