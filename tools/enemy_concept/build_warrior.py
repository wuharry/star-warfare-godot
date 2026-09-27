"""Rebuild a concept-driven warrior on bug01's recovered rig and eight clips.

Run Blender 5.1 --background --python tools/enemy_concept/build_warrior.py.
Only writes the concept warrior model and its scratch diagnostics; source assets
and the supplied warrior_chitin_v2.png are read-only inputs.
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
ALBEDO = DEST / 'warrior_chitin_v2.png'
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
def prominent_head(point):
    pivot=Vector((0,.58,1.25))
    delta=Vector(point)-pivot
    return pivot+Vector((delta.x*1.14,delta.y*1.04+.10,delta.z*1.12))

new_specs = {}
for side, sign in [('L', -1), ('R', 1)]:
    points = [Vector((sign*.43, .20, 1.21)), Vector((sign*.76, .18, 1.69)),
              Vector((sign*.96, .31, 2.35)), Vector((sign*.60, 1.00, 2.66))]
    for i in range(3):
        name = f'Scythe_{side}{i+1:02d}'
        new_specs[name] = {'head': points[i], 'tail': points[i+1],
                           'parent': 'Bone' if i == 0 else f'Scythe_{side}{i:02d}', 'old_parent': 'Bone'}
    new_specs[f'Mandible_{side}'] = {'head': prominent_head((sign*.245, 1.08, 1.04)),
        'tail': prominent_head((sign*.45, 1.16, .78)), 'parent': 'Bone head01', 'old_parent': 'Bone head01'}
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
    shader.inputs['Roughness'].default_value = .92
    shader.inputs['Specular IOR Level'].default_value = .10
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat

shell = material('warrior_chitin_palette_v3', (.34,.095,.055))
tex = shell.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = bpy.data.images.load(str(ALBEDO), check_existing=True)
tex.interpolation = 'Linear'
vertex_tint=shell.node_tree.nodes.new('ShaderNodeVertexColor')
vertex_tint.layer_name='ConceptPalette'
paint_mix=shell.node_tree.nodes.new('ShaderNodeMixRGB')
paint_mix.blend_type='MULTIPLY'
paint_mix.inputs[0].default_value=1
shell.node_tree.links.new(tex.outputs['Color'],paint_mix.inputs[1])
shell.node_tree.links.new(vertex_tint.outputs['Color'],paint_mix.inputs[2])
shell.node_tree.links.new(paint_mix.outputs['Color'], shell.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
# Recovered arenas use baked environment textures with little dynamic fill.
# A restrained texture-coloured contribution keeps chitin readable there while
# retaining normal lighting/shadows; eyes and sensory seams remain brighter.
shell.node_tree.links.new(tex.outputs['Color'], shell.node_tree.nodes['Principled BSDF'].inputs['Emission Color'])
shell.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .12
dark = material('warrior_recess', (.014,.007,.022), .14)
gold = material('warrior_chitin_ridge', (.15,.060,.015), .10)
purple = material('warrior_purple_fissure', (.28,.012,.55), .55)
green = material('warrior_six_green_eyes', (.10,.43,.014), .45)
green.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .32
materials = [shell, dark, gold, purple, green]

verts, faces, weights, face_mats, uv_faces = [], [], [], [], []
paint_colors = []
part_ranges = {}

def palette_mix(a,b,t):
    t=max(0,min(1,t))
    return tuple(x*(1-t)+y*t for x,y in zip(a,b))

def srgb_hex(value):
    rgb=[int(value[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in rgb)

def chitin_tint(name,index,points,coords):
    """Hand-painted colour zones tied to each plate, not world lighting.

    Linear RGB colours separate plum recesses, mahogany panels, and amber
    ridges. The Godot chitin shader uses the old texture for fine grain only.
    """
    plum=srgb_hex('302433')
    mahogany=srgb_hex('6b4031')
    amber=srgb_hex('af763e')
    u,v=coords
    s,t=(u-.36)/.18,(v-.36)/.18
    if name=='arched_hood_shell':
        if index>=13*33:return plum
        centre=math.exp(-((s-.5)/.055)**2)
        panels=max(math.exp(-((s-.31)/.075)**2),math.exp(-((s-.69)/.075)**2))
        base=palette_mix(plum,mahogany,.22+.78*panels)
        base=palette_mix(base,amber,.80*centre)
        return palette_mix(plum,base,min(1,t*5)*min(1,(1-t)*7+.18))
    if name.startswith(('scythe_hook_','mandible_')):
        station=index//8
        total=max(1,len(points)//8-1)
        progress=station/total
        return palette_mix(mahogany,plum,.25+.70*progress)
    if name.startswith('abdomen_plate_'):
        column=index%13;row=(index//13)%4
        if index>=52:return plum
        arch=math.sin(math.pi*column/12)**2
        return palette_mix(plum,palette_mix(mahogany,amber,.25*arch),arch*(.40+.60*row/3))
    if name=='tapered_insect_face':
        x,y,z=points[index]
        centre=math.exp(-(x/.095)**2)
        return palette_mix(plum,palette_mix(mahogany,amber,.65*centre),.85)
    if name.startswith(('throat_','cheek_','neck_','thorax_','hood_rear')):
        return palette_mix(plum,mahogany,.20)
    if name.startswith(('walking_','scythe_arm_')):
        return palette_mix(plum,mahogany,math.sin(math.pi*max(0,min(1,s)))**2*.90)
    if name.startswith(('jaw_root_','leg_spine_','dorsal_spine_')):
        return palette_mix(mahogany,amber,.20)
    return mahogany

def append_part(name, local_verts, local_faces, bone, mat=0, uv_mode='shell', uvs=None):
    start = len(verts)
    inv = inverse_deform[bone]
    is_head=bone=='Bone head01' or bone.startswith('Mandible_')
    verts.extend([inv @ (prominent_head(p) if is_head else Vector(p)) for p in local_verts])
    weights.extend([bone] * len(local_verts))
    for i in range(len(local_verts)):
        coord=uvs[i] if uvs else (.36+.18*(i%7)/6,.36+.18*((i//7)%7)/6)
        paint_colors.append(chitin_tint(name,i,local_verts,coord) if mat==0 else (1,1,1))
    for face in local_faces:
        faces.append(tuple(start+i for i in face))
        face_mats.append(mat)
        if uvs:
            coords = [uvs[i] for i in face]
        else:
            # New pieces explicitly map into the clean large central chitin tile.
            coords = [(.36 + .18*(i % 7)/6, .36 + .18*((i//7) % 7)/6) for i in face]
        # The v2 swatch contains material grain only. Spread the old tile-local
        # coordinates across it; anatomical detail now belongs to the mesh.
        uv_faces.append([(.06+.88*(u-.36)/.18, .06+.88*(v-.36)/.18) for u,v in coords])
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

def blade(name, points, widths, depths, bone, mat=0, steps=3):
    """Continuous curved chitin, with a broad front and a bevelled cutting edge.

    The section stays in the XZ blade plane rather than rolling with the curve.
    Catmull-Rom stations round the contour without subdividing the whole rig.
    """
    p = [Vector(v) for v in points]
    samples = []
    for j in range(len(p)-1):
        a,b,c,d = p[max(0,j-1)],p[j],p[j+1],p[min(j+2,len(p)-1)]
        for k in range(steps):
            t=k/steps
            point=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            samples.append((point,widths[j]*(1-t)+widths[j+1]*t,depths[j]*(1-t)+depths[j+1]*t))
    samples.append((p[-1], widths[-1], depths[-1]))
    v,f,uv=[],[],[]
    section=[(-1,0),(-.78,.65),(0,1),(.78,.65),(1,0),(.78,-.65),(0,-1),(-.78,-.65)]
    for j,(point,width,depth) in enumerate(samples):
        tangent=samples[min(j+1,len(samples)-1)][0]-samples[max(j-1,0)][0]
        across=Vector((-tangent.z,0,tangent.x)).normalized()
        for i,(x,y) in enumerate(section):
            v.append(point+across*width*x+Vector((0,depth*y,0)))
            uv.append((.36+.18*i/7,.36+.18*j/(len(samples)-1)))
    bevel_start=len(face_mats)
    for j in range(len(samples)-1):
        for i in range(8):
            f.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
    f += [tuple(reversed(range(8))),tuple((len(samples)-1)*8+i for i in range(8))]
    append_part(name,v,f,bone,mat,uvs=uv)
    if mat==0:
        # Two narrow sides of the cross-section are actual cutting bevels.
        # Give them a separate chitin tone instead of painting bright UV bands.
        for j in range(len(samples)-1):
            ridge_sides=(3,4) if name.endswith('_R') else (0,7)
            shadow_sides=(0,7) if name.endswith('_R') else (3,4)
            for i in ridge_sides:face_mats[bevel_start+j*8+i]=2
            for i in shadow_sides:face_mats[bevel_start+j*8+i]=1

def dorsal_plate(name, y, z, width, length, bone):
    """An overlapping arched plate, not a bead sitting on the abdomen."""
    v,f,uv=[],[],[]
    for layer in range(2):
        for j in range(4):
            t=j/3
            for i in range(13):
                a=-2.0+4.0*i/12
                inset=.018*layer
                v.append(((width*(1-.10*t)-inset)*math.sin(a),
                          y+length*(.5-t)-.045*abs(math.sin(a))**1.5*t,
                          z-.20+(.37-inset)*math.cos(a)+.025*math.sin(t*math.pi)))
                uv.append((.36+.18*i/12,.36+.18*t))
    for layer in range(2):
        for j in range(3):
            for i in range(12):
                a=layer*52+j*13+i
                face=(a,a+13,a+14,a+1)
                f.append(face if layer==0 else tuple(reversed(face)))
    perimeter=list(range(13))+[j*13+12 for j in range(1,4)]+list(range(50,38,-1))+[26,13]
    for i,a in enumerate(perimeter):
        b=perimeter[(i+1)%len(perimeter)]
        f.append((a,b,b+52,a+52))
    append_part(name,v,f,bone,0,uvs=uv)

# Thorax and segmented abdomen replace the old mammalian/dragon-face shell.
ellipsoid('thorax',(0,.12,.91),(.33,.40,.29),'Bone',1,seg=12,rings=6)
ellipsoid('abdomen',(0,-.67,.80),(.25,.69,.18),'Bone',1,seg=12,rings=6)
for sign in (-1,1):
    ellipsoid(f'thorax_side_carapace_{sign}',(sign*.25,.18,.87),(.15,.39,.26),'Bone',0,seg=12,rings=6)
for i in range(5):
    y=-.10-i*.27
    width=.46-i*.045
    z=1.04-i*.043
    dorsal_plate(f'abdomen_plate_{i}',y,z,width,.39,'Bone')
    arc=[-1.5+3*j/8 for j in range(9)]
    tube(f'abdomen_glow_{i}',[(width*.904*math.sin(a),y-.1794-.0432*abs(math.sin(a))**1.5,z-.20+.373*math.cos(a)+.0031) for a in arc],[.004]*9,'Bone',3,sides=6)
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
            tube(f'walking_{side}_{limb}_{j}',[a,a.lerp(b,.25),mid,a.lerp(b,.8),b],[radius*.68,radius*.91,radius,radius*.65,.018 if j==2 else radius*.64],chain[j],0,sides=8)
            if j>0:
                spike(f'leg_spine_{side}_{limb}_{j}',mid,mid+Vector((sign*.12,0,.24)),.065,chain[j],0)
                tube(f'leg_glow_{side}_{limb}_{j}',[mid+Vector((0,.09,.01)),b.lerp(mid,.7)+Vector((0,.07,.01))],[.018,.012],chain[j],3,sides=4)
        ellipsoid(f'leg_joint_{side}_{limb}',points[2],(.12,.11,.11),chain[2],1,seg=12,rings=6)

# A thick continuous hood wraps OVER an inset face. Its lower edge is an
# actual arch, so the six-eye face is not a flat disc stuck onto a closed cone.
hood_outer=[(-.44,.55,.99),(-.61,.42,1.23),(-.54,.20,1.62),(-.31,-.02,1.91),
            (0,-.16,2.06),(.31,-.02,1.91),(.54,.20,1.62),(.61,.42,1.23),(.44,.55,.99)]
hood_inner=[(-.29,1.05,.98),(-.35,1.14,1.14),(-.30,1.21,1.34),(-.16,1.25,1.48),
            (0,1.26,1.53),(.16,1.25,1.48),(.30,1.21,1.34),(.35,1.14,1.14),(.29,1.05,.98)]
def hood_point(index,t):
    lo=max(0,min(7,int(index))); w=index-lo
    outer=Vector(hood_outer[lo]).lerp(Vector(hood_outer[lo+1]),w)
    inner=Vector(hood_inner[lo]).lerp(Vector(hood_inner[lo+1]),w)
    return outer.lerp(inner,t)+Vector((0,.075*math.sin(math.pi*t),0))
hood_v,hood_f,hood_uv=[],[],[]
hood_rows,hood_cols=13,33
for layer in range(2):
    for j in range(hood_rows):
        t=j/(hood_rows-1)
        for i in range(hood_cols):
            point=hood_point(8*i/(hood_cols-1),t)
            if layer:point+=Vector((0,-.055,-.018))
            hood_v.append(point)
            hood_uv.append((.36+.18*i/(hood_cols-1),.36+.18*t))
stride=hood_rows*hood_cols
for layer in range(2):
    for j in range(hood_rows-1):
        for i in range(hood_cols-1):
            a=layer*stride+j*hood_cols+i; face=(a,a+1,a+hood_cols+1,a+hood_cols)
            hood_f.append(face if layer==0 else tuple(reversed(face)))
# Roll over the brow, crown and cheek edges rather than drawing gold pipes.
for i in range(hood_cols-1):
    a=(hood_rows-1)*hood_cols+i; hood_f.append((a,a+stride,a+stride+1,a+1))
    hood_f.append((i,i+1,i+stride+1,i+stride))
for j in range(hood_rows-1):
    for i in (0,hood_cols-1):
        a=j*hood_cols+i;hood_f.append((a,a+hood_cols,a+hood_cols+stride,a+stride))
append_part('arched_hood_shell',hood_v,hood_f,'Bone head01',0,uvs=hood_uv)
# A narrow bevel on the actual brow edge, not a separate pipe silhouette.
for i in range(hood_cols-1):
    a=hood_point(8*i/(hood_cols-1),.95)
    b=hood_point(8*(i+1)/(hood_cols-1),.95)
    c=hood_point(8*(i+1)/(hood_cols-1),1)
    d=hood_point(8*i/(hood_cols-1),1)
    append_part(f'brow_bevel_{i}',[p+Vector((0,.004,0)) for p in (a,b,c,d)],[(0,1,2,3)],'Bone head01',2)
# Rear chitin sweeps down into the neck, concealing the old exposed ball.
back_v=[Vector(p) for p in hood_outer]+[Vector((0,-.30,1.40)),Vector((0,.31,.90))]
back_f=[(i,i+1,9) for i in range(8)]+[(0,9,10),(9,8,10)]
append_part('hood_rear_mantle',back_v,back_f,'Bone head01',0)
for i in range(3):
    ellipsoid(f'neck_overlapping_plate_{i}',(0,.38-i*.16,1.02-i*.09),(.36-i*.025,.22,.16),'Bone',0,seg=12,rings=5)
for sign in (-1,1):
    cheek=[(sign*.31,1.045,1.08),(sign*.47,.78,1.02),(sign*.45,.50,.95),
           (sign*.34,.63,.72),(sign*.23,.92,.81),(sign*.31,1.06,.94),
           (sign*.40,.86,.95)]
    append_part(f'cheek_carapace_{sign}',cheek,[(i,(i+1)%6,6) for i in range(6)],'Bone head01',0)
# Flush, pointed sensory insets follow the same surface as the hood.
for index in (1.3,2.6,5.4,6.7):
    for suffix,spread,mat,offset in [('recess',.20,1,.003),('glow',.115,3,.007)]:
        points,polys=[],[]
        for j in range(9):
            t=.24+.42*j/8
            half=spread*(1-abs(j-4)/4)
            for q in (-1,0,1):
                i=index+q*half
                di=hood_point(i+.001,t)-hood_point(i-.001,t)
                dt=hood_point(i,t+.001)-hood_point(i,t-.001)
                normal=di.cross(dt).normalized()
                if normal.y<0:normal=-normal
                points.append(hood_point(i,t)+normal*offset)
        for j in range(8):
            for k in range(2):polys.append((j*3+k,j*3+k+1,(j+1)*3+k+1,(j+1)*3+k))
        append_part(f'hood_inset_{index}_{suffix}',points,polys,'Bone head01',mat)
# A tapered insect face, curved in both axes and sloping back beneath the brow.
face_levels=[(.83,.045,1.08,.94),(.94,.145,1.16,.86),(1.08,.245,1.20,.85),
             (1.22,.28,1.205,.85),(1.36,.23,1.17,.88),(1.48,.105,1.12,.94),(1.52,.035,1.06,.99)]
face_v,face_f,face_uv=[],[],[]
for j,(z,width,front,back) in enumerate(face_levels):
    for i in range(16):
        a=2*math.pi*i/16
        face_v.append((width*math.cos(a),(front+back)/2+(front-back)/2*math.sin(a),z))
        face_uv.append((.36+.18*i/15,.36+.18*j/(len(face_levels)-1)))
for j in range(len(face_levels)-1):
    for i in range(16):face_f.append((j*16+i,j*16+(i+1)%16,(j+1)*16+(i+1)%16,(j+1)*16+i))
face_f += [tuple(reversed(range(16))),tuple((len(face_levels)-1)*16+i for i in range(16))]
append_part('tapered_insect_face',face_v,face_f,'Bone head01',0,uvs=face_uv)
def face_surface_y(x,z):
    for a,b in zip(face_levels,face_levels[1:]):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]); width=a[1]*(1-t)+b[1]*t
            front=a[2]*(1-t)+b[2]*t;back=a[3]*(1-t)+b[3]*t
            return (front+back)/2+(front-back)/2*math.sqrt(max(0,1-(x/width)**2))
    raise ValueError('Eye outside face surface')
for row,(x,z) in enumerate([(.105,1.345),(.205,1.205),(.115,1.075)]):
    for side,sign in [('L',-1),('R',1)]:
        y=face_surface_y(x,z)
        ellipsoid(f'eye_socket_{side}_{row}',(sign*x,y-.002,z),(.061,.024,.069),'Bone head01',1,seg=12,rings=6)
        ellipsoid(f'green_eye_{side}_{row}',(sign*x,y+.006,z),(.040,.024,.048),'Bone head01',4,seg=16,rings=8)
# Overlapping throat scutes cover the thorax exposed below the mouth.
for j,(z,y,width) in enumerate([(.79,.94,.27),(.66,.81,.24),(.56,.66,.20)]):
    points=[(-width,y,z+.06),(0,y+.025,z+.11),(width,y,z+.06),
            (width*.66,y+.025,z-.055),(0,y+.05,z-.09),(-width*.66,y+.025,z-.055),(0,y+.075,z+.005)]
    append_part(f'throat_scute_{j}',points,[(i,(i+1)%6,6) for i in range(6)],'Bone head01',0)
# Short central mouth with chitin palps; there is no bare spherical chin.
ellipsoid('mouth_cavity',(0,1.135,.925),(.09,.02,.085),'Bone head01',1,seg=12,rings=5)
for sign in (-1,1):
    blade(f'mouth_palp_{sign}',[(sign*.072,1.157,1.01),(sign*.065,1.19,.945),(sign*.027,1.20,.88)],[.03,.023,.001],[.017,.014,.001],'Bone head01',2,steps=3)

# Paired long hooked scythes: three real articulated bones per side.
for side,sign in [('L',-1),('R',1)]:
    for j in (1,2):
        spec=new_specs[f'Scythe_{side}{j:02d}']
        a,b=spec['head'],spec['tail']
        tube(f'scythe_arm_{side}_{j}',[a,a.lerp(b,.45),b],[.105,.145 if j==2 else .12,.095],f'Scythe_{side}{j:02d}',0,sides=10)
        ellipsoid(f'scythe_joint_{side}_{j}',a,(.12,.11,.11),f'Scythe_{side}{j:02d}',1,seg=8,rings=4)
        tube(f'arm_fissure_{side}_{j}',[a.lerp(b,.2)+Vector((0,.105,0)),a.lerp(b,.75)+Vector((0,.105,0))],[.018,.021],f'Scythe_{side}{j:02d}',3,sides=4)
    hook=[(sign*.96,.31,2.35),(sign*1.02,.37,2.55),(sign*.99,.55,2.77),
          (sign*.84,.77,2.91),(sign*.64,.98,2.92),(sign*.44,1.15,2.82),(sign*.31,1.27,2.64),(sign*.25,1.33,2.47)]
    blade('scythe_hook_'+side,hook,[.15,.17,.19,.18,.15,.10,.055,.001],[.045,.05,.06,.058,.045,.035,.018,.001],f'Scythe_{side}03',0,steps=3)
    tube('scythe_glow_'+side,[(x,y+.095,z) for x,y,z in hook[1:6]],[.008]*5,f'Scythe_{side}03',3,sides=6)
    for j in (1,2,3,4):
        p=Vector(hook[j])
        spike(f'scythe_barb_{side}_{j}',p,p+Vector((sign*.05,-.09,.16)),.049,f'Scythe_{side}03',0)
    jaw=[(sign*.245,1.08,1.04),(sign*.395,1.10,1.005),(sign*.49,1.14,.885),
         (sign*.49,1.19,.72),(sign*.39,1.24,.595),(sign*.24,1.265,.535),(sign*.20,1.25,.63)]
    ellipsoid('jaw_root_'+side,jaw[0],(.125,.10,.14),f'Mandible_{side}',0,seg=12,rings=6)
    blade('mandible_'+side,jaw,[.09,.125,.125,.105,.073,.028,.001],[.061,.068,.066,.052,.036,.017,.001],f'Mandible_{side}',0,steps=3)
    for j in (1,2,3):
        p=Vector(jaw[j]); p.x-=sign*.07
        spike(f'mandible_tooth_{side}_{j}',p,p+Vector((-sign*.12,.008,.005 if j==1 else .042)),.040,f'Mandible_{side}',2)

mesh=bpy.data.meshes.new('warrior_concept_geometry')
mesh.from_pydata(verts,[],faces)
mesh.update()
obj=bpy.data.objects.new('warrior_Skinned',mesh)
bpy.context.collection.objects.link(obj)
for mat in materials: mesh.materials.append(mat)
uv=mesh.uv_layers.new(name='UVMap')
paint=mesh.color_attributes.new(name='ConceptPalette',type='FLOAT_COLOR',domain='CORNER')
for poly,mat,coords in zip(mesh.polygons,face_mats,uv_faces):
    poly.material_index=mat
    poly.use_smooth=True
    for li,coord in zip(poly.loop_indices,coords):
        uv.data[li].uv=coord
        color=paint_colors[mesh.loops[li].vertex_index] if mat==0 else (1,1,1)
        paint.data[li].color=(*color,1)
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
 'export_optimize_animation_size':False,'export_lights':False,'export_cameras':False,
 'export_vertex_color':'NAME','export_vertex_color_name':'ConceptPalette'}
args={key:value for key,value in requested.items() if key in props}
bpy.ops.export_scene.gltf(**args)
export_doc=json.loads((DEST/'warrior.gltf').read_text())
# The bundled Godot 4.7.2 import left vertex colouring disabled on the first
# primitive while enabling subsequent ones. Put the uniform dark surface first;
# it needs no tint. Keep the non-uniform chitin after it and verify in Godot.
for exported_mesh in export_doc.get('meshes',[]):
    exported_mesh['primitives'].sort(key=lambda p:0 if p['material']==1 else 1)
for image in export_doc.get('images',[]):
    # Portable URI: supplied atlas already exists beside the model, never rewritten.
    image['uri']=ALBEDO.name
assert len(export_doc.get('images', [])) == 1, 'Expected exactly one atlas image'
assert export_doc['materials'][0]['pbrMetallicRoughness'].get('baseColorTexture'), 'Chitin texture was not exported'
assert all('COLOR_0' in p['attributes'] for m in export_doc['meshes'] for p in m['primitives']), 'Concept palette vertex colors were lost'
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
 'materials':[m.name for m in materials],'albedo_path':ALBEDO.relative_to(ROOT).as_posix(),'albedo_sha256':albedo_hash_before,
 'albedo_unchanged':hashlib.sha256(ALBEDO.read_bytes()).hexdigest()==albedo_hash_before,
 'palette':{'revision':'concept_palette_v3','attribute':'COLOR_0','shell_emission':.12,'specular_ior_level':.10,
            'zones':['plum recesses','mahogany panels','amber ridge accents','violet seams','green eyes']},
 'head_emphasis':{'pivot':[0,.58,1.25],'scale':[1.14,1.04,1.12],'forward_offset':.10,'space':'Blender authoring idle pose'},
 'scope':'Runtime prototype; preserves recovered source rig/animations, no rights-clean claim.'}
(SCRATCH/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(SCRATCH/'warrior_preview.blend'))
print('WARRIOR_BUILD_PASS',json.dumps({k:report[k] for k in ('bone_count','vertex_count','triangle_count','mesh_count','export_clips','albedo_unchanged')}),flush=True)
