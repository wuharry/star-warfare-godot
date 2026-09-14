"""Build a standalone, offline comparison from actual Godot captures.

Only copies original reference bytes and writes HTML/JSON; no image editing.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "test_output/thunder_detail_preview"
REFERENCE = ROOT / "docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png"
PUBLISHED = ROOT / "docs/art/thunder_detail_v4"
SW2 = ROOT / "test_output/thunder_v4_source_audit"
SW2_FRAMES = ("head_3q", "head_back_3q", "full_3q", "full_back_3q")


def copy_source_reference(destination):
    """Keep extracted SW2 source renders distinct from the actual game captures."""
    if not all((SW2 / (name + ".png")).is_file() for name in SW2_FRAMES):
        return []
    folder = destination / "sw2_reference"
    folder.mkdir(exist_ok=True)
    for name in SW2_FRAMES:
        shutil.copy2(SW2 / (name + ".png"), folder / (name + ".png"))
    return list(SW2_FRAMES)


def render_html(destination, manifests):
    template = (Path(__file__).parent / "preview.html").read_text(encoding="utf-8")
    payload = json.dumps(manifests, ensure_ascii=False).replace("</", "<\\/")
    relative_root = "../../../" if destination == PUBLISHED else "../../"
    source_frames = copy_source_reference(destination)
    html = template.replace("__CAPTURE_DATA__", payload).replace("__REPO_REL__", relative_root)
    html = html.replace("__SOURCE_DATA__", json.dumps(source_frames))
    (destination / "index.html").write_text(html, encoding="utf-8")


def publish(manifests):
    current = manifests.get("current")
    if not current or any(part["revision"] != "thunder_detail_v4" for part in current["parts"]):
        raise RuntimeError("Publishing requires captured thunder_detail_v4 runtime parts")
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
    print(f"THUNDER_DETAIL_PREVIEW_PUBLISH_PASS stages={','.join(manifests)}")
    print(PUBLISHED / "index.html")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="After visual approval, copy the final offline report to docs/art/thunder_detail_v4")
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
    print(f"THUNDER_DETAIL_PREVIEW_BUILD_PASS stages={','.join(manifests)} frames={sum(len(m['frames']) for m in manifests.values())}")
    print(OUT / "index.html")
    if arguments.publish:
        publish(manifests)


if __name__ == "__main__":
    main()
