"""Import distinct recovered audio and UI atlases, retaining existing HD art.

PCM comparison ignores WAV metadata. References can share one existing file
across games. Source UI coordinates remain native, never assume the SW1 2x scale.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

from PIL import Image

from reconstruct_sources import ROOT, REPORT, digest, save_json, safe_name

DEST = ROOT / "assets/recovered_sources"


def audio_key(path: Path) -> str:
    data = path.read_bytes()
    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        position = 12
        chunks = {}
        while position + 8 <= len(data):
            name, length = struct.unpack_from("<4sI", data, position)
            position += 8
            chunks[name] = data[position:position + length]
            position += length + (length & 1)
        if b"fmt " in chunks and b"data" in chunks:
            return "pcm:" + digest(chunks[b"fmt "][:16] + chunks[b"data"])
    return "file:" + digest(data)


def existing_audio() -> dict[str, Path]:
    found = {}
    tracked = subprocess.run(["git", "ls-files", "-z", "--", "assets"], cwd=ROOT, check=True, capture_output=True).stdout
    for name in sorted(tracked.decode("utf-8").split("\0")):
        if not name:
            continue
        path = ROOT / name
        if path.suffix.lower() in {".wav", ".mp3", ".ogg"}:
            # Prefer existing authored paths over previously generated copies.
            if DEST not in path.parents and not any((parent / ".gdignore").exists() for parent in path.parents if parent != ROOT):
                found.setdefault(audio_key(path), path)
    return found


def existing_ui() -> dict[tuple, Path]:
    found = {}
    for directory in [ROOT / "assets/ui", ROOT / "assets/original/ui"]:
        for path in directory.rglob("*.png"):
            with Image.open(path) as image:
                found.setdefault((image.width, image.height, digest(image.convert("RGBA").tobytes())), path)
    return found


def relative(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def copy_verified(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if source.read_bytes() != target.read_bytes():
            raise ValueError(f"Refusing to overwrite different media: {target}")
    else:
        shutil.copyfile(source, target)


def main() -> None:
    known_audio = existing_audio()
    known_ui = existing_ui()
    inventories = {game: json.loads((REPORT / game / "inventory.json").read_text(encoding="utf-8")) for game in ["sw1", "sw2", "com"]}
    records = []
    runtime = {"audio": {}, "ui": {}}
    for game, inventory in inventories.items():
        for obj in inventory["objects"]:
            if obj["type"] != "AudioClip":
                continue
            for sample in obj.get("samples", []):
                source = ROOT / sample["export"]
                key = audio_key(source)
                existing = known_audio.get(key)
                if existing is None and game == "sw1":
                    # The prior original extraction retained MP3 rather than
                    # decoding it. Keep those equivalent original songs.
                    matches = [p for p in (ROOT / "assets/original/audio").rglob("*.mp3") if p.stem.casefold() == obj["name"].casefold()]
                    if len(matches) == 1:
                        existing = matches[0]
                if existing is not None:
                    output, decision = existing, "reuse_existing"
                else:
                    path = obj["resources"][0] if obj["resources"] else obj["name"]
                    parts = [safe_name(part) for part in path.split("/")]
                    output = DEST / game / "audio" / ("/".join(parts) + source.suffix.lower())
                    copy_verified(source, output)
                    decision = "import_unique"
                known_audio[key] = output
                asset_id = f"{game}:{obj['name']}"
                if asset_id in runtime["audio"] and runtime["audio"][asset_id] != relative(output):
                    asset_id += ":" + obj["file"]
                runtime["audio"][asset_id] = relative(output)
                for path in obj["resources"]:
                    runtime["audio"][f"{game}:{path}"] = relative(output)
                records.append({"game": game, "type": "audio", "name": obj["name"], "file": obj["file"], "path_id": obj["path_id"],
                                "decision": decision, "target": relative(output), "source_pcm": key,
                                "source_sha256": sample["sha256"], "target_sha256": digest(output.read_bytes()), "duration": obj["length"]})
    for game, inventory in inventories.items():
        text_names = {o["name"] for o in inventory["objects"] if o["type"] == "TextAsset"}
        for obj in inventory["objects"]:
            if obj["type"] != "Texture2D" or "export" not in obj:
                continue
            name = obj["name"]
            paired = name in text_names and (name.startswith("UI_") or name in {"BattleHUD", "Common", "UIDemo"})
            selected = game == "sw2" and paired
            selected |= game == "com" and name in {"Equipments", "CommonUI", "CommonUI@2x", "RankUI", "RankUI@2x", "ChatUI_Atlas", "GuildUI_Atlas"}
            selected |= game == "sw1" and name in {"HUD", "weapons1"}
            if not selected:
                continue
            source = ROOT / obj["export"]
            # Existing 2x SW1 atlases are accepted HD replacements of this asset.
            existing = ROOT / f"assets/ui/{name}.png" if game == "sw1" else None
            decision = "preserve_existing_hd" if existing and existing.exists() else "reuse_existing_pixels"
            if not existing or not existing.exists():
                existing = known_ui.get((obj["width"], obj["height"], obj["pixels_sha256"]))
            output = existing or (DEST / game / "ui" / (safe_name(name) + ".png"))
            if not existing:
                copy_verified(source, output)
                decision = "import_unique"
            known_ui[(obj["width"], obj["height"], obj["pixels_sha256"])] = output
            meta = {"texture": relative(output), "source_pixel_scale": 2 if decision == "preserve_existing_hd" else 1}
            if name in {"HUD", "weapons1"} and game == "sw1":
                meta["atlas"] = f"res://assets/ui/{name}.json"
            elif game == "com" and name == "Equipments":
                atlas = DEST / game / "ui/Equipments.json"
                copy_verified(REPORT / "com/equipment_atlas.json", atlas)
                meta["atlas"] = relative(atlas)
            elif paired:
                candidates = [o for o in inventory["objects"] if o["type"] == "TextAsset" and o["name"] == name]
                assert len(candidates) == 1
                source_json = ROOT / candidates[0]["export"]
                parsed = json.loads(source_json.read_text(encoding="utf-8-sig"))
                assert "frames" in parsed
                parsed.setdefault("meta", {})["source_pixel_scale"] = 1
                atlas = DEST / game / "ui" / (safe_name(name) + ".json")
                save_json(atlas, parsed)
                meta["atlas"] = relative(atlas)
            runtime["ui"][f"{game}:{name}"] = meta
            records.append({"game": game, "type": "ui", "name": name, "file": obj["file"], "path_id": obj["path_id"],
                            "decision": decision, "target": relative(output), "pixels_sha256": obj["pixels_sha256"], **meta})
    save_json(DEST / "catalog.json", runtime)
    save_json(REPORT / "media_mapping.json", {"method": "WAV fmt+PCM SHA256; original MP3 identity; native RGBA SHA256; explicit SW1 HD replacement identity", "records": records})
    summary = {"counts": dict(Counter((r["type"] + ":" + r["decision"]) for r in records)),
               "audio_clips": sum(r["type"] == "audio" for r in records), "ui_atlases": len(runtime["ui"])}
    save_json(REPORT / "media_summary.json", summary)
    print("SOURCE_MEDIA_PASS", json.dumps(summary))


if __name__ == "__main__":
    main()
