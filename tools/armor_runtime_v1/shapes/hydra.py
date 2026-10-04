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

KNOTS=[(1.24, 1.24), (1.2673, 1.338), (1.4, 1.414), (1.4431, 1.430), (1.4553, 1.444), (1.5018, 1.505), (1.5706, 1.64), (1.574, 1.643), (1.591, 1.658), (1.65, 1.684), (1.6985, 1.704), (1.8371, 1.8371), (1.9, 1.9)]
