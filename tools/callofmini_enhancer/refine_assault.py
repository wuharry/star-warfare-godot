"""Blender background authoring pass for Assault Armor only.

Input/output are produced/consumed by refine_assault.gd. All surfaces are
processed together so UV splits and equipment boundaries share positions.
The existing skeleton, sockets, helmet, textures and item IDs stay intact.
"""
import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "test_output/assault_refinement"


def smooth(a, b, value):
    t = min(1.0, max(0.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def sculpt(position):
    x, y, z = position
    # Wrap the shoulder instead of retaining a flat projecting slab.
    shoulder = smooth(0.30, 0.41, abs(x)) * smooth(1.04, 1.18, y)
    y -= 0.065 * shoulder * smooth(0.36, 0.52, abs(x))
    x *= 1.0 - 0.045 * shoulder
    z *= 1.0 + 0.06 * shoulder
    return Vector((x, y, z))


def main():
    source = json.loads((WORK / "mesh_input.json").read_text())
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    weights_layer = bm.verts.layers.deform.new()
    for slot, surface in enumerate(source["surfaces"]):
        vertices = []
        for i, position in enumerate(surface["vertices"]):
            vertex = bm.verts.new(position)
            for k in range(4):
                weight = surface["weights"][4 * i + k]
                if weight > 0.0:
                    bone = surface["bones"][4 * i + k]
                    vertex[weights_layer][bone] = weight
            vertices.append(vertex)
        indices = surface["indices"]
        for offset in range(0, len(indices), 3):
            # Godot triangles wind clockwise; Blender uses counterclockwise.
            ids = [indices[offset], indices[offset + 2], indices[offset + 1]]
            face = bm.faces.new([vertices[i] for i in ids])
            face.material_index = slot
            for loop, i in zip(face.loops, ids):
                loop[uv_layer].uv = surface["uvs"][i]
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.000001)
    head_slots = {i for i, s in enumerate(source["surfaces"]) if s["part"].startswith("ArmorHead")}
    # Add shoulder profile loops; limbs are replaced by the canonical meshes
    # in refine_assault.gd instead of trying to round the source box shapes.
    for side in (-1, 1):
        for width in (0.425, 0.46):
            faces = [f for f in bm.faces if f.material_index not in head_slots
                     and min(v.co.y for v in f.verts) > 1.04]
            edges = list({e for f in faces for e in f.edges})
            verts = list({v for f in faces for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=verts + edges + faces, dist=0.000001,
                                  plane_co=(side * width, 0, 0), plane_no=(1, 0, 0))
    for vertex in bm.verts:
        if not any(f.material_index in head_slots for f in vertex.link_faces):
            vertex.co = sculpt(vertex.co)
    bm.normal_update()
    # Remove only coplanar triangulation edges, leaving UV/material boundaries.
    candidates = [e for e in bm.edges if e.is_manifold
                  and all(f.material_index not in head_slots for f in e.link_faces)]
    bmesh.ops.dissolve_limit(bm, angle_limit=0.008, verts=[], edges=candidates,
                            delimit={"UV", "MATERIAL"})
    bm.normal_update()
    # Real rounded geometry at hard plate edges. Never bevel across equipment
    # ownership boundaries: original and new armor must still mix cleanly.
    edges = []
    for edge in bm.edges:
        if not edge.is_manifold:
            continue
        slots = [f.material_index for f in edge.link_faces]
        if any(slot in head_slots for slot in slots):
            continue
        parts = [source["surfaces"][slot]["part"] for slot in slots]
        if parts[0] != parts[1]:
            continue
        midpoint = (edge.verts[0].co + edge.verts[1].co) * 0.5
        if midpoint.y < 1.0 or abs(midpoint.x) < 0.28:
            continue
        if edge.calc_face_angle() > math.radians(32):
            edges.append(edge)
    bevel = bmesh.ops.bevel(bm, geom=edges, offset=0.022, segments=3, material=-1,
                            affect="EDGES", profile=0.5, clamp_overlap=True,
                            loop_slide=True)
    bevel_faces = set(bevel["faces"])
    # Store subtle, fixed highlight/shadow modulation in mesh vertex colors.
    # Original armor is unlit, so relying on scene lamps would change its look.
    colors = bm.loops.layers.color.new("ArmorForm")
    bm.normal_update()
    light = Vector((-0.4, 0.85, -0.3)).normalized()
    for face in bm.faces:
        is_bevel = face in bevel_faces
        for loop in face.loops:
            value = 0.94 + 0.06 * face.normal.dot(light)
            if is_bevel:
                value = min(1.0, value + 0.06)
            loop[colors] = (value, value, value, 1.0)
    mesh = bpy.data.meshes.new("Assault_RefinedMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Assault Armor - rounded plate prototype", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Keep a local editable authoring artifact, not an imported second rig.
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "AssaultArmor_refined.blend"))
    mesh.calc_loop_triangles()
    output = {"source_sha256": source["source_sha256"], "surfaces": []}
    for slot, original in enumerate(source["surfaces"]):
        surface = {"part": original["part"], "surface": original["surface"],
                   "vertices": [], "normals": [], "uvs": [], "colors": [],
                   "bones": [], "weights": [], "indices": []}
        for triangle in mesh.loop_triangles:
            if triangle.material_index != slot:
                continue
            for loop_index in [triangle.loops[0], triangle.loops[2], triangle.loops[1]]:
                loop = mesh.loops[loop_index]
                vertex = mesh.vertices[loop.vertex_index]
                surface["indices"].append(len(surface["vertices"]))
                surface["vertices"].append(list(vertex.co))
                surface["normals"].append(list(mesh.corner_normals[loop_index].vector))
                surface["uvs"].append(list(mesh.uv_layers["UVMap"].data[loop_index].uv))
                surface["colors"].append(list(mesh.color_attributes["ArmorForm"].data[loop_index].color)[:3])
                groups = sorted([(g.group, g.weight) for g in vertex.groups if g.weight > 0], key=lambda p: -p[1])[:4]
                assert groups, "Bevel lost a skin weight"
                total = sum(weight for _, weight in groups)
                groups += [(0, 0.0)] * (4 - len(groups))
                surface["bones"].extend(bone for bone, _ in groups)
                surface["weights"].extend(weight / total for _, weight in groups)
        output["surfaces"].append(surface)
    (WORK / "mesh_output.json").write_text(json.dumps(output), encoding="utf-8")
    stats = [{"part": s["part"], "surface": s["surface"], "before_triangles": len(old["indices"]) // 3,
              "after_triangles": len(s["indices"]) // 3} for old, s in zip(source["surfaces"], output["surfaces"])]
    (WORK / "refinement_report.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")
    print("ASSAULT_BLENDER_PASS", stats)


if __name__ == "__main__":
    main()
