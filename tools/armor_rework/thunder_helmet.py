"""Thunder v4: paired SW2 head topology, fitted crown and machined respirator.

Y up, facing -Z. Rear/ear/visor/cheek topology and UVs use the paired source.
"""
import json
import math
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from thunder_visor import expand_visor


def _subdivide_source(source):
    """Linear refinement before bending the visor, preserving UV/hard seams.

    Midpoints stay exactly on the source triangles. Additional samples let
    the enlarged lower arc bend smoothly without serrating its engraved UVs.
    """
    result = dict(source)
    for name in ['positions_game', 'normals_game', 'uv']:
        result[name] = [list(v) for v in source[name]]
    edges = {}

    def midpoint(a, b):
        key = tuple(sorted((a,b)))
        if key not in edges:
            edges[key] = len(result['positions_game'])
            for name in ['positions_game','normals_game','uv']:
                value = (Vector(result[name][a])+Vector(result[name][b]))*.5
                result[name].append(list(value.normalized() if name=='normals_game' else value))
        return edges[key]

    result['submeshes'] = []
    for submesh in source['submeshes']:
        faces = []
        for a,b,c in submesh:
            ab,bc,ca = midpoint(a,b),midpoint(b,c),midpoint(c,a)
            faces.extend([(a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)])
        result['submeshes'].append(faces)
    return result


def _part(owner, name, vertices, faces, slots, materials):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for material in materials:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world = owner.matrix_world.copy()
    obj.vertex_groups.new(name='Bip01 Head').add(list(range(len(vertices))), 1, 'REPLACE')
    uv = mesh.uv_layers.new(name='UVMap')
    for poly, slot in zip(mesh.polygons, slots):
        poly.material_index = slot
        axis = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop_index in poly.loop_indices:
            p = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (p[axes[0]]*3+.5, p[axes[1]]*3+.5)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    return obj


def _octagon(width, bottom, top, bevel, z):
    return [(-width+bevel,bottom,z),(width-bevel,bottom,z),
            (width,bottom+bevel,z),(width,top-bevel,z),
            (width-bevel,top,z),(-width+bevel,top,z),
            (-width,top-bevel,z),(-width,bottom+bevel,z)]


def _ring_piece(owner, name, loops, band_slots, materials):
    count = len(loops[0])
    verts = [p for ring in loops for p in ring]
    faces, slots = [], []
    # Depth loops form actual bevels and recessed intake, sealed by a floor.
    for ring, slot in enumerate(band_slots):
        for i in range(count):
            j = (i+1)%count
            faces.append((ring*count+i,ring*count+j,(ring+1)*count+j,(ring+1)*count+i))
            slots.append(slot)
    faces.append(tuple(range((len(loops)-1)*count,len(loops)*count)))
    slots.append(10)
    faces.append(tuple(reversed(range(count))))
    slots.append(6)
    return _part(owner,name,verts,faces,slots,materials)


def _block(owner, name, outline, front_z, back_z, material, materials):
    verts = [(x,y,front_z) for x,y in outline]+[(x,y,back_z) for x,y in outline]
    n = len(outline)
    faces = [tuple(range(n)),tuple(reversed(range(n,2*n)))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return _part(owner,name,verts,faces,[material]*len(faces),materials)


def _neck_bridge(owner, materials):
    # The SW2 helmet's sealed underside previously floated above the SW1
    # torso. A fitted dark socket overlaps both pieces throughout head poses.
    profile = [(1.18,.105),(1.23,.116),(1.27,.122),(1.31,.125),(1.40,.125),(1.49,.120)]
    rings = []
    # Fine moulded ribs have actual sloping walls, avoiding a featureless
    # black tube in the low camera. They sit inside the original hard nape.
    for i in range(46):
        y = 1.18 + .31*i/45
        a,b = next((a,b) for a,b in zip(profile,profile[1:]) if a[0]-1e-6<=y<=b[0]+1e-6)
        t = (y-a[0])/(b[0]-a[0])
        radius = a[1]+(b[1]-a[1])*t
        rings.append((y,radius+(.0015 if i%2 else 0)))
    count = 24
    vertices = [(radius*math.sin(i*math.tau/count),y,
                 .022+radius*.92*math.cos(i*math.tau/count))
                for y,radius in rings for i in range(count)]
    faces = []
    for ring in range(len(rings)-1):
        for i in range(count):
            j = (i+1)%count
            faces.append((ring*count+i,ring*count+j,(ring+1)*count+j,(ring+1)*count+i))
    faces += [tuple(reversed(range(count))),tuple(range((len(rings)-1)*count,len(rings)*count))]
    return _part(owner,'Fitted neck socket',vertices,faces,[10]*len(faces),materials)


def refine_helmet(obj, material_slots):
    source = json.loads((ROOT/'assets/armors/thunder/source_sw2/modern_head.json').read_text())
    original_triangle_count = sum(len(submesh) for submesh in source['submeshes'])
    source = _subdivide_source(source)
    vertices = [Vector(v) for v in source['positions_game']]
    normals = [Vector(n).normalized() for n in source['normals_game']]
    # Lower the tall original rear crest while keeping its original vent UVs.
    deformed = expand_visor(vertices,source)
    for index, vertex in enumerate(vertices):
        if vertex.y > 1.865:
            vertex.y = 1.865+(vertex.y-1.865)*.28
            deformed.add(index)
        # Fold the source nose latch inside the new housing. Move every UV
        # duplicate at the same coordinate together, preserving sealed faces.
        if abs(vertex.x)<.05 and 1.395<vertex.y<1.44 and vertex.z<-.15:
            vertex.y = 1.395+(vertex.y-1.395)*.18
            deformed.add(index)
    faces = []
    for submesh in source['submeshes']:
        for face in submesh:
            a,b,c = (Vector(source['positions_game'][i]) for i in face)
            expected = sum((normals[i] for i in face),Vector())
            faces.append(face if (b-a).cross(c-a).dot(expected)>=0 else list(reversed(face)))
    mesh = bpy.data.meshes.new('Thunder_SW2_fitted_head')
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    for material in material_slots:
        mesh.materials.append(material)
    uv = mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:
        uv.data[loop.index].uv = source['uv'][loop.vertex_index][:2]
    for poly in mesh.polygons:
        poly.material_index = 11
        poly.use_smooth = True
    # Preserve source split normals outside deformed crown. Average the crown
    # by position rather than UV vertex to avoid a visible center UV seam.
    crown_normals = {}
    for poly in mesh.polygons:
        for index in poly.vertices:
            if index in deformed:
                key = tuple(round(c,6) for c in vertices[index])
                crown_normals[key] = crown_normals.get(key,Vector())+poly.normal*poly.area
    for index,vertex in enumerate(vertices):
        if index in deformed:
            normals[index] = crown_normals[tuple(round(c,6) for c in vertex)].normalized()
    mesh.normals_split_custom_set_from_vertices(normals)
    obj.data = mesh
    obj.vertex_groups.clear()
    obj.vertex_groups.new(name='Bip01 Head').add(list(range(len(vertices))),1,'REPLACE')
    pieces = [_neck_bridge(obj,material_slots)]
    pieces.append(_ring_piece(obj,'Six-plane respirator housing',[
        _octagon(.054,1.301,1.414,.014,-.244),
        _octagon(.060,1.304,1.414,.015,-.279),
        _octagon(.046,1.319,1.405,.010,-.323),
        _octagon(.033,1.338,1.391,.006,-.332),
        _octagon(.027,1.345,1.386,.004,-.326),
        _octagon(.025,1.347,1.384,.003,-.311),
    ],[6,12,12,13,10],material_slots))
    for index,y in enumerate([1.353,1.363,1.373]):
        pieces.append(_block(obj,f'Recessed intake louvre {index+1}',
            [(-.023,y),(.023,y),(.023,y+.003),(-.023,y+.003)],-.320,-.314,13,material_slots))
    pieces.append(_block(obj,'Intake center latch',
        [(-.007,1.375),(.007,1.375),(.007,1.395),(-.007,1.395)],-.332,-.321,10,material_slots))
    pieces.append(_ring_piece(obj,'Respirator lower heel',[
        _octagon(.044,1.294,1.328,.009,-.264),
        _octagon(.041,1.296,1.324,.008,-.314),
        _octagon(.033,1.301,1.318,.005,-.327),
    ],[12,13],material_slots))
    for sign in [-1,1]:
        points = [(sign*x,y,z) for x,y,z in [
            (.039,1.323,-.281),(.071,1.332,-.272),(.086,1.365,-.247),
            (.070,1.383,-.256),(.052,1.372,-.288),
            (.045,1.326,-.302),(.068,1.337,-.292),(.078,1.362,-.272),
            (.067,1.374,-.281),(.052,1.365,-.309)]]
        side_faces = [(0,1,2,3,4),(9,8,7,6,5)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
        pieces.append(_part(obj,f'Cheek respirator bevel {sign}',points,side_faces,[6,5,7,5,7,6,5],material_slots))
    # User feedback: hug the jaw rather than projecting as a second box.
    # Keep the mount plane, compress all housing/louvre/wing depths together
    # so the recessed intake retains its thickness and sealed back.
    for piece in pieces[1:]:
        for vertex in piece.data.vertices:
            vertex.co.z = -.241+(vertex.co.z+.241)*.44
        piece.data.update()
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    obj['thunder_raised_plates'] = len(pieces)+6
    obj['thunder_original_head_triangles'] = original_triangle_count
    obj['thunder_detail'] = 'Paired SW2 helmet, engraved visor normal map, low crown, recessed six-plane respirator'
