"""Fit the approved C08 silhouette to the original rest-space cage.

All offsets are calculated from true original positions, never the last build.
Keep original indices, UVs and bindings. Front is -Z; physical seam duplicates
receive the same continuous deformation. Side/back forms are inferred from
the quarter-view concept and separately checked against the 20% budget.
"""
import math


def clamp(value):
    return min(1.0, max(0.0, value))


def bump(value, center, radius):
    return clamp(1.0 - abs(value - center) / radius)


def reshape(point, surface_id=0):
    x, y, z = point
    front = clamp((-z - .10) / .12)
    lower = clamp((1.53 - y) / .26) * front
    # Short lower guard and a shallower glass V; leave the cloth neck alone.
    yy = y + .086 * lower
    zz = z + .035 * lower
    xx = x
    # The legacy side cap is almost twice as long as tall. Its six original
    # rim points become a near-circular, thicker ear plate without new UVs.
    ear = clamp((abs(x) - .225) / .040)
    ear *= clamp((y - 1.51) / .025) * clamp((1.72 - y) / .025)
    ear *= clamp((z + .14) / .025) * clamp((.175 - z) / .025)
    xx -= math.copysign(.012 * ear, x)
    yy += ((y - 1.605) * .15 + .005) * ear
    zz -= (z - .025) * .30 * ear
    crown = bump(y, 1.8955, .145) * clamp((.22 - abs(x)) / .22)
    yy -= .026 * crown
    return [xx, yy, zz]


def reshape_part(part_name, point, surface_id=0):
    if part_name == 'ArmorHead_07':
        return reshape(point, surface_id)
    x, y, z = point
    if part_name != 'ArmorBody_07':
        return list(point)
    if surface_id == 0 and abs(x) > .46 and y > 1.40:
        # Shorten along the fin and widen its far end into a blunt wedge.
        # Uniform rotation alone made a thin hook. Local thickness scales
        # continuously from the root and stays within the true-source budget.
        dx, dy = abs(x) - .48, y - 1.42
        along = (2 * dx + dy) / math.sqrt(5)
        across = (-dx + 2 * dy) / math.sqrt(5)
        angle = math.atan2(1, 2) + math.radians(15)
        thickness = 1 + 2 * clamp(along / .12)
        ax = .48 + .65 * along * math.cos(angle) - thickness * across * math.sin(angle)
        yy = 1.42 + .65 * along * math.sin(angle) + thickness * across * math.cos(angle)
        zz = z - .020 * clamp(along / .15)
        return [math.copysign(ax, x), yy, zz]
    if surface_id == 1:
        front = clamp((-z - .10) / .12)
        chest = bump(y, 1.13, .24) * front
        # Separate the central service spine from the broader chest cheeks.
        center = clamp((.13 - abs(x)) / .13)
        y += .022 * chest * center
        z += .018 * chest * center
    return [x, y, z]
