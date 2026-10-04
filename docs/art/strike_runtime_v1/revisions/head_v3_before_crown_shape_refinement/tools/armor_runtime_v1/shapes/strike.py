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

KNOTS=[(1.25, 1.25), (1.2829, 1.3), (1.3917, 1.402), (1.4915, 1.46), (1.6086, 1.66), (1.6139, 1.665), (1.697, 1.705), (1.7991, 1.807), (1.9, 1.9)]
