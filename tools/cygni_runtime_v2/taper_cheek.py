"""Final shape adjustment: keep the generated atlas's exact UV placement."""
import bpy
import json
from pathlib import Path
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/"docs/art/cygni_runtime_v2"
C=Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))


def main():
    bpy.ops.wm.open_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    mesh=bpy.data.objects["ArmorHead_11"].data
    rules=[((.145,1.338,-.104),1.440),((.205,1.459,-.027),1.540),((.135,1.350,-.027),1.490)]
    uv_before=[tuple(i.uv) for i in mesh.uv_layers["TargetUV"].data]
    changes=[]
    for old,new_y in rules:
        count=0
        for vertex in mesh.vertices:
            game=C.inverted()@vertex.co
            if abs(abs(game.x)-old[0])<.000002 and abs(game.y-old[1])<.000002 and abs(game.z-old[2])<.000002:
                before=list(game)
                game.y=new_y
                vertex.co=C@game
                mesh.attributes["SourceGamePoint"].data[vertex.index].vector=game
                changes.append({"vertex":vertex.index,"before":before,"after":list(game)})
                count+=1
        if count!=2:
            raise ValueError("Expected the untapered build.py model; run build.py first: "+str(old))
    mesh.update()
    if uv_before!=[tuple(i.uv) for i in mesh.uv_layers["TargetUV"].data]:
        raise ValueError("Taper changed TargetUV")
    record={"change":"Raise cheek side-connection lower edge toward rear to avoid a rectangular hanging jaw slab. Front visor/chin, UV/material masks, joints, head envelope and topology unchanged.","vertices":changes,"uv_unchanged":True,"texture_reused":"head_r3_original.png; exact TargetUV retained, no projected refit","views":"All final review views use the same edited model."}
    (WORK/"generation_records/geometry_taper.json").write_text(json.dumps(record,indent=2)+"\n")
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/"CH_Cygni_master.blend"))
    print("CHEEK_TAPER_PASS changed=",len(changes))


if __name__=="__main__":main()
