"""Fit C09 narrow blunt crown rails and its simpler open face to the source cage.

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
    ax = abs(x)
    front = clamp((-z - .12) / .14)
    lower = clamp((1.53 - y) / .314) * front
    yy = y + .100 * lower
    zz = z + .030 * lower
    center = clamp((.20 - ax) / .20)
    # The original center brow is a deep downward chevron. Raise that lip,
    # including its adjacent edge vertices, rather than merely painting over
    # the V. This opens the single continuous glass and flattens its top edge.
    brow = bump(y, 1.60, .14) * clamp((-z - .24) / .10) * center
    yy += .040 * brow
    # Flatten the lowest central eyebrow tip to the neighboring glass corners.
    # Keep this lift above the lower visor/chin, retaining one thin brow bevel.
    yy += .047 * bump(y, 1.445, .065) * center * front
    # Suppress the forward beak while retaining a broad shallow face window.
    zz += .045 * bump(y, 1.59, .18) * center * front
    # Narrow the broad side forehead plates from BOTH boundaries. Inner rail
    # edges move outward; outer edges move inward. The continuous field acts
    # on coincident seam copies identically and leaves the lower cheek alone.
    rail = clamp((y - 1.63) / .10) * clamp((.08 - z) / .16)
    rail *= clamp((ax - .02) / .04)
    lateral = max(-1.0, min(1.0, (.16 - ax) / .085))
    xx = x + math.copysign(1.0, x) * .050 * lateral * rail if ax > 1e-6 else x
    # Lower the blunt rail peaks and the intervening roof together. The mask
    # includes the front roof, avoiding a tall central ridge between low rails.
    crown = clamp((y - 1.74) / .18) * clamp((z + .32) / .16)
    yy -= .080 * crown
    # Source center vertices 6/118/68/9 form three differently sloped V faces.
    # Place this front board on one shallow curved plane instead of retaining
    # those recesses. The side rail outer faces and the cloth neck are outside
    # the mask. All masks use original coordinates, never the previous build.
    board = clamp((-z - .21) / .025) * clamp((.21 - ax) / .055)
    board *= clamp((y - 1.440) / .005)
    # The closely spaced rear edge of the single brow bevel must stay behind
    # its front lip. Projecting both onto the board reverses that thin face.
    bevel_back = clamp((z + .32) / .012) * clamp((1.525 - y) / .020)
    bevel_back *= clamp((ax - .04) / .030)
    board *= 1.0 - bevel_back
    board_z = -.240 + .340 * (yy - 1.803) + .800 * xx * xx
    zz += (board_z - zz) * board
    # Round the existing lateral ear outline in its Y/Z plane. This is a
    # compact faceted shell, not a new floating disk or additional topology.
    ear = clamp((ax - .14) / .09)
    ear *= clamp((y - 1.50) / .05) * clamp((1.85 - y) / .04)
    ear *= clamp((z + .08) / .04) * clamp((.22 - z) / .04)
    ey, ez = y - 1.665, z - .075
    radius = math.hypot(ey, ez)
    if radius > .112:
        scale = .112 / radius
        yy += ey * (scale - 1.0) * ear
        zz += ez * (scale - 1.0) * ear
    return [xx, yy, zz]


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
        # Compress its long lower pentagonal plate from the lower edge; do not
        # push the entire slot up into the black neck as the earlier fit did.
        z += .020 * chest * center
        y += .032 * bump(y, 1.035, .085) * front * center
        # The concept's outer thigh shell reaches nearly to the knee. Stretch
        # the actual lower shell edge, leaving the hip attachment fixed. Use
        # original y for this field so no offset is stacked on another fit.
        thigh = clamp((.76 - point[1]) / .34) * clamp((point[1] - .30) / .10)
        thigh *= clamp((-point[2] - .02) / .06) * clamp((abs(x) - .075) / .10)
        y -= .065 * thigh
    return [x, y, z]
