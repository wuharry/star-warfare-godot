"""Inventory user-supplied XAPKs and recover Unity objects without executing them.

Raw APK/OBB contents and bulk exports stay in ignored test_output; provenance and
selected game integrations are kept separately. Uses the installed UnityPy.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import zipfile

import UnityPy

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "test_output/source_reconstruction"
REPORT = ROOT / "docs/reconstruction_v1"
GAME_IDS = {
    "com.ifreyrgames.starwarfare": "sw1",
    "com.ifreyr.sw2": "sw2",
    "com.trinitigame.android.callofminiinfinity": "com",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def save_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def safe_name(value: str) -> str:
    return re.sub(r"[^\w.\-]", "_", value)[:140] or "unnamed"


def unpack(game_filter: str | None) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / ".gdignore").touch()
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / ".gdignore").touch()
    manifests = []
    for archive in sorted((ROOT / "原資料").glob("*.xapk")):
        with zipfile.ZipFile(archive) as outer:
            manifest = json.loads(outer.read("manifest.json"))
            game = GAME_IDS[manifest["package_name"]]
            if game_filter and game != game_filter:
                continue
            destination = WORK / game / "raw"
            destination.mkdir(parents=True, exist_ok=True)
            members = []
            for container in outer.infolist():
                if not container.filename.endswith((".apk", ".obb")):
                    continue
                blob = outer.read(container)
                with zipfile.ZipFile(io.BytesIO(blob)) as inner:
                    for member in inner.infolist():
                        if member.is_dir():
                            continue
                        relative = PurePosixPath(member.filename)
                        if relative.is_absolute() or ".." in relative.parts:
                            raise ValueError(f"Unsafe archive member: {relative}")
                        data = inner.read(member)
                        record = {"container": container.filename, "path": member.filename,
                                  "bytes": len(data), "sha256": digest(data)}
                        # Unity data + executable metadata are inspected, never run.
                        if member.filename.startswith(("assets/bin/Data/", "lib/")):
                            output = destination.joinpath(*relative.parts)
                            if output.exists() and output.read_bytes() != data:
                                raise ValueError(f"APK/OBB path collision: {output}")
                            output.parent.mkdir(parents=True, exist_ok=True)
                            if not output.exists():
                                output.write_bytes(data)
                            record["extracted"] = output.relative_to(ROOT).as_posix()
                        members.append(record)
            record = {"id": game, "archive": archive.relative_to(ROOT).as_posix(),
                      "sha256": digest(archive.read_bytes()), "manifest": manifest,
                      "members": members}
            save_json(REPORT / game / "source.json", record)
            manifests.append({k: record[k] for k in ("id", "archive", "sha256", "manifest")})
            print(f"UNPACKED {game}: {len(members)} members", flush=True)
    if not game_filter:
        save_json(REPORT / "sources.json", manifests)


def load_game(game: str):
    data = WORK / game / "raw/assets/bin/Data"
    # UnityPy joins .splitN files and resolves external .resource streams itself.
    return UnityPy.load(str(data))


def inventory(game: str, export: bool) -> int:
    env = load_game(game)
    objects = []
    errors = []
    containers: dict[tuple[str, int], list[str]] = {}
    resource_pointers = list(env.container.items())
    for candidate in env.objects:
        if candidate.type.name == "ResourceManager":
            resource_pointers.extend(candidate.read().m_Container)
    for name, pointer in resource_pointers:
        try:
            obj = pointer.deref()
            containers.setdefault((obj.assets_file.name, obj.path_id), []).append(name)
        except Exception as exc:
            errors.append({"operation": "container", "name": name, "error": str(exc)})
    for obj in env.objects:
        kind = obj.type.name
        record = {"file": obj.assets_file.name, "path_id": obj.path_id,
                  "type": kind, "bytes": obj.byte_size,
                  "resources": containers.get((obj.assets_file.name, obj.path_id), [])}
        try:
            record["name"] = obj.peek_name() or ""
        except Exception:
            record["name"] = ""
        name = safe_name(record["name"])
        stem = f"{name}__{Path(obj.assets_file.name).name}_{obj.path_id}"
        try:
            if kind == "TextAsset":
                value = obj.read()
                payload = value.m_Script
                if isinstance(payload, str):
                    payload = payload.encode("utf-8", errors="surrogateescape")
                output = WORK / game / "text" / (stem + ".bytes")
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(payload)
                record.update(export=output.relative_to(ROOT).as_posix(), sha256=digest(payload), payload_bytes=len(payload))
            elif kind == "Texture2D":
                value = obj.read()
                record.update(width=value.m_Width, height=value.m_Height, format=int(value.m_TextureFormat))
                if value.m_Width == 0 or value.m_Height == 0:
                    record["export_state"] = "empty_runtime_generated_texture"
                elif export:
                    image = value.image
                    output = WORK / game / "textures" / (stem + ".png")
                    output.parent.mkdir(parents=True, exist_ok=True)
                    image.save(output)
                    record.update(export=output.relative_to(ROOT).as_posix(), pixels_sha256=digest(image.convert("RGBA").tobytes()))
            elif kind == "AudioClip":
                value = obj.read()
                record.update(channels=value.m_Channels, frequency=value.m_Frequency, length=value.m_Length)
                if export:
                    samples = value.samples
                    record["samples"] = []
                    for sample_name, payload in samples.items():
                        output = WORK / game / "audio" / (stem + "__" + safe_name(sample_name))
                        output.parent.mkdir(parents=True, exist_ok=True)
                        output.write_bytes(payload)
                        record["samples"].append({"export": output.relative_to(ROOT).as_posix(), "sha256": digest(payload), "bytes": len(payload)})
            elif kind in {"MonoBehaviour", "Sprite"}:
                # Keep serialized fields / reference links when the build has trees.
                try:
                    tree = obj.read_typetree()
                    output = WORK / game / "objects" / (stem + ".json")
                    save_json(output, tree)
                    record["tree"] = output.relative_to(ROOT).as_posix()
                except (ValueError, KeyError, TypeError, AttributeError):
                    record["tree_available"] = False
        except Exception as exc:
            record["error"] = f"{type(exc).__name__}: {exc}"
            errors.append({"file": record["file"], "path_id": obj.path_id, "type": kind, "name": record["name"], "error": record["error"]})
        objects.append(record)
    counts = dict(sorted(Counter(o["type"] for o in objects).items()))
    save_json(REPORT / game / "inventory.json", {"game": game, "unity_versions": sorted({f.unity_version for f in env.assets}),
              "object_counts": counts, "objects": objects, "errors": errors, "media_exported": export})
    print(f"INVENTORY {game}: {len(objects)} objects, {counts}, {len(errors)} errors", flush=True)
    return len(errors)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["unpack", "inventory", "export"])
    parser.add_argument("--game", choices=GAME_IDS.values())
    args = parser.parse_args()
    if args.action == "unpack":
        unpack(args.game)
    else:
        error_count = 0
        for game in ([args.game] if args.game else GAME_IDS.values()):
            error_count += inventory(game, args.action == "export")
        if error_count:
            raise RuntimeError(f"{error_count} object read/export failures; inspect inventory errors")


if __name__ == "__main__":
    main()
