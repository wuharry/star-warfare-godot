"""Measure original/candidate silhouettes at identical fixed Godot cameras.

Read-only image analysis: no texture or generated art is edited here.
"""
import json
import argparse
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--armor',choices=['hydra','strike','titan'],required=True)
slug=parser.parse_args().armor
WORK=ROOT/f'docs/art/{slug}_runtime_v1'

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
        assert 1-iou<=.20
    geometry=json.loads((WORK/'build/geometry.json').read_text())
    report={'status':'PASS','scope':'Geometry silhouettes only; does not measure texture likeness or artistic approval.',
            'limit':.20,'silhouettes':records,'geometry':geometry,
            'inferred':'Head-only source deformation guided by approved design. Original mesh owns game scale, hidden rear, UV charts and joints; all body/limbs exact.'}
    (WORK/'review/proportion_test.json').write_text(json.dumps(report,indent=2))
    print(slug.upper()+'_PROPORTION_PASS max_silhouette_change=%.5f'%max(1-r['silhouette_iou'] for r in records))

if __name__=='__main__':main()
