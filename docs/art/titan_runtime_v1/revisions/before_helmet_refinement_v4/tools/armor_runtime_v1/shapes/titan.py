"""Titan helmet v3: rounded crown, compact ears and a shallow U chin guard.

The approved C-06 concept supplies the forms; the original cage supplies the
game's head scale, UVs and rig. Coordinates are in original Godot rest space.
The concept has only a quarter view: side/back depth is inferred, constrained
to the original-total 20% envelope. Only visor arcs receive edge subdivisions;
the three broad UV charts remain connected.
"""
import copy
import math

def interpolate(value, knots):
    if value<knots[0][0] or value>knots[-1][0]:return value
    for (a,b),(c,d) in zip(knots,knots[1:]):
        if a<=value<=c:return b+(d-b)*(value-a)/(c-a)
    return value

def reshape(point, surface_id=0):
    x,y,z=point
    weight=min(1.0,max(0.0,(-z+.015)/.19))
    mapped=interpolate(y,KNOTS)
    # Concept: the blue lower frame wraps across the chin, rather than ending
    # in a deep V. Spread only the lower front side corners; the neck stays put.
    lower=max(0.0,1.0-abs(y-1.39)/.105)
    side=min(1.0,abs(x)/.10)
    widened=x*(1.0+.20*lower*side*weight)
    # Inferred ear depth: reduce the box's lateral corners, retaining its
    # original attachment and three connected UV regions.
    ear=max(0.0,min(1.0,(abs(x)-.27)/.0492))
    widened-= (.040*ear if x>=0 else -.040*ear)
    # Concept: a convex upper face, not a flat forehead above a shield visor.
    upper=max(0.0,1.0-abs(y-1.815)/.10)
    forward=.050*upper*weight
    # Lower side glass follows the convex face rather than falling back into
    # the old pointed shield. The center and temple remain on the same cage.
    lower_glass=max(0.0,1.0-abs(y-1.46)/.075)*side
    forward+=.038*lower_glass*weight
    chin=.030*max(0.0,1.0-abs(y-1.30)/.07)*weight
    return [widened,y+(mapped-y)*weight,z-forward-chin]

# Heights are fitted to the same game cage, not the adult concept body.
KNOTS=[(1.26,1.26),(1.2994,1.405),(1.3525,1.410),(1.456,1.485),
       (1.4898,1.508),(1.7002,1.735),(1.7957,1.845),
       (1.8473,1.899),(1.8571,1.906),(1.94,1.94)]


def refine_surface(original, positions, uv):
    """Split only three visor arc families; retain all original vertex IDs.

    UV midpoints stay on existing chart edges. Parents/pairs let validators
    independently prove that every old triangle is only subdivided, not lost.
    """
    row = copy.deepcopy(original)
    authored = copy.deepcopy(positions)
    row['uv'] = copy.deepcopy(uv)
    parents = list(range(len(row['indices']) // 3))
    added = []
    edges = [(19, 20, [0, 0, -.018]), (20, 22, [0, .004, -.023]),
             (22, 79, [0, .018, -.020])]
    specifications = []
    key = lambda p: tuple(round(v, 5) for v in p)
    for a, b, bend in edges:
        for sign in [-1, 1]:
            pa, pb = list(original['positions'][a]), list(original['positions'][b])
            pa[0] *= sign; pb[0] *= sign
            spec = (frozenset((key(pa), key(pb))), bend)
            if spec not in specifications:
                specifications.append(spec)
    for edge, bend in specifications:
        indices, next_parents, cache = [], [], {}
        for start in range(0, len(row['indices']), 3):
            tri = row['indices'][start:start + 3]
            match = next(((tri[j], tri[(j + 1) % 3], tri[(j + 2) % 3]) for j in range(3)
                          if frozenset((key(row['positions'][tri[j]]), key(row['positions'][tri[(j + 1) % 3]]))) == edge), None)
            parent = parents[start // 3]
            if match is None:
                indices.extend(tri); next_parents.append(parent); continue
            a, b, c = match
            pair = tuple(sorted((a, b)))
            if pair not in cache:
                assert row['bone_indices'][a] == row['bone_indices'][b]
                assert row['weights'][a] == row['weights'][b]
                vertex = len(row['positions']); cache[pair] = vertex
                for field in ['positions', 'raw_positions', 'uv', 'normals']:
                    row[field].append([(x + y) / 2 for x, y in zip(row[field][a], row[field][b])])
                for field in ['bone_indices', 'bone_names', 'weights']:
                    row[field].append(copy.deepcopy(row[field][a]))
                authored.append([(x + y) / 2 + d for x, y, d in zip(authored[a], authored[b], bend)])
                added.append({'index': vertex, 'parents': list(pair), 'bend': bend})
            vertex = cache[pair]
            indices.extend([a, vertex, c, vertex, b, c]); next_parents.extend([parent, parent])
        row['indices'], parents = indices, next_parents
    assert len(row['indices']) <= len(original['indices']) * 1.20
    assert len(row['uv']) <= len(original['uv']) * 1.20
    row['triangle_parents'], row['added_vertices'] = parents, added
    return row, authored


def adjust_uv(point, uv):
    # The native atlas has a rim at its left padding. Sample continuous glass
    # at the mirrored face center rather than turning padding into a blue nose.
    u, v = uv
    if math.dist(uv, [.00318, .50565]) < .00002:
        return [.070, v]
    if math.dist(uv, [.03587, .76207]) < .00002:
        return [.100, .700]
    return list(uv)
