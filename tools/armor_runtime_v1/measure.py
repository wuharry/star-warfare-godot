"""Measure original/candidate silhouettes at identical fixed Godot cameras.

Read-only image analysis: no texture or generated art is edited here.
"""
import json
import argparse
import hashlib
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def capture_path(value, work):
    if value is None:
        return work/'review/engine'
    path=Path(value).expanduser()
    if path.is_absolute():
        return path.resolve()
    for candidate in [ROOT/path,work/path,work/'review'/path]:
        if candidate.is_dir():
            return candidate.resolve()
    raise FileNotFoundError('Capture directory does not exist: '+value)

def report_path(value, work):
    if value is None:
        return work/'review/proportion_test.json'
    path=Path(value).expanduser()
    if path.is_absolute():
        return path
    return (work/'review'/path) if len(path.parts)==1 else ROOT/path

def mask(path):
    im=Image.open(path).convert('RGB')
    background=im.getpixel((0,0))
    return im.size,{(i%im.width,i//im.width) for i,p in enumerate(im.getdata())
                    if max(abs(p[c]-background[c]) for c in range(3))>18}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--armor',choices=['hydra','strike','titan','atom','pegasus'],required=True)
    parser.add_argument('--capture-dir',help='Capture directory; default review/engine. Explicit captures must match current SCN, target and five maps.')
    parser.add_argument('--report',help='Report path, or a filename within this armor review directory.')
    args=parser.parse_args();slug=args.armor
    work=ROOT/f'docs/art/{slug}_runtime_v1'
    config=json.loads((work/'runtime_config.json').read_text(encoding='utf-8'))
    output=report_path(args.report,work)
    report={'status':'FAIL','scope':'Geometry silhouettes only; does not measure texture likeness or artistic approval.',
            'limit':.20,'silhouettes':[],
            'inferred':'Head-only source deformation guided by approved design. Original mesh owns game scale, hidden rear, UV charts and joints; all body/limbs exact.'}
    if config.get('geometry_mode')=='original_source_bounded_refinement':
        report['geometry_mode']=config['geometry_mode']
        report['geometry_parts']=config['geometry_parts']
        report['inferred']=('Approved concept guides positions in the explicitly configured original parts: '+', '.join(config['geometry_parts'])+
                            '. Their normal/tangent frames are recalculated; all other surface arrays and every original UV0, index, vertex count, skin, weight and transform stay exact. '
                            'Per-part displacement/dimension budgets are cumulative from the true original source, never from the last revision. Hidden side/back forms remain inferred from the approved concept; image silhouette change is measured independently at the same four original cameras.')
    try:
        captures=capture_path(args.capture_dir,work)
        report['capture_directory']=str(captures.relative_to(ROOT)) if captures.is_relative_to(ROOT) else str(captures)
        summary_path=captures/'capture.json'
        summary=None
        if args.capture_dir is not None or summary_path.is_file():
            summary=json.loads(summary_path.read_text(encoding='utf-8'))
            report['capture_summary_sha256']=digest(summary_path)
            assets=ROOT/config['asset']
            scene=assets/f'{slug}.scn';target=work/'build/target.json'
            maps={label:assets/config.get('texture_files',{}).get(label,label+'_diffuse.png')
                  for label in ['head','body','shoulder','hand','foot']}
            hashes={'current_scene_sha256':digest(scene),'target_sha256':digest(target),
                    'canonical_diffuse_sha256':{label:digest(path) for label,path in maps.items()}}
            report.update(hashes)
            assert summary['scene_sha256_at_start']==hashes['current_scene_sha256'],'Capture SCN hash is stale'
            assert summary['target_sha256_at_start']==hashes['target_sha256'],'Capture target hash is stale'
            assert summary['canonical_diffuse_sha256_at_start']==hashes['canonical_diffuse_sha256'],'Capture five-map hashes are stale'
            report['capture_matches_current_resources']=True
        for view in ['front','side','rear','quarter']:
            original=captures/f'original_clay_{view}.png';candidate=captures/f'new_clay_{view}.png'
            if summary is not None:
                for path in [original,candidate]:
                    key='res://'+path.relative_to(ROOT).as_posix()
                    assert summary['capture_sha256'][key]==digest(path),'Captured clay PNG hash changed: '+key
            size,a=mask(original)
            size_b,b=mask(candidate)
            assert size==size_b
            iou=len(a&b)/len(a|b)
            report['silhouettes'].append({'view':view,'silhouette_iou':iou,'silhouette_changed_fraction':1-iou,'camera_identical':True,'pixels':list(size)})
            assert 1-iou<=.20
        report['geometry']=json.loads((work/'build/geometry.json').read_text(encoding='utf-8'))
        report['geometry_sha256']=digest(work/'build/geometry.json')
        report['source_sha256']=digest(work/'build/source.json')
        report['status']='PASS'
    except (AssertionError,KeyError,ValueError,OSError,ZeroDivisionError) as error:
        report['error']=str(error) or type(error).__name__
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    if report['status']=='PASS':
        print(slug.upper()+'_PROPORTION_PASS max_silhouette_change=%.5f'%max(1-r['silhouette_iou'] for r in report['silhouettes']))
        return 0
    print(slug.upper()+'_PROPORTION_FAIL '+report['error'])
    return 1

if __name__=='__main__':raise SystemExit(main())
