"""Rebuild a concept-driven warrior on bug01's recovered rig and eight clips.

Run Blender 5.1 --background --python tools/enemy_concept/build_warrior.py.
Only writes the concept warrior model and its scratch diagnostics; source assets
and the supplied warrior_albedo.png are read-only inputs.
"""
import bpy
import json
import math
import hashlib
from pathlib import Path
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/models/enemies/animated/bug01/bug01.gltf'
DEST = ROOT / 'assets/models/enemies/concept/warrior'
SCRATCH = ROOT / 'test_output/enemy_concept_runtime/model_build'
DEST.mkdir(parents=True, exist_ok=True)
SCRATCH.mkdir(parents=True, exist_ok=True)
(SCRATCH / '.gdignore').write_text('')
ALBEDO = DEST / 'warrior_albedo.png'
albedo_hash_before = hashlib.sha256(ALBEDO.read_bytes()).hexdigest()
doc = json.loads(SOURCE.read_text(encoding='utf-8'))
for key in ('extensionsRequired', 'extensionsUsed'):
    doc[key] = [x for x in doc.get(key, []) if x != 'KHR_node_visibility']
for node in doc.get('nodes', []):
    node.get('extensions', {}).pop('KHR_node_visibility', None)
for entry in doc.get('buffers', []) + doc.get('images', []):
    if 'uri' in entry and not entry['uri'].startswith('data:'):
        entry['uri'] = (SOURCE.parent / entry['uri']).as_posix()
clean = SCRATCH / 'source_import.gltf'
clean.write_text(json.dumps(doc), encoding='utf-8')
bpy.ops.wm.read_factory_settings(use_empty=True)
# Source clips end on 1/30-second boundaries. Import/export on that clock so
# integer-frame sampling does not truncate the 0.4-second locomotion loops.
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=str(clean))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
original_bones = [b.name for b in rig.data.bones]
actions = list(bpy.data.actions)
clip_names = [a.name for a in actions]
for obj in list(bpy.data.objects):
    if obj != rig:
        bpy.data.objects.remove(obj, do_unlink=True)
rig.hide_render = False
rig.animation_data_create()
for track in rig.animation_data.nla_tracks:
    track.mute = True

def activate(action):
    rig.animation_data.action = action
    slot = next((s for s in action.slots if s.identifier == 'OBbug01'), action.slots[0])
    rig.animation_data.action_slot = slot

idle = next(a for a in actions if a.name == 'idle')
activate(idle)
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()
rig_world = rig.matrix_world.copy()
deform = {p.name: rig_world @ p.matrix @ p.bone.matrix_local.inverted() @ rig_world.inverted() for p in rig.pose.bones}
inverse_deform = {name: m.inverted() for name, m in deform.items()}
idle_heads = {p.name: rig_world @ p.head for p in rig.pose.bones}
reference_pose = {'action': 'idle', 'frame': 0, 'heads': {k: list(v) for k,v in idle_heads.items()}}

# New bones are positioned in idle space, then mapped through parent skinning
# back into rest space. The old recovered rest is intentionally not normalized.
new_specs = {}
for side, sign in [('L', -1), ('R', 1)]:
    points = [Vector((sign*.43, .20, 1.21)), Vector((sign*.76, .18, 1.69)),
              Vector((sign*.96, .31, 2.35)), Vector((sign*.60, 1.00, 2.66))]
    for i in range(3):
        name = f'Scythe_{side}{i+1:02d}'
        new_specs[name] = {'head': points[i], 'tail': points[i+1],
                           'parent': 'Bone' if i == 0 else f'Scythe_{side}{i:02d}', 'old_parent': 'Bone'}
    new_specs[f'Mandible_{side}'] = {'head': Vector((sign*.20, .94, 1.03)),
        'tail': Vector((sign*.36, 1.29, .82)), 'parent': 'Bone head01', 'old_parent': 'Bone head01'}
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
for name, spec in new_specs.items():
    bone = rig.data.edit_bones.new(name)
    inv = inverse_deform[spec['old_parent']]
    bone.head = rig_world.inverted() @ inv @ spec['head']
    bone.tail = rig_world.inverted() @ inv @ spec['tail']
    bone.parent = rig.data.edit_bones[spec['parent']]
    bone.use_connect = False
    bone.use_deform = True
bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()
for name, spec in new_specs.items():
    inverse_deform[name] = inverse_deform[spec['old_parent']]

def material(name, color, emission=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = .88
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat

shell = material('warrior_chitin_atlas', (.34,.095,.055))
tex = shell.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = bpy.data.images.load(str(ALBEDO), check_existing=True)
tex.interpolation = 'Linear'
shell.node_tree.links.new(tex.outputs['Color'], shell.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
# Recovered arenas use baked environment textures with little dynamic fill.
# A restrained texture-coloured contribution keeps chitin readable there while
# retaining normal lighting/shadows; eyes and sensory seams remain brighter.
shell.node_tree.links.new(tex.outputs['Color'], shell.node_tree.nodes['Principled BSDF'].inputs['Emission Color'])
shell.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .60
dark = material('warrior_recess', (.035,.012,.02))
gold = material('warrior_chitin_ridge', (.26,.105,.035))
purple = material('warrior_purple_fissure', (.29,.018,.45), .40)
green = material('warrior_six_green_eyes', (.08,.55,.018), .45)
materials = [shell, dark, gold, purple, green]

verts, faces, weights, face_mats, uv_faces = [], [], [], [], []
part_ranges = {}

def append_part(name, local_verts, local_faces, bone, mat=0, uv_mode='shell', uvs=None):
    start = len(verts)
    inv = inverse_deform[bone]
    verts.extend([inv @ Vector(p) for p in local_verts])
    weights.extend([bone] * len(local_verts))
    for face in local_faces:
        faces.append(tuple(start+i for i in face))
        face_mats.append(mat)
        if uvs:
            coords = [uvs[i] for i in face]
        else:
            # New pieces explicitly map into the clean large central chitin tile.
            coords = [(.36 + .18*(i % 7)/6, .36 + .18*((i//7) % 7)/6) for i in face]
        uv_faces.append(coords)
    part_ranges[name] = {'vertex_start': start, 'vertex_count': len(local_verts), 'bone': bone,
                         'triangle_count': sum(len(f)-2 for f in local_faces)}

def ellipsoid(name, center, radius, bone, mat=0, seg=10, rings=5):
    v, f, uv = [], [], []
    for j in range(rings+1):
        theta = math.pi*j/rings
        for i in range(seg):
            phi = 2*math.pi*i/seg
            v.append((center[0]+radius[0]*math.sin(theta)*math.cos(phi),
                      center[1]+radius[1]*math.sin(theta)*math.sin(phi),
                      center[2]+radius[2]*math.cos(theta)))
            uv.append((.36+.18*i/(seg-1), .36+.18*j/rings))
    for j in range(rings):
        for i in range(seg):
            ni=(i+1)%seg
            if j == 0: f.append((j*seg+i,(j+1)*seg+i,(j+1)*seg+ni))
            elif j == rings-1: f.append((j*seg+i,(j+1)*seg+i,j*seg+ni))
            else: f.append((j*seg+i,(j+1)*seg+i,(j+1)*seg+ni,j*seg+ni))
    append_part(name,v,f,bone,mat,uvs=uv)

def tube(name, points, radii, bone, mat=0, sides=6, flatten=1.0):
    points=[Vector(p) for p in points]
    v, f, uv = [], [], []
    for j,p in enumerate(points):
        tangent=(points[min(j+1,len(points)-1)]-points[max(j-1,0)]).normalized()
        axis = tangent.cross(Vector((0,1,0)))
        if axis.length < .1: axis=tangent.cross(Vector((1,0,0)))
        axis.normalize()
        second=tangent.cross(axis).normalized()
        for i in range(sides):
            ang=2*math.pi*i/sides
            v.append(p + radii[j]*(math.cos(ang)*axis + math.sin(ang)*second*flatten))
            # A clean chitin tile avoids repeating the old atlas's joint bands
            # on every small new part; fissures are separate actual geometry.
            uv.append((.36+.18*i/max(1,sides-1), .36+.18*j/max(1,len(points)-1)))
    for j in range(len(points)-1):
        for i in range(sides):
            ni=(i+1)%sides
            f.append((j*sides+i,j*sides+ni,(j+1)*sides+ni,(j+1)*sides+i))
    f.append(tuple(reversed(range(sides))))
    f.append(tuple((len(points)-1)*sides+i for i in range(sides)))
    append_part(name,v,f,bone,mat,uvs=uv)

def spike(name, base, tip, radius, bone, mat=0):
    tube(name,[base,tip],[radius,.001],bone,mat,sides=4)

# Thorax and segmented abdomen replace the old mammalian/dragon-face shell.
ellipsoid('thorax',(0,.12,.91),(.38,.43,.36),'Bone',1,seg=10,rings=5)
ellipsoid('abdomen',(0,-.67,.80),(.42,.76,.33),'Bone',1,seg=10,rings=5)
for i in range(5):
    y=-.10-i*.27
    width=.46-i*.045
    z=1.04-i*.043
    ellipsoid(f'abdomen_plate_{i}',(0,y,z),(width,.25,.20),'Bone',0,seg=8,rings=4)
    tube(f'abdomen_glow_{i}',[(-width*.8,y-.14,z+.10),(0,y-.21,z+.16),(width*.8,y-.14,z+.10)],[.017,.021,.017],'Bone',3,sides=4)
    spike(f'dorsal_spine_{i}',(0,y,z+.14),(0,y-.14,z+.39),.07,'Bone',0)
spike('tail',(0,-1.24,.78),(0,-1.72,.91),.16,'Bone',0)

# Four existing walking-leg chains retain all legacy joint names and motion.
for side, sign in [('l',-1),('r',1)]:
    for limb in ('f','b'):
        chain=[f'Bone {side} leg {limb}{j:02d}' for j in range(1,5)]
        points=[idle_heads[n] for n in chain]
        for j in range(3):
            a,b=points[j],points[j+1]
            mid=a.lerp(b,.5)
            radius=[.12,.145,.14][j]
            tube(f'walking_{side}_{limb}_{j}',[a,mid,b],[radius*.62,radius,.025 if j==2 else radius*.55],chain[j],0,sides=6)
            if j>0:
                spike(f'leg_spine_{side}_{limb}_{j}',mid,mid+Vector((sign*.12,0,.24)),.065,chain[j],0)
                tube(f'leg_glow_{side}_{limb}_{j}',[mid+Vector((0,.09,.01)),b.lerp(mid,.7)+Vector((0,.07,.01))],[.018,.012],chain[j],3,sides=4)
        ellipsoid(f'leg_joint_{side}_{limb}',points[2],(.13,.12,.12),chain[2],1,seg=8,rings=4)

# A tall faceted triangular hood with an actual recessed six-eye face below it.
hood_v,hood_f,hood_uv=[],[],[]
levels=[(1.02,.44,.38,.39),(1.44,.47,.54,.43),(1.78,.30,.28,.29),(2.00,.16,.025,.06)]
for j,(z,cy,rx,ry) in enumerate(levels):
    for i in range(8):
        ang=2*math.pi*i/8
        hood_v.append((rx*math.cos(ang),cy+ry*math.sin(ang),z))
        hood_uv.append((.36+.18*i/7,.36+.18*j/3))
for j in range(3):
    for i in range(8): hood_f.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
hood_f.append(tuple(reversed(range(8))))
hood_f.append(tuple(24+i for i in range(8)))
append_part('triangular_hood',hood_v,hood_f,'Bone head01',0,uvs=hood_uv)
for side,sign in [('L',-1),('R',1)]:
    tube('hood_ridge_'+side,[(0,.23,1.99),(sign*.31,.58,1.70),(sign*.48,.71,1.30),(sign*.31,.80,1.03)],[.017,.032,.031,.02],'Bone head01',2,sides=4)
    tube('hood_fissure_'+side,[(sign*.22,.72,1.61),(sign*.38,.78,1.41),(sign*.39,.78,1.26)],[.018,.021,.012],'Bone head01',3,sides=4)
ellipsoid('face_recess',(0,.88,1.16),(.285,.185,.27),'Bone head01',1,seg=10,rings=5)
for row,(x,z) in enumerate([(.115,1.33),(.17,1.19),(.10,1.065)]):
    for side,sign in [('L',-1),('R',1)]:
        center=(sign*x,1.028,z)
        ellipsoid(f'eye_socket_{side}_{row}',center,(.079,.047,.08),'Bone head01',2,seg=8,rings=4)
        ellipsoid(f'green_eye_{side}_{row}',(sign*x,1.069,z),(.052,.036,.055),'Bone head01',4,seg=8,rings=4)
        ellipsoid(f'eye_core_{side}_{row}',(sign*x,1.102,z),(.019,.009,.024),'Bone head01',1,seg=6,rings=3)

# Paired long hooked scythes: three real articulated bones per side.
for side,sign in [('L',-1),('R',1)]:
    for j in (1,2):
        spec=new_specs[f'Scythe_{side}{j:02d}']
        a,b=spec['head'],spec['tail']
        tube(f'scythe_arm_{side}_{j}',[a,a.lerp(b,.45),b],[.09,.145 if j==2 else .12,.085],f'Scythe_{side}{j:02d}',0,sides=6)
        ellipsoid(f'scythe_joint_{side}_{j}',a,(.12,.11,.11),f'Scythe_{side}{j:02d}',1,seg=8,rings=4)
        tube(f'arm_fissure_{side}_{j}',[a.lerp(b,.2)+Vector((0,.105,0)),a.lerp(b,.75)+Vector((0,.105,0))],[.018,.021],f'Scythe_{side}{j:02d}',3,sides=4)
    hook=[(sign*.96,.31,2.35),(sign*1.02,.37,2.55),(sign*.99,.55,2.77),
          (sign*.84,.77,2.91),(sign*.64,.98,2.92),(sign*.44,1.15,2.82),(sign*.31,1.27,2.64),(sign*.25,1.33,2.47)]
    tube('scythe_hook_'+side,hook,[.15,.17,.19,.18,.15,.10,.055,.001],f'Scythe_{side}03',0,sides=6,flatten=.52)
    tube('scythe_glow_'+side,[(x,y+.095,z) for x,y,z in hook[1:6]],[.016]*5,f'Scythe_{side}03',3,sides=4)
    for j in (1,2,3,4):
        p=Vector(hook[j])
        spike(f'scythe_barb_{side}_{j}',p,p+Vector((sign*.05,-.09,.16)),.049,f'Scythe_{side}03',0)
    jaw=[(sign*.20,.94,1.03),(sign*.35,1.12,.98),(sign*.43,1.28,.83),(sign*.34,1.43,.67),(sign*.16,1.48,.64),(sign*.055,1.43,.76)]
    tube('mandible_'+side,jaw,[.10,.105,.095,.075,.04,.001],f'Mandible_{side}',0,sides=6,flatten=.62)
    for j in (1,2,3):
        p=Vector(jaw[j])
        spike(f'mandible_tooth_{side}_{j}',p,p+Vector((-sign*.13,.02,.055)),.031,f'Mandible_{side}',2)

mesh=bpy.data.meshes.new('warrior_concept_geometry')
mesh.from_pydata(verts,[],faces)
mesh.update()
obj=bpy.data.objects.new('warrior_Skinned',mesh)
bpy.context.collection.objects.link(obj)
for mat in materials: mesh.materials.append(mat)
uv=mesh.uv_layers.new(name='UVMap')
for poly,mat,coords in zip(mesh.polygons,face_mats,uv_faces):
    poly.material_index=mat
    poly.use_smooth=True
    for li,coord in zip(poly.loop_indices,coords): uv.data[li].uv=coord
for name in original_bones+list(new_specs): obj.vertex_groups.new(name=name)
for i,bone in enumerate(weights): obj.vertex_groups[bone].add([i],1.0,'REPLACE')
mod=obj.modifiers.new('Shared recovered skeleton','ARMATURE')
mod.object=rig
obj.parent=rig
obj.matrix_parent_inverse=rig.matrix_world.inverted()
for p in rig.pose.bones:
    if p.name in new_specs: p.rotation_mode='QUATERNION'

# Add local quaternion channels only to the new bones; legacy curves untouched.
def local_axis(bone_name, world_axis):
    return (rig.data.bones[bone_name].matrix_local.to_3x3().inverted() @ Vector(world_axis)).normalized()
animation_report={}
for action in actions:
    activate(action)
    first,last=map(float,action.frame_range)
    samples=sorted(set([first,last]+[first+(last-first)*i/16 for i in range(17)]))
    animation_report[action.name]={'first':first,'last':last,'new_bones':list(new_specs),'samples':len(samples)}
    for frame in samples:
        t=(frame-first)/max(last-first,1e-6)
        phase=2*math.pi*t
        attack=math.sin(math.pi*min(1,t/.62)) if action.name=='attack' else 0
        for side,sign in [('L',-1),('R',1)]:
            offset=.4 if side=='L' else -.4
            if action.name=='attack':
                angles=[-1.1*attack,-.45*attack,.60*attack]
            elif action.name.startswith('dead'):
                angles=[-.90*t,-.45*t,.35*t]
            elif action.name=='attacked':
                hit=math.sin(math.pi*t)
                angles=[.40*hit,.25*hit,-.25*hit]
            elif action.name.startswith('run'):
                wave=math.sin(phase+offset)
                angles=[.12*wave,.09*wave,-.07*wave]
            else:
                wave=math.sin(phase+offset)
                angles=[.035*wave,.035*wave,-.03*wave]
            for j,angle in enumerate(angles,1):
                name=f'Scythe_{side}{j:02d}'
                rig.pose.bones[name].rotation_quaternion=Quaternion(local_axis(name,(1,0,0)),angle)
                rig.pose.bones[name].keyframe_insert('rotation_quaternion',frame=frame,group=name)
            name=f'Mandible_{side}'
            jaw=(.38*attack if action.name=='attack' else .06*math.sin(phase))
            if action.name.startswith('dead'): jaw=.20*t
            rig.pose.bones[name].rotation_quaternion=Quaternion(local_axis(name,(0,0,1)),sign*jaw)
            rig.pose.bones[name].keyframe_insert('rotation_quaternion',frame=frame,group=name)

activate(idle)
bpy.context.scene.frame_set(0)
rig.data.pose_position='POSE'
bpy.context.view_layer.update()
for o in bpy.context.scene.objects: o.select_set(False)
rig.select_set(True)
obj.select_set(True)
bpy.context.view_layer.objects.active=rig
props=bpy.ops.export_scene.gltf.get_rna_type().properties
requested={'filepath':str(DEST/'warrior.gltf'),'export_format':'GLTF_SEPARATE','use_selection':True,
 'export_animations':True,'export_animation_mode':'ACTIONS','export_force_sampling':True,
 'export_frame_range':False,'export_def_bones':False,'export_skins':True,'export_materials':'EXPORT',
 'export_image_format':'AUTO','export_keep_originals':True,'export_texture_dir':'.','export_yup':True,'export_anim_single_armature':True,
 'export_optimize_animation_size':False,'export_lights':False,'export_cameras':False}
args={key:value for key,value in requested.items() if key in props}
bpy.ops.export_scene.gltf(**args)
export_doc=json.loads((DEST/'warrior.gltf').read_text())
for image in export_doc.get('images',[]):
    # Portable URI: supplied atlas already exists beside the model, never rewritten.
    image['uri']='warrior_albedo.png'
assert len(export_doc.get('images', [])) == 1, 'Expected exactly one atlas image'
assert export_doc['materials'][0]['pbrMetallicRoughness'].get('baseColorTexture'), 'Chitin texture was not exported'
assert sorted(a['name'] for a in export_doc.get('animations', [])) == sorted(clip_names), 'Source animation names were lost'
for source_clip in doc['animations']:
    source_end = max(doc['accessors'][s['input']]['max'][0] for s in source_clip['samplers'])
    output_clip = next(a for a in export_doc['animations'] if a['name'] == source_clip['name'])
    output_end = max(export_doc['accessors'][s['input']]['max'][0] for s in output_clip['samplers'])
    assert abs(source_end-output_end) < 1e-5, f"Clip duration changed: {source_clip['name']} {source_end} -> {output_end}"
assert hashlib.sha256(ALBEDO.read_bytes()).hexdigest() == albedo_hash_before, 'Supplied atlas changed during export'
(DEST/'warrior.gltf').write_text(json.dumps(export_doc,indent=2)+'\n',encoding='utf-8',newline='\n')
mesh.calc_loop_triangles()
report={'source':str(SOURCE.relative_to(ROOT)),'output':str((DEST/'warrior.gltf').relative_to(ROOT)),
 'coordinate_system':'Blender +Y front = Godot -Z front, +Z up', 'reference_pose':reference_pose,
 'original_bones':original_bones,'added_bones':list(new_specs),'bone_count':len(rig.data.bones),
 'vertex_count':len(mesh.vertices),'triangle_count':len(mesh.loop_triangles),'mesh_count':1,
 'parts':part_ranges,'clips':animation_report,'export_clips':[a['name'] for a in export_doc.get('animations',[])],
 'materials':[m.name for m in materials],'albedo_sha256':albedo_hash_before,
 'albedo_unchanged':hashlib.sha256(ALBEDO.read_bytes()).hexdigest()==albedo_hash_before,
 'scope':'Runtime prototype; preserves recovered source rig/animations, no rights-clean claim.'}
(SCRATCH/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(SCRATCH/'warrior_preview.blend'))
print('WARRIOR_BUILD_PASS',json.dumps({k:report[k] for k in ('bone_count','vertex_count','triangle_count','mesh_count','export_clips','albedo_unchanged')}),flush=True)
