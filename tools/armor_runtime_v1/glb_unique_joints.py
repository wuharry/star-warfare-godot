"""Preserve legacy bind matrices while giving every glTF skin a unique joint.

Godot's Skin accepts repeated named binds. glTF's skin schema instead requires
unique node indices. An identity child joint follows the same animated parent,
so replacing a repeated joint reference leaves its global transform unchanged.
No mesh, texture, inverse-bind matrix or original joint is rewritten here.
"""
import json
import argparse
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument("--armor",choices=["hydra","strike","titan"],required=True)
slug=parser.parse_args().armor
config=json.loads((ROOT/f"docs/art/{slug}_runtime_v1/runtime_config.json").read_text())
path=ROOT/config["asset"]/f"{slug}.glb"
raw=path.read_bytes()
magic,version,length=struct.unpack_from("<III",raw)
assert magic==0x46546c67 and version==2 and length==len(raw)
size,kind=struct.unpack_from("<II",raw,12)
assert kind==0x4e4f534a
data=json.loads(raw[20:20+size])
added=[]
for skin_index,skin in enumerate(data["skins"]):
    seen=set()
    for bind,node_index in enumerate(skin["joints"]):
        if node_index in seen:
            parent=data["nodes"][node_index]
            alias=len(data["nodes"])
            name=parent.get("name","Joint")+f"_Bind_{skin_index}_{bind}"
            data["nodes"].append({"name":name,"extras":{"legacy_bind_alias":True}})
            parent.setdefault("children",[]).append(alias)
            skin["joints"][bind]=alias
            added.append({"name":name,"parent":parent.get("name"),"skin":skin_index,"bind":bind})
        seen.add(node_index)
    assert len(skin["joints"])==len(set(skin["joints"]))
encoded=json.dumps(data,separators=(",",":"),ensure_ascii=False).encode()
encoded+=b" "*((-len(encoded))%4)
tail=raw[20+size:]
output=struct.pack("<III",magic,version,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),kind)+encoded+tail
path.write_bytes(output)
(ROOT/config["work"]/"build/glb_bind_aliases.json").write_text(json.dumps({"original_bones":28,"aliases":added,"schema":"https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/skin.schema.json","rule":"skin.joints uniqueItems=true; identity children preserve parent global pose"},indent=2))
print(slug.upper()+"_GLB_UNIQUE_JOINTS_PASS aliases="+str(len(added)))
