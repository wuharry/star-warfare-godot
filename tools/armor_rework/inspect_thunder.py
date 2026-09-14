"""Inspect Thunder's unchanged source bind-pose coordinates with Blender."""
import json
import runpy
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
runpy.run_path(str(Path(__file__).with_name('inspect_source.py')))
report = {}
for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.name.endswith('_06'):
        continue
    counts = {}
    for vertex in obj.data.vertices:
        for group in vertex.groups:
            name = obj.vertex_groups[group.group].name
            counts[name] = counts.get(name, 0) + group.weight
    report[obj.name] = {
        'matrix': [list(row) for row in obj.matrix_world],
        'bounds': [[min(v.co[i] for v in obj.data.vertices), max(v.co[i] for v in obj.data.vertices)] for i in range(3)],
        'groups': counts,
        'materials': [m.name for m in obj.data.materials],
    }
(ROOT / 'test_output/armor_rework/thunder_source.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
head = bpy.data.objects['ArmorHead_06']
texture = bpy.data.images.load(str(ROOT / 'assets/equipment_refined/textures/f8d96c60d30f.png'))
pixels = list(texture.pixels)
width, height = texture.size
print('HEAD_ORANGE_FACES')
for p in head.data.polygons:
    uv = sum((head.data.uv_layers.active.data[i].uv for i in p.loop_indices), __import__('mathutils').Vector((0, 0))) / len(p.loop_indices)
    pixel = (int(uv.y * (height - 1)) * width + int(uv.x * (width - 1))) * 4
    r, g, b = pixels[pixel:pixel+3]
    if r > b * 1.3 and r > .12:
        print(p.index, list(p.vertices), [round(n, 4) for n in p.center], [round(n, 3) for n in (r,g,b)])
