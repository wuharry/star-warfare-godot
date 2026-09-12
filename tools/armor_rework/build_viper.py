"""Refine the actual Viper meshes, preserving silhouette, UVs and source weights.

Run in Blender, then compile_viper.gd in Godot. No replacement primitive armor.
"""
import bpy
import bmesh
import hashlib
import json
import math
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
runpy.run_path(str(Path(__file__).with_name('inspect_source.py')))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.endswith('_00')]
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o not in parts:
        bpy.data.objects.remove(o, do_unlink=True)

MATERIAL_KEYS = ['head', 'body', 'shoulder', 'arms', 'legs']
SUFFIX = {'head': 'head', 'body': 'body', 'jian': 'shoulder', 'hand': 'arms', 'foot': 'legs'}
materials = {}
for key in MATERIAL_KEYS:
    m = bpy.data.materials.new('ViperRefined_' + key)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value = .72
    p.inputs['Metallic'].default_value = .05
    image = bpy.data.images.load(str(ROOT / f'assets/armors/viper/textures/{key}.png'))
    tex = m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = image
    m.node_tree.links.new(tex.outputs['Color'], p.inputs['Base Color'])
    materials[key] = m

output = []
report = []
for o in parts:
    old_bounds = [[min(v.co[i] for v in o.data.vertices), max(v.co[i] for v in o.data.vertices)] for i in range(3)]
    old_triangles = sum(len(p.vertices) - 2 for p in o.data.polygons)
    slots = [SUFFIX[m.name.rsplit('_', 1)[-1]] for m in o.data.materials]
    for i, key in enumerate(slots):
        o.data.materials[i] = materials[key]
    for modifier in list(o.modifiers):
        o.modifiers.remove(modifier)
    # Weld only identical positions; loop UVs retain the original island seams.
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=.000001)
    bm.to_mesh(o.data); bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    o.hide_set(False); o.hide_render = False; o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bevel = o.modifiers.new('Subtle original edge refinement', 'BEVEL')
    bevel.width = .0012 if 'Hand' in o.name else .002
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(42)
    bevel.use_clamp_overlap = True
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    # Bevel interpolation can overshoot deform weights below zero. Godot clamps
    # them on upload, so clamp before normalizing in both native and runtime data.
    for v in o.data.vertices:
        groups = sorted((g for g in v.groups if g.weight > 0), key=lambda g: g.weight, reverse=True)[:4]
        total = sum(g.weight for g in groups)
        assert total > 0, (o.name, v.index)
        normalized = {g.group: g.weight / total for g in groups}
        for group_index in [g.group for g in v.groups]:
            if group_index in normalized:
                o.vertex_groups[group_index].add([v.index], normalized[group_index], 'REPLACE')
            else:
                o.vertex_groups[group_index].remove([v.index])
    o.data.calc_loop_triangles()
    attrs = {'name': o.name, 'positions': [], 'normals': [], 'uv': [], 'bones': [], 'weights': [], 'materials': []}
    normals = o.data.corner_normals
    for tri in o.data.loop_triangles:
        attrs['materials'].append(MATERIAL_KEYS.index(slots[tri.material_index]))
        for li in tri.loops:
            vi = o.data.loops[li].vertex_index; v = o.data.vertices[vi]
            attrs['positions'].extend(v.co)
            attrs['normals'].extend(normals[li].vector)
            attrs['uv'].extend(o.data.uv_layers.active.data[li].uv)
            groups = sorted(v.groups, key=lambda g: g.weight, reverse=True)[:4]
            total = sum(g.weight for g in groups)
            assert total > 0, (o.name, vi)
            attrs['bones'].append([o.vertex_groups[g.group].name for g in groups])
            attrs['weights'].append([g.weight / total for g in groups])
    output.append(attrs)
    new_bounds = [[min(v.co[i] for v in o.data.vertices), max(v.co[i] for v in o.data.vertices)] for i in range(3)]
    deviation = max(abs(new_bounds[i][k] - old_bounds[i][k]) for i in range(3) for k in range(2))
    assert deviation < .005, (o.name, 'silhouette bounds changed', deviation)
    report.append({'part': o.name, 'original_triangles': old_triangles, 'triangles': len(attrs['materials']), 'max_bounds_change_m': deviation, 'material_keys': slots})
    arm = o.modifiers.new('Original player rig', 'ARMATURE'); arm.object = rig

out = ROOT / 'test_output/armor_rework'
(out / 'viper_meshes.json').write_text(json.dumps(output, separators=(',', ':')))
source = ROOT / 'assets/models/player/animated/player.gltf'
summary = {
    'approach': 'original mesh refinement; original UVs and bone weights retained',
    'concept_reference': '068f4785eee8542217b2e0a3ab4f72b16056f5bf / v2 Viper style anchor',
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'parts': report,
}
(ROOT / 'assets/armors/viper/build_report.json').write_text(json.dumps(summary, indent=2) + '\n')
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
bpy.data.orphans_purge(do_recursive=True)
for key, m in materials.items():
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE':
            n.image.filepath = f'//../../../assets/armors/viper/textures/{key}.png'
bpy.context.preferences.filepaths.save_version = 0
native = ROOT / 'docs/art/armor_rework'
native.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(native / 'viper.blend'), compress=True)
print('VIPER_MODEL_BUILD_PASS parts=4 triangles=' + str(sum(len(p['materials']) for p in output)))
