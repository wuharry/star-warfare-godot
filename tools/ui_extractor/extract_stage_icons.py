#!/usr/bin/env python3
"""Recover the level-select thumbnail table from the legacy UI resources.

The menu never laid its stage icons out in level order. StageChoiseUI.Create
builds each icon with

    uIStageIcon.m_background.AddObject(State.Normal, unitUI, 8, i)

where unitUI is Res2DManager.vUI[3], 8 is the frame and i is the stage index,
so the atlas rectangle for stage i is whatever frame 8's module i happens to
point at. Those rectangles are scattered across three atlas pages in no
particular order, which is why slicing a page into a grid and handing out the
cells in order pairs almost every sector with the wrong picture.

This reads the shipped binaries without Unity and prints (or writes) the real
table. Format mirrors Res2DManager.LoadData, UnitUI.Load, MImage.Load,
Frame.Load and Anim.Load from the decompiled project.

    python extract_stage_icons.py --assets-root <Star-Warfare>/Assets [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

# Where each icon table lives and which scene its entries load.
#
# Solo: StageChoiseUI.Create builds icon i from vUI[3] frame 8 module i, and
# StartGame loads "Level" + (i + 1). Entries past TOTAL_STAGE (8) are the boss
# shortcuts, which remap onto earlier scenes.
#
# Versus and boss: CreateRoomUI.ResetUIStage builds them from vUI[5] frames 4/5/6
# (survival / boss / VS), and MultiMenuScript.StartGame turns a global stage
# index into a scene -- VS index n becomes mapId 12 + n, i.e. Level 13 + n.
MODES = {
    "solo": {
        "unit": 3,
        "frame": 8,
        "levels": [1, 2, 3, 4, 5, 6, 7, 8, 3, 5, 4],
    },
    "vs": {
        "unit": 5,
        "frame": 6,
        "levels": [13, 14, 15, 16, 17, 18, 19, 20, 21],
    },
    "boss": {
        "unit": 5,
        "frame": 5,
        "levels": [3, 5, 4, 6, 7, 8],
    },
    "survival": {
        "unit": 5,
        "frame": 4,
        "levels": [1, 2, 3, 4, 5, 6, 7, 8],
    },
}


class Reader:
    def __init__(self, data: bytes, position: int = 0) -> None:
        self.data = data
        self.position = position

    def i16(self) -> int:
        value = struct.unpack_from("<h", self.data, self.position)[0]
        self.position += 2
        return value

    def i32(self) -> int:
        value = struct.unpack_from("<i", self.data, self.position)[0]
        self.position += 4
        return value

    def u8(self) -> int:
        value = self.data[self.position]
        self.position += 1
        return value

    def unicode(self) -> str:
        count = self.i16()
        text = self.data[self.position:self.position + count].decode("utf-16-le")
        self.position += count
        return text


def load_data(reader: Reader, count: int, kind: int):
    if count <= 0:
        count = reader.i16()
    if count <= 0:
        return None
    if kind == 0:
        return [reader.unicode() for _ in range(count)]
    if kind == 1:
        return [reader.i32() for _ in range(count)]
    if kind == 2:
        return [reader.i16() for _ in range(count)]
    if kind == 3:
        value = list(reader.data[reader.position:reader.position + count])
        reader.position += count
        return value
    if kind == 5:
        return [load_data(reader, 0, 1) for _ in range(count)]
    raise ValueError(f"unsupported class {kind}")


def read_unit_ui(data: bytes, offset: int) -> dict:
    reader = Reader(data, offset)
    dib = load_data(reader, 0, 2)

    images = []
    for _ in range(reader.i16()):                       # MImage
        flags = reader.i16()
        rect = (reader.i16(), reader.i16(), reader.i16(), reader.i16())
        images.append({"page": flags >> 4, "rotate": flags & 0xF, "rect": rect})

    rects = []
    for _ in range(max(0, reader.i16())):               # MRect
        width = reader.i16(); height = reader.i16()
        has_background = reader.u8() == 1
        background_color = reader.i32()
        border_width = reader.u8()
        border_color = reader.i32()
        arc_length = reader.i16()
        rects.append({
            "size": (width, height),
            "has_background": has_background,
            "background_color": background_color,
            "border_width": border_width,
            "border_color": border_color,
            "arc_length": arc_length,
        })

    for _ in range(max(0, reader.i16())):               # MText
        reader.unicode(); reader.i32()

    for _ in range(max(0, reader.i16())):               # MLine
        reader.i32(); reader.u8()
        reader.i16(); reader.i16(); reader.i16(); reader.i16()

    frames = []
    for _ in range(reader.i16()):                       # Frame
        modules = []
        for _ in range(reader.i16()):
            flags = reader.i16()
            modules.append({
                "index": flags & 0xFFF,
                "type": (flags >> 12) & 0xF,
                "position": (reader.i16(), reader.i16()),
            })
        frames.append({"modules": modules, "size": (reader.i16(), reader.i16())})

    anim = []
    for _ in range(reader.i16()):                       # Anim
        flags = reader.i16()
        anim.append({
            "frame": (flags >> 4) & 0xFFF,
            "freq": flags & 0xF,
            "position": (reader.i16(), reader.i16()),
        })

    return {
        "dib": dib,
        "images": images,
        "rects": rects,
        "frames": frames,
        "anim": anim,
        "end": reader.position,
    }


def read_ui_offsets(res_path: Path) -> list[int]:
    reader = Reader(res_path.read_bytes())
    header = reader.i32()
    reader.i16()                                        # version
    groups = load_data(reader, header >> 24, 5)
    return groups[4]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--mode", choices=sorted(MODES), default="solo")
    parser.add_argument("--unit", type=int, help="override Res2DManager.vUI index")
    parser.add_argument("--frame", type=int, help="override the frame holding the icons")
    parser.add_argument("--dump-layout", action="store_true",
                        help="print every module's original 960x640 screen rectangle")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    mode = MODES[args.mode]
    unit_index = args.unit if args.unit is not None else mode["unit"]
    frame_index = args.frame if args.frame is not None else mode["frame"]
    levels = mode["levels"]

    ui_root = args.assets_root / "Resources" / "ui"
    offsets = read_ui_offsets(ui_root / "res.bytes")
    unit = read_unit_ui((ui_root / "resUI.bytes").read_bytes(), offsets[unit_index])

    # A clean parse lands exactly on the next unit's offset. Checking it here
    # turns any format drift into an error instead of plausible garbage.
    if unit_index + 1 < len(offsets) and unit["end"] != offsets[unit_index + 1]:
        raise SystemExit(
            "parse ended at 0x%x but the next unit starts at 0x%x"
            % (unit["end"], offsets[unit_index + 1])
        )

    if args.dump_layout:
        anim = unit["anim"][frame_index]
        frame = unit["frames"][anim["frame"]]
        print("vUI[%d] anim %d -> frame %d, anim position %s, %d modules"
              % (unit_index, frame_index, anim["frame"], anim["position"], len(frame["modules"])))
        for module_index, module in enumerate(frame["modules"]):
            kind = module["type"]
            source_index = module["index"]
            if kind == 0:
                source = unit["images"][source_index]
                width, height = source["rect"][2:]
                source_text = "page %d rect %s" % (source["page"], source["rect"])
            elif kind == 1:
                width, height = unit["rects"][source_index]["size"]
                source_text = "MRect %d" % source_index
            else:
                width, height = 0, 0
                source_text = "type %d index %d" % (kind, source_index)
            x = anim["position"][0] + module["position"][0] + 480
            y = 320 - (anim["position"][1] + module["position"][1])
            print("  %02d  screen=(%4d,%4d,%3d,%3d)  %s"
                  % (module_index, x, y, width, height, source_text))
        return 0

    frame = unit["frames"][frame_index]
    if len(frame["modules"]) != len(levels):
        raise SystemExit(
            "%s expects %d icons but frame %d holds %d"
            % (args.mode, len(levels), frame_index, len(frame["modules"]))
        )
    records = []
    for stage_index, module in enumerate(frame["modules"]):
        if module["type"] != 0:
            continue
        image = unit["images"][module["index"]]
        level = levels[stage_index]
        records.append({
            "stage": stage_index,
            "level": level,
            "page": image["page"],
            "rect": list(image["rect"]),
        })

    print("%s: vUI[%d] frame %d -- %d icons, module size %s, pages %s"
          % (args.mode, unit_index, frame_index, len(records), frame["size"], unit["dib"]))
    for record in records:
        print("  stage %2d -> Level %-4s page %-3d rect %s"
              % (record["stage"], record["level"], record["page"], tuple(record["rect"])))

    if args.json:
        args.json.write_text(json.dumps(records, indent=2), encoding="utf-8")
        print("wrote %s" % args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
