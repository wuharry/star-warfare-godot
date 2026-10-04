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


def reshape(name, point, surface_id=0):
    # Helmet refinement v3: derive every candidate point from the true original
    # rest-space source. Shared neck surface1 and all other parts stay exact.
    p = Vector(point)
    if name != 'ArmorHead_02' or surface_id != 0:
        return p
    x,y,z=p
    def near(yy,zz,tolerance=.0002):
        return abs(y-yy)<tolerance and abs(z-zz)<tolerance
    # Collapse the heavy front blue brow from ~90mm to ~30-45mm.
    if near(1.5974,-.3867): p.y=1.660
    elif near(1.6040,-.3404): p.y=1.653
    elif near(1.6010,-.3375): p.y=1.653
    elif near(1.6044,-.2883): p.y=1.645
    elif near(1.6257,-.1415): p.y=1.651
    elif near(1.6204,-.1506): p.y=1.644
    # Smooth the existing crown's layered strip into one shallow arc. No faces
    # or channels added; its transverse groove expression is painted separately.
    if near(1.9271,-.0443): p.y=1.910
    elif near(1.9091,-.0444): p.y=1.901
    elif near(1.8914,-.0427): p.y=1.898
    elif near(1.8487,-.2769): p.y=1.845
    elif near(1.8142,-.2550): p.y=1.830
    elif near(1.8328,-.2679): p.y=1.834
    elif near(1.7789,-.3559): p.y=1.792
    elif near(1.7684,-.3405): p.y=1.784
    elif near(1.8713,.1293): p.y=1.877
    elif near(1.8390,.1057): p.y=1.865
    elif near(1.8530,.1144): p.y=1.866
    elif near(1.7090,.2083): p.y=1.735
    # Shorter, almost flat-topped respirator and a shallow stepped visor notch.
    if near(1.5070,-.3274): p.y=1.463; p.z=-.324
    elif near(1.4732,-.3119): p.y=1.458; p.z=-.321
    elif near(1.4417,-.3604): p.y=1.412; p.z=-.337
    elif near(1.4276,-.3567): p.y=1.409; p.z=-.334
    elif near(1.3142,-.3095): p.y=1.337; p.z=-.310
    elif near(1.2911,-.3097): p.y=1.330; p.z=-.310
    elif near(1.3700,-.3359): p.y=1.378; p.z=-.333
    elif near(1.3664,-.3394): p.y=1.375; p.z=-.332
    # Compact the existing oblique cheek/jaw polygons without new ear geometry.
    if near(1.3953,-.2920): p.x*=.94; p.y=1.404; p.z=-.282
    elif near(1.3212,-.2526): p.x*=.93; p.y=1.345; p.z=-.247
    elif near(1.3719,-.0975): p.x*=.96; p.y=1.394
    elif near(1.4222,-.2404): p.x*=.94; p.y=1.439
    elif near(1.4332,-.2459): p.x*=.97; p.y=1.450
    elif near(1.4136,-.2800): p.x*=.96; p.y=1.426
    elif near(1.4815,-.1315): p.x*=.96
    elif near(1.4850,-.1422): p.x*=.96
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
    geometry={'parts':{}, 'constraint':'Helmet refinement v3: original-total head shape/dimension/UV <=20%, latest user authorization. UV stays exact against stylev2 (inherited chin/body sampling only); head surface1 neck and all other geometry exact original. Original charts/count/topology/Skin retained. Absolute UV displacement recorded separately.', 'stage':'helmet_refinement_v3', 'user_authorized_original_total_head_limit':.20}
    for name,part in SOURCE['parts'].items():
        points=[]; uv=[]; weights=[]; bone_names=[]; faces=[]; mids=[]; offsets=[]; target_surfaces=[]
        deltas=[]; uv_by_surface=[]
        for sid,row in enumerate(part['surfaces']):
            offset=len(points); offsets.append(offset)
            authored=[reshape(name,p,sid) for p in row['positions']]
            authored_uv=[adjusted_uv(name,p,t,sid) for p,t in zip(authored,row['uv'])]
            points.extend(C@p for p in authored); uv.extend(authored_uv)
            weights.extend(row['weights']); bone_names.extend(row['bone_names'])
            # Engine winding differs under the handedness conversion C.
            for i in range(0,len(row['indices']),3):
                faces.append(tuple(offset+j for j in reversed(row['indices'][i:i+3]))); mids.append(sid)
            target_surfaces.append({'positions':[list(p) for p in authored], 'uv':authored_uv, 'label':LABELS[name][sid]})
            deltas.extend((p-Vector(old)).length for p,old in zip(authored,row['positions']))
            changed=sum((Vector(a)-Vector(b)).length>.000001 for a,b in zip(authored_uv,row['uv']))
            assert changed/len(row['uv'])<=(.20 if name=='ArmorHead_02' and sid==0 else .15), (name,sid,'material UV budget exceeded')
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
        assert len(uv) == len(original_uv) and changed_uv/len(original_uv) <= (.20 if name=='ArmorHead_02' else .15)
        old=[Vector(p) for row in part['surfaces'] for p in row['positions']]
        new=[C.inverted()@p for p in points]
        bounds=lambda ps:{'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
        before=bounds(old); after=bounds(new)
        ratios=[abs((after['max'][i]-after['min'][i])/(before['max'][i]-before['min'][i])-1) for i in range(3)]
        max_delta=max(deltas)
        normalizer=min(before['max'][i]-before['min'][i] for i in range(3))
        assert max(ratios)<=(.20 if name=='ArmorHead_02' else .15) and max_delta/normalizer<=(.20 if name=='ArmorHead_02' else .15)
        geometry['parts'][name]={'bounds_game':after,'original_bounds':before,'dimension_delta_fraction':ratios,'max_rest_displacement':max_delta,'max_displacement_fraction_of_smallest_dimension':max_delta/normalizer,'triangles':len(faces),'uv_preserved':changed_uv==0, 'original_uv_charts':original_charts,'uv_charts':edited_charts,'uv_coordinate_count':len(uv), 'original_uv_coordinate_count':len(original_uv), 'uv_changed_count':changed_uv, 'uv_changed_fraction':changed_uv/len(original_uv), 'uv_max_displacement_from_original':max(uv_displacements), 'uv_rms_displacement_from_original':math.sqrt(sum(distance*distance for distance in uv_displacements)/len(uv_displacements)), 'uv_by_surface':uv_by_surface,'weight_source':'original, unchanged'}
        if name == 'ArmorHead_02':
            row=part['surfaces'][0]; candidate=target_surfaces[0]['positions']
            reversed_triangles=0;zero_area=0;cosines=[];groups={}
            for index,point in enumerate(row['positions']):groups.setdefault(tuple(point),[]).append(index)
            for offset in range(0,len(row['indices']),3):
                ids=row['indices'][offset:offset+3]
                old_points=[Vector(row['positions'][i]) for i in ids]
                new_points=[Vector(candidate[i]) for i in ids]
                a=(old_points[1]-old_points[0]).cross(old_points[2]-old_points[0])
                b=(new_points[1]-new_points[0]).cross(new_points[2]-new_points[0])
                if b.length<=1e-10:zero_area+=1
                if a.length>1e-10 and b.length>1e-10:
                    cosine=a.normalized().dot(b.normalized());cosines.append(cosine)
                    if cosine<0:reversed_triangles+=1
            seam=max((Vector(candidate[a])-Vector(candidate[b])).length for group in groups.values() for a in group for b in group)
            geometry['parts'][name]['shape_quality']={'reversed_triangles':reversed_triangles,'zero_area_triangles':zero_area,'coincident_seam_max_rest_gap':seam,'min_triangle_normal_cosine_from_original':min(cosines)}
            assert reversed_triangles==0 and zero_area==0 and seam==0
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
    print('TANK_BUILD_PASS helmet v3 original-total head<=20%, other parts unchanged; triangles='+str(sum(p['triangles'] for p in geometry['parts'].values())))

if __name__=='__main__':main()
