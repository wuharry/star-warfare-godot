"""Build a standalone, offline comparison from actual Godot captures.

Only copies original reference bytes and writes HTML/JSON; no image editing.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "test_output/thunder_concept_preview"
REFERENCE = ROOT / "docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png"
PUBLISHED = ROOT / "docs/art/thunder_concept_v3"


def render_html(destination, manifests):
    template = (Path(__file__).parent / "preview.html").read_text(encoding="utf-8")
    payload = json.dumps(manifests, ensure_ascii=False).replace("</", "<\\/")
    relative_root = "../../../" if destination == PUBLISHED else "../../"
    html = template.replace("__CAPTURE_DATA__", payload).replace("__REPO_REL__", relative_root)
    (destination / "index.html").write_text(html, encoding="utf-8")


def publish(manifests):
    current = manifests.get("current")
    if not current or any(part["revision"] != "thunder_concept_v3" for part in current["parts"]):
        raise RuntimeError("Publishing requires captured thunder_concept_v3 runtime parts")
    scene_hash = hashlib.sha256((ROOT / "assets/armors/thunder/thunder.scn").read_bytes()).hexdigest()
    if current.get("runtime_scene_sha256") != scene_hash:
        raise RuntimeError("Runtime scene changed since capture; capture the final build before publishing")
    for resource, captured_hash in current.get("runtime_resource_sha256", {}).items():
        source = ROOT / resource.removeprefix("res://")
        if hashlib.sha256(source.read_bytes()).hexdigest() != captured_hash:
            raise RuntimeError(f"Runtime resource changed since capture: {resource}")
    # Copy only the frames listed by each selected stage. Diagnostic candidates,
    # generated textures, browser profiles, and unrelated scratch files stay out.
    PUBLISHED.mkdir(parents=True, exist_ok=True)
    (PUBLISHED / ".gdignore").write_text("", encoding="utf-8")
    for stage, data in manifests.items():
        destination = PUBLISHED / stage
        destination.mkdir(exist_ok=True)
        for frame in data["frames"]:
            shutil.copy2(OUT / stage / frame["file"], destination / frame["file"])
        shutil.copy2(OUT / stage / "manifest.json", destination / "manifest.json")
    shutil.copy2(REFERENCE, PUBLISHED / "reference.png")
    render_html(PUBLISHED, manifests)
    print(f"THUNDER_PREVIEW_PUBLISH_PASS stages={','.join(manifests)}")
    print(PUBLISHED / "index.html")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="After visual approval, copy the final offline report to docs/art/thunder_concept_v3")
    arguments = parser.parse_args()
    manifests = {}
    for stage in ("baseline", "current"):
        manifest = OUT / stage / "manifest.json"
        if manifest.exists():
            data = json.loads(manifest.read_text(encoding="utf-8"))
            if data["status"] == "FAIL" or not data["save_unchanged"]:
                raise RuntimeError(f"Invalid capture manifest: {manifest}")
            for frame in data["frames"]:
                if Path(frame["file"]).name != frame["file"]:
                    raise ValueError("Capture filenames must be local basenames")
                if not (manifest.parent / frame["file"]).is_file():
                    raise FileNotFoundError(frame["file"])
            manifests[stage] = data
    if not manifests:
        raise RuntimeError("Run capture.tscn first; no real runtime captures found")
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(REFERENCE, OUT / "reference.png")
    render_html(OUT, manifests)
    print(f"THUNDER_PREVIEW_BUILD_PASS stages={','.join(manifests)} frames={sum(len(m['frames']) for m in manifests.values())}")
    print(OUT / "index.html")
    if arguments.publish:
        publish(manifests)


if __name__ == "__main__":
    main()
