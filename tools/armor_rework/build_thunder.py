"""Build the full reference Thunder helmet and armor on the existing rig.

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
        texture_dir = 'assets/equipment_refined/textures' if index == 0 else 'assets/armors/thunder/textures'
        image = bpy.data.images.load(str(ROOT / texture_dir / f'{texture_stems[index]}.png'))
        tex = nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    else:
        shader.inputs['Base Color'].default_value = colors[index - 5]
        if index == 9:
            tex = nodes.new('ShaderNodeTexImage')
            tex.image = bpy.data.images.load(str(ROOT / 'assets/armors/thunder/textures/amber_visor_paint.png'))
            mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        if index in [5, 6, 7]:
            tex = nodes.new('ShaderNodeTexImage')
            tex.image = bpy.data.images.load(str(ROOT / 'assets/armors/thunder/textures/blue_shell_paint.png'), check_existing=True)
            tint = nodes.new('ShaderNodeMixRGB')
            tint.blend_type = 'MULTIPLY'
            tint.inputs[0].default_value = 1.0
            tint.inputs[2].default_value = [(1,1,1,1),(.43,.50,.55,1),(1.45,1.35,1.22,1)][index-5]
            mat.node_tree.links.new(tex.outputs['Color'], tint.inputs[1])
            mat.node_tree.links.new(tint.outputs['Color'], shader.inputs['Base Color'])
    materials.append(mat)
mat = bpy.data.materials.new('Thunder_PairedHelmet')
mat.use_nodes = True
tree = mat.node_tree
shader = tree.nodes.get('Principled BSDF')
shader.inputs['Roughness'].default_value = .68
shader.inputs['Metallic'].default_value = .08
tex = tree.nodes.new('ShaderNodeTexImage')
tex.image = bpy.data.images.load(str(ROOT / 'assets/armors/thunder/textures/helmet_detail_albedo.png'))
tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
texn = tree.nodes.new('ShaderNodeTexImage')
texn.image = bpy.data.images.load(str(ROOT / 'assets/armors/thunder/textures/helmet_detail_normal.png'))
texn.image.colorspace_settings.name = 'Non-Color'
normal = tree.nodes.new('ShaderNodeNormalMap')
tree.links.new(texn.outputs['Color'], normal.inputs['Color'])
tree.links.new(normal.outputs['Normal'], shader.inputs['Normal'])
materials.append(mat)
for name, color in [('RespiratorSteel', (.042, .052, .068, 1)), ('RespiratorEdge', (.10, .125, .15, 1))]:
    mat = bpy.data.materials.new('Thunder_' + name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = color
    shader.inputs['Roughness'].default_value = .65
    shader.inputs['Metallic'].default_value = .12
    materials.append(mat)
helmet = module('thunder_helmet')
body = module('thunder_body')
helmet.refine_helmet(parts[0], materials)
for obj in parts[1:]:
    body.refine_body(obj, materials[:11])
output = []
report = []
for obj in parts:
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    bpy.context.view_layer.objects.active = obj
    triangulate = obj.modifiers.new('Triangulate closed detail caps', 'TRIANGULATE')
    triangulate.min_vertices = 5
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    obj.data.calc_loop_triangles()
    assert obj.data.uv_layers.active is not None, (obj.name, 'missing UV layer')
    obj.data.calc_tangents(uvmap=obj.data.uv_layers.active.name)
    attrs = {'name': obj.name, 'positions': [], 'normals': [], 'tangents': [], 'uv': [], 'bones': [], 'weights': [], 'materials': []}
    normal_data = obj.data.corner_normals
    for tri in obj.data.loop_triangles:
        material = obj.data.materials[tri.material_index]
        attrs['materials'].append(materials.index(material))
        for loop in tri.loops:
            vertex = obj.data.vertices[obj.data.loops[loop].vertex_index]
            attrs['positions'].extend(vertex.co)
            attrs['normals'].extend(normal_data[loop].vector.normalized())
            attrs['tangents'].extend(obj.data.loops[loop].tangent)
            attrs['tangents'].append(obj.data.loops[loop].bitangent_sign)
            attrs['uv'].extend(obj.data.uv_layers.active.data[loop].uv)
            groups = sorted((g for g in vertex.groups if g.weight > 0), key=lambda g: g.weight, reverse=True)[:4]
            total = sum(g.weight for g in groups)
            assert total > 0, (obj.name, vertex.index, 'unweighted vertex')
            attrs['bones'].append([obj.vertex_groups[g.group].name for g in groups])
            attrs['weights'].append([g.weight / total for g in groups])
    output.append(attrs)
    report.append({'name': obj.name, 'triangles': len(attrs['materials']),
                   'authored_panels': obj.get('thunder_raised_plates', 0),
                   'bounds': [[min(v.co[i] for v in obj.data.vertices), max(v.co[i] for v in obj.data.vertices)] for i in range(3)]})
    armature = obj.modifiers.new('Original player rig', 'ARMATURE')
    armature.object = rig
out = ROOT / 'test_output/armor_rework'
(out / 'thunder_meshes.json').write_text(json.dumps(output, separators=(',', ':')))
asset_dir = ROOT / 'assets/armors/thunder'
asset_dir.mkdir(parents=True, exist_ok=True)
concept = ROOT / 'docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png'
(asset_dir / 'build_report.json').write_text(json.dumps({
    'design': 'Thunder detail v4 / paired SW2 helmet, recessed respirator and faceted armor',
    'revision': 'thunder_detail_v4',
    'concept': str(concept.relative_to(ROOT)),
    'concept_sha256': hashlib.sha256(concept.read_bytes()).hexdigest(),
    'source_sha256': hashlib.sha256((ROOT / 'assets/models/player/animated/player.gltf').read_bytes()).hexdigest(),
    'parts': report,
    'texture_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((asset_dir / 'textures').glob('*.png'))},
    'scope': 'Paired original SW2 helmet topology/UV/normal map, low concept crown, recessed respirator, chamfered body armor, original bind pose; set06 only',
    'head_source_sha256': hashlib.sha256((asset_dir / 'source_sw2/modern_head.json').read_bytes()).hexdigest(),
}, indent=2) + '\n')
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
bpy.data.orphans_purge(do_recursive=True)
for image in bpy.data.images:
    if image.filepath and Path(image.filepath).is_absolute():
        image.filepath = '//../../../' + Path(image.filepath).relative_to(ROOT).as_posix()
native = ROOT / 'docs/art/armor_rework'
native.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(native / 'thunder.blend'), compress=True)
print('THUNDER_MODEL_BUILD_PASS', json.dumps(report))
