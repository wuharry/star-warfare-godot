"""Export exact game-space corners, named weights and the compatible rigged GLB.

Blender is the authoring artifact; Godot's source skeleton is the binding
authority. Generated diffuse paths are assigned only after recorded output exists.
"""
import bpy
import json
import sys
import hashlib
from pathlib import Path
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/"docs/art/cygni_runtime_v2"
OUT=ROOT/"assets/armors/cygni_v2"
C=Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))


def main():
    bpy.ops.wm.open_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    rig=bpy.data.objects["OriginalPlayerRig"]
    rig.animation_data_clear()
    rig.data.pose_position="REST"
    # Imported helper/socket bones can differ from Godot's default rests.
    # Restore the exact engine rests, including gun mounts, in the native file.
    runtime=json.loads((WORK/"build/runtime_rig.json").read_text())
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False);rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode="EDIT")
    for item in runtime:
        bone=rig.data.edit_bones[item["name"]]
        length=bone.length
        bone.matrix=Matrix(item["matrix"])
        bone.length=length
    bpy.ops.object.mode_set(mode="OBJECT")
    models=list(bpy.data.collections["LOW"].objects)
    OUT.mkdir(parents=True,exist_ok=True)
    generated={}
    if "--geometry-only" not in sys.argv:
        selection=json.loads((WORK/"generation_records/selection.json").read_text())
        if set(selection["parts"])!={"head","body","hand","foot"}:
            raise ValueError("Expected four recorded diffuse selections")
        for label in ["head","body","hand","foot"]:
            source=selection["parts"][label]
            original=ROOT/source["path"]
            if not original.exists():raise ValueError("Missing actual ImageGen output: "+label)
            if hashlib.sha256(original.read_bytes()).hexdigest()!=source["sha256"]:
                raise ValueError("Generated output hash changed: "+label)
            image=bpy.data.images.load(str(original),check_existing=False)
            image.scale(512,512)
            image.filepath_raw=str(OUT/(label+"_diffuse.png"));image.file_format="PNG"
            image.save()
            generated[label]=image
    payload={"revision":"cygni_runtime_v2","id":11,"parts":[]}
    for ob in models:
        label=ob.name.removeprefix("Armor").removesuffix("_11").lower()
        texture=OUT/(label+"_diffuse.png")
        if texture.exists():
            mat=bpy.data.materials.new("Cygni_"+label+"_painted")
            nt=mat.node_tree;nt.nodes.clear()
            output=nt.nodes.new("ShaderNodeOutputMaterial")
            sh=nt.nodes.new("ShaderNodeEmission")
            node=nt.nodes.new("ShaderNodeTexImage")
            # Reusing a packed image by file path can retain the previous
            # generation even after a new PNG has been written at that path.
            node.image=generated.get(label) or bpy.data.images.load(str(texture),check_existing=False)
            uv=nt.nodes.new("ShaderNodeUVMap");uv.uv_map="TargetUV"
            nt.links.new(uv.outputs[0],node.inputs[0]);nt.links.new(node.outputs["Color"],sh.inputs[0]);nt.links.new(sh.outputs[0],output.inputs[0])
            ob.data.materials.clear();ob.data.materials.append(mat)
            for p in ob.data.polygons:p.material_index=0
            ob["guide_only"]=False
        mesh=ob.data;mesh.calc_loop_triangles()
        uv=mesh.uv_layers["TargetUV"]
        record={"name":ob.name,"positions":[],"normals":[],"uv":[],"bones":[],"weights":[],"colors":[],"source_uv":[],"source_positions":[],"source_cage":[]}
        groups={g.index:g.name for g in ob.vertex_groups}
        for tri in mesh.loop_triangles:
            for li in tri.loops:
                loop=mesh.loops[li];v=mesh.vertices[loop.vertex_index]
                point=C.inverted() @ (ob.matrix_world @ v.co)
                normal=(C.inverted().to_3x3() @ ob.matrix_world.to_3x3() @ tri.normal).normalized()
                weights=sorted([(groups[g.group],g.weight) for g in v.groups if g.weight>1e-7],key=lambda v:-v[1])[:4]
                if not weights:raise ValueError("Unweighted vertex "+ob.name)
                total=sum(w for _,w in weights)
                record["positions"].extend(point);record["normals"].extend(normal);record["uv"].extend(uv.data[li].uv)
                record["bones"].append([n for n,w in weights]);record["weights"].append([w/total for n,w in weights]);record["colors"].extend([1,1,1,1])
                record["source_uv"].extend(mesh.uv_layers["OriginalUV"].data[li].uv)
                record["source_positions"].extend(mesh.attributes["SourceGamePoint"].data[v.index].vector)
                record["source_cage"].append(mesh.attributes["SourceCage"].data[tri.polygon_index].value)
        payload["parts"].append(record)
    (WORK/"build/game_meshes.json").write_text(json.dumps(payload,separators=(",",":")))
    if "--geometry-only" not in sys.argv:
        if any(o.get("guide_only",True) for o in models):raise ValueError("No finished generated diffuse for all parts")
        bpy.ops.object.select_all(action="DESELECT")
        for ob in models+[rig]:
            ob.hide_render=False;ob.hide_set(False);ob.select_set(True)
        # Keep the parent armature so glTF can emit the skin rather than baking
        # a pose into static vertices. The unchanged modifier remains active.
        for ob in models:
            world=ob.matrix_world.copy();ob.parent=rig;ob.matrix_world=world
        rig.data.pose_position="POSE"
        for pose in rig.pose.bones:pose.matrix_basis=Matrix.Identity(4)
        # The final GLB is exported by compile.gd from the actual engine skin.
        # Do not overwrite it with Blender's inverse-rest approximation.
        # Remove unreferenced meshes and imported actions from deleted suits.
        # Original comparison meshes remain in SOURCE; engine owns animation clips.
        bpy.data.orphans_purge(do_recursive=True)
        bpy.ops.file.pack_all()
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    print("CYGNI_EXPORT_PASS parts=4 triangles="+str(sum(len(p["positions"])//9 for p in payload["parts"])))


if __name__=="__main__":main()
