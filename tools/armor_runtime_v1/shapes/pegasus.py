"""Fit C09 low crown rails, shallow face and compact chin to the original cage.

Coordinates are true original game rest positions. No topology, UV or rig
changes; no stacking offsets onto an intermediate build.
"""
import math


def clamp(value):
    return min(1.0, max(0.0, value))


def bump(value, center, radius):
    return clamp(1.0 - abs(value - center) / radius)


def reshape(point, surface_id=0):
    x, y, z = point
    front = clamp((-z - .12) / .14)
    lower = clamp((1.53 - y) / .314) * front
    yy = y + .090 * lower
    zz = z + .030 * lower
    # Suppress the forward beak while retaining a wide continuous visor.
    zz += .026 * bump(y, 1.59, .18) * clamp((.20 - abs(x)) / .20) * front
    # Both rail peaks AND the intervening center must drop. Lowering only
    # the peaks leaves an equally misleading triangular central crown.
    crown = clamp((y - 1.77) / .153) * clamp((z + .22) / .06)
    yy -= .070 * crown
    return [x, yy, zz]


def reshape_part(part_name, point, surface_id=0):
    if part_name == 'ArmorHead_08':
        return reshape(point, surface_id)
    x, y, z = point
    if part_name != 'ArmorBody_08':
        return list(point)
    if surface_id == 1:
        # Retain stacked shoulder topology while softening its outer point.
        outside = clamp((abs(x) - .42) / .115)
        x -= math.copysign(.021 * outside, x)
        y += .022 * outside * bump(y, 1.25, .15)
    else:
        front = clamp((-z - .10) / .13)
        chest = bump(y, 1.16, .19) * front
        center = clamp((.15 - abs(x)) / .15)
        # A shallow central recess carries the concept's dark service slot.
        z += .020 * chest * center
        y += .018 * chest * center
        # Extend the original outer thigh plates, retaining their weights.
        thigh = bump(y, .60, .23) * front * clamp((abs(x) - .10) / .12)
        y -= .030 * thigh
    return [x, y, z]
