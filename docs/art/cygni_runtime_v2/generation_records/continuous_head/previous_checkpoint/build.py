"""Reference-sized Cygni prototype; source rig and old limb cages are retained.

The flat colour/lighting images produced here are UV placement guides, not the
delivered diffuse maps. Final painted maps come from the recorded ImageGen run.
"""
import bpy
import bmesh
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "docs/art/cygni_runtime_v2"
OUT = ROOT / "test_output/cygni_runtime_v2"
C = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
PALETTE = {"white": (.60, .62, .59, 1), "green": (.045, .065, .05, 1),
           "black": (.012, .016, .014, 1), "copper": (.32, .13, .04, 1),
           "gold": (.53, .29, .055, 1)}


def emission(name, color):
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    sh = nt.nodes.new("ShaderNodeEmission")
    sh.inputs["Color"].default_value = color
    nt.links.new(sh.outputs[0], out.inputs[0])
    mat.diffuse_color = color
    return mat


def move_collection(ob, name):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    for old in list(ob.users_collection):
        old.objects.unlink(ob)
    col.objects.link(ob)


class Part:
    def __init__(self, name):
        self.name = name
        self.vertices = []
        self.faces = []
        self.weights = []
        self.roles = []
        self.groups = []
        self.source_uv = []
        self.source_materials = []
        self.source_positions = []

    def add(self, verts, faces, role, bone="Bip01 Head", group=""):
        offset = len(self.vertices)
        self.vertices.extend(verts)
        self.weights.extend([{bone: 1.0} for _ in verts])
        self.faces.extend([tuple(i + offset for i in f) for f in faces])
        self.roles.extend([role] * len(faces))
        self.groups.extend([group] * len(faces))
        self.source_uv.extend([None] * len(faces))
        self.source_materials.extend([None] * len(faces))
        self.source_positions.extend(verts)

    def plate(self, xy, role, depth, bone="Bip01 Head", thickness=.012, side=1, group=""):
        # Coordinates are chosen in the original game's Y-up, -Z-front frame.
        front = [(side*x, y, depth(x, y) if callable(depth) else depth) for x, y in xy]
        rear = [(x, y, z + thickness) for x, y, z in front]
        n = len(front)
        faces = [tuple(range(n)), tuple(range(n, 2*n))[::-1]]
        faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
        self.add(front + rear, faces, role, bone, group)

    def object(self, rig):
        mesh = bpy.data.meshes.new(self.name + "Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        cage = mesh.attributes.new(name="SourceCage",type="BOOLEAN",domain="FACE")
        for i,mat in enumerate(self.source_materials):cage.data[i].value=mat is not None
        source_face = mesh.attributes.new(name="SourceFace",type="INT",domain="FACE")
        for i,mat in enumerate(self.source_materials):source_face.data[i].value=i if mat else -1
        position = mesh.attributes.new(name="SourceGamePoint",type="FLOAT_VECTOR",domain="POINT")
        for i,point in enumerate(self.source_positions):position.data[i].vector=point
        # Assign source UVs while the loop order still matches self.faces.
        # Reversing normals first changes the vertex order of some faces and
        # would attach their original UVs to the wrong corners.
        ob = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(ob)
        for role in PALETTE:
            mesh.materials.append(bpy.data.materials["Guide_" + role])
        old_uv = mesh.uv_layers.new(name="OriginalUV")
        old_slots = {}
        for poly, role, uvs, mat in zip(mesh.polygons, self.roles, self.source_uv, self.source_materials):
            if mat:
                if mat.name not in old_slots:
                    copy = mat.copy()
                    nt = copy.node_tree
                    tex = next(n for n in nt.nodes if n.type=="TEX_IMAGE" and n.image)
                    uvnode = nt.nodes.new("ShaderNodeUVMap")
                    uvnode.uv_map="OriginalUV"
                    nt.links.new(uvnode.outputs[0],tex.inputs["Vector"])
                    # Raw original material appearance, without real lighting.
                    sh=nt.nodes.new("ShaderNodeEmission")
                    out=next(n for n in nt.nodes if n.type=="OUTPUT_MATERIAL")
                    nt.links.new(tex.outputs["Color"],sh.inputs[0])
                    nt.links.new(sh.outputs[0],out.inputs[0])
                    old_slots[mat.name]=len(mesh.materials)
                    mesh.materials.append(copy)
                poly.material_index=old_slots[mat.name]
                for li,uv in zip(poly.loop_indices,uvs):old_uv.data[li].uv=uv
            else:
                poly.material_index = list(PALETTE).index(role)
        for name in rig.data.bones.keys():
            group = ob.vertex_groups.new(name=name)
            for i, weights in enumerate(self.weights):
                if name in weights:
                    group.add([i], weights[name], "REPLACE")
        # The glTF splits vertices at old UV seams. Weld those coincident cage
        # vertices before authoring a new UV layout; otherwise each triangle
        # becomes a separate tiny island. Bone weights remain on the deform layer.
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        # Check corner correspondence, not just UV range or posed bounds.
        # Those checks cannot detect a UV attached to the wrong vertex.
        checked = 0
        for poly in mesh.polygons:
            source_index = mesh.attributes["SourceFace"].data[poly.index].value
            if source_index < 0:
                continue
            expected = [(Vector(self.source_positions[vi]), Vector(uv))
                        for vi,uv in zip(self.faces[source_index],self.source_uv[source_index])]
            for li in poly.loop_indices:
                point = mesh.attributes["SourceGamePoint"].data[mesh.loops[li].vertex_index].vector
                original,uv = min(expected,key=lambda pair:(pair[0]-point).length_squared)
                if (original-point).length>0.00002 or (mesh.uv_layers["OriginalUV"].data[li].uv-uv).length>0.000001:
                    raise ValueError(f"Source UV corner mismatch: {self.name} face {source_index}")
            checked += 1
        ob["source_uv_checked_faces"] = checked
        mesh.transform(C)
        modifier = ob.modifiers.new("OriginalGameRig", "ARMATURE")
        modifier.object = rig
        move_collection(ob, "LOW")
        return ob


def helmet():
    p = Part("ArmorHead_11")
    # Crown/rear shell: the front stops at the brow, leaving a real visor opening.
    # Ring stations follow the original helmet envelope, not adult concept scale.
    stations = [(1.35, .135, .12, .095), (1.48, .205, .19, .13),
                (1.69, .238, .28, .19), (1.82, .236, .29, .19),
                (1.925, .17, .205, .14), (1.9784, .09, .12, .07)]
    n = 16
    verts = []
    for y, w, front, back in stations:
        for j in range(n):
            a = 2 * math.pi * j/n
            verts.append((w * math.sin(a), y, -.035 - math.cos(a)*(front if math.cos(a)>0 else back)))
    faces = []
    for k in range(len(stations)-1):
        for j in range(n):
            # Remove the central forward sector below brow height.
            if k < 2 and (j in [0, 1, 2, 13, 14, 15]):
                continue
            faces.append((k*n+j, k*n+(j+1)%n, (k+1)*n+(j+1)%n, (k+1)*n+j))
    faces += [tuple(range((len(stations)-1)*n, len(verts))), tuple(range(n))[::-1]]
    p.add(verts, faces, "white", group="shell")
    face_z = lambda x,y: -.387 + 1.72*x*x + .065*(1.69-y)
    # Visor perimeter and central stem are one continuous curved glass insert.
    upper = [(-.208,1.753),(-.135,1.769),(-.068,1.758),(0,1.741),(.068,1.758),(.135,1.769),(.208,1.753)]
    lower = [(-.195,1.655),(-.132,1.632),(-.070,1.590),(0,1.583),(.070,1.590),(.132,1.632),(.195,1.655)]
    vv = [(x,y,face_z(x,y)) for x,y in upper+lower]
    vf = [(i,i+1,i+8,i+7) for i in range(6)]
    vv += [(-.056,1.430,face_z(-.056,1.430)),(0,1.391,face_z(0,1.391)),(.056,1.430,face_z(.056,1.430))]
    vf += [(9,10,15,14),(10,11,16,15)]
    p.add(vv, vf, "gold", group="visor")
    # Seal and sloping cheek structures connect the glass to the side shell.
    for s in [-1,1]:
        # Join the face perimeter to the rear shell with actual side volume.
        # A front mask hovering in front of a crown was a rejected earlier fault.
        contour=[(.218,1.753),(.237,1.624),(.188,1.459),(.104,1.338)]
        front=[(s*x,y,face_z(x,y)+.018) for x,y in contour]
        middle=[(s*x,y,z) for x,y,z in [(.244,1.753,-.165),(.241,1.624,-.148),(.208,1.459,-.131),(.145,1.338,-.104)]]
        rear=[(s*x,y,-.027) for x,y in [(.235,1.753),(.232,1.624),(.205,1.459),(.135,1.350)]]
        joins=[(j,j+1,j+5,j+4) for j in range(3)]+[(j+4,j+5,j+9,j+8) for j in range(3)]
        p.add(front+middle+rear,joins,"white",group="side_cheek_connection")
        p.plate([(.064,1.583),(.198,1.650),(.211,1.749),(.232,1.735),(.224,1.618),(.088,1.567),(.071,1.419),(.058,1.420)], "black", lambda x,y:face_z(x,y)+.008, side=s, group="seal")
        p.plate([(.208,1.68),(.237,1.624),(.188,1.459),(.104,1.338),(.047,1.338),(.071,1.431),(.085,1.593),(.185,1.634)], "white", face_z, side=s, thickness=.031, group="cheek")
        # Inset vent is a dark face on a bevel, not a separate round ear button.
        p.plate([(.145,1.526),(.185,1.565),(.185,1.524),(.125,1.445),(.112,1.453)], "green", lambda x,y:face_z(x,y)-.005, side=s, thickness=.005, group="vent")
        p.plate([(.064,1.802),(.116,1.845),(.207,1.799),(.218,1.739),(.123,1.745)], "white", lambda x,y:face_z(x,y)-.002, side=s, thickness=.018, group="brow")
        p.plate([(.180,1.814),(.204,1.801),(.207,1.772),(.182,1.788)], "copper", lambda x,y:face_z(x,y)-.006, side=s, thickness=.003, group="indicator")
        # Two short swept fins with angular ear brackets, visible in silhouette.
        for y, z, endx in [(1.750,.04,.341),(1.625,.085,.312)]:
            p.plate([(.219,y),(.250,y-.011),(endx,y+.103),(endx-.012,y+.051),(.259,y-.051)], "white", z, side=s, thickness=.055, group="fin")
            p.plate([(.267,y+.021),(endx-.016,y+.077),(endx-.020,y+.045),(.267,y-.002)], "copper", z-.003, side=s, thickness=.004, group="fin_insert")
    p.plate([(-.10,1.901),(-.077,1.952),(0,1.976),(.077,1.952),(.10,1.901),(.061,1.84),(-.061,1.84)], "white", lambda x,y:-.185-(1.95-y)*1.3, thickness=.014, group="crown")
    p.plate([(-.051,1.392),(-.040,1.334),(0,1.317),(.040,1.334),(.051,1.392),(0,1.407)], "white", face_z, thickness=.026, group="chin")
    # Rear shell patch and neck seal preserve a dark moving joint beneath helmet.
    p.plate([(-.077,1.565),(-.070,1.66),(.070,1.66),(.077,1.565)], "green", .159, thickness=.014, group="rear_vent")
    v = [(r*math.sin(2*math.pi*j/12),y,.055+r*math.cos(2*math.pi*j/12)) for y,r in [(1.210,.102),(1.355,.125)] for j in range(12)]
    p.add(v, [(j,(j+1)%12,(j+1)%12+12,j+12) for j in range(12)], "black", "Bip01 Neck", "neck")
    return p


def source_part(original, rig):
    # Retain source skin weights and original joints, making separate UV seams
    # weldable without changing the old cage's silhouette.
    p = Part(original.name)
    p.vertices = [tuple(original.matrix_world @ v.co) for v in original.data.vertices]
    p.source_positions = list(p.vertices)
    names = {g.index:g.name for g in original.vertex_groups}
    p.weights = [{names[g.group]:g.weight for g in v.groups if g.weight>1e-8} for v in original.data.vertices]
    source_uv = original.data.uv_layers.active
    for poly in original.data.polygons:
        p.faces.append(tuple(poly.vertices))
        # Average the original diffuse to recover large material regions only.
        mat = original.data.materials[poly.material_index]
        image = next((n.image for n in mat.node_tree.nodes if n.type=="TEX_IMAGE" and n.image), None)
        rgb = [.07,.08,.065]
        if image:
            uvs = [source_uv.data[i].uv for i in poly.loop_indices]
            uv = sum(uvs, Vector((0,0)))/len(uvs)
            px = min(image.size[0]-1,max(0,int(uv.x*image.size[0])))
            py = min(image.size[1]-1,max(0,int(uv.y*image.size[1])))
            off = (py*image.size[0]+px)*4
            rgb = list(image.pixels[off:off+3])
        mx,mn = max(rgb),min(rgb)
        role = "copper" if rgb[0]>rgb[1]*1.30 and rgb[0]>rgb[2]*1.45 and mx>.16 else ("white" if mn>.20 and mx-mn<.23 else ("black" if mx<.045 else "green"))
        p.roles.append(role)
        p.groups.append("source_cage")
        p.source_uv.append([tuple(source_uv.data[i].uv) for i in poly.loop_indices])
        p.source_materials.append(mat)
    return p


def reshape_body(p):
    # Shorten the existing shoulder fins in their connected cage, preserving
    # weights; the new front plates are supported by the old torso beneath them.
    for i,(x,y,z) in enumerate(p.vertices):
        if abs(x)>.48 and y>1.38:
            p.vertices[i] = (math.copysign(.48+(abs(x)-.48)*.65,x),1.38+(y-1.38)*.78,z)
    for side in [-1,1]:
        p.plate([(.079,1.304),(.154,1.328),(.291,1.215),(.251,1.118),(.129,1.038),(.087,1.095),(.161,1.18)],"white",lambda x,y:-.285+.62*x*x,"Bip01 Spine1",.018,side,"chest_v")
        p.plate([(.178,1.183),(.231,1.227),(.254,1.20),(.209,1.158)],"copper",lambda x,y:-.288+.62*x*x,"Bip01 Spine1",.004,side,"chest_insert")
    p.plate([(-.063,1.307),(.063,1.307),(.048,1.262),(.03,1.158),(-.03,1.158),(-.048,1.262)],"white",-.268,"Bip01 Spine1",.012,group="chest_center")
    p.plate([(-.042,1.264),(.042,1.264),(.027,1.175),(-.027,1.175)],"copper",-.281,"Bip01 Spine1",.003,group="sternum")
    return p


def unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.data.uv_layers.new(name="TargetUV")
    ob.data.uv_layers.active_index=len(ob.data.uv_layers)-1
    ob.data.uv_layers.active.active_render=True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=.018, area_weight=0.25, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_guides(ob, label):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = 8
    # A normal-based, deliberately coarse light guide helps the generator paint
    # upper/front surfaces consistently. It is never a delivered painted texture.
    mesh = ob.data
    colors = mesh.color_attributes.new(name="PlacementLight", type="FLOAT_COLOR", domain="CORNER")
    light = Vector((-.3,-.6,1)).normalized()
    for poly in mesh.polygons:
        base = PALETTE[list(PALETTE)[min(poly.material_index,len(PALETTE)-1)]]
        factor = .52 + .48*max(0,poly.normal.dot(light))
        for loop in poly.loop_indices:
            colors.data[loop].color = (*[v*factor for v in base[:3]],1)
    image = bpy.data.images.new(label+"_placement",512,512,alpha=False)
    image.generated_color=(.018,.026,.021,1)
    image.filepath_raw=str(WORK/"build"/(label+"_uv_guide.png"))
    image.file_format="PNG"
    backups=[]
    for mat in mesh.materials:
        # Unique temporary material per object; no shader mutations on others.
        copy=mat.copy()
        nt=copy.node_tree
        sh=next(n for n in nt.nodes if n.type=="EMISSION")
        if mat.name.startswith("Guide_"):
            col=nt.nodes.new("ShaderNodeVertexColor")
            col.layer_name="PlacementLight"
            nt.links.new(col.outputs["Color"],sh.inputs["Color"])
        node=nt.nodes.new("ShaderNodeTexImage")
        node.image=image
        nt.nodes.active=node
        backups.append(mat)
        mesh.materials[len(backups)-1]=copy
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.bake(type="EMIT",use_clear=False)
    image.save()
    for i,mat in enumerate(backups):mesh.materials[i]=mat
    # SVG export works without the viewport GPU required by Blender's PNG UV
    # exporter. This is exact topology data, independent of image generation.
    bpy.ops.uv.export_layout(filepath=str(WORK/"build"/(label+"_uv_lines.svg")),mode="SVG",size=(512,512),opacity=.14,export_all=True)


def main():
    # Use the initialized reference scene but rebuild all owned output objects.
    bpy.ops.wm.open_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    for collection in ["LOW","RIG_DEF","SOURCE"]:
        old=bpy.data.collections.get(collection)
        if old:
            for ob in list(old.objects):bpy.data.objects.remove(ob,do_unlink=True)
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(OUT/"source_blender.gltf"))
    imported=set(bpy.data.objects)-before
    rig=next(ob for ob in imported if ob.type=="ARMATURE")
    rig.animation_data_clear()
    rig.data.pose_position="REST"
    sources={ob.name:ob for ob in imported if ob.name in ["ArmorHead_11","ArmorBody_11","ArmorHand_11","ArmorFoot_11"]}
    # Capture immutable original rests before rotating the presentation frame.
    rests={b.name:[list(r) for r in rig.matrix_world @ b.matrix_local] for b in rig.data.bones}
    source_matrices={ob:ob.matrix_world.copy() for ob in sources.values()}
    models={"Head":helmet(),"Body":reshape_body(source_part(sources["ArmorBody_11"],rig)),"Hand":source_part(sources["ArmorHand_11"],rig),"Foot":source_part(sources["ArmorFoot_11"],rig)}
    for role,color in PALETTE.items():emission("Guide_"+role,color)
    for ob in list(imported):
        if ob not in sources.values() and ob!=rig:bpy.data.objects.remove(ob,do_unlink=True)
    rig.parent=None
    rig.matrix_world=C @ rig.matrix_world
    move_collection(rig,"RIG_DEF")
    rig.name="OriginalPlayerRig"
    for ob in sources.values():
        mat=source_matrices[ob]
        ob.parent=None
        ob.matrix_world=C @ mat
        ob.name="Original_"+ob.name
        ob.hide_render=True
        ob.hide_set(True)
        move_collection(ob,"SOURCE")
    low=[]
    for label,part in models.items():
        ob=part.object(rig)
        unwrap(ob)
        bake_guides(ob,label.lower())
        low.append(ob)
    bpy.context.scene.world = bpy.context.scene.world or bpy.data.worlds.new("CygniWorld")
    bpy.context.scene.world.color=(.015,.015,.015)
    bpy.context.scene.view_settings.view_transform="Standard"
    bpy.context.scene.render.image_settings.file_format="PNG"
    bpy.context.scene.render.film_transparent=True
    rig.data.pose_position="POSE"
    for pose in rig.pose.bones:pose.matrix_basis=Matrix.Identity(4)
    for ob in low:ob["revision"]="cygni_runtime_v2"; ob["guide_only"]=True
    manifest={"revision":"cygni_runtime_v2","coordinate_transform":[list(r) for r in C],"source_rests":rests,"parts":{}}
    for ob in low:
        pts=[C.inverted() @ v.co for v in ob.data.vertices]
        ob.data.calc_loop_triangles()
        manifest["parts"][ob.name]={"vertices":len(pts),"triangles":len(ob.data.loop_triangles),"source_uv_checked_faces":ob["source_uv_checked_faces"],"bounds_game":{"min":[min(p[i] for p in pts) for i in range(3)],"max":[max(p[i] for p in pts) for i in range(3)]}}
    (WORK/"build"/"geometry.json").write_text(json.dumps(manifest,indent=2))
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    print("CYGNI_GEOMETRY_BUILT",json.dumps(manifest["parts"]))


if __name__=="__main__":main()
