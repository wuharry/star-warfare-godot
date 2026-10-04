"""Original-source head-only local deformation, approved concept reference.

UV/topology/skin are untouched. Monotone front height remap enlarges the
visor and shortens its lower trim while the original rest joints stay fixed.
"""

def interpolate(value, knots):
    if value<knots[0][0] or value>knots[-1][0]:return value
    for (a,b),(c,d) in zip(knots,knots[1:]):
        if a<=value<=c:return b+(d-b)*(value-a)/(c-a)
    return value

def reshape(point, surface_id=0):
    x,y,z=point
    weight=min(1.0,max(0.0,(-z-.15)/.15))
    mapped=interpolate(y,KNOTS)
    return [x,y+(mapped-y)*weight,z]

KNOTS=[(1.26, 1.26), (1.2994, 1.335), (1.456, 1.475), (1.4898, 1.506), (1.7002, 1.762), (1.8473, 1.864), (1.94, 1.94)]
