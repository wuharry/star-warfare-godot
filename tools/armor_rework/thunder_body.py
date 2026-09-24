"""Fitted Thunder shells matching the blue/gold full-body concept.

The original rig and UV paint remain in place. Authored closed layers obtain
paint and interpolated bone weights from each corresponding original surface.
Coordinates are the recovered bind pose: Y up, front toward minus Z.
"""
from collections import Counter
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

MATERIAL_COUNT = 11
DARK_NAVY = 6

class _Surface:
    """Immutable source triangles used to project both UVs and skinning."""
    def __init__(self, obj, material):
        mesh = obj.data
        mesh.calc_loop_triangles()
        self.coords = [v.co.copy() for v in mesh.vertices]
        self.triangles = [tri for tri in mesh.loop_triangles if tri.material_index == material]
        self.uvs = [v.uv.copy() for v in mesh.uv_layers.active.data]
        self.weights = [{g.group: g.weight for g in v.groups if g.weight > 0} for v in mesh.vertices]

class _Shells:
    """Authored bevelled caps with physically connected walls and backing."""
    def __init__(self, obj, fit_profile=None):
        self.fit_profile = fit_profile or {}
        self.bm = bmesh.new()
        self.bm.from_mesh(obj.data)
        self.uv = self.bm.loops.layers.uv.active
        self.deform = self.bm.verts.layers.deform.active
        if self.uv is None or self.deform is None:
            raise ValueError('Thunder body needs original UVs and skin weights')
        self.surfaces, self.panels = {}, []
        self.obj = obj
        self.original_faces = set(self.bm.faces)
        self.original_face_order = list(self.bm.faces)
        self.cutouts = {}

    def surface(self, material):
        if material not in self.surfaces:
            self.surfaces[material] = _Surface(self.obj, material)
        return self.surfaces[material]

    def vertex(self, point, weights):
        vertex = self.bm.verts.new(point)
        for group, weight in weights.items():
            vertex[self.deform][group] = weight
        return vertex

    def face(self, vertices, uvs, material):
        face = self.bm.faces.new(vertices)
        face.material_index = material
        face.smooth = False
        for loop, uv in zip(face.loops, uvs):
            loop[self.uv].uv = uv
        return face

    def panel(self, name, material, outline, height=.022, bevel=.075, back=False,
              bulge=.003, cap_material=None):
        """Clip the exact textured source triangles to an authored shell outline.

        Sampling only a polygon's corners would interpolate across unrelated UV
        islands and distort the yellow markings. Clipping each original triangle
        retains every original UV seam and all intermediate surface curvature.
        """
        source = self.surface(material)
        outer_tree = None
        if self.fit_profile.get('outer_surface_only', False):
            outer_tree = BVHTree.FromPolygons(source.coords,
                [tuple(t.vertices) for t in source.triangles], all_triangles=True)
        if 'abdomen rib' not in name:
            # Keep the closed supporting wall tucked under its painted plate;
            # exaggerated extrusion reads as a loose strap at macro distance.
            height *= .75 if material in (1, 3) else .82
            bulge *= .85
        signed_area = sum(a[0] * b[1] - b[0] * a[1]
                          for a, b in zip(outline, outline[1:] + outline[:1]))
        winding = 1 if signed_area > 0 else -1
        direction = 1 if back else -1
        paint = material if cap_material is None else cap_material
        wall_material = 10 if 'abdomen rib' in name else DARK_NAVY
        patches = []
        patch_faces = []

        def interpolate(a, b, t):
            weights = {group: a[2].get(group, 0) * (1 - t) + b[2].get(group, 0) * t
                       for group in set(a[2]) | set(b[2])}
            return a[0].lerp(b[0], t), a[1].lerp(b[1], t), weights

        for triangle in source.triangles:
            if triangle.normal.z * direction < .12:
                continue
            if outer_tree is not None:
                center = sum((source.coords[i] for i in triangle.vertices), Vector()) / 3
                ray_origin = center + Vector((0, 0, direction * 10))
                hit, _, _, _ = outer_tree.ray_cast(ray_origin, Vector((0, 0, -direction)), 20)
                if hit is None or abs(hit.z - center.z) > .0001:
                    continue
            polygon = [(source.coords[index].copy(), source.uvs[loop].copy(), source.weights[index].copy())
                       for index, loop in zip(triangle.vertices, triangle.loops)]
            for a, b in zip(outline, outline[1:] + outline[:1]):
                def distance(vertex):
                    return winding * ((b[0] - a[0]) * (vertex[0].y - a[1])
                                      - (b[1] - a[1]) * (vertex[0].x - a[0]))
                result = []
                if not polygon:
                    break
                for previous, current in zip(polygon[-1:] + polygon[:-1], polygon):
                    dp, dc = distance(previous), distance(current)
                    if (dp >= -1e-9) != (dc >= -1e-9):
                        result.append(interpolate(previous, current, dp / (dp - dc)))
                    if dc >= -1e-9:
                        result.append(current)
                polygon = result
            clean = []
            for point in polygon:
                if not clean or (clean[-1][0] - point[0]).length > 1e-7:
                    clean.append(point)
            if len(clean) > 2 and (clean[0][0] - clean[-1][0]).length < 1e-7:
                clean.pop()
            if len(clean) >= 3:
                patches.append(clean)
                patch_faces.append(triangle.polygon_index)
        if not patches:
            raise ValueError(f'Thunder panel has no fitted surface: {name}')

        if self.fit_profile.get('largest_component_only', False):
            # A front projection can catch a second disconnected surface on a
            # bent cuff or calf. Keep the main shell before registering cutouts;
            # the discarded island must retain its original painted geometry.
            parents = list(range(len(patches)))

            def root(index):
                while parents[index] != index:
                    parents[index] = parents[parents[index]]
                    index = parents[index]
                return index

            for i, patch in enumerate(patches):
                for j in range(i):
                    if any((a[0] - b[0]).length_squared < 1e-12
                           for a in patch for b in patches[j]):
                        parents[root(i)] = root(j)
            areas = Counter()
            for i, patch in enumerate(patches):
                origin = patch[0][0]
                areas[root(i)] += sum((patch[k][0] - origin).cross(patch[k + 1][0] - origin).length
                                     for k in range(1, len(patch) - 1)) * .5
            largest = max(areas, key=areas.get)
            kept = [i for i in range(len(patches)) if root(i) == largest]
            patches = [patches[i] for i in kept]
            patch_faces = [patch_faces[i] for i in kept]
        for face_index in patch_faces:
            cut = (outline, direction)
            cuts = self.cutouts.setdefault(face_index, [])
            if cut not in cuts:
                cuts.append(cut)

        # Cut the source patches at the authored crest before lifting them.
        # A per-vertex bump on an arbitrary source triangle makes a lumpy cap;
        # this explicit edge gives each side a readable hard-surface facet,
        # while retaining the original UV seams and bone interpolation.
        ridge_axis = 1 if material == 2 else 0
        ridge_min = min(point[ridge_axis] for point in outline)
        ridge_max = max(point[ridge_axis] for point in outline)
        ridge_center = (ridge_min + ridge_max) * .5
        if bulge > .0001 and 'abdomen rib' not in name:
            split_patches = []
            for polygon in patches:
                for sign in (-1, 1):
                    half = []
                    for previous, current in zip(polygon[-1:] + polygon[:-1], polygon):
                        dp = (previous[0][ridge_axis] - ridge_center) * sign
                        dc = (current[0][ridge_axis] - ridge_center) * sign
                        if (dp >= -1e-9) != (dc >= -1e-9):
                            half.append(interpolate(previous, current, dp / (dp - dc)))
                        if dc >= -1e-9:
                            half.append(current)
                    if len(half) >= 3:
                        split_patches.append(half)
            patches = split_patches

        points, weights, edge_counts, oriented = {}, {}, Counter(), {}
        keyed = []
        for polygon in patches:
            keys, uvs = [], []
            for point, uv, influences in polygon:
                # UV-seam copies can straddle a rounded coordinate boundary.
                # Match by distance so interior triangle seams cannot acquire
                # duplicate vertical walls or bright raised bevel ridges.
                key = next((existing_key for existing_key, existing_point in points.items()
                            if (existing_point - point).length_squared < 1e-12), None)
                if key is None:
                    key = len(points)
                    points[key] = point
                    strongest = dict(sorted(influences.items(), key=lambda pair: pair[1], reverse=True)[:4])
                    total = sum(strongest.values())
                    weights[key] = {group: weight / total for group, weight in strongest.items() if weight > 0}
                keys.append(key)
                uvs.append(uv)
            # A clipped sliver narrower than the seam tolerance can collapse
            # during welding; discard it instead of constructing a zero-area
            # face or using the same BMesh vertex twice in one polygon.
            unique = []
            seen = set()
            for key, uv in zip(keys, uvs):
                if key not in seen:
                    unique.append((key, uv))
                    seen.add(key)
            if len(unique) < 3:
                continue
            keys, uvs = map(list, zip(*unique))
            keyed.append((keys, uvs))
        # Original UV islands can triangulate the same geometric edge into
        # different spans. Make those T-junctions explicit before finding the
        # perimeter, otherwise an internal seam acquires a tall navy wall.
        connected = []
        for keys, uvs in keyed:
            expanded_keys, expanded_uvs = [], []
            for i, (a, b) in enumerate(zip(keys, keys[1:] + keys[:1])):
                segment = points[b] - points[a]
                length_sq = segment.length_squared
                cuts = [(0.0, a)]
                if length_sq > 1e-12:
                    for key, point in points.items():
                        if key in (a, b):
                            continue
                        t = (point - points[a]).dot(segment) / length_sq
                        if 1e-6 < t < 1 - 1e-6 and (point - points[a] - segment * t).length_squared < 1e-12:
                            cuts.append((t, key))
                for t, key in sorted(cuts):
                    expanded_keys.append(key)
                    expanded_uvs.append(uvs[i].lerp(uvs[(i + 1) % len(uvs)], t))
            connected.append((expanded_keys, expanded_uvs))
        keyed = connected
        for keys, uvs in keyed:
            for i, (a, b) in enumerate(zip(keys, keys[1:] + keys[:1])):
                edge = tuple(sorted((a, b)))
                edge_counts[edge] += 1
                inside_uv = sum(uvs, Vector((0.0, 0.0))) / len(uvs)
                oriented[edge] = (a, b, uvs[i], uvs[(i + 1) % len(uvs)], inside_uv)
        # At a shoulder's side/top or a boot's instep the fitted front-facing
        # triangles end before the authored polygon. Blend into that boundary
        # than treating this arbitrary projection limit as a decorative rim.
        soft_boundaries = []
        if 'abdomen rib' not in name:
            for edge, count in edge_counts.items():
                if count != 1:
                    continue
                start, end = (points[key] for key in edge)
                midpoint = (start + end) * .5
                on_outline = False
                for a, b in zip(outline, outline[1:] + outline[:1]):
                    a, b = Vector((a[0], a[1])), Vector((b[0], b[1]))
                    span = b - a
                    t = max(0.0, min(1.0, (Vector((midpoint.x, midpoint.y)) - a).dot(span) / span.length_squared))
                    if (Vector((midpoint.x, midpoint.y)) - a - span * t).length < .00002:
                        on_outline = True
                        break
                if not on_outline:
                    soft_boundaries.append((start, end))

        def boundary_blend(point):
            if not self.fit_profile.get('blend_source_boundaries', True):
                return 1.0
            result = 1.0
            for a, b in soft_boundaries:
                span = b - a
                t = max(0.0, min(1.0, (point - a).dot(span) / max(span.length_squared, 1e-12)))
                result = min(result, (point - a - span * t).length / .018)
            return result
        center = sum(points.values(), Vector()) / len(points)
        # Each plate is a broad manufactured surface rather than a lifted copy
        # of the coarse recovered triangles. Retain enough source curvature to
        # fit the moving joints, and make the angular crest the primary break.
        flatten = self.fit_profile.get('flatten', {1: .12, 2: .15, 3: .18, 4: .25}[material])
        if 'abdomen rib' in name:
            flatten = 0.0
        xyz = list(points.values())
        normal_matrix = Matrix(((sum(p.x*p.x for p in xyz), sum(p.x*p.y for p in xyz), sum(p.x for p in xyz)),
                                (sum(p.x*p.y for p in xyz), sum(p.y*p.y for p in xyz), sum(p.y for p in xyz)),
                                (sum(p.x for p in xyz), sum(p.y for p in xyz), len(xyz))))
        coefficients = normal_matrix.inverted_safe() @ Vector((sum(p.x*p.z for p in xyz),
                                                                sum(p.y*p.z for p in xyz),
                                                                sum(p.z for p in xyz)))
        def plane_z(point):
            return coefficients.x * point.x + coefficients.y * point.y + coefficients.z
        clear_plane = max(direction * (p.z - plane_z(p)) for p in xyz)
        flare = 0.0
        if material == 2:
            flare = .009 if 'crown' in name else (.007 if 'middle' in name else .004)
        base, lip, cap = {}, {}, {}
        for key, point in points.items():
            # Use the requested inset instead of clipping every plate to the
            # same tiny bevel. This creates a visible sloping face between the
            # dark side wall and the painted armor, without growing its outline.
            edge_blend = boundary_blend(point)
            # A fitted painted lip has a small highlight, not a wide blue
            # border that outlines the whole chest or forearm like a ribbon.
            bevel_width = bevel * (.58 if material in (1, 3) else .78)
            inset = (center - point) * min(bevel_width, .09) * edge_blend
            inset.z = 0
            cap_point = point + inset
            cap_point.z = point.z * (1 - flatten) + (plane_z(point) + direction * clear_plane) * flatten
            ridge = max(0.0, 1.0 - abs(point[ridge_axis] - ridge_center)
                        / max((ridge_max - ridge_min) * .5, .0001))
            cap_point.z += direction * (height + bulge * ridge)
            cap_point.z = point.z + (cap_point.z - point.z) * edge_blend
            lift_limit = self.fit_profile.get('max_lift', 0.0)
            if lift_limit > 0:
                cap_point.z = point.z + direction * max(0.0, min(lift_limit, direction * (cap_point.z - point.z)))
            if flare:
                cap_point.x += (1 if point.x > 0 else -1) * flare * max(0.0, (abs(point.x) - .28) / .34) * edge_blend
            base[key] = self.vertex(point + Vector((0, 0, direction * .0007 * edge_blend)), weights[key])
            lip_point = point.copy()
            # The chamfer follows the cap profile. A fixed source-depth lip
            # turned oblique shoulder surfaces into long vertical dark bars.
            lip_point.z = cap_point.z - direction * max(height * .35, .004) * edge_blend
            lip[key] = self.vertex(lip_point, weights[key])
            cap[key] = self.vertex(cap_point, weights[key])
        for keys, uvs in keyed:
            self.face(tuple(cap[key] for key in keys), uvs, paint)
            self.face(tuple(base[key] for key in reversed(keys)), tuple(reversed(uvs)), wall_material)
        for edge, count in edge_counts.items():
            if count != 1:
                continue
            a, b, ua, ub, inside_uv = oriented[edge]
            if boundary_blend(points[a]) < .0001 and boundary_blend(points[b]) < .0001:
                continue
            self.face((base[a], base[b], lip[b], lip[a]), (ua, ub, ub, ua), wall_material)
            # Keep the actual atlas finish on the chamfer. Sample a tiny strip
            # toward this source triangle's interior, so padding or neighboring
            # UV islands cannot become a new stripe across the armor edge.
            uv_inset = inside_uv - (ua + ub) * .5
            if uv_inset.length > .000001:
                uv_inset *= min(.002, uv_inset.length * .06) / uv_inset.length
            bevel_uv = (ua + uv_inset, ub + uv_inset, ub, ua)
            self.face((lip[a], lip[b], cap[b], cap[a]), bevel_uv,
                      10 if 'abdomen rib' in name else paint)
        self.panels.append(name)

    def finish(self):
        self._replace_covered_source()
        # The recovered mesh includes deliberately wound disconnected closure
        # faces. Recalculating them flips inner shoulders/knee closures; keep
        # their original winding and orient only the new closed shell volumes.
        bmesh.ops.recalc_face_normals(self.bm, faces=[face for face in self.bm.faces
                                                    if face not in self.original_faces])
        self.bm.normal_update()
        self.bm.to_mesh(self.obj.data)
        self.obj.data.update()
        self.bm.free()

    def _replace_covered_source(self):
        """Remove the old painted patch underneath each new closed shell.

        Leaving both painted surfaces visible along a raised rim doubles gold
        stripes during bent-arm poses. Exact UV triangle subtraction leaves the
        untouched outside paint and lets the navy shell backing close the cut.
        """
        mesh = self.obj.data
        mesh.calc_loop_triangles()
        triangles = [triangle for triangle in mesh.loop_triangles
                     if triangle.polygon_index in self.cutouts]
        removed = [self.original_face_order[index] for index in self.cutouts]
        self.original_faces.difference_update(removed)
        bmesh.ops.delete(self.bm, geom=removed, context='FACES_ONLY')

        def blend(a, b, t):
            influences = {group: a[2].get(group, 0) * (1 - t) + b[2].get(group, 0) * t
                          for group in set(a[2]) | set(b[2])}
            return a[0].lerp(b[0], t), a[1].lerp(b[1], t), influences

        def half_plane(polygon, a, b, winding, keep_inside):
            def distance(vertex):
                value = winding * ((b[0] - a[0]) * (vertex[0].y - a[1])
                                   - (b[1] - a[1]) * (vertex[0].x - a[0]))
                return value if keep_inside else -value
            result = []
            if not polygon:
                return result
            for previous, current in zip(polygon[-1:] + polygon[:-1], polygon):
                dp, dc = distance(previous), distance(current)
                if (dp >= -1e-10) != (dc >= -1e-10):
                    result.append(blend(previous, current, dp / (dp - dc)))
                if dc >= -1e-10:
                    result.append(current)
            clean = []
            for point in result:
                if not clean or (clean[-1][0] - point[0]).length > 1e-7:
                    clean.append(point)
            if len(clean) > 2 and (clean[0][0] - clean[-1][0]).length < 1e-7:
                clean.pop()
            if len(clean) < 3:
                return []
            normal = sum((a[0].cross(b[0]) for a, b in zip(clean, clean[1:] + clean[:1])), Vector())
            return clean if normal.length > 1e-10 else []

        for triangle in triangles:
            original_poly = mesh.polygons[triangle.polygon_index]
            fragments = [[(mesh.vertices[index].co.copy(), mesh.uv_layers.active.data[loop].uv.copy(),
                           {g.group: g.weight for g in mesh.vertices[index].groups if g.weight > 0})
                          for index, loop in zip(triangle.vertices, triangle.loops)]]
            for outline, direction in self.cutouts[triangle.polygon_index]:
                if triangle.normal.z * direction < .12:
                    continue
                area = sum(a[0] * b[1] - b[0] * a[1]
                           for a, b in zip(outline, outline[1:] + outline[:1]))
                winding = 1 if area > 0 else -1
                outside = []
                for fragment in fragments:
                    remainder = fragment
                    for a, b in zip(outline, outline[1:] + outline[:1]):
                        piece = half_plane(remainder, a, b, winding, False)
                        if piece:
                            outside.append(piece)
                        remainder = half_plane(remainder, a, b, winding, True)
                        if not remainder:
                            break
                fragments = outside
            for polygon in fragments:
                vertices, uvs = [], []
                for point, uv, influences in polygon:
                    weights = dict(sorted(influences.items(), key=lambda item: item[1], reverse=True)[:4])
                    total = sum(weights.values())
                    vertices.append(self.vertex(point, {group: weight / total for group, weight in weights.items() if weight > 0}))
                    uvs.append(uv)
                face = self.face(vertices, uvs, original_poly.material_index)
                face.smooth = original_poly.use_smooth
                self.original_faces.add(face)

def _side(points, side):
    return [(x * side, y) for x, y in points]

def _fit_rear_collar(obj):
    """Tuck the recovered rear collar corners beneath the shoulder crown.

    Those tall rear body triangles look like separate fins in the rifle idle
    pose. Lower only the upper outer collar; keep its existing closed faces,
    UV islands, and skin influences rather than cutting a hole at the neck.
    """
    body_vertices = {index for face in obj.data.polygons if face.material_index == 1
                     for index in face.vertices}
    for index in body_vertices:
        point = obj.data.vertices[index].co
        if point.y <= 1.30 or point.z <= .115 or abs(point.x) >= .29:
            continue
        side_blend = max(0.0, min(1.0, (abs(point.x) - .06) / .07))
        point.y -= (point.y - 1.30) * .72 * side_blend
    obj.data.update()


def _body(shells):
    for side in (-1, 1):
        # Chest tabs tuck under the upper breastplate. Preserve the exposed
        # ribbed abdomen and its original small yellow vertical markers.
        shells.panel(f'{side} lower breastplate', 1, _side([
            (.012, 1.122), (.110, 1.151), (.163, 1.093),
            (.145, 1.024), (.014, .988),
        ], side), height=.029, bevel=.090, bulge=.010)
        shells.panel(f'{side} chest side guard', 1, _side([
            (.147, 1.139), (.234, 1.163), (.242, 1.086),
            (.213, 1.030), (.155, 1.042),
        ], side), height=.024, bevel=.085, bulge=.006)
        shells.panel(f'{side} upper breastplate', 1, _side([
            (.007, 1.239), (.098, 1.257), (.152, 1.292),
            (.225, 1.240), (.233, 1.162), (.113, 1.137), (.010, 1.163),
        ], side), height=.024, bevel=.075, bulge=.010)
        # Wide overlapping shoulder lames; the original joint remains beneath.
        shells.panel(f'{side} shoulder lower tier', 2, _side([
            (.292, 1.179), (.454, 1.195), (.568, 1.120),
            (.544, 1.080), (.390, 1.066), (.302, 1.087),
        ], side), height=.022, bevel=.070, bulge=.009)
        shells.panel(f'{side} shoulder middle tier', 2, _side([
            (.287, 1.289), (.438, 1.287), (.597, 1.180),
            (.548, 1.146), (.429, 1.134), (.291, 1.178),
        ], side), height=.027, bevel=.075, bulge=.011)
        shells.panel(f'{side} shoulder crown tier', 2, _side([
            (.279, 1.388), (.397, 1.379), (.508, 1.311),
            (.543, 1.271), (.438, 1.244), (.286, 1.286),
        ], side), height=.030, bevel=.080, bulge=.010)
        shells.panel(f'{side} shoulder rear lower', 2, _side([
            (.294, 1.222), (.463, 1.238), (.563, 1.150),
            (.535, 1.090), (.352, 1.079), (.300, 1.128),
        ], side), height=.016, bevel=.035, back=True)
        shells.panel(f'{side} shoulder rear crown', 2, _side([
            (.282, 1.372), (.405, 1.365), (.532, 1.277),
            (.479, 1.233), (.296, 1.265),
        ], side), height=.021, bevel=.035, back=True)
        # The hip and thigh panels belong to ArmorBody in the original rig.
        shells.panel(f'{side} upper thigh side plate', 1, _side([
            (.178, .802), (.255, .830), (.287, .705),
            (.267, .627), (.177, .644),
        ], side), height=.018, bevel=.045)
        shells.panel(f'{side} lower thigh side plate', 1, _side([
            (.183, .635), (.274, .641), (.281, .521),
            (.251, .437), (.186, .467),
        ], side), height=.020, bevel=.055)
        for index, y in enumerate((.886, .912, .938, .964)):
            shells.panel(f'{side} abdomen rib {index}', 1, _side([
                (.119, y), (.164, y + .014), (.163, y + .021), (.118, y + .007),
            ], side), height=.0035, bevel=.015)
    shells.panel('pelvic shield', 1, [
        (0, .866), (.142, .777), (.112, .697), (0, .642),
        (-.112, .697), (-.142, .777),
    ], height=.025, bevel=.045, bulge=.004)

def _arms(shells):
    for side in (-1, 1):
        # Keep the angled upper edge/gold stripe and overlap the smaller cuff.
        shells.panel(f'{side} forearm main shell', 3, _side([
            (.418, .850), (.550, .903), (.566, .832),
            (.544, .752), (.480, .747), (.445, .789),
        ], side), height=.019, bevel=.075, bulge=.009)
        shells.panel(f'{side} forearm wrist cuff', 3, _side([
            (.467, .745), (.550, .751), (.565, .667),
            (.492, .643), (.463, .682),
        ], side), height=.014, bevel=.085, bulge=.004)
        shells.panel(f'{side} forearm rear shell', 3, _side([
            (.435, .847), (.552, .905), (.567, .827),
            (.545, .741), (.465, .751),
        ], side), height=.012, bevel=.065, back=True, bulge=.005)

def _legs(shells):
    for side in (-1, 1):
        # Broad, layered shin plates tuck beneath angular knee frames.
        shells.panel(f'{side} broad shin shield', 4, _side([
            (.083, .347), (.153, .379), (.245, .347),
            (.278, .258), (.244, .169), (.160, .145), (.087, .213),
        ], side), height=.030, bevel=.080, bulge=.015)
        shells.panel(f'{side} knee frame', 4, _side([
            (.086, .419), (.128, .464), (.223, .455),
            (.259, .397), (.231, .342), (.123, .345),
        ], side), height=.052, bevel=.105, bulge=.007)
        shells.panel(f'{side} greave lower overlap', 4, _side([
            (.111, .239), (.227, .235), (.248, .183),
            (.218, .145), (.111, .148), (.090, .191),
        ], side), height=.030, bevel=.085, bulge=.007)
        shells.panel(f'{side} rear calf shell', 4, _side([
            (.102, .401), (.220, .408), (.263, .328),
            (.239, .184), (.116, .173), (.087, .301),
        ], side), height=.018, bevel=.055, back=True)
        # Keep the toe cap separate from the shin so the ankle can articulate.
        shells.panel(f'{side} boot toe cap', 4, _side([
            (.094, .106), (.225, .109), (.273, .050),
            (.251, .027), (.080, .027), (.065, .051),
        ], side), height=.014, bevel=.090, bulge=.006)

def refine_body(obj, material_slots):
    """Refit one original part using the common eleven material slots."""
    if len(material_slots) != MATERIAL_COUNT:
        raise ValueError('Thunder body expects eleven material slots')
    if obj.get('thunder_raised_plates', False):
        raise ValueError('refine_body must run once per fresh source mesh')
    if obj.name.startswith('ArmorBody_06'):
        source_map, author = {0: 1, 1: 2}, _body
    elif obj.name.startswith('ArmorHand_06'):
        source_map, author = {0: 3}, _arms
    elif obj.name.startswith('ArmorFoot_06'):
        source_map, author = {0: 4}, _legs
    else:
        raise ValueError(f'Unsupported Thunder part: {obj.name}')
    old_materials = [p.material_index for p in obj.data.polygons]
    if set(old_materials) - source_map.keys():
        raise ValueError(f'Unexpected source material layout: {obj.name}')
    obj.data.materials.clear()
    for material in material_slots:
        obj.data.materials.append(material)
    for poly, old in zip(obj.data.polygons, old_materials):
        poly.material_index = source_map[old]
    if obj.name.startswith('ArmorBody_06'):
        _fit_rear_collar(obj)
    original_vertices = len(obj.data.vertices)
    shells = _Shells(obj)
    try:
        author(shells)
        names = shells.panels[:]
        shells.finish()
    except Exception:
        if shells.bm.is_valid:
            shells.bm.free()
        raise
    obj['thunder_raised_plates'] = len(names)
    obj['thunder_original_vertices'] = original_vertices
    obj['thunder_plate_approach'] = 'Closed chamfered shells with authored split crests; source UV cutouts and original skin weights'
    obj['thunder_shell_names'] = names
    return obj
