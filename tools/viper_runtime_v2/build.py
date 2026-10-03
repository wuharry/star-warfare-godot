"""Locally reshape the source cage; retain weights; adjust only visor and front-torso UV.

Godot's source snapshot is authoritative for rest-space positions and bind names.
Engine delivery preserves the original Skin; this editable Blender master uses a
rest-space deformation rig so repeated legacy bind aliases need no weight edits.
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/viper_runtime_v2'
SOURCE = json.loads((WORK/'build/source.json').read_text())
C = Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
LABELS = {'ArmorHead_00':['head'], 'ArmorBody_00':['body','shoulder'],
          'ArmorHand_00':['hand'], 'ArmorFoot_00':['foot']}


def reshape(name, point):
    p = Vector(point)
    if name != 'ArmorHead_00':
        return p
    # Inferred local contour translation from approved helmet; metres in the
    # measured original game's frame. Neck/attachment and rear remain untouched.
    x,y,z = p
    if z < -.18 and y < 1.52:
        amount = min(1.0, max(0.0,(1.52-y)/.23))
        p.x *= 1.0-.14*amount  # more fitted lower jaw after user's faceplate correction
        p.y += .035*amount     # thinner blue chin; neck/attachment unchanged
        p.z += .036*amount
    if z < -.27 and 1.34 < y < 1.41:
        p.y = y-.020           # lower polygonal lens tip, inferred from approved art
        p.z = z-.012
    if z < -.25 and 1.57 < y < 1.62:
        p.y += .026            # raise continuous upper lens edge; reduce heavy brow
        p.x *= 1.10
        p.z -= .015
    if -.18 < z < -.07 and 1.40 < y < 1.62 and abs(x) > .13:
        p.x *= .90             # inward-swept cheek sides instead of visor goggle cuts
        p.z -= .025
    if z < -.25 and 1.57 < y < 1.71:
        p.z -= .018            # short brow projection, no floating face plates
    if y > 1.78 and z < -.16:
        p.z += .010            # coherent rounded crown/front transition
    return p


def adjusted_uv(name, point, uv, surface_id=0):
    # User allows local helmet UV changes (20%); keep the original four chart
    # regions and source geometry topology. Only the 18 existing visor coordinates move.
    if name == 'ArmorHead_00' and uv[0] > .59 and uv[1] > .69:
        x,y,_ = point
        return [.603 + .340 * min(1.0, max(0.0,(x+.196)/.392)),
                .701 + .250 * min(1.0, max(0.0,(1.618-y)/.26))]
    # The existing front chest occupies one mirrored half at the left atlas
    # edge. Sample the selected v8 paint's chest/strap region with only its
    # 20 original coordinates. Back, thighs and shoulder stay exact.
    if name == 'ArmorBody_00' and surface_id == 0 and uv[0] < .26 and .38 < uv[1] < .69:
        return [.029 + (uv[0] - .029) * .60,
                .275 + (uv[1] - .415) * (.230 / .272)]
    # Extend the connected front belly into its painted black core and blue
    # groin. These 12 existing coordinates retain their horizontal placement.
    if name == 'ArmorBody_00' and surface_id == 0 and uv[0] < .24 and .69 < uv[1] < .885:
        return [uv[0], .505 + (uv[1] - .687) * (.345 / .189)]
    return list(uv)


def uv_components(surfaces):
    adjacency={}
    for row in surfaces:
        keys=[tuple(round(c,6) for c in uv) for uv in row['uv']]
        for offset in range(0,len(row['indices']),3):
            triangle=[keys[i] for i in row['indices'][offset:offset+3]]
            for vertex in triangle:adjacency.setdefault(vertex,set()).update(triangle)
    unseen=set(adjacency); count=0
    while unseen:
        count+=1; stack=[unseen.pop()]
        while stack:
            for neighbor in adjacency[stack.pop()]:
                if neighbor in unseen:unseen.remove(neighbor);stack.append(neighbor)
    return count


def material(label, path):
    mat=bpy.data.materials.new(label); mat.diffuse_color=(.3,.45,.6,1)
    nodes=mat.node_tree.nodes; nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial'); emit=nodes.new('ShaderNodeEmission')
    tex=nodes.new('ShaderNodeTexImage'); tex.image=bpy.data.images.load(str(path))
    mat.node_tree.links.new(tex.outputs['Color'],emit.inputs['Color'])
    mat.node_tree.links.new(emit.outputs[0],out.inputs['Surface'])
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'
    low=bpy.data.collections.new('LOW'); scene.collection.children.link(low)
    rigcol=bpy.data.collections.new('RIG_DEF'); scene.collection.children.link(rigcol)
    arm=bpy.data.armatures.new('Original28Bones'); rig=bpy.data.objects.new('ViperRig',arm)
    rigcol.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for row in SOURCE['bones']:
        bone=arm.edit_bones.new(row['name']); m=C@Matrix(row['matrix'])
        bone.head=m.translation; bone.tail=bone.head+(m.to_3x3()@Vector((0,.06,0)))
        if row['parent']>=0:bone.parent=arm.edit_bones[SOURCE['bones'][row['parent']]['name']]
    bpy.ops.object.mode_set(mode='OBJECT'); rig.select_set(False)
    target={'revision':'viper_runtime_v2','id':0,'parts':{}}
    geometry={'parts':{}, 'constraint':'Local shape/dimension changes <=20%; changed UV coordinates <=20% per part, only visor and front chest/abdomen; original chart/coordinate count and skin retained. Absolute UV displacement is recorded separately.'}
    for name,part in SOURCE['parts'].items():
        points=[]; uv=[]; weights=[]; bone_names=[]; faces=[]; mids=[]; offsets=[]; target_surfaces=[]
        deltas=[]
        for sid,row in enumerate(part['surfaces']):
            offset=len(points); offsets.append(offset)
            authored=[reshape(name,p) for p in row['positions']]
            authored_uv=[adjusted_uv(name,p,t,sid) for p,t in zip(authored,row['uv'])]
            points.extend(C@p for p in authored); uv.extend(authored_uv)
            weights.extend(row['weights']); bone_names.extend(row['bone_names'])
            # Engine winding differs under the handedness conversion C.
            for i in range(0,len(row['indices']),3):
                faces.append(tuple(offset+j for j in reversed(row['indices'][i:i+3]))); mids.append(sid)
            target_surfaces.append({'positions':[list(p) for p in authored], 'uv':authored_uv, 'label':LABELS[name][sid]})
            deltas.extend((p-Vector(old)).length for p,old in zip(authored,row['positions']))
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(points,[],faces); mesh.update()
        ob=bpy.data.objects.new(name,mesh); low.objects.link(ob)
        layer=mesh.uv_layers.new(name='SourceUV_VisorTorsoLocal')
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; src=ROOT/row['texture'].removeprefix('res://')
            delivered=ROOT/f'assets/armors/viper_v2/{label}_diffuse.png'
            mesh.materials.append(material(label,delivered if delivered.exists() else src))
        for poly,sid in zip(mesh.polygons,mids):
            poly.material_index=sid
            for li in poly.loop_indices:
                u,v=uv[mesh.loops[li].vertex_index]; layer.data[li].uv=(u,1-v)
        for row in SOURCE['bones']:ob.vertex_groups.new(name=row['name'])
        for i,(names,ws) in enumerate(zip(bone_names,weights)):
            accumulated={}
            for key,w in zip(names,ws):accumulated[key]=accumulated.get(key,0)+w
            for key,w in accumulated.items():
                if w>0:ob.vertex_groups[key].add([i],w,'REPLACE')
        modifier=ob.modifiers.new('PreservedSourceWeights','ARMATURE'); modifier.object=rig
        ob.parent=rig
        target['parts'][name]={'surfaces':target_surfaces}
        original_charts=uv_components(part['surfaces'])
        edited_charts=uv_components([{**row,'uv':target_surfaces[sid]['uv']} for sid,row in enumerate(part['surfaces'])])
        assert edited_charts == original_charts
        original_uv=[t for row in part['surfaces'] for t in row['uv']]
        uv_displacements=[(Vector(a)-Vector(b)).length for a,b in zip(uv,original_uv)]
        changed_uv=sum(distance > .000001 for distance in uv_displacements)
        assert len(uv) == len(original_uv) and changed_uv/len(original_uv) <= .20
        old=[Vector(p) for row in part['surfaces'] for p in row['positions']]
        new=[C.inverted()@p for p in points]
        bounds=lambda ps:{'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
        before=bounds(old); after=bounds(new)
        ratios=[abs((after['max'][i]-after['min'][i])/(before['max'][i]-before['min'][i])-1) for i in range(3)]
        max_delta=max(deltas)
        normalizer=min(before['max'][i]-before['min'][i] for i in range(3))
        assert max(ratios)<=.20 and max_delta/normalizer<=.20
        geometry['parts'][name]={'bounds_game':after,'original_bounds':before,'dimension_delta_fraction':ratios,'max_rest_displacement':max_delta,'max_displacement_fraction_of_smallest_dimension':max_delta/normalizer,'triangles':len(faces),'uv_preserved':changed_uv==0, 'original_uv_charts':original_charts,'uv_charts':edited_charts,'uv_coordinate_count':len(uv), 'original_uv_coordinate_count':len(original_uv), 'uv_changed_count':changed_uv, 'uv_changed_fraction':changed_uv/len(original_uv), 'uv_max_displacement_from_original':max(uv_displacements), 'uv_rms_displacement_from_original':math.sqrt(sum(distance*distance for distance in uv_displacements)/len(uv_displacements)), 'weight_source':'original, unchanged'}
        # Exact continuous UV chart wire guides; technical edges are never paint edges.
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; paths=[]
            for j in range(0,len(row['indices']),3):
                coords=[target_surfaces[sid]['uv'][idx] for idx in row['indices'][j:j+3]]
                paths.append('<polygon points="'+' '.join(f'{u*1024:.3f},{v*1024:.3f}' for u,v in coords)+'" fill="none" stroke="#9ad9e8" stroke-width="1"/>')
            guide_name='head_uv_v6' if label=='head' else 'body_uv_v8' if label=='body' else f'{label}_uv'
            (WORK/'guides'/f'{guide_name}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'+''.join(paths)+'</svg>')
    (WORK/'build/target.json').write_text(json.dumps(target,indent=2))
    (WORK/'build/geometry.json').write_text(json.dumps(geometry,indent=2))
    scene.view_settings.view_transform='Standard'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'build/viper_master.blend'))
    print('VIPER_BUILD_PASS local edits within20%, triangles='+str(sum(p['triangles'] for p in geometry['parts'].values())))

if __name__=='__main__':main()
