"""Raise the approved Thunder B body plates from the recovered skinned surfaces.

Called by the Thunder build, inside Blender. The source surface, per-loop UVs
and skin weights stay in place; new plate caps reuse those UVs and weights.
Only the narrow sidewalls use a dark hard-surface material; chamfers continue
the original paint color instead of drawing bright borders over its markings.
Coordinates are the source mesh's local Y-up / front-minus-Z bind pose.
"""

from collections import Counter

import bmesh
from mathutils import Vector


MATERIAL_COUNT = 11
DARK_NAVY = 6


def _position_key(position, points):
    """Join copied UV seams by distance, never weld the original mesh.

    Rounding coordinates alone splits values lying across a rounding boundary,
    even when they are less than a micrometre apart. Such splits would turn
    internal source triangle edges into unwanted plate boundaries.
    """
    for key, existing in points.items():
        if (existing - position).length_squared < 0.00001 ** 2:
            return key
    return len(points)


def _raise_plate(bm, selected, height, inset, uv_layer, deform_layer):
    """Copy a connected source patch with a solid-looking rim and a planar cap.

    The weights of every new vertex are copied from its corresponding source
    vertex, including seam duplicates. This keeps the cap attached during the
    original animations instead of binding the whole armor to one bone.
    """
    if not selected:
        return 0

    points = {}
    normals = {}
    weights = {}
    boundaries = Counter()
    oriented_edges = {}
    faces = []
    for face in selected:
        keys = []
        for loop in face.loops:
            key = _position_key(loop.vert.co, points)
            keys.append(key)
            if key not in points:
                points[key] = loop.vert.co.copy()
                normals[key] = Vector()
                positive = sorted(
                    ((group, weight) for group, weight in loop.vert[deform_layer].items()
                     if weight > 0.0), key=lambda pair: pair[1], reverse=True,
                )[:4]
                total = sum(weight for _, weight in positive)
                if total <= 0.0:
                    raise ValueError("Thunder source plate has an unweighted vertex")
                weights[key] = {group: weight / total for group, weight in positive}
            normals[key] += face.normal * face.calc_area()
        faces.append((keys, [loop[uv_layer].uv.copy() for loop in face.loops], face.material_index))
        face_uvs = [loop[uv_layer].uv.copy() for loop in face.loops]
        for index, (a, b) in enumerate(zip(keys, keys[1:] + keys[:1])):
            edge = tuple(sorted((a, b)))
            boundaries[edge] += 1
            oriented_edges[edge] = (a, b, face.material_index,
                                    face_uvs[index], face_uvs[(index + 1) % len(keys)])

    if any(count > 2 for count in boundaries.values()):
        raise ValueError("Thunder source plate patch is non-manifold")
    centroid = sum(points.values(), Vector()) / len(points)
    rings = [dict(), dict(), dict()]
    for key, point in points.items():
        normal = normals[key].normalized()
        # Move the cap in the tangent plane, so its exposed border reads as a
        # bevel rather than leaving an entire detached/levitating surface.
        to_center = centroid - point
        tangent_inset = (to_center - normal * to_center.dot(normal)) * inset
        positions = (
            point + normal * 0.0005,
            point + normal * (height * 0.55),
            point + normal * height + tangent_inset,
        )
        for ring, position in zip(rings, positions):
            vertex = bm.verts.new(position)
            for group, weight in weights[key].items():
                vertex[deform_layer][group] = weight
            ring[key] = vertex

    base, lip, cap = rings
    for keys, uvs, material_index in faces:
        face = bm.faces.new([cap[key] for key in keys])
        face.material_index = material_index
        face.smooth = False
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv

    for edge, count in boundaries.items():
        if count != 1:
            continue
        a, b, paint_material, uv_a, uv_b = oriented_edges[edge]
        # The chamfer carries the same edge texels as the cap. A uniform bright
        # metal material here falsely reads as extra outlines/triangulation.
        for lower, upper, material in ((base, lip, DARK_NAVY), (lip, cap, paint_material)):
            wall = bm.faces.new((lower[a], lower[b], upper[b], upper[a]))
            wall.material_index = material
            wall.smooth = False
            for loop, uv in zip(wall.loops, (uv_a, uv_b, uv_b, uv_a)):
                loop[uv_layer].uv = uv
    return 1


def refine_body(obj, material_slots):
    """Return ``obj`` with original materials remapped and raised Thunder plates.

    ``material_slots`` is the common ordered list of eleven Blender materials:
    head, body, shoulder, arms, legs, steel blue, navy, bevel, gold, visor, joint.
    The caller handles armature modifiers, triangulation and runtime export.
    """
    if len(material_slots) != MATERIAL_COUNT:
        raise ValueError("Thunder body expects the common eleven material slots")
    if obj.get("thunder_raised_plates", False):
        raise ValueError("refine_body must only be called once per fresh source mesh")

    if obj.name.startswith("ArmorBody_06"):
        source_map = {0: 1, 1: 2}
        part = "body"
    elif obj.name.startswith("ArmorHand_06"):
        source_map = {0: 3}
        part = "arms"
    elif obj.name.startswith("ArmorFoot_06"):
        source_map = {0: 4}
        part = "legs"
    else:
        raise ValueError(f"Unsupported Thunder body part: {obj.name}")

    original_materials = [polygon.material_index for polygon in obj.data.polygons]
    if set(original_materials) - source_map.keys():
        raise ValueError(f"Unexpected source material layout in {obj.name}")
    obj.data.materials.clear()
    for material in material_slots:
        obj.data.materials.append(material)
    for polygon, original in zip(obj.data.polygons, original_materials):
        polygon.material_index = source_map[original]

    original_vertices = len(obj.data.vertices)
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        bm.normal_update()
        uv_layer = bm.loops.layers.uv.active
        deform_layer = bm.verts.layers.deform.active
        if uv_layer is None or deform_layer is None:
            raise ValueError(f"Thunder source must retain UVs and skin weights: {obj.name}")
        source_faces = list(bm.faces)
        count = 0
        if part == "body":
            # One continuous chest surface avoids an artificial bright center
            # seam. Its individual vertices still retain their source weights.
            chest = [face for face in source_faces
                     if face.material_index == 1
                     and 0.99 < face.calc_center_median().y < 1.255
                     and abs(face.calc_center_median().x) < 0.25
                     and face.normal.z < -0.75]
            if not chest:
                raise ValueError("Thunder expected chest patch is absent")
            count += _raise_plate(bm, chest, 0.016, 0.012, uv_layer, deform_layer)
        for side in (-1, 1):
            def select(material, y_min, y_max, x_min, x_max, normal_z=-0.55):
                return [face for face in source_faces
                        if face.material_index == material
                        and y_min < face.calc_center_median().y < y_max
                        and x_min < side * face.calc_center_median().x < x_max
                        and face.normal.z < normal_z]

            patches = []
            if part == "body":
                # Keep collar, waist and thigh undersuit uncovered. Shoulder
                # caps retain the source's separate left/right arm weights.
                patches = [
                    (select(2, 1.19, 1.37, 0.29, 0.52), 0.023, 0.025),
                    (select(2, 1.055, 1.18, 0.29, 0.52), 0.016, 0.025),
                ]
            elif part == "arms":
                # Forearm guard only: no fingers, wrist or upper-arm joint.
                patches = [(select(3, 0.73, 0.89, 0.36, 0.57, -0.7), 0.014, 0.020)]
            else:
                # The source knee is already a separate raised shape. Another
                # shell over its upper triangles cuts through its gold marker.
                # Keep it intact and refine only the shin and the foot toe cap.
                patches = [
                    (select(4, 0.205, 0.36, 0.085, 0.24, -0.75), 0.015, 0.015),
                    (select(4, 0.045, 0.09, 0.11, 0.22, -0.8), 0.006, 0.015),
                ]
            for selected, height, inset in patches:
                if not selected:
                    raise ValueError(f"Thunder expected armor patch is absent in {obj.name}")
                count += _raise_plate(bm, selected, height, inset, uv_layer, deform_layer)

        bm.normal_update()
        bm.to_mesh(obj.data)
        obj.data.update()
    finally:
        bm.free()

    obj["thunder_raised_plates"] = count
    obj["thunder_original_vertices"] = original_vertices
    obj["thunder_plate_approach"] = "source UV caps; inherited skin weights; real navy walls and painted chamfers"
    return obj
