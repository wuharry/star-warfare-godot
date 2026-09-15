"""Narrowed trapezoid face opening fitted to the original prototype shell.

Blue cheek plates define the aperture in geometry. The gold surface tapers
from a 0.41 m brow to a 0.086 m chin; it is not a recolour of a broad visor.
"""
import math
from mathutils import Vector
from thunder_prototype import _grid_shell, _dome


def _width(t):
    return .205*(1-t)+.043*t


def _point(s,t):
    x=s*_width(t)
    top=1.590+.052*abs(s)
    bottom=1.362+.018*abs(s)**2
    y=top*(1-t)+bottom*t
    z=-.025-.342*math.sqrt(max(.01,1-(x/.274)**2))
    return (x,y,z)


def _uv(s,t):
    # Sample the actual SW2 amber island, mirrored at the center seam.
    # Both side grooves remain inset within their own half of the aperture.
    rows=[(.0,.848,.935,.633),(.25,.823,.975,.707),
          (.50,.808,.937,.793),(.75,.791,.872,.884),(1.,.790,.821,.949)]
    for a,b in zip(rows,rows[1:]):
        if a[0]<=t<=b[0]:
            q=(t-a[0])/(b[0]-a[0])
            left=a[1]+(b[1]-a[1])*q
            right=a[2]+(b[2]-a[2])*q
            v=a[3]+(b[3]-a[3])*q
            return (left+(right-left)*abs(s),1-v)


def create_face(owner,materials):
    pieces=[]
    rows=[[_point(-1+2*c/40,r/20) for c in range(41)] for r in range(21)]
    glass=_grid_shell(owner,'Narrow trapezoid engraved aperture',rows,14,materials,.009)
    for polygon in glass.data.polygons:
        # The closed glass edge/back is plain amber. Only its front has the
        # engraved UV island; shell walls have no usable tangent-map UV area.
        if any(index >= 21*41 for index in polygon.vertices):
            polygon.material_index = 8
    for loop in glass.data.loops:
        index=loop.vertex_index%(21*41)
        glass.data.uv_layers.active.data[loop.index].uv=_uv(-1+2*(index%41)/40,(index//41)/20)
    pieces.append(glass)
    # Five strips across each side make a true inner lip, broad central plane,
    # outer bevel and attachment wall. The inner edge exactly hugs the glass.
    for side in [-1,1]:
        for section,(lo,hi) in enumerate([(0,.33),(.335,.665),(.67,1)]):
            plates=[]
            samples=[lo,lo+.009]+[lo+(hi-lo)*r/7 for r in range(1,7)]+[hi-.009,hi]
            for r,t in enumerate(samples):
                inner=Vector(_point(side,t))
                outer_x=.266*(1-t)+.109*t
                outer_y=inner.y-.004-.017*t
                outer_z=-.025-.342*math.sqrt(max(.01,1-(outer_x/.280)**2))+.024
                outer=Vector((side*outer_x,outer_y,outer_z))
                row=[]
                for q,lift in [(0,.002),(.07,.006),(.18,.014),(.82,.014),(1.,.0)]:
                    p=inner.lerp(outer,q)
                    p.z-=lift*(.35 if r in [0,len(samples)-1] else 1)
                    row.append(tuple(p))
                plates.append(row)
            cheek=_grid_shell(owner,f'Inward wrapping blue cheek {side} {section}',plates,5,materials,.021,False)
            for polygon in cheek.data.polygons:
                if polygon.index < (len(samples)-1)*4*2 and polygon.index % 8 == 0:
                    polygon.material_index = 7
            pieces.append(cheek)
        brow=[]
        for band in range(4):
            row=[]
            for c in range(17):
                s=side*(.21+.79*c/16)
                p=Vector(_point(s,0))
                # The diagonal rail sits above a narrow eye band, while the
                # inherited central crown drops down over its inner end.
                if band == 0:
                    phi=math.asin(p.x/.263)
                    theta=math.radians(78+6*math.sin(phi)**2)
                    p=_dome(theta,phi)
                    p.y+=.008
                    p.z+=.004
                else:
                    p.y += [.0,.018,.001,-.006][band]
                    p.z += [.0,-.002,-.007,.0][band]
                row.append(tuple(p))
            brow.append(row)
        rail=_grid_shell(owner,f'Diagonal brow bevel {side}',brow,5,materials,.016,True)
        for polygon in rail.data.polygons:
            if 32 <= polygon.index < 64 and polygon.index % 2 == 0:
                polygon.material_index=7
        pieces.append(rail)
    return pieces
