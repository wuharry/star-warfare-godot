"""Titan helmet: an elliptical pressure visor with a small curved frame.

The approved C-06 concept supplies the forms; the original cage supplies the
game's head scale, UVs and rig. Coordinates are in original Godot rest space.
The concept has only a quarter view: side/back depth is inferred, constrained
to the original-total 20% envelope. Only front visor/frame edges receive small
subdivisions, within 1.35 times the original head counts. Original UV charts,
vertex/weight prefixes and the hidden rear are retained. New UVs are original
edge midpoints; the front glass is a curved surface rather than a painted dome.
The v5 ear and lower-frame offsets adopt the checked 2026-10-06 alignment
candidate. Their direction is inferred from the single quarter-view concept.
"""
import copy
import math

def interpolate(value, knots):
    if value<knots[0][0] or value>knots[-1][0]:return value
    for (a,b),(c,d) in zip(knots,knots[1:]):
        if a<=value<=c:return b+(d-b)*(value-a)/(c-a)
    return value


RIM_CENTER_Y = 1.675
RIM_RADIUS_X = .265
RIM_RADIUS_Y = .270
RIM_LOWER_RADIUS_Y = .260
# Physical original front-frame positions, shared by duplicate UV seam IDs.
# Absolute x identifies both sides without changing their original IDs.
RIM_SOURCE_KEYS = {
    (0.0, 1.93498, -.04910), (.17458, 1.85708, -.05466),
    (.24883, 1.73095, -.06574), (.24882, 1.73095, -.06574),
    (.22905, 1.54933, -.07114), (.14712, 1.44999, -.18251),
    (.14712, 1.45000, -.18251), (.09627, 1.35253, -.14850),
    (.13121, 1.35791, -.14800), (0.0, 1.29936, -.22336),
}

# Checked draft_alignment_20261006 offsets in original Godot rest space.
# Physical keys, rather than the authored positions or UV indices, identify
# every original seam duplicate and mirrored counterpart. The comments retain
# the original representative IDs recorded by that separate review candidate.
DRAFT_ALIGNMENT_OFFSETS = {
    (.3171, 1.6063, -.0178): (-.012, .024, .020),  # 126: lower ear corner
    (.2329, 1.5495, -.0134): (-.004, .030, .025),  # 129: lower ear connector
    (.3191, 1.7001, -.0387): (-.010, 0, .010),     # 130
    (.3028, 1.6950, .0929): (-.007, 0, .007),      # 128
    (.3027, 1.7579, .0691): (-.007, 0, .007),      # 136
    (0.0, 1.2994, -.2234): (0, 0, .015),          # 194: central lower lip
    (.0963, 1.3525, -.1485): (0, 0, .012),        # 80
    (.1312, 1.3579, -.1480): (0, 0, .012),        # 84
    (.1471, 1.4500, -.1825): (0, 0, .008),        # 81
}


def align_ear_and_lower_frame(original, authored, added):
    """Apply the checked candidate without changing UVs, faces or bindings."""
    before = copy.deepcopy(authored)
    for index, point in enumerate(original['positions']):
        key = tuple(round(abs(value) if axis == 0 else value, 4)
                    for axis, value in enumerate(point))
        delta = DRAFT_ALIGNMENT_OFFSETS.get(key)
        if delta is None:
            continue
        dx, dy, dz = delta
        authored[index] = [
            before[index][0] + dx*(1 if point[0] > 0 else -1)
            if abs(point[0]) > 1e-5 else before[index][0],
            before[index][1] + dy,
            before[index][2] + dz,
        ]
    for record in added:
        index = record['index']
        a, b = record['parents']
        authored[index] = [
            before[index][axis] + ((authored[a][axis]-before[a][axis])
                                    + (authored[b][axis]-before[b][axis]))/2
            for axis in range(3)
        ]
        record['bend'] = [authored[index][axis]
                          - (authored[a][axis]+authored[b][axis])/2
                          for axis in range(3)]


def ellipse_rim(point):
    x, y, _ = point
    radius_y = RIM_LOWER_RADIUS_Y if y<RIM_CENTER_Y else RIM_RADIUS_Y
    angle = math.atan2((y-RIM_CENTER_Y)/radius_y, x/RIM_RADIUS_X)
    x = RIM_RADIUS_X*math.cos(angle)
    y = RIM_CENTER_Y+radius_y*math.sin(angle)
    # The frame follows a shallow tilted plane: a recessed crown and forward
    # lower lip, instead of projecting all rim points onto a flat front plane.
    z = -.020-.38*(RIM_CENTER_Y+RIM_RADIUS_Y-y)
    return [x, y, z]


def pressure_glass(point, source):
    x, y, z = point
    amount = min(1.0, max(0.0,(-source[2]-.10)/.10))
    amount *= min(1.0, max(0.0,(source[1]-1.41)/.10))
    radius_y = RIM_LOWER_RADIUS_Y if y<RIM_CENTER_Y else RIM_RADIUS_Y
    squared = (x/RIM_RADIUS_X)**2+((y-RIM_CENTER_Y)/radius_y)**2
    cap_z = -.350*math.sqrt(max(0.0,1.0-squared))
    return [x, y, z+(cap_z-z)*amount]

def reshape(point, surface_id=0):
    x,y,z=point
    weight=min(1.0,max(0.0,(-z+.015)/.19))
    mapped=interpolate(y,KNOTS)
    # Concept: the blue lower frame wraps across the chin, rather than ending
    # in a deep V. Spread only the lower front side corners; the neck stays put.
    lower=max(0.0,1.0-abs(y-1.39)/.105)
    side=min(1.0,abs(x)/.10)
    widened=x*(1.0+.05*lower*side*weight)
    # Inferred ear depth: reduce the box's lateral corners, retaining its
    # original attachment and three connected UV regions.
    ear=max(0.0,min(1.0,(abs(x)-.27)/.0492))
    widened-= (.040*ear if x>=0 else -.040*ear)
    # Keep the glass more upright without scaling the ear, rear or neck.
    # All factors use the true original point, not the previous iteration.
    visor_width=(min(1.0,max(0.0,(-z-.12)/.12))
                 *min(1.0,max(0.0,(y-1.36)/.12))
                 *min(1.0,max(0.0,(1.95-y)/.08)))
    widened*=1.0-.08*visor_width
    # Concept: a convex upper face, not a flat forehead above a shield visor.
    upper=max(0.0,1.0-abs(y-1.815)/.10)
    forward=.050*upper*weight
    # Lower side glass follows the convex face rather than falling back into
    # the old pointed shield. The center and temple remain on the same cage.
    lower_glass=max(0.0,1.0-abs(y-1.46)/.075)*side
    forward+=.038*lower_glass*weight
    chin=.030*max(0.0,1.0-abs(y-1.30)/.07)*weight
    point = [widened,y+(mapped-y)*weight,z-forward-chin]
    key = (round(abs(x),5), round(y,5), round(z,5))
    if key in RIM_SOURCE_KEYS:
        rim = ellipse_rim(point)
        if key == (.13121,1.35791,-.14800):
            # This outer lower connector owns a narrow frame triangle. Keep
            # its 6 mm band outside the curved rim instead of flattening all
            # three parent corners onto the same arc and reversing the face.
            rim[1] -= .006
            rim[2] -= .38*.006
        return rim
    if key == (.20250,1.55679,-.08687):
        # Close the existing side-cheek connector behind the narrower frame.
        # Leaving it at the old depth reverses its thin original parent face.
        point[2] -= .025
    return pressure_glass(point, [x,y,z])

# Heights are fitted to the same game cage, not the adult concept body.
KNOTS=[(1.26,1.26),(1.2994,1.405),(1.3525,1.410),(1.456,1.485),
       (1.4898,1.508),(1.7002,1.735),(1.7957,1.845),
       (1.8473,1.899),(1.8571,1.906),(1.94,1.94)]


def refine_surface(original, positions, uv):
    """Split selected front arcs once; retain all original vertex IDs.

    UV midpoints stay on existing chart edges. Parents/pairs let validators
    independently prove that every old triangle is only subdivided, not lost.
    """
    row = copy.deepcopy(original)
    authored = copy.deepcopy(positions)
    row['uv'] = copy.deepcopy(uv)
    parents = list(range(len(row['indices']) // 3))
    added = []
    edges = [(19,20,'glass'), (20,22,'glass'), (22,79,'glass'),
             (25,23,'rim'), (23,42,'rim'), (42,44,'return'),
             (44,27,'rim'), (27,26,'rim'), (26,194,'rim'),
             (20,18,'glass'), (18,24,'glass')]
    specifications = []
    # Original mirrored positions can differ by a few micrometres after skin
    # quantisation; 0.1 mm matching includes both halves of the same edge.
    key = lambda p: tuple(round(v, 4) for v in p)
    for a, b, kind in edges:
        for sign in [-1, 1]:
            pa, pb = list(original['positions'][a]), list(original['positions'][b])
            pa[0] *= sign; pb[0] *= sign
            spec = (frozenset((key(pa), key(pb))), kind)
            if spec not in specifications:
                specifications.append(spec)
    for edge, kind in specifications:
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
                midpoint = [(x+y)/2 for x,y in zip(authored[a],authored[b])]
                source_midpoint = [(x+y)/2 for x,y in zip(original['positions'][a],original['positions'][b])]
                curved = ellipse_rim(midpoint) if kind in ['rim','return'] else reshape(source_midpoint)
                if kind=='return':
                    # This secondary side return was visible as a separate
                    # gold wing behind the pressure visor in quarter view.
                    # Tuck only its arc midpoint inward/back; keep every old
                    # vertex and the main visor's size exactly unchanged.
                    curved[0] -= math.copysign(.012,curved[0])
                    curved[2] += .040
                bend = [x-y for x,y in zip(curved,midpoint)]
                authored.append(curved)
                added.append({'index': vertex, 'parents': list(pair), 'bend': bend})
            vertex = cache[pair]
            indices.extend([a, vertex, c, vertex, b, c]); next_parents.extend([parent, parent])
        row['indices'], parents = indices, next_parents
    assert len(row['indices']) <= len(original['indices']) * 1.35
    assert len(row['uv']) <= len(original['uv']) * 1.35
    align_ear_and_lower_frame(original, authored, added)
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
