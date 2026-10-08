"""Atom first integration retains every true-original head position.

Its selected design is transferred through the five original UV atlases.
No deformation, topology refinement or UV callback is authorized here.
"""


def reshape(point, surface_id=0):
    return list(point)
