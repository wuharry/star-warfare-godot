"""Embed engine-skinned rest geometry and source PNGs for an offline 3D comparison."""
import base64
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/"docs/art/cygni_runtime_v2"
data=json.loads((WORK/"build/viewer_meshes.json").read_text())
for parts in data.values():
    for part in parts:
        path=ROOT/part["texture"]
        part["image"]="data:image/png;base64,"+base64.b64encode(path.read_bytes()).decode()
        # The complete source records remain in viewer_meshes.json; this copy
        # carries the exact rest-skinned vertices and original target UVs.
        for name in ["positions","uv"]:part[name]=[round(x,7) for x in part[name]]
template=(ROOT/"tools/cygni_runtime_v2/viewer.template.html").read_text()
(WORK/"index.html").write_text(template.replace("__MESH_DATA__",json.dumps(data,separators=(",",":"))))
print("CYGNI_VIEWER_BUILT offline WebGL, two synchronized actual rest meshes")
