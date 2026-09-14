"""Thunder B helmet: low crown spine, V visor, cheek rails and chin unit.

Coordinates are the recovered mesh's bind-pose XYZ (Y up, front -Z).
Keep the existing dome UVs/neck skin; new hard pieces follow Bip01 Head.
"""
import math
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform


def _piece(owner, name, vertices, faces, material, slots, bevel=0.002):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for slot in slots:
        mesh.materials.append(slot)
    for poly in mesh.polygons:
        poly.material_index = material
    group = obj.vertex_groups.new(name='Bip01 Head')
    group.add(list(range(len(mesh.vertices))), 1.0, 'REPLACE')
    mesh.uv_layers.new(name='UVMap')
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    if bevel:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Machined edge', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.affect = 'EDGES'
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(24)
        mod.material = material
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def _front_plate(owner, name, outline, depth, material, slots, bevel=.002):
    """Extrude an authored front outline toward the skull (+Z)."""
    vertices = list(outline) + [(x, y, z + depth) for x, y, z in outline]
    count = len(outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, count * 2)))]
    for index in range(count):
        nxt = (index + 1) % count
        faces.append((index, nxt, nxt + count, index + count))
    return _piece(owner, name, vertices, faces, material, slots, bevel)


def _fitted_crown(owner, slots):
    """Fit the new low rib to the skull surface, reusing its blue-painted UVs."""
    source = owner.data
    source.calc_loop_triangles()
    triangles = list(source.loop_triangles)
    coords = [v.co.copy() for v in source.vertices]
    bvh = BVHTree.FromPolygons(coords, [t.vertices[:] for t in triangles], all_triangles=True)
    center = Vector((0, 1.61, -.035))
    path = [(.16, 1.80, .068), (.10, 1.86, .080), (.02, 1.88, .086),
            (-.09, 1.88, .089), (-.19, 1.86, .082), (-.26, 1.79, .070),
            (-.32, 1.71, .056), (-.38, 1.64, .042), (-.39, 1.57, .031),
            (-.37, 1.48, .019)]
    vertices, uvs = [], []
    for z, y, width in path:
        for fraction in (-1, -.84, 0, .84, 1):
            direction = (Vector((width * fraction, y, z)) - center).normalized()
            hit, normal, index, distance = bvh.ray_cast(center + direction * 2, -direction, 4)
            if hit is None:
                raise ValueError('Crown projection missed source helmet')
            lift = .003 if abs(fraction) == 1 else .014
            vertices.append(hit + normal * lift)
            tri = triangles[index]
            uv_coords = [Vector((*source.uv_layers.active.data[loop].uv, 0)) for loop in tri.loops]
            uv = barycentric_transform(hit, *(coords[i] for i in tri.vertices), *uv_coords)
            uvs.append((uv.x, uv.y))
    faces = []
    for ring in range(len(path) - 1):
        for column in range(4):
            a = ring * 5 + column
            faces.append((a, a+1, a+6, a+5))
    piece = _piece(owner, 'Skull fitted broad crown', vertices, faces, 0, slots, 0)
    for poly in piece.data.polygons:
        # Recessed narrow rails expose physical dark sides, not a white outline.
        poly.material_index = 6 if poly.index % 4 in (0, 3) else 0
        for loop in poly.loop_indices:
            vertex = piece.data.loops[loop].vertex_index
            piece.data.uv_layers.active.data[loop].uv = uvs[vertex]
    return piece


def refine_helmet(obj, material_slots):
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    obj.data.materials.clear()
    for material in material_slots:
        obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    # Source's duplicated UV-seam vertices must move together.
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        if y > 1.95:
            vertex.co.y = 1.858
        if y < 1.35 and z < -.17:
            vertex.co.y += (1.35 - y) * .8
        # Turn the old pronounced circular ear boss into a compact inset housing.
        if abs(x) > .225 and 1.42 < y < 1.62 and -.10 < z < .07:
            vertex.co.x = math.copysign(.225 + (abs(x) - .225) * .32, x)
    # The atlas carries the actual face aperture lower than the forehead shell.
    # Keep its UV-defined edge; the head material selectively lights the amber.
    obj.data.update()
    # Weld coincident bind-pose vertices but retain each loop's UV seam.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=.000001)
    bm.to_mesh(obj.data)
    bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new('Helmet shell edge refinement', 'BEVEL')
    bevel.width = .0025
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(38)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    pieces = [obj]
    pieces.append(_fitted_crown(obj, material_slots))
    # Cheek rails border the visor, with separate dark beds and solid blue covers.
    for side in (-1, 1):
        def mirrored(points):
            return [(side * x, y, z) for x, y, z in points]
        rail = [(.199, 1.544, -.173), (.165, 1.454, -.265), (.110, 1.378, -.308),
                (.059, 1.343, -.350), (.044, 1.319, -.343), (.098, 1.331, -.313),
                (.168, 1.401, -.250), (.211, 1.506, -.152)]
        pieces.append(_front_plate(obj, f'Cheek rail {side}', mirrored(rail), .022, 5, material_slots))
        # Small angular ear cover; no large round neon headset discs.
        outline = [(side * .244, 1.580, -.075), (side * .250, 1.586, -.018),
                   (side * .248, 1.552, .021), (side * .244, 1.489, .009),
                   (side * .239, 1.466, -.045), (side * .238, 1.501, -.083)]
        ear_vertices = outline + [(x - side * .016, y, z) for x, y, z in outline]
        faces = [tuple(range(6)), tuple(reversed(range(6, 12)))]
        faces += [(i, (i + 1) % 6, (i + 1) % 6 + 6, i + 6) for i in range(6)]
        pieces.append(_piece(obj, f'Recessed ear housing {side}', ear_vertices, faces, 6, material_slots, .003))
    chin = [(-.041, 1.408, -.354), (.041, 1.408, -.354), (.057, 1.388, -.370),
            (.047, 1.328, -.366), (.029, 1.313, -.351), (-.029, 1.313, -.351),
            (-.047, 1.328, -.366), (-.057, 1.388, -.370)]
    pieces.append(_front_plate(obj, 'Faceted respirator housing', chin, .031, 6, material_slots, .004))
    vent = [(-.028, 1.389, -.374), (.028, 1.389, -.374), (.028, 1.359, -.374), (-.028, 1.359, -.374)]
    pieces.append(_front_plate(obj, 'Respirator inset', vent, .005, 10, material_slots, .001))
    slot = [(-.007, 1.385, -.377), (.007, 1.385, -.377), (.007, 1.369, -.378), (-.007, 1.369, -.378)]
    pieces.append(_front_plate(obj, 'Respirator center latch', slot, .005, 7, material_slots, .001))
    for height in (1.348, 1.337):
        line = [(-.025, height+.002, -.372), (.025, height+.002, -.372),
                (.025, height-.002, -.372), (-.025, height-.002, -.372)]
        pieces.append(_front_plate(obj, 'Lower vent', line, .004, 10, material_slots, 0))
    bpy.ops.object.select_all(action='DESELECT')
    for piece in pieces:
        piece.hide_set(False)
        piece.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    return obj
