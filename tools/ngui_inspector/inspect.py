#!/usr/bin/env python3
"""List legacy NGUI widgets with hierarchy, position, size and atlas sprite."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def documents(text: str) -> list[tuple[int, int, str]]:
    pattern = re.compile(r"^--- !u!(\d+) &(\d+)\s*$", re.MULTILINE)
    matches = list(pattern.finditer(text))
    return [
        (int(match.group(1)), int(match.group(2)), text[match.end():matches[index + 1].start() if index + 1 < len(matches) else len(text)])
        for index, match in enumerate(matches)
    ]


def vector(body: str, name: str, default: tuple[float, float, float]) -> tuple[float, float, float]:
    match = re.search(rf"^\s*{re.escape(name)}:\s*\{{([^}}]+)\}}", body, re.MULTILINE)
    if not match:
        return default
    values = {key: float(value) for key, value in re.findall(r"([xyz]):\s*([-+0-9.eE]+)", match.group(1))}
    return values.get("x", default[0]), values.get("y", default[1]), values.get("z", default[2])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefab", type=Path)
    args = parser.parse_args()
    docs = documents(args.prefab.read_text(encoding="utf-8-sig"))
    names: dict[int, str] = {}
    active: dict[int, bool] = {}
    transforms: dict[int, tuple[int, int, tuple[float, ...], tuple[float, ...]]] = {}
    transform_by_game: dict[int, int] = {}
    widgets: list[tuple[int, str, str, str]] = []
    for class_id, file_id, body in docs:
        game_match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
        game_id = int(game_match.group(1)) if game_match else 0
        if class_id == 1:
            name_match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", body, re.MULTILINE)
            names[file_id] = name_match.group(1) if name_match else f"GameObject_{file_id}"
            active_match = re.search(r"^\s*m_IsActive:\s*(\d+)", body, re.MULTILINE)
            active[file_id] = active_match is None or active_match.group(1) == "1"
        elif class_id == 4:
            father_match = re.search(r"m_Father:\s*\{fileID:\s*(\d+)\}", body)
            transforms[file_id] = (
                game_id,
                int(father_match.group(1)) if father_match else 0,
                vector(body, "m_LocalPosition", (0.0, 0.0, 0.0)),
                vector(body, "m_LocalScale", (1.0, 1.0, 1.0)),
            )
            transform_by_game[game_id] = file_id
        elif class_id == 114:
            sprite = re.search(r"^\s*mSpriteName:\s*(.*?)\s*$", body, re.MULTILINE)
            label = re.search(r"^\s*mText:\s*(.*?)\s*$", body, re.MULTILINE)
            if sprite or label:
                color = re.search(r"^\s*mColor:\s*\{([^}]+)\}", body, re.MULTILINE)
                widgets.append((game_id, "sprite" if sprite else "label", (sprite or label).group(1), color.group(1) if color else ""))

    def path_for(game_id: int) -> str:
        result: list[str] = []
        transform_id = transform_by_game.get(game_id, 0)
        while transform_id in transforms:
            current_game, father, _position, _scale = transforms[transform_id]
            result.append(names.get(current_game, str(current_game)))
            transform_id = father
        return "/".join(reversed(result))

    for game_id, kind, value, color in sorted(widgets, key=lambda item: path_for(item[0])):
        transform = transforms.get(transform_by_game.get(game_id, 0))
        position = transform[2] if transform else (0.0, 0.0, 0.0)
        scale = transform[3] if transform else (1.0, 1.0, 1.0)
        state = "on " if active.get(game_id, True) else "off"
        print(f"{state} {kind:6} pos={position[0]:7.1f},{position[1]:7.1f} size={scale[0]:7.1f}x{scale[1]:7.1f} {value!r}  {path_for(game_id)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
