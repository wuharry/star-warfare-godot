"""Build Tank editable master from original skin-space snapshot.

The original four-part topology, bones, weights and UV charts are retained.
The lower helmet guard is subtly tightened; a few front UV samples align the
approved collar and single chin vent with the generated diffuse atlas.
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/tank_runtime_v1'
SOURCE = json.loads((WORK/'build/source.json').read_text())
C = Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
LABELS = {'ArmorHead_02':['head','hand'], 'ArmorBody_02':['body','shoulder'],
          'ArmorHand_02':['hand'], 'ArmorFoot_02':['foot']}


def reshape(name, point):
    # Keep the established large visor and central notch. The approved image
    # slightly tightens the lower guard; hidden rear and neck remain original.
    p = Vector(point)
    if name != 'ArmorHead_02':
        return p
    x,y,z = p
    if z < -.18 and y < 1.49:
        amount = min(1.0,max(0.0,(1.49-y)/.20))
        p.x *= 1.0-.06*amount
        p.y += .010*amount
        p.z -= .012*amount
        if abs(x) < .065 and 1.34 < y < 1.44:
            p.z -= .004
    return p


def adjusted_uv(name, point, uv, surface_id=0):
    # Keep all chart boundaries/counts, mirrored duplicate coordinates and the
    # original atlas layout. Only the chin seam and upper front torso sample
    # different pixels; the lower torso slot, back, limbs and neck stay exact.
    u,v=uv
    if name=='ArmorHead_02' and surface_id==0:
        if (abs(u-.0400)<.0001 and abs(v-.7358)<.0001) or (.0441<u<.0444 and .6461<v<.6464):
            return [u+.017,v]
    if name=='ArmorBody_02' and surface_id==0 and u<.26:
        shifts={.4151:.135,.5184:.1184,.3766:.120,.3404:.070,
                .5254:.100,.5032:.130}
        for row,shift in shifts.items():
            if abs(v-row)<.0001:
                return [u,v-shift]
    return [u,v]


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
    tex=nodes.new('ShaderNodeTexImage'); tex.image=bpy.data.images.load(str(path),check_existing=True)
    mat.node_tree.links.new(tex.outputs['Color'],emit.inputs['Color'])
    mat.node_tree.links.new(emit.outputs[0],out.inputs['Surface'])
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'
    low=bpy.data.collections.new('LOW'); scene.collection.children.link(low)
    rigcol=bpy.data.collections.new('RIG_DEF'); scene.collection.children.link(rigcol)
    arm=bpy.data.armatures.new('Original28Bones'); rig=bpy.data.objects.new('TankRig',arm)
    rigcol.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for row in SOURCE['bones']:
        bone=arm.edit_bones.new(row['name']); m=C@Matrix(row['matrix'])
        bone.head=m.translation; bone.tail=bone.head+(m.to_3x3()@Vector((0,.06,0)))
        if row['parent']>=0:bone.parent=arm.edit_bones[SOURCE['bones'][row['parent']]['name']]
    bpy.ops.object.mode_set(mode='OBJECT'); rig.select_set(False)
    target={'revision':'tank_runtime_v1','id':2,'parts':{}}
    guide_polygons={}
    geometry={'parts':{}, 'constraint':'Local shape/dimension changes <=15%; changed UV coordinates <=15% per material and per part; chin-seam and upper-front-chest sampling edits only. Original chart/coordinate count, topology and skin retained. Absolute UV displacement is recorded separately.'}
    for name,part in SOURCE['parts'].items():
        points=[]; uv=[]; weights=[]; bone_names=[]; faces=[]; mids=[]; offsets=[]; target_surfaces=[]
        deltas=[]; uv_by_surface=[]
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
            changed=sum((Vector(a)-Vector(b)).length>.000001 for a,b in zip(authored_uv,row['uv']))
            assert changed/len(row['uv'])<=.15, (name,sid,'material UV budget exceeded')
            uv_by_surface.append({'surface':sid,'label':LABELS[name][sid],
                                  'uv_coordinate_count':len(row['uv']),
                                  'uv_changed_count':changed,
                                  'uv_changed_fraction':changed/len(row['uv'])})
            def signed_area(coords,tri):
                a,b,c=[coords[index] for index in tri]
                return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
            for start in range(0,len(row['indices']),3):
                tri=row['indices'][start:start+3]
                before=signed_area(row['uv'],tri);after=signed_area(authored_uv,tri)
                assert abs(before)<=1e-8 or before*after>0, (name,sid,start//3,'UV triangle folded')
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(points,[],faces); mesh.update()
        ob=bpy.data.objects.new(name,mesh); low.objects.link(ob)
        layer=mesh.uv_layers.new(name='OriginalUV_LocalFrontSampling')
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; src=ROOT/row['texture'].removeprefix('res://')
            delivered=ROOT/f'assets/armors/tank_v1/{label}_diffuse.png'
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
        assert len(uv) == len(original_uv) and changed_uv/len(original_uv) <= .15
        old=[Vector(p) for row in part['surfaces'] for p in row['positions']]
        new=[C.inverted()@p for p in points]
        bounds=lambda ps:{'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
        before=bounds(old); after=bounds(new)
        ratios=[abs((after['max'][i]-after['min'][i])/(before['max'][i]-before['min'][i])-1) for i in range(3)]
        max_delta=max(deltas)
        normalizer=min(before['max'][i]-before['min'][i] for i in range(3))
        assert max(ratios)<=.15 and max_delta/normalizer<=.15
        geometry['parts'][name]={'bounds_game':after,'original_bounds':before,'dimension_delta_fraction':ratios,'max_rest_displacement':max_delta,'max_displacement_fraction_of_smallest_dimension':max_delta/normalizer,'triangles':len(faces),'uv_preserved':changed_uv==0, 'original_uv_charts':original_charts,'uv_charts':edited_charts,'uv_coordinate_count':len(uv), 'original_uv_coordinate_count':len(original_uv), 'uv_changed_count':changed_uv, 'uv_changed_fraction':changed_uv/len(original_uv), 'uv_max_displacement_from_original':max(uv_displacements), 'uv_rms_displacement_from_original':math.sqrt(sum(distance*distance for distance in uv_displacements)/len(uv_displacements)), 'uv_by_surface':uv_by_surface,'weight_source':'original, unchanged'}
        # Exact continuous UV chart wire guides; technical edges are never paint edges.
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; paths=[]
            for j in range(0,len(row['indices']),3):
                coords=[target_surfaces[sid]['uv'][idx] for idx in row['indices'][j:j+3]]
                paths.append('<polygon points="'+' '.join(f'{u*1024:.3f},{v*1024:.3f}' for u,v in coords)+'" fill="none" stroke="#9ad9e8" stroke-width="1"/>')
            # Preserve the immutable original guides used by image generation.
            guide_name=f'{label}_authored_uv'
            guide_polygons.setdefault(guide_name,[]).extend(paths)
    for guide_name,paths in guide_polygons.items():
        (WORK/'guides'/f'{guide_name}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'+''.join(paths)+'</svg>')
    (WORK/'build/target.json').write_text(json.dumps(target,indent=2))
    (WORK/'build/geometry.json').write_text(json.dumps(geometry,indent=2))
    scene.view_settings.view_transform='Standard'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'build/tank_master.blend'))
    print('TANK_BUILD_PASS local edits within15%, triangles='+str(sum(p['triangles'] for p in geometry['parts'].values())))

if __name__=='__main__':main()
