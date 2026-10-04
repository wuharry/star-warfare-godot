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
    result=[x,y+(mapped-y)*weight,z]
    # The original forehead ledge rises and then falls by about49mm at the
    # crown-rail join. Move existing coincident points together, never add
    # topology, UV or a new hard seam. These coordinates are true source
    # rest positions, so the deformation is not stacked onto an earlier pass.
    for source_y,source_z,crown_y in CROWN_POINTS:
        if abs(y-source_y)<.00002 and abs(z-source_z)<.00002:
            result[1]=crown_y
            break
    return result

KNOTS=[(1.25, 1.25), (1.2829, 1.3), (1.3917, 1.402), (1.4915, 1.46), (1.6086, 1.66), (1.6139, 1.665), (1.697, 1.705), (1.7991, 1.807), (1.9, 1.9)]

CROWN_POINTS=[
    (1.82627,-.32964,1.806),  # Front ledge: remove the tall raised plate.
    (1.80057,-.26465,1.806),  # Existing ledge return, matched to front cap.
    (1.77714,-.25936,1.812),  # Crown root: remove the downward step.
    (1.79906,-.28203,1.840),  # Existing center point rounds the front crown.
]
