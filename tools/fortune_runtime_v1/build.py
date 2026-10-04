"""Shape Fortune locally; preserve its original rig and adjust only the front-chin UV.

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
WORK = ROOT / 'docs/art/fortune_runtime_v1'
SOURCE = json.loads((WORK/'build/source.json').read_text())
C = Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
LABELS = {'ArmorHead_01':['head'], 'ArmorBody_01':['body','shoulder'],
          'ArmorHand_01':['hand'], 'ArmorFoot_01':['foot']}


def reshape(name, point):
    p = Vector(point)
    if name != 'ArmorHead_01':
        return p
    x, y, z = p
    # The approved crown is rounded. A large reduction of its centre apex made
    # the first runtime revision look flat, so retain its original arc while
    # lowering only the small centre ridge and smoothing the front forehead.
    if y > 1.82 and abs(x) < .12:
        amount = min(1.0, max(0.0, (y - 1.82) / .094))
        p.y -= .014 * amount
    if z < -.24 and 1.74 < y < 1.82:
        p.y -= .018 if abs(x) < .08 else .005
        p.z -= .003
    # Flatten both original V-shaped eyebrow rings into one horizontal, thin
    # lip. Shared source positions take the same edit on both UV seam copies.
    if z < -.30 and 1.63 < y < 1.70:
        p.y = 1.643
        p.z = -.333 if abs(x) < .08 else -.308
    elif z < -.30 and 1.56 < y <= 1.63:
        p.y = 1.615
        p.z = -.337 if abs(x) < .08 else -.307
    if z < -.24 and 1.59 < y < 1.61 and (z > -.30 or (abs(x) < .08 and z > -.31)):
        p.y = 1.606
        p.z = z - .012
    # The purple visor has broad planar facets instead of an old nose button.
    if abs(x) < .08 and 1.45 < y < 1.54 and z < -.30:
        p.z = -.320
    # Make the green lower mask genuinely short rather than painting a shorter
    # chin on the old long jaw. The rear neck/rig vertices remain untouched.
    if y < 1.40 and z < -.185:
        amount = min(1.0, max(0.0, (1.40 - y) / .115))
        p.y = 1.353 + (y - 1.285) * .44
        p.z += .015 + .010 * amount
        p.x *= 1.0 - .08 * amount
    if .13 < abs(x) and 1.41 < y < 1.62 and z < -.10:
        p.x *= .96
    # Helmet refinement v8 is a new local shape pass, always evaluated from
    # ORIGINAL positions. It is not a further 15% allowance on the v7 mesh.
    # Reduce the sparse crown cage's tall centre crest; lower its two existing
    # side upper-ring points into the same rounded arc, without adding
    # geometry or moving a UV coordinate.
    if abs(x) < .08 and y > 1.88 and z > -.10:
        p.y = 1.886
    elif abs(x) < .08 and y > 1.86 and z < -.10:
        p.y = 1.861
    elif abs(x) < .08 and 1.81 < y < 1.84 and z > .10:
        p.y = 1.815
    elif .15 < abs(x) < .19 and y > 1.82:
        # Final compromise: 14mm below the previous upper ring, not the
        # rejected 28mm trial which made the sparse front cage too pointed.
        p.y = y - .007
    if z < -.24 and 1.74 < y < 1.82:
        p.y = y - (.025 if abs(x) < .08 else .014)
    # Keep a short, nearly level brow instead of the old two deep V rings.
    if z < -.30 and 1.63 < y < 1.70:
        p.z = -.325 if abs(x) < .08 else -.304
    elif z < -.30 and 1.56 < y <= 1.63:
        p.y = 1.626
        p.z = -.323 if abs(x) < .08 else -.303
    if z < -.24 and 1.59 < y < 1.61 and (z > -.30 or (abs(x) < .08 and z > -.31)):
        # The inner brow duplicates share an original triangle with the outer
        # ring. Keep them distinct; flattening both to 1.626 collapses that face.
        p.y = 1.617
        p.z = z - .007
    if abs(x) < .08 and 1.45 < y < 1.54 and z < -.30:
        p.z = -.308
    # Lift the existing three lower-visor points into a short level lip; the
    # purple atlas will carry a dark continuous visor, rather than a blue nose.
    if z < -.29 and 1.41 < y < 1.43 and abs(x) < .06:
        p.y = 1.426
        p.z = -.303
    # Recess the jutting lower mask. The most shortened lower vertices already
    # use much of their original displacement budget, so cap their combined
    # x/y/z change to 74.8mm (below the original 76.1386mm 15% limit).
    if z < -.185 and y < 1.41:
        p.z += .018
        delta = p - Vector(point)
        if delta.length > .0748:
            p = Vector(point) + delta.normalized() * .0748
    return p


def adjusted_uv(name, point, uv, surface_id=0):
    # The generated solid green short chin lies beside the old blue slot.
    # Retarget only its 22 original coordinates, without adding charts,
    # changing coordinate count, or altering the rest of the source atlas.
    if name == 'ArmorHead_01' and uv[0] < .10 and .55 < uv[1] < .76:
        return [uv[0] + .085, uv[1]]
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


def head_shape_quality(part, target_surfaces):
    """Check that shaping never opens source seams or reverses a triangle."""
    reversed_triangles = 0
    zero_area_triangles = 0
    coincident_groups = {}
    for source, target in zip(part['surfaces'], target_surfaces):
        for before, after in zip(source['positions'], target['positions']):
            key = tuple(round(value, 6) for value in before)
            coincident_groups.setdefault(key, []).append(Vector(after))
        for offset in range(0, len(source['indices']), 3):
            ids = source['indices'][offset:offset+3]
            a, b, c = [Vector(source['positions'][i]) for i in ids]
            x, y, z = [Vector(target['positions'][i]) for i in ids]
            original_normal = (b-a).cross(c-a)
            authored_normal = (y-x).cross(z-x)
            reversed_triangles += int(original_normal.dot(authored_normal) < 0)
            zero_area_triangles += int(authored_normal.length_squared < 1e-14)
    gap = max((points[0]-point).length for points in coincident_groups.values() for point in points)
    assert reversed_triangles == 0 and zero_area_triangles == 0
    assert gap < .000002, 'Shaping opened an original coincident head seam'
    return {'reversed_triangles': reversed_triangles, 'zero_area_triangles': zero_area_triangles,
            'coincident_seam_max_rest_gap': gap,
            'note': 'Original coincident positions and triangle orientation compared in Godot rest space.'}


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
    arm=bpy.data.armatures.new('Original28Bones'); rig=bpy.data.objects.new('FortuneRig',arm)
    rigcol.objects.link(rig); bpy.context.view_layer.objects.active=rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for row in SOURCE['bones']:
        bone=arm.edit_bones.new(row['name']); m=C@Matrix(row['matrix'])
        bone.head=m.translation; bone.tail=bone.head+(m.to_3x3()@Vector((0,.06,0)))
        if row['parent']>=0:bone.parent=arm.edit_bones[SOURCE['bones'][row['parent']]['name']]
    bpy.ops.object.mode_set(mode='OBJECT'); rig.select_set(False)
    target={'revision':'fortune_runtime_v1','id':1,'parts':{}}
    geometry={'parts':{}, 'constraint':'Local shape/dimension changes <=15%; changed UV coordinates <=15% per material surface, front chin only; original chart/coordinate count and skin retained. Absolute UV displacement is recorded separately.'}
    for name,part in SOURCE['parts'].items():
        points=[]; uv=[]; weights=[]; bone_names=[]; faces=[]; mids=[]; offsets=[]; target_surfaces=[]
        deltas=[]
        for sid,row in enumerate(part['surfaces']):
            offset=len(points); offsets.append(offset)
            authored=[reshape(name,p) for p in row['positions']]
            authored_uv=[adjusted_uv(name,p,t,sid) for p,t in zip(authored,row['uv'])]
            surface_uv_distances=[(Vector(a)-Vector(b)).length for a,b in zip(authored_uv,row['uv'])]
            assert sum(distance>.000001 for distance in surface_uv_distances)/len(row['uv']) <= .15, f"{name}/{sid}: per-material UV budget exceeded"
            assert uv_components([row]) == uv_components([{**row,'uv':authored_uv}]), f"{name}/{sid}: original chart count changed"
            points.extend(C@p for p in authored); uv.extend(authored_uv)
            weights.extend(row['weights']); bone_names.extend(row['bone_names'])
            # Engine winding differs under the handedness conversion C.
            for i in range(0,len(row['indices']),3):
                faces.append(tuple(offset+j for j in reversed(row['indices'][i:i+3]))); mids.append(sid)
            target_surfaces.append({'positions':[list(p) for p in authored], 'uv':authored_uv, 'label':LABELS[name][sid]})
            deltas.extend((p-Vector(old)).length for p,old in zip(authored,row['positions']))
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(points,[],faces); mesh.update()
        ob=bpy.data.objects.new(name,mesh); low.objects.link(ob)
        layer=mesh.uv_layers.new(name='SourceUV_Preserved')
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; src=ROOT/row['texture'].removeprefix('res://')
            delivered=ROOT/f'assets/armors/fortune_v1/{label}_diffuse.png'
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
        geometry['parts'][name]={'bounds_game':after,'original_bounds':before,'dimension_delta_fraction':ratios,'max_rest_displacement':max_delta,'max_displacement_fraction_of_smallest_dimension':max_delta/normalizer,'triangles':len(faces),'uv_preserved':changed_uv==0, 'original_uv_charts':original_charts,'uv_charts':edited_charts,'uv_coordinate_count':len(uv), 'original_uv_coordinate_count':len(original_uv), 'uv_changed_count':changed_uv, 'uv_changed_fraction':changed_uv/len(original_uv), 'uv_by_surface':[{'label':LABELS[name][sid],'uv_coordinate_count':len(row['uv']),'uv_changed_count':sum((Vector(a)-Vector(b)).length>.000001 for a,b in zip(target_surfaces[sid]['uv'],row['uv'])),'uv_charts':uv_components([row])} for sid,row in enumerate(part['surfaces'])], 'uv_max_displacement_from_original':max(uv_displacements), 'uv_rms_displacement_from_original':math.sqrt(sum(distance*distance for distance in uv_displacements)/len(uv_displacements)), 'weight_source':'original, unchanged'}
        if name == 'ArmorHead_01':
            geometry['parts'][name]['shape_quality'] = head_shape_quality(part, target_surfaces)
        # Exact continuous UV chart wire guides; technical edges are never paint edges.
        for sid,row in enumerate(part['surfaces']):
            label=LABELS[name][sid]; paths=[]
            for j in range(0,len(row['indices']),3):
                coords=[target_surfaces[sid]['uv'][idx] for idx in row['indices'][j:j+3]]
                paths.append('<polygon points="'+' '.join(f'{u*1024:.3f},{v*1024:.3f}' for u,v in coords)+'" fill="none" stroke="#9ad9e8" stroke-width="1"/>')
            guide_name='head_uv_authored' if label=='head' else f'{label}_uv'
            (WORK/'guides'/f'{guide_name}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#17222d"/>'+''.join(paths)+'</svg>')
    (WORK/'build/target.json').write_text(json.dumps(target,indent=2))
    (WORK/'build/geometry.json').write_text(json.dumps(geometry,indent=2))
    scene.view_settings.view_transform='Standard'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'build/fortune_master.blend'))
    print('FORTUNE_BUILD_PASS local edits within15%, triangles='+str(sum(p['triangles'] for p in geometry['parts'].values())))

if __name__=='__main__':main()
