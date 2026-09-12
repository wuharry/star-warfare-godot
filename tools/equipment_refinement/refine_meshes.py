"""Subtle edits to original geometry in original coordinates; run in Blender."""
import bpy
import bmesh
import json
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'test_output/equipment_refinement'
data = json.loads((WORK / 'sources.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
reports = []
output = {}
SOFT_SETS = {22, 23, 26, 28}
EFFECT_NAMES = ('eff', 'qiangkou', 'gong_1', 'sniper', 'standard_7', 'rpg_mat', 'christmas_02', 'guiji')


def refine(mesh, kind, set_id=-1):
    results = []
    for sid, surface in enumerate(mesh['surfaces']):
        a = surface['arrays']
        vertices = a['0']
        indices = a.get('12') or list(range(len(vertices)))
        triangles = [indices[i:i+3][::-1] for i in range(0, len(indices), 3)]
        bounds = [[min(v[k] for v in vertices), max(v[k] for v in vertices)] for k in range(3)]
        longest = max(hi-lo for lo, hi in bounds)
        width = (.0012 if 'Hand' in mesh['name'] else .002) if kind == 'armor' else longest * .0012
        soft = kind == 'armor' and set_id in SOFT_SETS and ('Hand' in mesh['name'] or 'Foot' in mesh['name'])
        effect = kind == 'weapon' and any(word in surface['material'].lower() for word in EFFECT_NAMES)
        bm = bmesh.new()
        deform = bm.verts.layers.deform.new() if a.get('10') else None
        uv_layers = {key: bm.loops.layers.uv.new(key) for key in ('4', '5') if a.get(key)}
        color = bm.loops.layers.float_color.new('color') if a.get('3') else None
        source_normal = bm.loops.layers.float_color.new('source_normal')
        verts = [bm.verts.new(v) for v in vertices]
        bm.verts.ensure_lookup_table()
        influences = len(a.get('10', [])) // len(vertices)
        if deform:
            for vi, v in enumerate(verts):
                for k in range(influences):
                    weight = a['11'][vi*influences+k]
                    if weight > 0:
                        v[deform][a['10'][vi*influences+k]] = weight
        for triangle in triangles:
            try:
                face = bm.faces.new([verts[i] for i in triangle])
            except ValueError:
                continue
            for loop, vi in zip(face.loops, triangle):
                loop[source_normal] = [*a['1'][vi], 1.0]
                for key, layer in uv_layers.items():
                    loop[layer].uv = a[key][vi]
                if color:
                    loop[color] = a['3'][vi]
        # Boundaries include UV/material cuts, magazine slots and limb seams:
        # leave them at the exact source coordinates.
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.000001)
        bm.normal_update()
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle() > math.radians(42)]
        changed = bool(edges) and not soft and not effect
        if changed:
            bmesh.ops.bevel(bm, geom=edges, offset=width, segments=2, affect='EDGES', clamp_overlap=True)
        bm.normal_update()
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.normal_update()
        new_bounds = [[min(v.co[k] for v in bm.verts), max(v.co[k] for v in bm.verts)] for k in range(3)]
        deviation = max(abs(new_bounds[k][j]-bounds[k][j]) for k in range(3) for j in range(2))
        guarded = deviation > width * 2 + .00001
        if guarded:
            # Acute corners can amplify a bevel. Keep authored geometry there.
            changed = False
        arrays = {key: [] for key in a if key in ('0', '1', '3', '4', '5', '10', '11')}
        if changed:
            for face in bm.faces:
                for loop in reversed(list(face.loops)):
                    v = loop.vert
                    arrays['0'].append(list(v.co))
                    # Interpolate the authored split normals, including the rounded
                    # helmet shading. Replacing them with face normals looks faceted.
                    normal = Vector(loop[source_normal][:3])
                    arrays['1'].append(list(normal.normalized() if normal.length > .0001 else face.normal))
                    for key, layer in uv_layers.items():
                        arrays[key].append(list(loop[layer].uv))
                    if color:
                        arrays['3'].append(list(loop[color]))
                    if deform:
                        weights = sorted(((i, w) for i, w in v[deform].items() if w > 0), key=lambda p:-p[1])[:4]
                        total = sum(w for _, w in weights)
                        assert total > 0, (mesh['name'], sid)
                        arrays['10'].extend([i for i, _ in weights] + [0] * (4-len(weights)))
                        arrays['11'].extend([w/total for _, w in weights] + [0.] * (4-len(weights)))
            arrays['12'] = list(range(len(arrays['0'])))
        else:
            arrays = a
        reports.append({'mesh': mesh['name'], 'surface': sid, 'material': surface['material'],
                        'original_triangles': len(triangles),
                        'triangles': len(arrays.get('12') or arrays['0']) // 3,
                        'edge_width_source_units': width if changed else 0,
                        'max_bounds_change': deviation if changed else 0,
                        'treatment': 'original_edge_bevel' if changed else ('retain_acute_corner' if guarded else ('retain_soft_surface' if soft else 'retain_surface'))})
        results.append(arrays)
        bm.free()
    return results


for entry in data['entries']:
    if entry['kind'] == 'armor':
        for mesh in entry['parts']:
            output[mesh['name']] = refine(mesh, 'armor', entry['id'])
        print('REFINED', entry['key'], flush=True)
for name, mesh in data['weapon_meshes'].items():
    output[name] = refine(mesh, 'weapon')
    print('REFINED', name, flush=True)
(WORK / 'meshes.json').write_text(json.dumps(output, separators=(',', ':')))
out = ROOT / 'assets/equipment_refined'
(out / 'mesh_report.json').write_text(json.dumps(reports, indent=2) + '\n')
print('EQUIPMENT_MESH_PASS', len(output), 'meshes')
