"""Thunder prototype v5: rounded shell, narrow trapezoid and inward cheek plates.

All coordinates use the original Y-up, -Z-forward bind pose. The pointed source
shell is replaced, and every new helmet vertex follows the original Head bind.
"""
import math
import bpy
import bmesh
from mathutils import Vector


def _piece(owner, name, vertices, faces, material, slots, bevel=.002, smooth=False):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for slot in slots:
        mesh.materials.append(slot)
    for poly in mesh.polygons:
        poly.material_index = material
        poly.use_smooth = smooth
    obj.vertex_groups.new(name='Bip01 Head').add(list(range(len(vertices))), 1.0, 'REPLACE')
    mesh.uv_layers.new(name='UVMap')
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for edge in bm.edges:
        if edge.is_manifold and edge.calc_face_angle() > math.radians(45):
            edge.smooth = False
    bm.to_mesh(mesh)
    bm.free()
    if bevel:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Reference edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(28)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        axis = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop in poly.loop_indices:
            co = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            obj.data.uv_layers.active.data[loop].uv = (co[axes[0]] * 1.6 + .5, co[axes[1]] * 1.6)
    return obj


def _front_plate(owner, name, outline, depth, material, slots, bevel=.002):
    n = len(outline)
    verts = list(outline) + [(x, y, z + depth) for x, y, z in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2*n)))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    return _piece(owner, name, verts, faces, material, slots, bevel)


def _grid_shell(owner, name, rows, material, slots, depth=.009, smooth=True):
    """Closed curved plate, with an inward shell and connected boundary."""
    cyclic = all((Vector(row[0])-Vector(row[-1])).length < 1e-6 for row in rows)
    if cyclic:
        rows = [row[:-1] for row in rows]
    width = len(rows[0])
    verts = [Vector(v) for row in rows for v in row]
    n = len(verts)
    center = Vector((0, 1.57, -.025))
    verts += [v - (v-center).normalized()*depth for v in verts[:]]
    faces = []
    for r in range(len(rows)-1):
        for c in range(width if cyclic else width-1):
            a = r*width+c
            nxt = r*width+(c+1)%width
            face = (a, nxt, nxt+width, a+width)
            faces += [face, tuple(i+n for i in reversed(face))]
    if cyclic:
        boundaries = [list(range(width)),list(reversed(range(n-width,n)))]
    else:
        boundary = list(range(width))
        boundary += [r*width+width-1 for r in range(1,len(rows))]
        boundary += list(range(n-2,n-width-1,-1))
        boundary += [r*width for r in range(len(rows)-2,0,-1)]
        boundaries = [boundary]
    for boundary in boundaries:
        for i, a in enumerate(boundary):
            b = boundary[(i+1)%len(boundary)]
            faces.append((a, b, b+n, a+n))
    return _piece(owner,name,verts,faces,material,slots,0,smooth)


def _dome(theta, phi, lift=0):
    return Vector(((.266+lift)*math.sin(theta)*math.sin(phi),
                   1.588+(.326+lift)*math.cos(theta),
                   -.025-(.314+lift)*math.sin(theta)*math.cos(phi)))


def _line(owner, name, points, radius, material, slots):
    closed=(Vector(points[0])-Vector(points[-1])).length < 1e-6
    if closed:
        points=points[:-1]
    rows = []
    for i, p in enumerate(points):
        p = Vector(p)
        before=(i-1)%len(points) if closed else max(i-1,0)
        after=(i+1)%len(points) if closed else min(i+1,len(points)-1)
        tangent = (Vector(points[after]) - Vector(points[before])).normalized()
        normal = (p - Vector((0,1.57,-.025))).normalized()
        cross = tangent.cross(normal).normalized()
        rows.append([p+radius*(math.cos(a)*normal+math.sin(a)*cross) for a in [j*math.tau/6 for j in range(6)]])
    verts=[p for row in rows for p in row]
    faces=[]
    for row in range(len(rows) if closed else len(rows)-1):
        nxt=(row+1)%len(rows)
        for c in range(6):
            faces.append((row*6+c,row*6+(c+1)%6,nxt*6+(c+1)%6,nxt*6+c))
    if not closed:
        faces.extend([tuple(reversed(range(6))),tuple(range(len(verts)-6,len(verts)))])
    return _piece(owner,name,verts,faces,material,slots,0,True)


def _catmull(points, steps=6):
    out = []
    p = [Vector(points[0])] + [Vector(v) for v in points] + [Vector(points[-1])]
    for i in range(1,len(p)-2):
        a,b,c,d = p[i-1:i+3]
        for j in range(steps):
            t = j/steps
            out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    out.append(Vector(points[-1]))
    return out


def refine_helmet(obj, material_slots):
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    obj.data.clear_geometry()
    for uv_layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(uv_layer)
    obj.data.uv_layers.new(name='UVMap')
    obj.data.materials.clear()
    for mat in material_slots:
        obj.data.materials.append(mat)
    pieces = []
    rows = []
    for r in range(19):
        row = []
        for c in range(73):
            phi = c*math.tau/72
            end = math.radians(78+6*math.sin(phi)**2+34*max(0,-math.cos(phi)))
            row.append(_dome(.012 + (end-.012)*r/18,phi))
        rows.append(row)
    pieces.append(_grid_shell(obj,'Continuous rounded shell',rows,5,material_slots,.014))
    # Separate curved armor leaves make real stepped panel boundaries. The
    # shared paint swatch stays continuous without projecting old atlas motifs.
    panel_rows = [
        [(25,35,69),(35,28,78),(49,30,78),(57,33,67),(63,39,67),(68,45,67)],
        [(64,24,39),(70,24,75),(77,25,78),(81,31,77)],
        [(43,85,123),(54,83,136),(69,83,140),(83,87,143),(96,96,142)],
        [(31,143,167),(50,147,168),(73,149,169),(94,149,169),(109,151,168)],
    ]
    for side in (-1,1):
        for number, outline in enumerate(panel_rows):
            patch_rows=[]
            dense_outline=[]
            for first,last in zip(outline,outline[1:]):
                steps=math.ceil((last[0]-first[0])/3.0)
                for step in range(steps):
                    t=step/steps
                    dense_outline.append(tuple(a+(b-a)*t for a,b in zip(first,last)))
            dense_outline.append(outline[-1])
            for theta,left,right in dense_outline:
                patch_rows.append([_dome(math.radians(theta),side*math.radians(left+(right-left)*i/8),.006) for i in range(9)])
            patch=_grid_shell(obj,f'Curved crown armor leaf {side} {number}',patch_rows,5,material_slots,.009)
            pieces.append(patch)
            border=list(patch_rows[0])
            border += [row[-1] for row in patch_rows[1:]]
            border += list(reversed(patch_rows[-1][:-1]))
            border += [row[0] for row in reversed(patch_rows[1:-1])]
            border.append(border[0])
            pieces.append(_line(obj,f'Machined crown leaf edge {side} {number}',border,.0009,7,material_slots))
    rows = []
    for r in range(7):
        row=[]
        for c in range(49):
            phi = math.radians(72+216*c/48)
            t=r/6
            upper=1.62-.10*(1-math.cos(phi))/2
            lower=1.32+.045*abs(math.sin(phi))
            row.append((.259*(1-.16*t)*math.sin(phi),upper*(1-t)+lower*t,-.025-(.307-.05*t)*math.cos(phi)))
        rows.append(row)
    pieces.append(_grid_shell(obj,'Wraparound cheek and nape shell',rows,6,material_slots,.018))
    # Closed inner jaw under the visible V rails. The previous open front-only
    # rail left a view through to the background from either side.
    liner=[]
    for r in range(5):
        row=[]
        t=r/4
        for c in range(73):
            phi=c*math.tau/72
            front_angle=min(phi,math.tau-phi)
            front_x=abs(.257*math.sin(phi))
            upper=1.362+.283*min(1,max(0,(front_x-.043)/.162)) if front_angle<math.radians(95) else 1.48
            lower=1.31+.070*abs(math.sin(phi))
            depth=.335 if math.cos(phi)>=0 else .267
            row.append(((.242-.020*t)*math.sin(phi),upper*(1-t)+lower*t,-.025-(depth-.049*t)*math.cos(phi)))
        liner.append(row)
    pieces.append(_grid_shell(obj,'Closed fitted inner jaw liner',liner,6,material_slots,.027))

    # Sample the actual ellipsoid cross section. The underside intersects the
    # shell by a small amount, leaving a closed seam instead of a floating arch.
    rows=[]
    for step in range(49):
        angle=math.radians(-125+223*step/48)
        a=math.degrees(angle)
        w=.090 if a<70 else .090-(a-70)/28*.038
        row=[]
        for u in [-1,-.91,-.80,-.4,0,.4,.80,.91,1]:
            x=u*w
            radial=math.sqrt(1-(x/.266)**2)
            lift=.016-.007*abs(u)**4
            front_lift=max(0,min(1,(a-50)/35))*.031
            y=1.588+(.326*radial+lift)*math.cos(angle)
            z=-.025-(.314*radial+lift+front_lift)*math.sin(angle)
            if step==48:
                y-=.030*(1-abs(u))
            row.append((x,y,z))
        rows.append(row)
    spine=_grid_shell(obj,'Continuous broad crown spine',rows,5,material_slots,.045)
    pieces.append(spine)
    for side in (-1,1):
        edge=[row[0 if side<0 else -1] for row in rows]
        pieces.append(_line(obj,f'Spine shadow channel {side}',edge,.0035,6,material_slots))
        inner_edge=[(row[2 if side<0 else -3][0],row[2 if side<0 else -3][1]+.001,row[2 if side<0 else -3][2]-.001) for row in rows[9:-4]]
        pieces.append(_line(obj,f'Spine narrow parallel channel {side}',inner_edge,.0012,6,material_slots))
        points=[_dome(math.radians(t),side*math.radians(p),.001) for t,p in
                [(23,57),(35,57),(47,57),(58,57),(64,53),(69,53),(70,66),(77,66)]]
        pieces.append(_line(obj,f'Cap engraved channel {side}',_catmull(points,4),.0018,6,material_slots))
        points=[_dome(math.radians(t),side*math.radians(p),.002) for t,p in
                [(55,105),(65,105),(68,98),(74,98),(78,115),(88,115)]]
        pieces.append(_line(obj,f'Side shell panel seam {side}',_catmull(points,3),.0016,6,material_slots))
        rowset=[]
        for t in [29,31,42,44]:
            rowset.append([_dome(math.radians(t),side*math.radians(p),.010) for p in [50,54,61,65]])
        pieces.append(_grid_shell(obj,f'Crown amber inset {side}',rowset,8,material_slots,.008))
        outline=[(side*.279,1.600,-.081),(side*.282,1.611,-.015),(side*.281,1.582,.033),
                 (side*.275,1.49,.023),(side*.266,1.468,-.043),(side*.272,1.504,-.090)]
        n=len(outline)
        verts=outline+[(x-side*.024,y,z) for x,y,z in outline]
        faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        pieces.append(_piece(obj,f'Angular ear cartridge {side}',verts,faces,6,material_slots,.004))
        inset=[(side*.285,1.586,-.063),(side*.287,1.590,-.011),(side*.283,1.514,-.005),(side*.281,1.498,-.038)]
        verts=inset+[(x-side*.007,y,z) for x,y,z in inset]
        faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        pieces.append(_piece(obj,f'Ear recessed inset {side}',verts,faces,10,material_slots,.002))

    collar=[]
    for y in [1.285,1.345]:
        collar.append([(.166*math.sin(i*math.tau/32),y,-.004-.156*math.cos(i*math.tau/32)) for i in range(33)])
    pieces.append(_grid_shell(obj,'Dark neck collar',collar,10,material_slots,.015))
    from thunder_face import create_face
    from thunder_helmet import create_respirator, _neck_bridge
    pieces += create_face(obj,material_slots)
    pieces += create_respirator(obj,material_slots,front_offset=-.097)
    pieces.append(_neck_bridge(obj,material_slots))
    # Seal the visible underside from the jaw/nape to the neck socket, so a
    # low camera sees a fitted gasket rather than the hollow shell interior.
    gasket=[]
    for ring in range(4):
        t=ring/3
        row=[]
        for c in range(49):
            phi=c*math.tau/48
            outer=Vector((.228*math.sin(phi),1.309+.07*abs(math.sin(phi)),
                          -.025-(.286 if math.cos(phi)>=0 else .258)*math.cos(phi)))
            inner=Vector((.119*math.sin(phi),1.335,.022-.113*math.cos(phi)))
            row.append(tuple(outer.lerp(inner,t)))
        gasket.append(row)
    pieces.append(_grid_shell(obj,'Sealed underside neck gasket',gasket,10,material_slots,.012))
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.select_set(True)
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.join()
    obj['thunder_raised_plates'] = len(pieces)
    assert len(obj.data.uv_layers) > 0, 'Joined helmet must retain its painted surface UVs'
    obj.data.uv_layers.active_index = 0
    return obj
