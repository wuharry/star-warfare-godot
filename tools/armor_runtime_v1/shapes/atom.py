"""Fit C08 to the true original rest-space cage without accumulating offsets.

The broad visor, compact round guard and upright shoulder wedges are physical
changes. Atlas art supplies the crown strip, cheek windows and service lights.
Indices, UVs, weights, skin and the original neck/limb seam positions are inputs
only; no new topology or bindings are introduced. Front is physical -Z.
"""
import math


def clamp(value: float) -> float:
    return min(1.0, max(0.0, value))


def bump(value: float, center: float, radius: float) -> float:
    return clamp(1.0 - abs(value - center) / radius)


def reshape(point, surface_id=0):
    x, y, z = point
    xx, yy, zz = x, y, z

    # Round the front AND side lower guard. The prior front-only gate left
    # the two low cheek corners hanging below the shortened central chin.
    guard_front = max(clamp((-z - .10) / .12),
                      clamp((abs(x) - .13) / .065) * clamp((.005 - z) / .08))
    lower = clamp((1.51 - y) / .25) * guard_front
    yy += .073 * lower
    zz += .028 * lower
    xx -= math.copysign(.012 * lower * clamp((abs(x) - .07) / .14), x)

    # The painted cyan window actually occupies the lower front UV chart,
    # not the purple forehead points above it. Open that real front band;
    # a new atlas may extend glass upward without moving any UV coordinates.
    face = clamp((-z - .14) / .14)
    face_band = clamp((y - 1.38) / .065) * clamp((1.70 - y) / .10)
    yy += .22 * (y - 1.485) * face_band * face

    # The same original six-point ear rim stays nearly round in side view;
    # the metal disc is painted on that actual cap, never the rear chart.
    ear = clamp((abs(x) - .225) / .040)
    ear *= clamp((y - 1.51) / .025) * clamp((1.72 - y) / .025)
    ear *= clamp((z + .14) / .025) * clamp((.175 - z) / .025)
    xx -= math.copysign(.012 * ear, x)
    yy += ((y - 1.605) * .15 + .005) * ear
    zz -= (z - .025) * .30 * ear

    # Fit the existing upper rings to one smooth ellipsoidal cap rather
    # than shaving only the center apex into a flat, angular roof.
    cap = clamp((y - 1.73) / .10)
    radius = max(0.0, 1.0 - (x / .30) ** 2 - ((z + .025) / .36) ** 2)
    cap_y = 1.665 + .215 * math.sqrt(radius)
    yy += (cap_y - y) * cap
    return [xx, yy, zz]


def reshape_part(part_name, point, surface_id=0):
    if part_name == 'ArmorHead_07':
        return reshape(point, surface_id)
    x, y, z = point
    if part_name != 'ArmorBody_07':
        return list(point)
    if surface_id == 0 and abs(x) > .33 and y > 1.36:
        # Transform the WHOLE original plate, including its actual mount at
        # |X|=.365,Y=1.391. Rotating only |X|>.46 made an L-shaped antenna:
        # that left its long horizontal mount unchanged. One affine frame
        # gives a continuous short thick wedge from mount through tip.
        dx, dy = abs(x) - .365, y - 1.391
        original_axis = math.radians(21.4)
        along = dx * math.cos(original_axis) + dy * math.sin(original_axis)
        across = -dx * math.sin(original_axis) + dy * math.cos(original_axis)
        angle = math.radians(52)
        ax = .435 + .78 * along * math.cos(angle) - 2.5 * across * math.sin(angle)
        yy = 1.391 + .78 * along * math.sin(angle) + 2.5 * across * math.cos(angle)
        zz = z - .020 * clamp(along / .24)
        return [math.copysign(ax, x), yy, zz]
    if surface_id == 1:
        # A compact raised middle-chest service spine, independent of the
        # collar. Its light must be painted at the correct chest UV location.
        front = clamp((-z - .10) / .12)
        chest = bump(y, 1.10, .22) * front
        center = clamp((.14 - abs(x)) / .14)
        z -= .018 * chest * center
    return [x, y, z]
