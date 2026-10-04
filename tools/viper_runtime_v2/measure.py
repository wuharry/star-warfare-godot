"""Measure original/candidate silhouettes at identical fixed Godot cameras.

Read-only image analysis: no texture or generated art is edited here.
"""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/viper_runtime_v2'
SILHOUETTE_CHANGE_LIMIT=.15
LOCAL_GEOMETRY_CHANGE_LIMIT=.15

def mask(path):
    im=Image.open(path).convert('RGB')
    background=im.getpixel((0,0))
    return im.size,{(i%im.width,i//im.width) for i,p in enumerate(im.getdata())
                    if max(abs(p[c]-background[c]) for c in range(3))>18}

def main():
    records=[]
    for view in ['front','side','rear','quarter']:
        size,a=mask(WORK/f'review/engine/original_clay_{view}.png')
        size_b,b=mask(WORK/f'review/engine/new_clay_{view}.png')
        assert size==size_b
        iou=len(a&b)/len(a|b)
        records.append({'view':view,'silhouette_iou':iou,'silhouette_changed_fraction':1-iou,'camera_identical':True,'pixels':list(size)})
        assert 1-iou<=SILHOUETTE_CHANGE_LIMIT
    geometry=json.loads((WORK/'build/geometry.json').read_text())
    assert geometry.get('limits',{}).get('local_geometry_change_fraction')==LOCAL_GEOMETRY_CHANGE_LIMIT
    for name,part in geometry['parts'].items():
        assert max(part['dimension_delta_fraction'])<=LOCAL_GEOMETRY_CHANGE_LIMIT, f'{name}: dimensions exceed 15%'
        assert part['max_displacement_fraction_of_smallest_dimension']<=LOCAL_GEOMETRY_CHANGE_LIMIT, f'{name}: local displacement exceeds 15%'
    report={'status':'PASS','scope':'Geometry silhouettes only; does not measure texture likeness or artistic approval.',
            'limit':SILHOUETTE_CHANGE_LIMIT,
            'local_geometry_change_limit':LOCAL_GEOMETRY_CHANGE_LIMIT,
            'silhouettes':records,'geometry':geometry,
            'inferred':'Local chin/cheek/brow depth inferred from selected perspective art; original mesh owns game scale, hidden rear and all joint positions.'}
    (WORK/'review/proportion_test.json').write_text(json.dumps(report,indent=2))
    print('VIPER_PROPORTION_PASS max_silhouette_change=%.5f'%max(1-r['silhouette_iou'] for r in records))

if __name__=='__main__':main()
