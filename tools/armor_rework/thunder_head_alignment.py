"""Fit the existing Thunder A helmet toward the later C-07 head reference.

Apply once AFTER the current SW2/head authoring, in its Y-up, -Z-forward local
coordinates. This module does not load Blender/Godot, create geometry, change
UVs or touch material assignments, normals, bones or weights. The body stays
outside its scope. Side/rear crest depth is inferred from one quarter view;
these dimensions are engineering fits, not measurements of concept identity.
The 20% envelope is relative to the current A helmet supplied by the caller.
"""
import math


BROW_LIFT = .090
CHIN_LIFT = .085
CHIN_COMPRESSION = .25
INTAKE_NARROWING = .30
INTAKE_RECESS = .030
CROWN_FRONT_DROP = .020
CROWN_BACK_LIFT = .010
CROWN_SWEEP = .012
CROWN_RIDGE_LIFT = .035
CROWN_RIDGE_SWEEP = .020
GEOMETRY_LIMIT = .20


def _smoothstep(low, high, value):
    t = max(0.0, min(1.0, (value-low)/(high-low)))
    return t*t*(3.0-2.0*t)


def deform(point, material_id=None):
    """Return one fitted point; shared material/UV borders use the same field.

    The material argument is accepted for callers that enumerate per-corner
    material IDs, but intentionally does not select a different deformation.
    Evaluating one field at physical position avoids opening glass/frame or
    respirator material seams. Five-decimal keys give mirrored/source seam
    duplicates the same displacement while retaining their original tiny gap.
    """
    px, py, pz = point
    x, y, z = round(abs(px), 5), round(py, 5), round(pz, 5)
    front = _smoothstep(.10, .23, -z)
    centre = 1.0-_smoothstep(.035, .19, x)
    # Lift the old deep central V toward the higher temple corners. The
    # original brow/visor border moves together and retains a slight centre dip.
    brow = (_smoothstep(1.37, 1.50, y)
            * (1.0-_smoothstep(1.56, 1.79, y))*front*centre)
    # Raise the entire lower visor/cheek border toward the horizontal brow,
    # rather than making the glass taller by lifting only its upper edge.
    # The broad x falloff keeps the adjacent lower cheek/jaw pieces together;
    # the rear neck socket stays at its previous position.
    chin = (_smoothstep(1.24, 1.29, y)
            * (1.0-_smoothstep(1.40, 1.50, y))
            * _smoothstep(.075, .145, -z)
            * (1.0-_smoothstep(.14, .29, x)))
    # Keep the existing sealed intake as a small flush insert. Broad smooth
    # depth transitions preserve the thin source mount faces and closed caps.
    intake = (_smoothstep(1.24, 1.28, y)
              * (1.0-_smoothstep(1.42, 1.50, y))
              * (1.0-_smoothstep(.045, .085, x))
              * _smoothstep(.10, .18, -z))
    crown = (_smoothstep(1.73, 1.86, y)
             * (1.0-_smoothstep(.035, .115, x)))
    crown_front = _smoothstep(-.02, .22, -z)
    ridge = (_smoothstep(1.76, 1.86, y)
             * (1.0-_smoothstep(.035, .085, x)))
    dx = -x*INTAKE_NARROWING*intake
    if abs(px) <= .000005:
        dx = 0.0
    elif px < 0:
        dx = -dx
    dy = (BROW_LIFT*brow
          + (CHIN_LIFT+CHIN_COMPRESSION*(1.35-y))*chin
          + (CROWN_BACK_LIFT
             - (CROWN_BACK_LIFT+CROWN_FRONT_DROP)*crown_front)*crown
          + CROWN_RIDGE_LIFT*ridge)
    # Raising this narrow old crest without its backward movement reverses
    # thin rear roof faces. The coupled sweep keeps all original faces valid.
    dz = INTAKE_RECESS*intake+CROWN_SWEEP*crown+CROWN_RIDGE_SWEEP*ridge
    return [px+dx, py+dy, pz+dz]


def align_positions(points, triangles=None):
    """Fit the caller's head positions and reject an invalid geometry result.

    Pass the original triangle vertex indices to also check every face normal.
    The caller retains all other mesh arrays and recomputes affected normals.
    """
    before = [list(point) for point in points]
    after = [deform(point) for point in before]
    measure_alignment(before, after, triangles)
    return after


def measure_alignment(before, after, triangles=None):
    """Measure against this round's current A head, never an enlarged baseline."""
    if not before or len(before) != len(after):
        raise ValueError('Thunder alignment requires the unchanged head vertex count')
    if any(len(point) != 3 or not all(math.isfinite(v) for v in point)
           for points in (before, after) for point in points):
        raise ValueError('Thunder alignment has invalid positions')
    bounds = lambda points: [[min(p[i] for p in points), max(p[i] for p in points)]
                             for i in range(3)]
    old, new = bounds(before), bounds(after)
    spans = [high-low for low, high in old]
    normalizer = min(spans)
    if normalizer <= 0:
        raise ValueError('Thunder alignment baseline has a zero-size axis')
    displacement = max(math.dist(a, b) for a, b in zip(before, after))/normalizer
    dimensions = [abs((high-low)/span-1.0)
                  for (low, high), span in zip(new, spans)]
    if displacement > GEOMETRY_LIMIT or max(dimensions) > GEOMETRY_LIMIT:
        raise ValueError('Thunder alignment exceeds the current-head 20% envelope')
    report = {
        'vertices': len(after), 'bounds_before': old, 'bounds_after': new,
        'normalizer_smallest_before_axis': normalizer,
        'max_displacement_fraction': displacement,
        'dimension_delta_fractions': dimensions,
        'geometry_limit': GEOMETRY_LIMIT,
        'triangle_normal_check': 'NOT RUN',
    }
    if triangles is None:
        return report
    cosines = []
    for triangle in triangles:
        if len(triangle) != 3 or any(i < 0 or i >= len(before) for i in triangle):
            raise ValueError('Thunder alignment has invalid triangle indices')
        old_normal = _normal([before[i] for i in triangle])
        new_normal = _normal([after[i] for i in triangle])
        old_size, new_size = math.dist(old_normal, [0, 0, 0]), math.dist(new_normal, [0, 0, 0])
        if old_size <= 1e-12 or new_size <= 1e-12:
            raise ValueError('Thunder alignment has a degenerate source or fitted triangle')
        cosine = sum(a*b for a, b in zip(old_normal, new_normal))/(old_size*new_size)
        if cosine <= 0:
            raise ValueError('Thunder alignment reverses a current-head face normal')
        cosines.append(cosine)
    report.update({'triangle_normal_check': 'PASS', 'triangles': len(cosines),
                   'minimum_parent_normal_cosine': min(cosines) if cosines else None})
    return report


def _normal(points):
    a, b, c = points
    u, v = [x-y for x, y in zip(b, a)], [x-y for x, y in zip(c, a)]
    return [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
