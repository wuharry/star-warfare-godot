#!/usr/bin/env python3
"""Read Star Warfare's legacy resDataSets.bytes without running Unity.

The format mirrors Res2DManager.LoadData and UnitDataTable.Load from the
decompiled Unity project. Tables are stored consecutively in the data file.
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO


def read_exact(stream: BinaryIO, size: int) -> bytes:
    data = stream.read(size)
    if len(data) != size:
        raise EOFError(f"wanted {size} bytes at 0x{stream.tell() - len(data):x}")
    return data


def read_i16(stream: BinaryIO) -> int:
    return struct.unpack("<h", read_exact(stream, 2))[0]


def read_i32(stream: BinaryIO) -> int:
    return struct.unpack("<i", read_exact(stream, 4))[0]


def read_unicode(stream: BinaryIO) -> str:
    byte_count = read_i16(stream)
    if byte_count < 0:
        raise ValueError(f"negative UTF-16 byte count at 0x{stream.tell() - 2:x}")
    return read_exact(stream, byte_count).decode("utf-16-le")


@dataclass
class UnityTable:
    index: int
    offset: int
    labels: list[str]
    formats: list[int]
    string_rows: list[list[str]]
    number_rows: list[list[int]]

    def value(self, row: int, column: int) -> str | int:
        value_format = self.formats[column] & 0xFFFFFFFF
        value_type = value_format & 0xFF
        storage_index = (value_format >> 8) & 0xFF
        bit_offset = (value_format >> 16) & 0xFF
        bit_width = (value_format >> 24) & 0xFF
        if value_type == 0:
            return self.string_rows[row][storage_index]
        value = self.number_rows[row][storage_index] >> bit_offset
        if bit_width < 32:
            value &= (1 << bit_width) - 1
        return value

    def decoded_rows(self) -> list[list[str | int]]:
        return [
            [self.value(row, column) for column in range(len(self.formats))]
            for row in range(len(self.number_rows))
        ]


def read_table(stream: BinaryIO, index: int) -> UnityTable:
    offset = stream.tell()
    column_count = read_i16(stream)
    row_count = read_i16(stream)
    if column_count <= 0 or row_count < 0:
        raise ValueError(
            f"invalid table {index} header at 0x{offset:x}: "
            f"{column_count} columns, {row_count} rows"
        )
    labels = [read_unicode(stream) for _ in range(column_count)]
    formats = [read_i32(stream) for _ in range(column_count)]
    string_count = read_i16(stream)
    number_count = read_i16(stream)
    if string_count < 0 or number_count < 0:
        raise ValueError(f"invalid storage counts in table {index}")
    string_rows: list[list[str]] = []
    number_rows: list[list[int]] = []
    for _ in range(row_count):
        string_rows.append([read_unicode(stream) for _ in range(string_count)])
        number_rows.append([read_i32(stream) for _ in range(number_count)])
    return UnityTable(index, offset, labels, formats, string_rows, number_rows)


def read_tables(path: Path) -> list[UnityTable]:
    tables: list[UnityTable] = []
    with path.open("rb") as stream:
        while stream.tell() < path.stat().st_size:
            tables.append(read_table(stream, len(tables)))
    return tables


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--table", type=int, action="append", dest="tables")
    args = parser.parse_args()
    tables = read_tables(args.dataset)
    selected = tables if args.tables is None else [tables[index] for index in args.tables]
    output = []
    for table in selected:
        output.append(
            {
                "index": table.index,
                "offset": table.offset,
                "columns": len(table.formats),
                "rows": len(table.number_rows),
                "labels": table.labels,
                "formats": [value & 0xFFFFFFFF for value in table.formats],
                "data": table.decoded_rows(),
            }
        )
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
