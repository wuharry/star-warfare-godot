"""Connected concept helmet blockout. No texture or floating face plates.

The shell and visor are different faces of one continuous cage. Original
Cygni measurements set its envelope; new concepts set the T aperture and
swept cheek transition. Depths and the unseen back remain inferred.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import runpy
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build import Part, export_json

WORK = ROOT / "test_output/armor_concept_runtime"
NATIVE = ROOT / "docs/art/armor_runtime_v1/armor_11/repair_shell_v4"
REVISION = "concept_cygni_connected_shell_v4"
HEAD = "Bip01 Head"
GRAY = (.57, .57, .57, 1)
LENS = (.15, .15, .15, 1)
SEAL = (.055, .055, .055, 1)
# Y, half-width, centre-front Z, side Z, centre-back Z. Y-up/-Z-forward.
# Scale envelope is from original Cygni; intermediate sections are inferred.
ROWS = [
    (1.278, .106, -.355, -.015, .143),
    (1.340, .160, -.365, -.045, .190),
    (1.430, .219, -.411, -.076, .225),
    (1.550, .267, -.440, -.089, .244),
    (1.650, .294, -.4447, -.093, .253),
    (1.735, .300, -.416, -.084, .2551),
    (1.767, .294, -.426, -.078, .252),
    (1.810, .282, -.328, -.052, .247),
    (1.885, .226, -.226, -.014, .205),
    (1.950, .145, -.105, .025, .159),
    (1.9784, .028, .035, .055, .076),
]
U = (-1.0, -.88, -.64, -.28, -.18, 0.0, .18, .28, .64, .88, 1.0)
BACK_SEGMENTS = 12


def main() -> None:
    scope = runpy.run_path(str(ROOT / "tools/armor_rework/inspect_source.py"))
    rig = scope["rig"]
    for obj in list(bpy.data.objects):
        if obj != rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    low = bpy.data.collections.new("LOW")
    bpy.context.scene.collection.children.link(low)
    cage = Part("Cygni_ConnectedHelmet")
    vertices, faces, roles = [], [], []
    ring_size = len(U) + BACK_SEGMENTS - 1
    for row, (y, width, front, side, back) in enumerate(ROWS):
        for column, base_u in enumerate(U):
            u = base_u
            if row in (1, 2, 3) and abs(base_u) <= .28:
                # Constant stem columns taper continuously from the T bar to
                # its tip. Do not make a stair-step by changing face roles.
                stem_half_width = [.029, .056, .081][row - 1]
                u = base_u / .18 * stem_half_width / width
            yy = y
            if row in (0, 1, 2, 3):
                yy += [.082, .078, .060, .045][row] * abs(u) ** .80
            if row == 5:
                # Swept T brow: low at centre, raised over the eyes, low again
                # at the outer corner. It remains part of the crown cage.
                yy += -.027 * max(0.0, 1 - abs(u) / .28)
                yy -= .020 * max(0.0, (abs(u) - .64) / .36)
            a = abs(u)
            if row in (1, 2, 3, 4, 5, 6):
                # A flat central lens / swept cheek / angled return are three
                # real planes. An ellipsoid would make every area look alike.
                stops = [(0.0, front), (.28, front + .014),
                         (.64, front + .066), (.88, side - .104), (1.0, side)]
                for (lo, zlo), (hi, zhi) in zip(stops, stops[1:]):
                    if a <= hi:
                        z = zlo + (zhi - zlo) * (a - lo) / (hi - lo)
                        break
            else:
                z = front + (side - front) * a ** 2.15
            if row in (6, 7, 8) and abs(base_u) <= .28:
                # Integrated crown ridge, blending into its neighbours. No
                # separate upright plate in front of the dome.
                z -= .014 * (1 - abs(base_u) / .28)
                yy += .008 * (1 - abs(base_u) / .28)
            vertices.append((width * u, yy, z))
        for i in range(1, BACK_SEGMENTS):
            angle = i * math.pi / BACK_SEGMENTS
            vertices.append((width * math.cos(angle), y, side + (back - side) * math.sin(angle)))
    for row in range(len(ROWS) - 1):
        for column in range(ring_size):
            next_column = (column + 1) % ring_size
            faces.append((row * ring_size + column, row * ring_size + next_column,
                          (row + 1) * ring_size + next_column, (row + 1) * ring_size + column))
            midpoint = (U[column] + U[column + 1]) / 2 if column < len(U) - 1 else 2
            # The T window is NOT laid over a sphere. Its edge vertices are
            # shared with the white brow, cheeks and chin on the same cage.
            glass = ((row in (1, 2) and abs(midpoint) < .18)
                     or (row in (3, 4) and abs(midpoint) < .88))
            roles.append(1 if glass else 0)
    faces.extend([tuple(reversed(range(ring_size))),
                  tuple(range((len(ROWS) - 1) * ring_size, len(ROWS) * ring_size))])
    roles.extend([0, 0])
    cage.add("continuous crown, cheeks, brow and inset T window", vertices, faces, GRAY, HEAD)
    cage.loft("neck sleeve under shell", [(0, 1.1964, .018, .103, .105),
                                         (0, 1.355, .020, .112, .112)], SEAL, HEAD, 16)
    roles += [2] * (len(cage.faces) - len(roles))
    for sign in (-1, 1):
        # Closed short rear fins: roots overlap the existing shell volume.
        # Their inside ends are at X .205, never loose at X .27 in empty space.
        for y in (1.760, 1.860):
            v = [(sign * x, yy, z) for x, yy, z in [
                (.205, y, .085), (.279, y + .004, .080),
                (.3416, y + .040, .166), (.320, y + .099, .176),
                (.205, y + .060, .100),
                (.205, y, .103), (.279, y + .004, .098),
                (.3416, y + .040, .184), (.320, y + .099, .194),
                (.205, y + .060, .118)]]
            fs = [(0, 4, 3, 2, 1), (5, 6, 7, 8, 9)]
            fs += [(i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5)]
            cage.add("connected rear fin", v, fs, GRAY, HEAD)
            roles += [0] * len(fs)
    obj = cage.object(rig, low)
    # Part.object initializes the armature modifier. Keep source quads for
    # integral recesses and panel relief, then triangulate the delivery mesh.
    import bmesh
    mesh = bpy.data.meshes.new("Cygni_ConnectedHelmet_Cage")
    mesh.from_pydata(cage.vertices, [], cage.faces)
    for polygon, role in zip(mesh.polygons, roles):
        polygon.material_index = role
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.faces.ensure_lookup_table()
    spine_faces = [bm.faces[row * ring_size + column]
                   for row in (6, 7) for column in (3, 4, 5, 6)]
    # Recess cheek intakes IN the cage. Their rims and inner faces share real
    # edges; there is no separate dark card floating in front of a white plate.
    intake_faces = [bm.faces[2 * ring_size + column] for column in (1, 8)]
    for face in intake_faces:
        face.material_index = 2
    inset = bmesh.ops.inset_individual(bm, faces=intake_faces, thickness=.013,
                                      depth=-.006, use_even_offset=True)
    for face in inset["faces"]:
        face.material_index = 0
    # Stable face references were captured before either inset operation.
    bmesh.ops.inset_region(bm, faces=spine_faces, thickness=.006, depth=.005,
                          use_even_offset=True, use_boundary=True)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    old_mesh = obj.data
    obj.data = mesh
    bpy.data.meshes.remove(old_mesh)
    uv = mesh.uv_layers.new(name="UVMap_Blockout")
    colors = mesh.color_attributes.new(name="ArmorColor", type="FLOAT_COLOR", domain="CORNER")
    for role, tint in enumerate([GRAY, LENS, SEAL]):
        material = bpy.data.materials.new(["clay_shell", "clay_T_window", "clay_neck"][role])
        material.diffuse_color = tint
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        for index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[index].vertex_index].co
            uv.data[index].uv = (.5 + point.x, (point.y - 1.1964) / .782)
            colors.data[index].color = [GRAY, LENS, SEAL][polygon.material_index]
    # Reassign groups: the recreated mesh has the same indexed vertices.
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    group = obj.vertex_groups.new(name=HEAD)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    payload = export_json(obj)
    source_path = ROOT / "test_output/armor_facets/sources.json"
    sources = json.loads(source_path.read_text())
    entry = next(e for e in sources["entries"] if e["id"] == 11)
    original_head = entry["parts"][0]
    bind_map = {b["name"]: b["index"] for b in original_head["binds"]}
    arrays = {k: [] for k in ("0", "1", "3", "4", "10", "11", "12")}
    for triangle in range(len(payload["positions"]) // 9):
        for corner in (2, 1, 0):
            i = triangle * 3 + corner
            x, y, z = payload["positions"][i * 3:i * 3 + 3]
            nx, ny, nz = payload["normals"][i * 3:i * 3 + 3]
            arrays["0"].append([x, z, -y])
            arrays["1"].append([nx, nz, -ny])
            arrays["3"].append(payload["colors"][i * 4:i * 4 + 4])
            u, v = payload["uv"][i * 2:i * 2 + 2]
            arrays["4"].append([u, 1 - v])
            arrays["10"].extend([bind_map[HEAD], 0, 0, 0])
            arrays["11"].extend([1, 0, 0, 0])
    arrays["12"] = list(range(len(arrays["0"])))
    output = {"ArmorHead_11": [arrays]}
    for part in entry["parts"][1:]:
        binds = {b["name"]: b["index"] for b in part["binds"]}
        output[part["name"]] = []
        for surface in part["raw_surfaces"]:
            raw = copy.deepcopy(surface["arrays"])
            raw["10"] = [binds[part["raw_binds"][int(i)]["name"]] for i in raw["10"]]
            raw["3"] = [[1, 1, 1, 1] for _ in raw["0"]]
            output[part["name"]].append(raw)
    WORK.mkdir(parents=True, exist_ok=True)
    NATIVE.mkdir(parents=True, exist_ok=True)
    geometry_path = WORK / "repaired_armor_arrays.json"
    geometry_path.write_text(json.dumps(output, separators=(",", ":")))
    report = {"revision": REVISION, "status": "clay_geometry_review_pending",
              "body": "unaltered original Cygni geometry and existing refined textures",
              "head_triangles": len(arrays["12"]) // 3,
              "continuous_primary_cage": True, "visor_extrusion": 0,
              "bounds": [[min(v.co[i] for v in mesh.vertices), max(v.co[i] for v in mesh.vertices)] for i in range(3)],
              "source_fingerprints": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in [Path(__file__), ROOT / "tools/armor_concept_runtime/build.py", source_path, geometry_path]},
              "inferred": ["new front-to-side depth profile", "rear crown shape", "fin depth"],
              "not_done": ["production UV", "new painted texture", "visual acceptance", "other armor rollout"]}
    (WORK / "repaired_build.json").write_text(json.dumps(report, indent=2) + "\n")
    (NATIVE / "asset-manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(NATIVE / "master.blend"), compress=True)
    print("CYGNI_CONNECTED_SHELL_BUILD_PASS", report["head_triangles"], flush=True)


if __name__ == "__main__":
    main()
