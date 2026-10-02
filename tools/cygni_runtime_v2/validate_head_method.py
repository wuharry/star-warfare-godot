"""Compare authored head geometry/UV with the actual legacy reference."""
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/cygni_runtime_v2'
C = Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))


def uv_components(mesh, layer):
    mesh.calc_loop_triangles()
    edges = defaultdict(list)
    parents = list(range(len(mesh.loop_triangles)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for i, tri in enumerate(mesh.loop_triangles):
        uv = [tuple(round(v,6) for v in layer.data[li].uv) for li in tri.loops]
        for a,b in [(0,1),(1,2),(2,0)]:
            edges[tuple(sorted([uv[a],uv[b]]))].append(i)
    for ids in edges.values():
        for i in ids[1:]:
            parents[find(i)] = find(ids[0])
    return sorted(Counter(find(i) for i in range(len(parents))).values(),reverse=True)


def main():
    bpy.ops.wm.open_mainfile(filepath=str(WORK / 'CH_Cygni_master.blend'))
    new = bpy.data.objects['ArmorHead_11']
    source = bpy.data.objects['Original_ArmorHead_11']
    target = new.data.uv_layers['TargetUV']
    olduv = new.data.uv_layers['OriginalUV']
    uv_delta = max((a.uv-b.uv).length for a,b in zip(target.data,olduv.data))
    corrected_loops = 0
    for dst, src in zip(target.data, olduv.data):
        expected = src.uv.copy()
        for (u, v), new_u in [((.01345, .32237), .055), ((.01423, .29872), .070), ((.03512, .45943), .090)]:
            if abs(src.uv.x-u) < .00002 and abs(src.uv.y-v) < .00002:
                expected.x = new_u
                corrected_loops += 1
                break
        if (dst.uv-expected).length > .000001:
            raise ValueError('Unexpected UV edit outside the three visor seam points')
    max_move = 0
    changed = 0
    for v in new.data.vertices:
        original = new.data.attributes['SourceGamePoint'].data[v.index].vector
        delta = (C.inverted() @ v.co-original).length
        max_move = max(max_move,delta)
        changed += delta > .00002
    originals = uv_components(source.data,source.data.uv_layers.active)
    current = uv_components(new.data,target)
    if corrected_loops == 0 or originals != current or new['source_uv_checked_faces'] != len(source.data.polygons):
        raise ValueError('Lost original UV correspondence or chart reuse')
    old_source = ROOT / 'assets/models/player/animated/player.gltf'
    report = {
        'status':'PASS geometry/UV contract only; art awaits user review',
        'source_sha256':hashlib.sha256(old_source.read_bytes()).hexdigest(),
        'original_triangles':len(source.data.loop_triangles),
        'new_triangles':len(new.data.loop_triangles),
        'original_uv_components':originals,
        'new_uv_components':current,
        'exact_original_uv_reuse':uv_delta == 0,
        'approved_local_uv_correction': 'Three shared visor seam points; all other TargetUV coordinates unchanged',
        'corrected_uv_loops': corrected_loops,
        'maximum_uv_displacement': uv_delta,
        'source_faces_checked':int(new['source_uv_checked_faces']),
        'changed_welded_vertices':changed,
        'maximum_vertex_displacement_game_units':max_move,
        'scope':'Reshaped original cage; image-space connected UV edges merge overlapping mirrored charts; source collar/joints remain unchanged.',
        'art_limit':'Preserving topology and UV does not prove same-artist appearance or concept approval.',
    }
    (WORK/'review/continuous_head/method_validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('CYGNI_CONTINUOUS_HEAD_PASS', json.dumps(report))


if __name__ == '__main__':
    main()
