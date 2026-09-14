"""Render SW2 clay references; optional UV diagnostics are NOT valid original colors."""
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'assets/redesigned_armors/set_06_storm_thunder/reference_sw2_thunder'
OUT = Path(__file__).resolve().parent / 'references'
OUT.mkdir(parents=True, exist_ok=True)
probe = '--probe' in sys.argv
clay = not probe and '--textured-diagnostic' not in sys.argv
if probe or not clay:
    OUT = Path(__file__).resolve().parent / 'diagnostics'
    OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 8 if probe else 24
scene.render.resolution_x = 1200
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.color = (0.22, 0.22, 0.22)
scene.view_settings.view_transform = 'Standard'
objects = []
for part in (('head',) if probe else ('head', 'body', 'hand', 'foot')):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=str(SOURCE / 'models' / f'sw2_thunder_{part}.obj'), forward_axis='NEGATIVE_Y', up_axis='Z')
    material = bpy.data.materials.new(f'reference_{part}')
    material.use_nodes = True
    material.node_tree.nodes.clear()
    shader = material.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Roughness'].default_value = 0.6
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(SOURCE / 'textures' / f'sw2_thunder_{part}.png'))
    material.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
    if clay:
        material.node_tree.links.remove(shader.inputs['Base Color'].links[0])
        shader.inputs['Base Color'].default_value = (0.17, 0.21, 0.24, 1)
    for obj in set(bpy.data.objects) - before:
        if obj.type == 'MESH':
            obj.data.materials.clear()
            obj.data.materials.append(material)
            objects.append(obj)
points = [o.matrix_world @ Vector(c) for o in objects for c in o.bound_box]
low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
center = (low + high) / 2
height = high.z - low.z
print('THUNDER_REFERENCE_BOUNDS', list(low), list(high))
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, low.z - 0.005))
ground = bpy.context.object
mat = bpy.data.materials.new('neutral_ground')
mat.diffuse_color = (0.16, 0.17, 0.18, 1)
ground.data.materials.append(mat)
for name, offset, energy, size in (
    ('key', (-3, -4, 5), 450, 4),
    ('fill', (4, -2, 3), 280, 4),
    ('rim', (1, 3, 4), 400, 3),
):
    bpy.ops.object.light_add(type='AREA', location=center + Vector(offset))
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (center - light.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.camera_add()
camera = bpy.context.object
scene.camera = camera
camera.data.type = 'ORTHO'
camera.data.ortho_scale = height * 1.20
if probe:
    scene.render.resolution_x = 600
    scene.render.resolution_y = 700
    original_uvs = [[tuple(uv.uv) for uv in obj.data.uv_layers.active.data] for obj in objects]
    for mode in range(6):
        for obj, source_uvs in zip(objects, original_uvs):
            for uv, (u, v) in zip(obj.data.uv_layers.active.data, source_uvs):
                if mode < 4:
                    uv.uv = (-u if mode & 1 else u, 1-v if mode & 2 else v)
                else:
                    uv.uv = (abs(u), 1-v if mode == 5 else v)
        camera.location = center + Vector((-3, 6, 2))
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(OUT / f'uv_probe_{mode}.png')
        bpy.ops.render.render(write_still=True)
    sys.exit(0)
for name, offset in (('mk2_front', (-3, 6, 2)), ('mk2_rear', (3, -6, 2))):
    camera.location = center + Vector(offset)
    camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
    filename = name.replace('mk2_', 'mk2_clay_' if clay else 'invalid_uv_')
    scene.render.filepath = str(OUT / (filename + '.png'))
    bpy.ops.render.render(write_still=True)
print('THUNDER_REFERENCE_RENDER_PASS')
