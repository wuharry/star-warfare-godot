"""Build an armor editable master using its runtime_config and true original snapshot.

The original four-part topology, bones, weights and UV charts are retained.
Bounded refinements move only configured original parts. UV samples, topology,
weights and the remaining original part arrays stay exact.
"""
import json
import math
import sys
import importlib.util
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/armor_runtime_v1'))
from neck_source_contract import verify_neck

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
slug=next((a.split('=',1)[1] for a in args if a.startswith('--armor=')),None)
assert slug in ['hydra','strike','titan','atom','pegasus'], 'Pass -- --armor=hydra/strike/titan/atom/pegasus'
CONFIG=json.loads((ROOT/'docs/art'/f'{slug}_runtime_v1/runtime_config.json').read_text())
WORK=ROOT/CONFIG['work'];SOURCE=json.loads((ROOT/CONFIG['source']).read_text())
C = Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
LABELS=CONFIG['parts']; HEAD=f"ArmorHead_{CONFIG['runtime_id']:02}"
shape_path=ROOT/CONFIG.get('shape_file',f"tools/armor_runtime_v1/shapes/{slug}.py")
shape=None
if shape_path.exists():
    spec=importlib.util.spec_from_file_location('armor_shape',shape_path)
    shape=importlib.util.module_from_spec(spec);spec.loader.exec_module(shape)
    if hasattr(shape, 'configure_neck_source'):
        assert len(SOURCE['parts'][HEAD]['surfaces']) == 1
        neck_source_path = (ROOT / CONFIG['original_source_snapshot']).parent / 'source.json'
        neck_source = json.loads(neck_source_path.read_text(encoding='utf-8-sig'))
        assert SOURCE == neck_source, 'Neck guard requires the unchanged true original source'
        shape.configure_neck_source(neck_source['parts'][HEAD]['surfaces'][0])
    if hasattr(shape, 'configure_shell_fit'):
        shape.configure_shell_fit(CONFIG.get('shell_fit', {}))
contract=None; MOVABLE=set(); BOUNDED=False
if slug in ['atom','pegasus']:
    spec=importlib.util.spec_from_file_location('first_integration_contract',ROOT/'tools/armor_runtime_v1/first_integration_contract.py')
    contract=importlib.util.module_from_spec(spec);spec.loader.exec_module(contract)
    contract.verify_first_source(slug)
    MOVABLE=contract.geometry_parts(CONFIG,SOURCE['parts']); BOUNDED=bool(MOVABLE)
    if BOUNDED:assert shape and hasattr(shape,'reshape_part'), 'Bounded refinement requires reshape_part(name, point, surface_id)'

def reshape(name, point, surface_id=0):
    p=Vector(point)
    if BOUNDED:
        return Vector(shape.reshape_part(name,list(p),surface_id)) if name in MOVABLE else p
    return Vector(shape.reshape(list(p),surface_id)) if name==HEAD and shape else p

def adjusted_uv(name, point, uv, surface_id=0):
    if contract:return list(uv)
    if name == HEAD and shape and hasattr(shape, 'adjust_uv'):
        return shape.adjust_uv(list(point), list(uv))
    return list(uv) # All five authored maps use unchanged true original UV.


def bind_positions(part, row, authored):
    bones={bone['name']:Matrix(bone['matrix']) for bone in SOURCE['bones']}
    raw=[]
    for index,point in enumerate(authored):
        weighted=Matrix(((0,0,0),(0,0,0),(0,0,0)))
        for bind,weight in zip(row['bone_indices'][index],row['weights'][index]):
            record=part['bind_records'][bind]
            weighted+=(bones[record['name']]@Matrix(record['matrix'])).to_3x3()*weight
        delta=point-Vector(row['positions'][index])
        raw.append(list(Vector(row['raw_positions'][index])+weighted.inverted()@delta))
    return raw


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
    arm=bpy.data.armatures.new('Original28Bones'); rig=bpy.data.objects.new(CONFIG['name']+'Rig',arm)
    rigcol.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for row in SOURCE['bones']:
        bone=arm.edit_bones.new(row['name']); m=C@Matrix(row['matrix'])
        bone.head=m.translation; bone.tail=bone.head+(m.to_3x3()@Vector((0,.06,0)))
        if row['parent']>=0:bone.parent=arm.edit_bones[SOURCE['bones'][row['parent']]['name']]
    bpy.ops.object.mode_set(mode='OBJECT'); rig.select_set(False)
    target={'revision':CONFIG.get('active_helmet_revision',slug+'_runtime_v1'),'id':CONFIG['runtime_id'],'parts':{}}
    if contract:
        target['geometry_mode']='original_source_bounded_refinement' if BOUNDED else 'texture_only'
        target['geometry_parts']=CONFIG.get('geometry_parts',[]) if BOUNDED else []
    guide_polygons={}
    geometry={'parts':{},'stage':CONFIG.get('active_helmet_revision','original_integration_v1'),'constraint':'Original-total20% shape/dimensions; only explicitly configured visor edges may be subdivided. Broad chart count and original rig retained.','user_authorized_original_total_limit':.20}

    for name,part in SOURCE['parts'].items():
        points=[]; uv=[]; weights=[]; bone_names=[]; faces=[]; mids=[]; offsets=[]; target_surfaces=[]
        deltas=[]; uv_by_surface=[]
        for sid,row in enumerate(part['surfaces']):
            original_row=row
            offset=len(points); offsets.append(offset)
            authored=[reshape(name,p,sid) for p in row['positions']]
            authored_uv=[adjusted_uv(name,p,t,sid) for p,t in zip(authored,row['uv'])]
            if name == HEAD and shape and hasattr(shape, 'refine_surface') and not contract:
                row, authored_list=shape.refine_surface(row,[list(p) for p in authored],authored_uv)
                authored=[Vector(p) for p in authored_list]; authored_uv=row['uv']
            points.extend(C@p for p in authored); uv.extend(authored_uv)
            weights.extend(row['weights']); bone_names.extend(row['bone_names'])
            # Engine winding differs under the handedness conversion C.
            for i in range(0,len(row['indices']),3):
                faces.append(tuple(offset+j for j in reversed(row['indices'][i:i+3]))); mids.append(sid)
            target_row={'positions':[list(p) for p in authored], 'uv':authored_uv, 'label':LABELS[name][sid]}
            if contract:
                assert len(authored)==len(original_row['positions']) and row['indices']==original_row['indices']
                assert authored_uv==original_row['uv'], (name,sid,'Original UV0 must remain exact')
                geometry_changed=any((point-Vector(old)).length>1e-6 for point,old in zip(authored,original_row['positions']))
                target_row['geometry_changed']=geometry_changed
                if geometry_changed:
                    assert name in MOVABLE
                    target_row['raw_positions']=bind_positions(part,original_row,authored)
                    target_row['normals'],target_row['tangents']=contract.bind_normal_frames(original_row,target_row['raw_positions'])
                else:
                    # Retain exact original JSON decimals for unchanged surfaces.
                    target_row['positions']=original_row['positions']
            if CONFIG.get('preserve_all_geometry'):
                assert all((point-Vector(old)).length == 0 for point,old in zip(authored,original_row['positions'])), (name,sid,'Texture-only source positions changed')
                # Godot JSON decimal text differs from mathutils float32 by
                # about 5e-15; preserve original JSON samples for exact source
                # provenance after proving the actual Blender values are equal.
                target_row['positions'] = original_row['positions']
                assert authored_uv == original_row['uv'], (name,sid,'Texture-only source UV changed')
                assert row['indices'] == original_row['indices'], (name,sid,'Texture-only topology changed')
            if 'added_vertices' in row:
                for field in ['indices','bone_indices','bone_names','weights','triangle_parents','added_vertices']:
                    target_row[field]=row[field]
                target_row['baseline_positions']=row['positions']
            if name == HEAD and shape and hasattr(shape, 'configure_neck_source'):
                verify_neck(original_row, target_row)
            target_surfaces.append(target_row)
            deltas.extend((p-Vector(old)).length for p,old in zip(authored,row['positions']))
            changed=sum((Vector(a)-Vector(b)).length>.000001 for a,b in zip(authored_uv,original_row['uv']))
            assert changed/len(original_row['uv'])<=.20, (name,sid,'material UV budget exceeded')
            uv_by_surface.append({'surface':sid,'label':LABELS[name][sid],
                                  'uv_coordinate_count':len(row['uv']),
                                  'uv_changed_count':changed,
                                  'uv_changed_fraction':changed/len(original_row['uv'])})
            def signed_area(coords,tri):
                a,b,c=[coords[index] for index in tri]
                return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
            for start in range(0,len(original_row['indices']),3):
                tri=original_row['indices'][start:start+3]
                before=signed_area(original_row['uv'],tri);after=signed_area(authored_uv,tri)
                assert abs(before)<=1e-8 or before*after>0, (name,sid,start//3,'UV triangle folded')
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(points,[],faces); mesh.update()
        ob=bpy.data.objects.new(name,mesh); low.objects.link(ob)
        layer=mesh.uv_layers.new(name='OriginalUV_LocalFrontSampling')
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; src=ROOT/row['texture'].removeprefix('res://')
            texture_name=CONFIG.get('texture_files',{}).get(label,f'{label}_diffuse.png')
            delivered=ROOT/CONFIG['asset']/texture_name
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
        edited_charts=uv_components([{**row,**target_surfaces[sid]} for sid,row in enumerate(part['surfaces'])])
        assert edited_charts == original_charts
        original_uv=[t for row in part['surfaces'] for t in row['uv']]
        uv_displacements=[(Vector(a)-Vector(b)).length for a,b in zip(uv,original_uv)]
        changed_uv=sum(distance > .000001 for distance in uv_displacements)
        assert len(uv) <= len(original_uv)*(1.20 if name==HEAD else 1) and changed_uv/len(original_uv) <= .20
        old=[Vector(p) for row in part['surfaces'] for p in row['positions']]
        new=[C.inverted()@p for p in points]
        bounds=lambda ps:{'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)]}
        before=bounds(old); after=bounds(new)
        ratios=[abs((after['max'][i]-after['min'][i])/(before['max'][i]-before['min'][i])-1) for i in range(3)]
        max_delta=max(deltas)
        normalizer=min(before['max'][i]-before['min'][i] for i in range(3))
        assert max(ratios)<=.20 and max_delta/normalizer<=.20
        geometry['parts'][name]={'bounds_game':after,'original_bounds':before,'dimension_delta_fraction':ratios,'max_rest_displacement':max_delta,'max_displacement_fraction_of_smallest_dimension':max_delta/normalizer,'triangles':len(faces),'uv_preserved':changed_uv==0, 'original_uv_charts':original_charts,'uv_charts':edited_charts,'uv_coordinate_count':len(uv), 'original_uv_coordinate_count':len(original_uv), 'uv_changed_count':changed_uv, 'uv_changed_fraction':changed_uv/len(original_uv), 'uv_max_displacement_from_original':max(uv_displacements), 'uv_rms_displacement_from_original':math.sqrt(sum(distance*distance for distance in uv_displacements)/len(uv_displacements)), 'uv_by_surface':uv_by_surface,'weight_source':'original, unchanged'}
        if contract:
            quality=contract.part_shape_quality(part['surfaces'],target_surfaces)
            geometry['parts'][name]['shape_quality']=quality
            geometry['parts'][name]['added_vertex_count']=0
            geometry['parts'][name]['triangle_growth_fraction']=0
            geometry['parts'][name]['geometry_changed']=any(row['geometry_changed'] for row in target_surfaces)
            assert quality['reversed_triangles']==quality['new_degenerate_triangles']==0 and quality['coincident_seam_max_rest_gap']<=1e-6
        elif name == HEAD:
            row=part['surfaces'][0]; candidate=target_surfaces[0]['positions']
            reversed_triangles=0;zero_area=0;cosines=[];groups={}
            for index,point in enumerate(row['positions']):groups.setdefault(tuple(point),[]).append(index)
            head_target=target_surfaces[0]
            refined_indices=head_target.get('indices',row['indices'])
            parent_triangles=head_target.get('triangle_parents',list(range(len(row['indices'])//3)))
            for offset in range(0,len(refined_indices),3):
                ids=refined_indices[offset:offset+3]
                parent=parent_triangles[offset//3]
                old_ids=row['indices'][parent*3:parent*3+3]
                old_points=[Vector(row['positions'][i]) for i in old_ids]
                new_points=[Vector(candidate[i]) for i in ids]
                a=(old_points[1]-old_points[0]).cross(old_points[2]-old_points[0])
                b=(new_points[1]-new_points[0]).cross(new_points[2]-new_points[0])
                if b.length<=1e-10:zero_area+=1
                if a.length>1e-10 and b.length>1e-10:
                    cosine=a.normalized().dot(b.normalized());cosines.append(cosine)
                    if cosine<0:reversed_triangles+=1
            for index in range(len(row['positions']),len(candidate)):
                groups.setdefault(tuple(head_target['baseline_positions'][index]),[]).append(index)
            seam=max((Vector(candidate[a])-Vector(candidate[b])).length for group in groups.values() for a in group for b in group)
            geometry['parts'][name]['shape_quality']={'reversed_triangles':reversed_triangles,'zero_area_triangles':zero_area,'coincident_seam_max_rest_gap':seam,'min_triangle_normal_cosine_from_original':min(cosines)}
            geometry['parts'][name]['added_vertex_count']=len(candidate)-len(row['positions'])
            geometry['parts'][name]['triangle_growth_fraction']=len(faces)/(len(row['indices'])/3)-1
            geometry['parts'][name]['weight_source']='Original vertices unchanged; arc midpoint vertices inherit identical parent binds and weights'
            assert reversed_triangles==0 and zero_area==0 and seam==0
        # Exact continuous UV chart wire guides; technical edges are never paint edges.
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; paths=[]
            authored_indices=target_surfaces[sid].get('indices',row['indices'])
            for j in range(0,len(authored_indices),3):
                coords=[target_surfaces[sid]['uv'][idx] for idx in authored_indices[j:j+3]]
                paths.append('<polygon points="'+' '.join(f'{u*1024:.3f},{v*1024:.3f}' for u,v in coords)+'" fill="none" stroke="#9ad9e8" stroke-width="1"/>')
            # Preserve the immutable original guides used by image generation.
            guide_name=f'{label}_authored_uv'
            guide_polygons.setdefault(guide_name,[]).extend(paths)
    for guide_name,paths in guide_polygons.items():
        (WORK/'guides'/f'{guide_name}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'+''.join(paths)+'</svg>')
    if contract:
        geometry['geometry_mode']=target['geometry_mode'];geometry['geometry_parts']=target['geometry_parts']
        if BOUNDED:geometry['stage']=CONFIG.get('active_geometry_revision','approved_draft_refinement_v2')
        geometry['constraint']='True original source cumulative20% per-part rest displacement/dimensions; exact original UV0, indices, vertex counts, rig and weights.'
        contract.measure_original_geometry(SOURCE,target,geometry,{name:.20 for name in SOURCE['parts']},CONFIG)
    (WORK/'build/target.json').write_text(json.dumps(target,indent=2))
    (WORK/'build/geometry.json').write_text(json.dumps(geometry,indent=2))
    scene.view_settings.view_transform='Standard'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'build/{slug}_master.blend'))
    print(CONFIG['name'].upper()+'_BUILD_PASS original-total20% / original topology and Skin; triangles='+str(sum(p['triangles'] for p in geometry['parts'].values())))

if __name__=='__main__':main()
