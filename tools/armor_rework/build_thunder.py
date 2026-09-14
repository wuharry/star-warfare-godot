"""Build the approved Thunder B helmet/armor variant on the existing rig.

Blender --background --python tools/armor_rework/build_thunder.py
godot --headless --path . --script tools/armor_rework/compile_thunder.gd
"""
import hashlib
import importlib.util
import json
import runpy
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
runpy.run_path(str(HERE / 'inspect_source.py'))


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
names = ['ArmorHead_06', 'ArmorBody_06', 'ArmorHand_06', 'ArmorFoot_06']
parts = [bpy.data.objects[name] for name in names]
for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and obj not in parts:
        bpy.data.objects.remove(obj, do_unlink=True)
texture_stems = ['f8d96c60d30f', 'dce7a1446714', 'd6da6925f6b4', 'df2d0a0b46da', '14ceb45bf36d']
colors = [(0.16, .28, .43, 1), (.075, .13, .21, 1), (.24, .34, .44, 1),
          (.88, .56, .11, 1), (1, .61, .13, 1), (.018, .025, .035, 1)]
materials = []
for index in range(11):
    mat = bpy.data.materials.new(f'Thunder_{index:02d}')
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    output = nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Roughness'].default_value = .48
    shader.inputs['Metallic'].default_value = .28 if index >= 5 else .05
    if index < 5:
        image = bpy.data.images.load(str(ROOT / f'assets/equipment_refined/textures/{texture_stems[index]}.png'))
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    else:
        shader.inputs['Base Color'].default_value = colors[index - 5]
    materials.append(mat)
helmet = module('thunder_helmet')
body = module('thunder_body')
helmet.refine_helmet(parts[0], materials)
for obj in parts[1:]:
    body.refine_body(obj, materials)
output = []
report = []
for obj in parts:
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    obj.data.calc_loop_triangles()
    attrs = {'name': obj.name, 'positions': [], 'normals': [], 'uv': [], 'bones': [], 'weights': [], 'materials': []}
    normal_data = obj.data.corner_normals
    for tri in obj.data.loop_triangles:
        material = obj.data.materials[tri.material_index]
        attrs['materials'].append(materials.index(material))
        for loop in tri.loops:
            vertex = obj.data.vertices[obj.data.loops[loop].vertex_index]
            attrs['positions'].extend(vertex.co)
            attrs['normals'].extend(normal_data[loop].vector.normalized())
            attrs['uv'].extend(obj.data.uv_layers.active.data[loop].uv)
            groups = sorted((g for g in vertex.groups if g.weight > 0), key=lambda g: g.weight, reverse=True)[:4]
            total = sum(g.weight for g in groups)
            assert total > 0, (obj.name, vertex.index, 'unweighted vertex')
            attrs['bones'].append([obj.vertex_groups[g.group].name for g in groups])
            attrs['weights'].append([g.weight / total for g in groups])
    output.append(attrs)
    report.append({'name': obj.name, 'triangles': len(attrs['materials']),
                   'bounds': [[min(v.co[i] for v in obj.data.vertices), max(v.co[i] for v in obj.data.vertices)] for i in range(3)]})
    armature = obj.modifiers.new('Original player rig', 'ARMATURE')
    armature.object = rig
out = ROOT / 'test_output/armor_rework'
(out / 'thunder_meshes.json').write_text(json.dumps(output, separators=(',', ':')))
asset_dir = ROOT / 'assets/armors/thunder'
asset_dir.mkdir(parents=True, exist_ok=True)
concept = ROOT / 'docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png'
(asset_dir / 'build_report.json').write_text(json.dumps({
    'design': 'Thunder B / mk1 palette / approved reference helmet v2',
    'concept': str(concept.relative_to(ROOT)),
    'concept_sha256': hashlib.sha256(concept.read_bytes()).hexdigest(),
    'source_sha256': hashlib.sha256((ROOT / 'assets/models/player/animated/player.gltf').read_bytes()).hexdigest(),
    'parts': report,
    'scope': 'Original Thunder UV base and bind pose with authored hard shell geometry; set06 visual replacement only',
}, indent=2) + '\n')
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
bpy.data.orphans_purge(do_recursive=True)
for mat in materials[:5]:
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            node.image.filepath = '//../../../assets/equipment_refined/textures/' + Path(node.image.filepath).name
native = ROOT / 'docs/art/armor_rework'
native.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(native / 'thunder.blend'), compress=True)
print('THUNDER_MODEL_BUILD_PASS', json.dumps(report))
