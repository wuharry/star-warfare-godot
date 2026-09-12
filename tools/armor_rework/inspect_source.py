"""Read the recovered Blender bind pose without changing project assets."""
import bpy
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
source = ROOT / 'assets/models/player/animated/player.gltf'
document = json.loads(source.read_text())
document['extensionsRequired'] = [e for e in document.get('extensionsRequired', []) if e != 'KHR_node_visibility']
document['extensionsUsed'] = [e for e in document.get('extensionsUsed', []) if e != 'KHR_node_visibility']
for node in document['nodes']:
    node.get('extensions', {}).pop('KHR_node_visibility', None)
for item in document['buffers'] + document['images']:
    if 'uri' in item:
        item['uri'] = (source.parent / item['uri']).as_posix()
out = ROOT / 'test_output/armor_rework'
out.mkdir(parents=True, exist_ok=True)
temporary = out / 'blender_source.gltf'
temporary.write_text(json.dumps(document))
bpy.ops.import_scene.gltf(filepath=str(temporary))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
rig.animation_data_clear()
rig.data.pose_position = 'REST'
bpy.context.view_layer.update()
report = {'rig': rig.name, 'matrix': [list(v) for v in rig.matrix_world], 'bones': {}, 'parts': {}}
for bone in rig.data.bones:
    report['bones'][bone.name] = {
        'head': list(rig.matrix_world @ bone.head_local),
        'tail': list(rig.matrix_world @ bone.tail_local),
        'matrix': [list(v) for v in rig.matrix_world @ bone.matrix_local],
    }
for o in list(bpy.data.objects):
    if o.type != 'MESH' or not o.name.endswith('_00'):
        continue
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    report['parts'][o.name] = {
        'min': [min(v[i] for v in pts) for i in range(3)],
        'max': [max(v[i] for v in pts) for i in range(3)],
        'groups': [v.name for v in o.vertex_groups],
        'matrix': [list(v) for v in o.matrix_world],
    }
out = ROOT / 'test_output/armor_rework'
out.mkdir(parents=True, exist_ok=True)
(out / '.gdignore').write_text('')
(out / 'source.json').write_text(json.dumps(report, indent=2))
print('ARMOR_SOURCE_INSPECT_PASS')
