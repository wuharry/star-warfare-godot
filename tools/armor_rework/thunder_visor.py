"""Expand the paired Thunder visor while preserving its engraved source UVs.

The V3 prototype had a wide wraparound amber face. The SW2 shell supplies the
better panel topology, but its visor is substantially narrower and recessed.
Apply a continuous deformation to the connected front shell, so the visor and
its shared brow/cheek boundaries move together without opening seams.
"""
from collections import defaultdict


def _smoothstep(low, high, value):
    t = max(0.0, min(1.0, (value - low) / (high - low)))
    return t * t * (3.0 - 2.0 * t)


def _main_shell_indices(source):
    """Find the connected shell, excluding the two independent ear housings."""
    positions = source['positions_game']
    parent = list(range(len(positions)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def join(a, b):
        parent[find(a)] = find(b)

    duplicates = {}
    for index, position in enumerate(positions):
        key = tuple(round(value, 5) for value in position)
        if key in duplicates:
            join(index, duplicates[key])
        else:
            duplicates[key] = index
    for submesh in source['submeshes']:
        for face in submesh:
            join(face[0], face[1])
            join(face[0], face[2])
    groups = defaultdict(set)
    for index in range(len(positions)):
        groups[find(index)].add(index)
    return max(groups.values(), key=len)


def expand_visor(vertices, source):
    """Mutate Y-up/-Z-forward vertices and return all changed vertex indices.

    This runs before the independent crown and respirator adjustments. The
    bottom jaw rim and the entire original rear are fixed. The lower glass
    becomes a rounded wraparound arc; the upper diagonal brow is retained.
    Existing triangles, UVs and vertex ordering are deliberately unchanged.
    Callers recompute split normals only for the returned deformation region.
    """
    positions = source['positions_game']
    if len(vertices) != len(positions):
        raise ValueError('Thunder visor deformation requires the paired source vertex order')
    shell = _main_shell_indices(source)
    changed = set()
    # Quantized source positions make all UV/hard-normal duplicates receive
    # exactly the same result, including mirrored center-line duplicates.
    results = {}
    for index in sorted(shell):
        p = positions[index]
        if p[2] >= -.012 or p[1] <= 1.315 or p[1] >= 1.865:
            continue
        key = tuple(round(value, 5) for value in p)
        if key not in results:
            x, y, z = key
            front = _smoothstep(.012, .055, -z)
            rise = _smoothstep(1.37, 1.50, y)
            # A broader opening thins the thick inward cheek frame. Width
            # peaks at the visor and blends away through the lower forehead.
            width = rise * (1.0 - _smoothstep(1.68, 1.83, y))
            spread = 1.0 + .20 * width * front
            new_x = x * spread
            # Smooth spatial fields retain the continuous lower rail. Mapping
            # the few original corner vertices individually made that rail
            # wavy and turned curved texture grooves into sharp zigzags.
            brow = _smoothstep(1.44, 1.54, y) * (1.0 - _smoothstep(1.65, 1.865, y))
            brow_depth = max(_smoothstep(.065, .17, -z), _smoothstep(1.56, 1.62, y))
            lift = .095 * brow * brow_depth
            central = 1.0 - _smoothstep(.09, .19, abs(x))
            lower = _smoothstep(1.315, 1.39, y) * (1.0 - _smoothstep(1.45, 1.53, y))
            lower_drop = .041 * lower * central
            side = _smoothstep(.10, .15, abs(x)) * (1.0 - _smoothstep(.19, .23, abs(x)))
            side *= _smoothstep(1.44, 1.50, y) * (1.0 - _smoothstep(1.56, 1.625, y))
            side *= 1.0 - _smoothstep(.085, .145, -z)
            new_y = y + (lift - lower_drop - .045 * side) * front
            vertical = rise * (1.0 - _smoothstep(1.62, 1.865, y))
            # The visor stays behind the brow, but gains a little convexity
            # instead of reading as a deep hollow under the central ridge.
            recess = 1.0 - _smoothstep(.205, .255, -z)
            bulge = .018 * vertical * front * recess
            # Raising the original forward crest alone creates a cap brim.
            # Ease its high front back into the crown's rounded envelope.
            retreat = .075 * _smoothstep(1.68, 1.86, new_y) * _smoothstep(.23, .325, -z)
            results[key] = (new_x, new_y, z - bulge + retreat)
            # The tiny source nose is an attached hard-surface box. Translate
            # it as a block with the rounded opening instead of warping its
            # top/back/front faces into each other; the replacement housing
            # subsequently encloses it. Include every welded UV duplicate.
            if abs(x) < .046 and 1.375 <= y <= 1.433 and -.225 <= z <= -.17:
                results[key] = (x * 1.03, y - .039, z - .004)
        new = results[key]
        if max(abs(new[axis] - p[axis]) for axis in range(3)) > 1e-6:
            for axis in range(3):
                vertices[index][axis] = new[axis]
            changed.add(index)
    return changed
