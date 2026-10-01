"""Build concept-derived modular armor on the game's unchanged bind pose.

Blender --background --python tools/armor_concept_runtime/build.py -- --ids=11
The concept's long body is deliberately NOT a dimensional authority: Harvey
requires the original in-game proportions. Armor shell dimensions are inferred
around measured original bones; color and panel identity come from the art.
"""
from __future__ import annotations

import hashlib
import json
import math
import runpy
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "docs/art/original_armors_v1"
OUT = ROOT / "test_output/armor_concept_runtime"
NATIVE = ROOT / "docs/art/armor_runtime_v1"
IDS = (0, 1, 2, 3, 4, 5, 7, 8, 9, 11)
REVISION = "concept_armor_chibi_v1"
PREFIXES = ("ArmorHead_", "ArmorBody_", "ArmorHand_", "ArmorFoot_")
# Thunder already has a concept-authored rigged model and its selected helmet.
# Phoenix and every set after Cygni must retain the existing game assets.


def linear(c: float) -> float:
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def color(hex_color: str, role: float = .4) -> tuple[float, ...]:
    return (*[linear(int(hex_color[i:i+2], 16) / 255) for i in (1, 3, 5)], role)


class Part:
    """Closed fitted components, consolidated into one skinned equipment part."""

    def __init__(self, name: str):
        self.name = name
        self.vertices: list[tuple] = []
        self.faces: list[tuple] = []
        self.colors: list[tuple] = []
        self.weights: list[dict] = []
        self.components: list[str] = []

    def add(self, name, vertices, faces, tint, bone):
        offset = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.faces.extend(tuple(offset+i for i in f) for f in faces)
        self.colors.extend([tint] * len(vertices))
        self.weights.extend([dict(bone) if isinstance(bone, dict) else {bone: 1.0}
                             for _ in vertices])
        self.components.append(name)

    def plate(self, name, outline, z, depth, tint, bone, bevel=.008):
        """Chamfered closed polygon; bevel width is inferred from gameplay size."""
        cx = sum(p[0] for p in outline) / len(outline)
        cy = sum(p[1] for p in outline) / len(outline)
        n = len(outline)
        inner = []
        for x, y in outline:
            v = Vector((cx-x, cy-y))
            v.normalize()
            inner.append((x+v.x*bevel, y+v.y*bevel))
        verts = [(x, y, z+depth) for x, y in outline]
        verts += [(x, y, z+bevel) for x, y in outline]
        verts += [(x, y, z) for x, y in inner]
        faces = [tuple(reversed(range(n)))]
        for ring in range(2):
            for i in range(n):
                j = (i+1) % n
                faces.append((ring*n+i, ring*n+j, (ring+1)*n+j, (ring+1)*n+i))
        # Blender triangulates the actual concave boundary (T visors / U rails).
        # A center fan would incorrectly fill the empty corners of a T.
        faces.append(tuple(range(2*n,3*n)))
        self.add(name, verts, faces, tint, bone)

    def loft(self, name, rings, tint, bone, count=12):
        """Y-up ellipsoidal cross-sections, all radii in original game units."""
        vertices = []
        for x, y, z, rx, rz in rings:
            for i in range(count):
                a = 2*math.pi*i/count
                vertices.append((x+rx*math.sin(a), y, z+rz*math.cos(a)))
        faces = [tuple(reversed(range(count)))]
        for r in range(len(rings)-1):
            for i in range(count):
                j = (i+1) % count
                faces.append((r*count+i, r*count+j, (r+1)*count+j, (r+1)*count+i))
        faces.append(tuple(range((len(rings)-1)*count, len(rings)*count)))
        self.add(name, vertices, faces, tint, bone)

    def tube(self, name, a, b, r1, r2, tint, bone, count=12):
        a, b = Vector(a), Vector(b)
        axis = (b-a).normalized()
        cross = axis.cross(Vector((0, 0, 1)))
        if cross.length < .01:
            cross = axis.cross(Vector((0, 1, 0)))
        cross.normalize()
        other = axis.cross(cross).normalized()
        rings = [(a, r1*.88), (a+(b-a)*.10, r1),
                 (a+(b-a)*.85, r2), (b, r2*.88)]
        verts = [p+(cross*math.cos(i*math.tau/count)+other*math.sin(i*math.tau/count))*r
                 for p, r in rings for i in range(count)]
        faces = [tuple(reversed(range(count)))]
        for k in range(3):
            for i in range(count):
                j = (i+1)%count
                faces.append((k*count+i, k*count+j, (k+1)*count+j, (k+1)*count+i))
        faces.append(tuple(range(3*count, 4*count)))
        self.add(name, verts, faces, tint, bone)

    def disc(self, name, center, radius, tint, bone, axis=2, ring=False):
        # Circular connectors are physical rings, not painted circles.
        c = Vector(center)
        axes = [i for i in range(3) if i != axis]
        count = 20
        verts = []
        radii = [radius, radius*.80, radius*.75, radius*.75] if ring else [radius, radius*.82, .002, .002]
        for layer, r in enumerate(radii):
            for i in range(count):
                p = c.copy()
                p[axis] += [0, -.005, -.006, .008][layer]
                p[axes[0]] += r*math.cos(i*math.tau/count)
                p[axes[1]] += r*math.sin(i*math.tau/count)
                verts.append(p)
        faces = []
        for k in range(4):
            k2 = (k+1)%4
            for i in range(count):
                j = (i+1)%count
                faces.append((k*count+i, k*count+j, k2*count+j, k2*count+i))
        self.add(name, verts, faces, tint, bone)

    def object(self, rig, collection):
        mesh = bpy.data.meshes.new(self.name+"_mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        uv = mesh.uv_layers.new(name="UVMap")
        colors = mesh.color_attributes.new(name="ArmorColor", type="FLOAT_COLOR", domain="CORNER")
        for loop in mesh.loops:
            v = mesh.vertices[loop.vertex_index]
            uv.data[loop.index].uv = (v.co.x*1.6+.5, v.co.y*.5)
            colors.data[loop.index].color = self.colors[loop.vertex_index]
        groups = {n: obj.vertex_groups.new(name=n)
                  for n in sorted({n for w in self.weights for n in w})}
        for index, w in enumerate(self.weights):
            for name, weight in w.items():
                groups[name].add([index], weight, "REPLACE")
        mod = obj.modifiers.new("Original player skeleton", "ARMATURE")
        mod.object = rig
        obj["armor_rework"] = REVISION
        obj["components"] = json.dumps(self.components)
        return obj


def palette(design, armor_id):
    values = [p["hex"] for p in design["palette"]]
    first, second = values[:2]
    visor = next((p["hex"] for p in design["palette"] if "玻璃" in p["family"]), "#26333c")
    accents = {0: "#20252D", 1: "#6B8397", 2: "#93AD84", 3: "#9EAD66",
               4: "#52C7CE", 5: "#D79037", 7: "#58CDD0", 8: "#517EA8",
               9: "#68727B", 11: "#BA7D57"}
    if armor_id == 4 or armor_id == 7:
        visor = accents[armor_id]
    return {"paint": color(first), "secondary": color(second),
            "accent": color(accents[armor_id], .90 if armor_id in (4, 7) else .4),
            "glass": color(visor, .72), "cloth": color("#171E25", .08),
            "edge": color("#85939D", .55), "dark": color("#26323C", .4)}


def helmet(part, p, armor_id):
    bone = "Bip01 Head"
    # Measured baseline: head bounds Y 1.236..1.912, width .518, depth .660.
    # Ring placements/cheek shapes inferred to fit that game-sized envelope.
    wide = 1.04 if armor_id in (2, 5, 8) else 1.0
    part.loft("sealed crown and nape", [(0,1.26,.035,.13,.16), (0,1.35,.025,.22*wide,.235),
              (0,1.57,.020,.259*wide,.29), (0,1.73,.035,.245*wide,.255),
              (0,1.85,.045,.185*wide,.205), (0,1.90,.045,.085,.10),
              (0,1.912,.045,.024,.03)], p["paint"], bone, 24)
    part.loft("flexible neck seal", [(0,1.20,.03,.105,.105),(0,1.36,.03,.11,.11)], p["cloth"], bone, 16)
    for s in (-1,1):
        part.disc("ear coupling", (s*.255,1.58,.012),.09,p["dark"],bone,axis=0)
        part.disc("ear face", (s*.266,1.58,.012),.062,p["secondary"],bone,axis=0)
    if armor_id == 9:
        # Draco has a metal face shield and a physical narrow sight slit.
        part.plate("opaque shield face", [(-.22,1.67),(.22,1.67),(.19,1.52),(.08,1.34),
                    (0,1.31),(-.08,1.34),(-.19,1.52)],-.322,.07,p["secondary"],bone)
        part.plate("recessed sight slit", [(-.215,1.678),(.215,1.678),(.205,1.659),(-.205,1.659)],
                   -.338,.012,p["cloth"],bone,bevel=.003)
        part.plate("central shield ridge", [(-.026,1.655),(.026,1.655),(.045,1.40),(0,1.34),(-.045,1.40)],
                   -.345,.035,p["paint"],bone,bevel=.005)
    else:
        if armor_id == 11:
            # Selected T identity, tapered oblique cheeks, no square jaw blocks.
            outline = [(-.231,1.69),(.231,1.69),(.226,1.603),(.077,1.596),(.047,1.385),
                       (-.047,1.385),(-.077,1.596),(-.226,1.603)]
        elif armor_id == 2:
            outline = [(-.226,1.70),(.226,1.70),(.222,1.56),(.09,1.45),(0,1.50),(-.09,1.45),(-.222,1.56)]
        elif armor_id == 5:
            outline = [(-.20,1.80),(.20,1.80),(.233,1.63),(.17,1.42),(0,1.36),(-.17,1.42),(-.233,1.63)]
        elif armor_id == 1:
            outline = [(-.23,1.67),(.23,1.67),(.218,1.565),(0,1.54),(-.218,1.565)]
        elif armor_id in (4,7):
            outline = [(-.23,1.66),(.23,1.66),(.19,1.52),(.055,1.455),(0,1.48),(-.055,1.455),(-.19,1.52)]
        elif armor_id == 8:
            outline = [(-.224,1.67),(.224,1.67),(.17,1.56),(0,1.49),(-.17,1.56)]
        else:
            outline = [(-.223,1.68),(.223,1.68),(.215,1.53),(.115,1.43),(-.115,1.43),(-.215,1.53)]
        part.plate("visor gasket", [(x*1.045,1.57+(y-1.57)*1.065) for x,y in outline],
                   -.321,.025,p["cloth"],bone,bevel=.004)
        part.plate("single continuous visor", outline,-.334,.020,p["glass"],bone,bevel=.005)
        brow = p["secondary"] if armor_id in (1,2,3) else p["paint"]
        top = 1.80 if armor_id == 5 else (1.70 if armor_id == 2 else 1.69)
        part.plate("layered brow", [(-.245,top+.025),(-.15,top+.07),(.15,top+.07),
                   (.245,top+.025),(.234,top),(-.234,top)],-.345,.055,brow,bone)
        for s in (-1,1):
            inner = .055 if armor_id == 11 else (.075 if armor_id in (4,7) else .105)
            points = [(s*.24,1.57),(s*(inner+.018),1.52),(s*inner,1.38),
                      (s*.16,1.33),(s*.228,1.41)]
            part.plate("swept cheek enclosure",points,-.353,.09,p["paint"],bone,bevel=.009)
            part.plate("oblique cheek intake",[(s*.18,1.46),(s*.206,1.49),(s*.19,1.41),(s*.16,1.38)],
                       -.364,.008,p["cloth"],bone,bevel=.003)
        chin_width = .069 if armor_id in (4,7,11) else .115
        part.plate("short closed chin",[(-chin_width,1.375),(chin_width,1.375),(.06,1.305),(-.06,1.305)],
                   -.335,.09,p["paint"],bone)
    if armor_id in (0,1,2,3,4,7,8):
        part.plate("crown spine",[(-.05,1.895),(.05,1.895),(.075,1.75),(-.075,1.75)],
                   -.18,.08,p["cloth"] if armor_id == 0 else p["secondary"],bone)
    if armor_id == 3:
        part.plate("forehead device frame",[(-.064,1.80),(.064,1.80),(.064,1.733),(-.064,1.733)],
                   -.29,.04,p["accent"],bone)
        part.plate("forehead device recess",[(-.041,1.785),(.041,1.785),(.041,1.745),(-.041,1.745)],
                   -.303,.009,p["cloth"],bone,bevel=.003)
    if armor_id in (4,7):
        for x,y in [(-.09,1.80),(0,1.875),(.09,1.80)]:
            part.disc("crown status light",(x,y,-.245),.018,p["accent"],bone)
    if armor_id in (8,11):
        for s in (-1,1):
            part.plate("short swept helmet wing",[(s*.215,1.78),(s*.345,1.82),(s*.295,1.715),(s*.235,1.70)],
                       .00,.08,p["paint"],bone)
    if armor_id == 11:
        part.plate("dark brow seam",[(-.16,1.758),(.16,1.758),(.13,1.739),(-.13,1.739)],
                   -.29,.012,p["secondary"],bone,bevel=.003)
        for s in (-1,1):
            part.plate("helmet copper cheek latch",[(s*.178,1.432),(s*.21,1.455),(s*.208,1.412),(s*.177,1.392)],
                       -.365,.006,p["accent"],bone,bevel=.003)


def body(part, p, armor_id):
    spine, pelvis = "Bip01 Spine1", "Bip01 Pelvis"
    part.loft("flexible torso",[(0,.77,.02,.215,.13),(0,.94,.00,.24,.16),
              (0,1.20,.01,.29,.175),(0,1.35,.03,.18,.12)],p["cloth"],spine)
    part.loft("soft waist and pelvis",[(0,.65,.02,.195,.135),(0,.82,.025,.225,.145),
              (0,.89,.00,.21,.135)],p["cloth"],pelvis)
    part.loft("pressure collar",[(0,1.31,.025,.155,.13),(0,1.36,.025,.165,.14)],
              p["accent"] if armor_id in (2,3) else p["paint"],spine,16)
    # Chest plates split into two floating panels, leaving a flexible waist.
    for s in (-1,1):
        if armor_id == 11:
            chest=[(s*.045,1.30),(s*.255,1.31),(s*.27,1.13),(s*.15,1.035),(s*.06,1.065)]
        elif armor_id in (1,5):
            chest=[(s*.032,1.315),(s*.245,1.31),(s*.275,1.17),(s*.21,1.075),(s*.045,1.07)]
        elif armor_id in (3,4,7):
            chest=[(s*.05,1.315),(s*.225,1.29),(s*.282,1.19),(s*.205,1.075),(s*.05,1.11)]
        else:
            chest=[(s*.018,1.32),(s*.25,1.29),(s*.285,1.15),(s*.18,1.045),(s*.018,1.08)]
        part.plate("floating pectoral shell",chest,-.21,.070,p["paint"],spine)
        if armor_id == 11:
            part.plate("green chest insert",[(s*.078,1.284),(s*.209,1.283),
                       (s*.229,1.172),(s*.155,1.105),(s*.101,1.143)],
                       -.231,.012,p["secondary"],spine,bevel=.005)
        if armor_id in (0,5,9):
            part.plate("chest service aperture",[(s*.11,1.27),(s*.23,1.25),(s*.213,1.14),(s*.13,1.17)],
                       -.229,.008,p["cloth"],spine)
        if armor_id in (1,11):
            part.plate("U frame chest rail",[(s*.09,1.34),(s*.135,1.33),(s*.19,1.13),(s*.085,1.08),(s*.07,1.12),(s*.13,1.17)],
                       -.238,.021,p["secondary"] if armor_id == 1 else p["paint"],spine)
        if armor_id == 2:
            part.plate("sage blast collar",[(s*.11,1.36),(s*.25,1.37),(s*.235,1.26),(s*.115,1.265)],
                       -.222,.05,p["accent"],spine)
        # Shoulder harness straps and sockets are body-owned, matching the game.
        part.plate("shoulder harness strap",[(s*.215,1.37),(s*.258,1.37),(s*.268,1.27),(s*.23,1.24)],
                   -.17,.030,p["secondary"],spine)
        arm_bone=f"Bip01 {'L' if s<0 else 'R'} UpperArm"
        thigh_bone=f"Bip01 {'L' if s<0 else 'R'} Thigh"
        width=.155 if armor_id in (2,5,8,9) else .137
        part.loft("rounded shoulder underplate",[(s*.375,1.13,.045,width*.65,.12),
                  (s*.39,1.25,.045,width,.165),(s*.375,1.385,.04,width*.88,.155),
                  (s*.35,1.425,.04,width*.48,.10)],p["paint"],arm_bone)
        shoulder_top=p["cloth"] if armor_id==0 else p["paint"]
        part.plate("shoulder face cap",[(s*.29,1.355),(s*.41,1.395),(s*.515,1.31),
                   (s*.51,1.235),(s*.40,1.20),(s*.30,1.245)],-.126,.085,shoulder_top,arm_bone)
        if armor_id == 11:
            part.plate("green shoulder recess",[(s*.32,1.332),(s*.404,1.365),(s*.481,1.31),
                       (s*.478,1.256),(s*.404,1.229),(s*.327,1.26)],-.145,.01,p["secondary"],arm_bone)
            part.plate("copper shoulder fitting",[(s*.416,1.361),(s*.449,1.342),(s*.439,1.313),(s*.405,1.331)],
                       -.159,.010,p["accent"],arm_bone,bevel=.003)
        if armor_id in (2,3,5):
            part.plate("contrasting shoulder lip",[(s*.29,1.34),(s*.40,1.38),(s*.535,1.32),
                       (s*.53,1.275),(s*.40,1.32),(s*.295,1.29)],-.14,.025,p["accent"],arm_bone)
        if armor_id in (7,8,11):
            part.plate("short shoulder blade",[(s*.36,1.42),(s*.56,1.405),
                       (s*.50,1.335),(s*.39,1.33)],.01,.060,p["paint"],arm_bone)
        part.tube("upper-arm fabric",(s*.385,1.25,.06),(s*.443,.98,.06),.092,.080,p["cloth"],arm_bone)
        part.plate("upper-arm shield",[(s*.35,1.195),(s*.47,1.175),(s*.485,1.07),(s*.405,1.025),(s*.345,1.07)],
                   -.068,.05,p["paint"],arm_bone)
        if armor_id == 11:
            part.plate("green upper arm facet",[(s*.37,1.17),(s*.458,1.15),(s*.457,1.095),(s*.397,1.065)],
                       -.08,.009,p["secondary"],arm_bone,bevel=.004)
        # Thigh belongs to BODY in the existing modular SW skeleton/mesh contract.
        part.tube("thigh fabric",(s*.145,.76,.00),(s*.17,.40,-.016),.118,.102,p["cloth"],thigh_bone)
        part.plate("thigh hard shell",[(s*.075,.72),(s*.235,.75),(s*.295,.60),
                   (s*.25,.43),(s*.10,.435),(s*.04,.58)],-.129,.052,p["paint"],thigh_bone)
        if armor_id in (1,2,3,7,8,11):
            part.plate("contrasting thigh outer rail",[(s*.24,.75),(s*.281,.66),(s*.292,.48),
                       (s*.254,.45),(s*.248,.59),(s*.213,.72)],-.147,.026,p["secondary"],thigh_bone)
        part.plate("pelvic side plate",[(s*.155,.87),(s*.265,.82),(s*.255,.745),(s*.13,.765)],
                   -.13,.050,p["paint"],pelvis)
        if armor_id == 11:
            part.plate("copper thigh latch",[(s*.145,.695),(s*.20,.711),(s*.212,.674),(s*.157,.655)],
                       -.151,.010,p["accent"],thigh_bone,bevel=.004)
    for k in range(3):
        y=1.04-k*.073
        part.plate("abdominal articulated plate",[(-.155,y),(.155,y),(.13,y-.052),
                   (0,y-.072),(-.13,y-.052)],-.185+.022*k,.043,p["paint"],spine)
    if armor_id in (3,4,7,11):
        tint=p["accent"] if armor_id!=4 else color("#DDB44A",.55)
        part.plate("chest identity fitting",[(-.052,1.27),(.052,1.27),(.041,1.15),
                   (0,1.13),(-.041,1.15)],-.242,.023,tint,spine)
    part.plate("belt buckle",[(-.058,.885),(.058,.885),(.058,.81),(-.058,.81)],-.17,.030,p["secondary"],pelvis)
    part.plate("pelvic guard",[(-.102,.81),(.102,.81),(.08,.69),(0,.65),(-.08,.69)],-.145,.045,p["paint"],pelvis)
    # Back armor follows the turnaround; the independent backpack is not fused.
    part.plate("back thoracic shell",[(-.225,1.31),(.225,1.31),(.24,1.13),(.13,1.01),(-.13,1.01),(-.24,1.13)],
               .215,-.055,p["paint"],spine)


def limbs(arms, legs, p, armor_id, original_hand):
    for s in (-1,1):
        side="L" if s<0 else "R"
        forearm=f"Bip01 {side} Forearm"
        calf=f"Bip01 {side} Calf"
        foot=f"Bip01 {side} Foot"
        arms.tube("elbow flex joint",(s*.442,.99,.060),(s*.459,.89,.042),.075,.079,p["cloth"],forearm)
        arms.tube("fitted forearm shell",(s*.459,.935,.05),(s*.488,.735,.02),.098,.073,p["paint"],forearm)
        arms.plate("chamfered forearm guard",[(s*.395,.925),(s*.48,.957),(s*.55,.86),
                   (s*.55,.766),(s*.455,.741),(s*.409,.79)],-.066,.045,
                   p["secondary"] if armor_id in (1,7) else p["paint"],forearm)
        arms.plate("wrist rim",[(s*.423,.785),(s*.545,.785),(s*.547,.754),(s*.427,.737)],
                   -.076,.033,p["secondary"],forearm,bevel=.005)
        legs.tube("calf flexible core",(s*.171,.416,-.017),(s*.186,.15,.015),.098,.082,p["cloth"],calf)
        legs.plate("angular kneecap",[(s*.098,.462),(s*.242,.462),(s*.264,.403),
                   (s*.21,.35),(s*.132,.354),(s*.080,.407)],-.122,.040,p["secondary"],calf)
        if armor_id == 11:
            legs.plate("white knee cradle",[(s*.11,.456),(s*.232,.456),(s*.252,.404),
                       (s*.205,.366),(s*.138,.37),(s*.094,.406)],-.136,.007,p["paint"],calf)
            legs.plate("copper knee panel",[(s*.145,.437),(s*.204,.437),(s*.205,.4),(s*.146,.397)],
                       -.148,.009,p["accent"],calf,bevel=.004)
        legs.plate("tapered shin shell",[(s*.099,.345),(s*.247,.345),(s*.267,.26),
                   (s*.235,.137),(s*.14,.12),(s*.087,.24)],-.101,.045,p["paint"],calf)
        legs.plate("shin center facet",[(s*.157,.31),(s*.209,.315),(s*.216,.16),(s*.164,.144)],
                   -.119,.019,p["secondary"] if armor_id in (1,11) else p["paint"],calf,bevel=.004)
        if armor_id == 11:
            for sign in (-1,1):
                x=s*.182+sign*.059
                legs.plate("green calf oblique inlay",[(x-.015,.298),(x+.021,.276),(x+.012,.176),(x-.020,.203)],
                           -.119,.009,p["secondary"],calf,bevel=.003)
        legs.loft("armored boot",[(s*.187,.023,-.09,.12,.235),(s*.187,.06,-.09,.123,.235),
                  (s*.187,.126,-.065,.112,.197),(s*.188,.185,.002,.087,.105)],p["paint"],foot)
        legs.loft("boot sole",[(s*.187,.016,-.09,.122,.237),(s*.187,.045,-.09,.125,.24)],p["cloth"],foot)
        if armor_id in (4,7):
            arms.disc("forearm luminous connector",(s*.47,.858,-.099),.032,p["accent"],forearm,ring=True)
            legs.plate("knee status strips",[(s*.123,.427),(s*.213,.427),(s*.208,.414),(s*.128,.414)],
                       -.142,.006,p["accent"],calf,bevel=.003)
        if armor_id in (8,11):
            arms.plate("forearm inset",[(s*.44,.92),(s*.477,.93),(s*.527,.78),(s*.489,.77)],
                       -.088,.01,p["accent"],forearm,bevel=.003)
    # Reuse only the actual gloved hands, so the weapon sockets and grip do not
    # drift. All forearm shells above were built anew; source use is in manifest.
    source=original_hand.data
    for poly in source.polygons:
        if max(source.vertices[i].co.y for i in poly.vertices) > .750:
            continue
        vertices=[source.vertices[i] for i in poly.vertices]
        offset=len(arms.vertices)
        arms.vertices.extend(tuple(v.co) for v in vertices)
        arms.faces.append(tuple(range(offset,offset+len(vertices))))
        arms.colors.extend([p["cloth"]]*len(vertices))
        for v in vertices:
            groups=sorted([g for g in v.groups if g.weight>0],key=lambda g:g.weight,reverse=True)[:4]
            total=sum(g.weight for g in groups)
            arms.weights.append({original_hand.vertex_groups[g.group].name:g.weight/total for g in groups})
    arms.components.append("retained original glove geometry and grip weights")


def export_json(obj):
    mesh=obj.data
    mesh.calc_loop_triangles()
    attrs={"name":obj.name,"positions":[],"normals":[],"uv":[],"colors":[],"bones":[],"weights":[]}
    for tri in mesh.loop_triangles:
        for loop_index in tri.loops:
            loop=mesh.loops[loop_index]
            v=mesh.vertices[loop.vertex_index]
            attrs["positions"].extend(v.co)
            attrs["normals"].extend(mesh.corner_normals[loop_index].vector.normalized())
            attrs["uv"].extend(mesh.uv_layers.active.data[loop_index].uv)
            attrs["colors"].extend(mesh.color_attributes["ArmorColor"].data[loop_index].color)
            groups=[g for g in v.groups if g.weight>0]
            attrs["bones"].append([obj.vertex_groups[g.group].name for g in groups])
            attrs["weights"].append([g.weight for g in groups])
    return attrs


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    mapping=json.loads((ART/"runtime_mapping.json").read_text())["armor_mappings"]
    requested=next((a.split("=",1)[1] for a in sys.argv if a.startswith("--ids=")),None)
    ids=[int(v) for v in requested.split(",")] if requested else list(IDS)
    if not ids or not set(ids)<=set(IDS):
        raise ValueError(f"Only authorized non-Phoenix armor through Cygni: {IDS}")
    runpy.run_path(str(ROOT/"tools/armor_rework/inspect_source.py"))
    rig=next(o for o in bpy.data.objects if o.type=="ARMATURE")
    source_hand=bpy.data.objects["ArmorHand_00"]
    # Preserve measurement sources but never deliver them accidentally.
    source_hand.name="REF_original_gloves"
    for obj in list(bpy.data.objects):
        if obj.type=="MESH" and obj!=source_hand:
            bpy.data.objects.remove(obj,do_unlink=True)
    rig_collection=bpy.data.collections.new("RIG_DEF")
    bpy.context.scene.collection.children.link(rig_collection)
    for col in list(rig.users_collection):
        col.objects.unlink(rig)
    rig_collection.objects.link(rig)
    ref=bpy.data.collections.new("REF")
    bpy.context.scene.collection.children.link(ref)
    for col in list(source_hand.users_collection):
        col.objects.unlink(source_hand)
    ref.objects.link(source_hand)
    source_hand.hide_render=True
    source_hand.hide_set(True)
    source_hand.data.materials.clear()
    material=bpy.data.materials.new("ArmorVertexPalette")
    material.use_nodes=True
    tree=material.node_tree
    attribute=tree.nodes.new("ShaderNodeVertexColor")
    attribute.layer_name="ArmorColor"
    tree.links.new(attribute.outputs["Color"],tree.nodes.get("Principled BSDF").inputs["Base Color"])
    tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value=.52
    for armor_id in ids:
        low=bpy.data.collections.get("LOW")
        if low:
            for obj in list(low.objects):
                bpy.data.objects.remove(obj,do_unlink=True)
            bpy.data.collections.remove(low)
        low=bpy.data.collections.new("LOW")
        bpy.context.scene.collection.children.link(low)
        row=mapping[armor_id]
        design=json.loads((ART/row["data_file"]).read_text())
        p=palette(design,armor_id)
        parts=[Part(prefix+f"{armor_id:02d}") for prefix in PREFIXES]
        helmet(parts[0],p,armor_id)
        body(parts[1],p,armor_id)
        limbs(parts[2],parts[3],p,armor_id,source_hand)
        objects=[part.object(rig,low) for part in parts]
        for obj in objects:
            obj.data.materials.append(material)
        payload={"revision":REVISION,"id":armor_id,"name":row["legacy_set_name"],
                 "parts":[export_json(obj) for obj in objects]}
        (OUT/f"armor_{armor_id:02d}.json").write_text(json.dumps(payload,separators=(",",":")))
        native=NATIVE/f"armor_{armor_id:02d}"
        native.mkdir(parents=True,exist_ok=True)
        reference=ART/row["images"]["concept"]
        if armor_id==11:
            reference=ART/"revisions/c12_helmet_fusions_20260929/images/anubis_gold_t_swept.png"
        part_stats=[{"name":obj.name,"triangles":len(obj.data.polygons),
                     "vertices":len(obj.data.vertices),"components":part.components,
                     "bounds":[[min(v.co[i] for v in obj.data.vertices),max(v.co[i] for v in obj.data.vertices)] for i in range(3)]}
                    for obj,part in zip(objects,parts)]
        report={"id":armor_id,"name":row["legacy_set_name"],"revision":REVISION,
                "status":"rejected_flat_prototype_do_not_roll_out",
                "reference":str(reference.relative_to(ROOT)),"reference_sha256":hashlib.sha256(reference.read_bytes()).hexdigest(),
                "rig_source":"assets/models/player/animated/player.gltf","rig_changed":False,
                "proportion_authority":"original in-game large head / short body, explicitly chosen by Harvey",
                "inferred":["armor panel depths and bevel widths","back panels hidden by independent backpacks", "concept reshaped around original game skeleton; no 85% fidelity claim"],
                "retained_source":"original glove geometry and skin weights only; existing animations and skeleton",
                "parts":part_stats,"triangles":sum(v["triangles"] for v in part_stats),
                "texture_contract":{"base_color":"linear vertex colors from art palette", "role":"vertex alpha: cloth .08, paint .4, metal .55, glass .72, light .90", "roughness":"runtime shader by role", "normal":"geometric chamfers; no normal map"}}
        (native/"asset-manifest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
        (native/"asset-brief.md").write_text(f"# {row['legacy_set_name']} / original game proportions\n\n"
            f"ASSET CH_{row['legacy_set_name'].replace('.','')}\nCATEGORY modular human-worn armor\n"
            f"VIEWS {report['reference']} + {row['images']['turnaround']}; perspective concept defines shapes, not limb lengths\n"
            "SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912\n"
            "PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates\n"
            "PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots\n"
            f"SILHOUETTE {design['visual_identity']['head']}; {design['visual_identity']['shoulders']}\n"
            f"MATERIALS {design['palette']}\n"
            "ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library\n"
            f"INFERRED {report['inferred']}\nTARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character\n")
        # Native reference uses Y-up to preserve the actual game's attachment
        # coordinates. Generic skill renders expect Z-up: see review.py adapter.
        for action in list(bpy.data.actions):
            bpy.data.actions.remove(action)
        bpy.data.orphans_purge(do_recursive=True)
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(native/"master.blend"),compress=True)
        print("CONCEPT_ARMOR_BUILD",armor_id,report["triangles"],"triangles")


if __name__=="__main__":
    main()
