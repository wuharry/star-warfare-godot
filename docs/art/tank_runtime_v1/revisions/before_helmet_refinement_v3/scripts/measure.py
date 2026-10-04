"""Measure original/candidate silhouettes at identical fixed Godot cameras.

Read-only image analysis: no texture or generated art is edited here.
"""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/tank_runtime_v1'

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
        assert 1-iou<=.15
    geometry=json.loads((WORK/'build/geometry.json').read_text())
    report={'status':'PASS','scope':'Geometry silhouettes only; does not measure texture likeness or artistic approval.',
            'limit':.15,'silhouettes':records,'geometry':geometry,
            'inferred':'Local lower chin/cheek depth inferred from selected perspective art; original mesh owns game scale, hidden rear and all joint positions.'}
    (WORK/'review/proportion_test.json').write_text(json.dumps(report,indent=2))
    print('TANK_PROPORTION_PASS max_silhouette_change=%.5f'%max(1-r['silhouette_iou'] for r in records))

if __name__=='__main__':main()
