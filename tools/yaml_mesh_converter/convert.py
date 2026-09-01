#!/usr/bin/env python3
"""Convert legacy Unity YAML Mesh assets to Wavefront OBJ.

The Star Warfare project stores its meshes as text-serialized Unity 2017 assets.
This converter intentionally uses only Python's standard library, so it works on
a machine which has neither a Unity installation nor a Unity license.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence


CHANNEL_NAMES = ("position", "normal", "color", "uv0", "uv1", "tangent")
TEXTURE_PRIORITY = (
    "_MainTex",
    "_BaseMap",
    "_BaseColorMap",
    "_Albedo",
    "_texBase",
    "_tex2",
)


class ConversionError(RuntimeError):
    pass


@dataclass
class Channel:
    stream: int
    offset: int
    format: int
    dimension: int


@dataclass
class Stream:
    channel_mask: int
    offset: int
    stride: int


@dataclass
class SubMesh:
    first_byte: int
    index_count: int
    topology: int
    base_vertex: int = 0
    first_vertex: int = 0
    vertex_count: int = 0
    indices: list[int] = field(default_factory=list)


@dataclass
class MeshData:
    name: str
    positions: list[tuple[float, float, float]]
    normals: list[tuple[float, float, float]] | None
    uvs: list[tuple[float, float]] | None
    submeshes: list[SubMesh]
    source_path: Path


@dataclass
class PrefabRenderer:
    name: str
    kind: str
    mesh_guid: str
    material_guids: list[str]
    transform: tuple[tuple[float, ...], ...]


@dataclass
class MaterialInfo:
    name: str
    source_path: Path | None
    diffuse_source: Path | None
    diffuse_guid: str | None
    color: tuple[float, float, float, float]
    texture_property: str | None = None
    copied_name: str | None = None
    shader_guid: str | None = None
    shader_name: str = ""
    blend_mode: str = "opaque"
    cull_disabled: bool = False
    depth_write: bool = True
    alpha_scissor_threshold: float = 0.5


@dataclass
class ObjPiece:
    name: str
    mesh: MeshData
    transform: tuple[tuple[float, ...], ...]
    materials: list[MaterialInfo]


def _find_scalar(text: str, key: str, default: int | None = None) -> int:
    match = re.search(rf"^\s*{re.escape(key)}:\s*(-?\d+)\s*$", text, re.MULTILINE)
    if match:
        return int(match.group(1))
    if default is not None:
        return default
    raise ConversionError(f"Missing required field {key}")


def _parse_sequence_items(lines: Sequence[str], start: int, end: int, first_key: str) -> list[dict[str, int]]:
    items: list[dict[str, int]] = []
    current: dict[str, int] | None = None
    first_pattern = re.compile(rf"^\s*-\s+{re.escape(first_key)}:\s*(-?\d+)\s*$")
    field_pattern = re.compile(r"^\s+([A-Za-z][A-Za-z0-9_]*):\s*(-?\d+)\s*$")
    for line in lines[start:end]:
        first = first_pattern.match(line)
        if first:
            current = {first_key: int(first.group(1))}
            items.append(current)
            continue
        field_match = field_pattern.match(line)
        if current is not None and field_match:
            current[field_match.group(1)] = int(field_match.group(2))
    return items


def _line_index(lines: Sequence[str], exact: str, after: int = 0) -> int:
    for index in range(after, len(lines)):
        if lines[index].rstrip("\r\n") == exact:
            return index
    raise ConversionError(f"Missing YAML section: {exact.strip()}")


def _decode_component(data: bytes, offset: int, value_format: int) -> tuple[float, int]:
    """Decode Unity 2017.4's VertexFormat enum into an OBJ-friendly float."""
    if value_format == 0:  # Float32
        return struct.unpack_from("<f", data, offset)[0], 4
    if value_format == 1:  # Float16
        return struct.unpack_from("<e", data, offset)[0], 2
    if value_format == 2:  # UNorm8
        return data[offset] / 255.0, 1
    if value_format == 3:  # SNorm8
        return max(-1.0, struct.unpack_from("<b", data, offset)[0] / 127.0), 1
    if value_format == 4:  # UNorm16
        return struct.unpack_from("<H", data, offset)[0] / 65535.0, 2
    if value_format == 5:  # SNorm16
        return max(-1.0, struct.unpack_from("<h", data, offset)[0] / 32767.0), 2
    if value_format == 6:  # UInt8
        return float(data[offset]), 1
    if value_format == 7:  # SInt8
        return float(struct.unpack_from("<b", data, offset)[0]), 1
    if value_format == 8:  # UInt16
        return float(struct.unpack_from("<H", data, offset)[0]), 2
    if value_format == 9:  # SInt16
        return float(struct.unpack_from("<h", data, offset)[0]), 2
    if value_format == 10:  # UInt32
        return float(struct.unpack_from("<I", data, offset)[0]), 4
    if value_format == 11:  # SInt32
        return float(struct.unpack_from("<i", data, offset)[0]), 4
    raise ConversionError(f"Unsupported Unity VertexFormat value {value_format}")


def _component_size(value_format: int) -> int:
    if value_format in (0, 10, 11):
        return 4
    if value_format in (1, 4, 5, 8, 9):
        return 2
    if value_format in (2, 3, 6, 7):
        return 1
    raise ConversionError(f"Unsupported Unity VertexFormat value {value_format}")


def _decode_channel(
    data: bytes,
    vertex_count: int,
    channel: Channel,
    streams: Sequence[Stream],
) -> list[tuple[float, ...]]:
    if channel.stream < 0 or channel.stream >= len(streams):
        raise ConversionError(f"Channel refers to missing stream {channel.stream}")
    stream = streams[channel.stream]
    if stream.stride <= 0:
        raise ConversionError(f"Channel refers to empty stream {channel.stream}")
    values: list[tuple[float, ...]] = []
    for vertex_index in range(vertex_count):
        cursor = stream.offset + vertex_index * stream.stride + channel.offset
        components: list[float] = []
        try:
            for _ in range(channel.dimension):
                value, size = _decode_component(data, cursor, channel.format)
                components.append(value)
                cursor += size
        except struct.error as error:
            raise ConversionError(
                f"Vertex {vertex_index} channel overruns m_DataSize ({len(data)} bytes)"
            ) from error
        if cursor > len(data):
            raise ConversionError(
                f"Vertex {vertex_index} channel overruns m_DataSize ({len(data)} bytes)"
            )
        if not all(math.isfinite(value) for value in components):
            raise ConversionError(f"Vertex {vertex_index} contains a non-finite value")
        values.append(tuple(components))
    return values


def _packed_vector_block(compressed_text: str, field_name: str) -> str:
    marker = f"    {field_name}:"
    start = compressed_text.find(marker)
    if start < 0:
        raise ConversionError(f"Compressed mesh is missing {field_name}")
    body_start = compressed_text.find("\n", start)
    if body_start < 0:
        return ""
    end = compressed_text.find("\n    m_", body_start + 1)
    return compressed_text[body_start + 1 : end if end >= 0 else len(compressed_text)]


def _packed_scalar(block: str, key: str, default: float | None = None) -> float:
    match = re.search(
        rf"^\s*{re.escape(key)}:\s*(-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*$",
        block,
        re.MULTILINE,
    )
    if match:
        return float(match.group(1))
    if default is not None:
        return default
    raise ConversionError(f"Compressed vector is missing {key}")


def _unpack_packed_bits(data: bytes, item_count: int, bit_size: int) -> list[int]:
    if item_count == 0:
        return []
    if bit_size <= 0 or bit_size > 32:
        raise ConversionError(f"Invalid compressed vector bit size {bit_size}")
    required_bits = item_count * bit_size
    if required_bits > len(data) * 8:
        raise ConversionError(
            f"Compressed vector needs {required_bits} bits but contains only {len(data) * 8}"
        )
    values: list[int] = []
    mask = (1 << bit_size) - 1
    bit_offset = 0
    for _ in range(item_count):
        byte_offset = bit_offset // 8
        shift = bit_offset % 8
        # At most 32 bits are stored, but the value may straddle five bytes.
        chunk = int.from_bytes(data[byte_offset : byte_offset + 5], "little")
        values.append((chunk >> shift) & mask)
        bit_offset += bit_size
    return values


def _unpack_packed_int(compressed_text: str, field_name: str) -> list[int]:
    block = _packed_vector_block(compressed_text, field_name)
    item_count = int(_packed_scalar(block, "m_NumItems", 0))
    bit_size = int(_packed_scalar(block, "m_BitSize", 0))
    data_match = re.search(r"^\s*m_Data:\s*([0-9a-fA-F]*)\s*$", block, re.MULTILINE)
    if not data_match:
        raise ConversionError(f"Compressed vector {field_name} is missing m_Data")
    return _unpack_packed_bits(bytes.fromhex(data_match.group(1)), item_count, bit_size)


def _unpack_packed_float(compressed_text: str, field_name: str) -> list[float]:
    block = _packed_vector_block(compressed_text, field_name)
    item_count = int(_packed_scalar(block, "m_NumItems", 0))
    if item_count == 0:
        return []
    value_range = _packed_scalar(block, "m_Range")
    value_start = _packed_scalar(block, "m_Start")
    bit_size = int(_packed_scalar(block, "m_BitSize"))
    data_match = re.search(r"^\s*m_Data:\s*([0-9a-fA-F]*)\s*$", block, re.MULTILINE)
    if not data_match:
        raise ConversionError(f"Compressed vector {field_name} is missing m_Data")
    integers = _unpack_packed_bits(bytes.fromhex(data_match.group(1)), item_count, bit_size)
    denominator = float((1 << bit_size) - 1)
    return [value_start + float(value) * value_range / denominator for value in integers]


def _parse_compressed_mesh(
    path: Path,
    text: str,
    name: str,
    submeshes: list[SubMesh],
) -> MeshData:
    compressed_start = text.find("  m_CompressedMesh:")
    if compressed_start < 0:
        raise ConversionError(f"{path}: missing m_CompressedMesh")
    compressed_text = text[compressed_start:]
    vertex_values = _unpack_packed_float(compressed_text, "m_Vertices")
    if not vertex_values or len(vertex_values) % 3:
        raise ConversionError(f"{path}: compressed positions are empty or not xyz triples")
    vertex_count = len(vertex_values) // 3
    positions = [
        (vertex_values[index], vertex_values[index + 1], vertex_values[index + 2])
        for index in range(0, len(vertex_values), 3)
    ]

    uv_values = _unpack_packed_float(compressed_text, "m_UV")
    uvs = None
    if len(uv_values) >= vertex_count * 2:
        uvs = [
            (uv_values[index], uv_values[index + 1])
            for index in range(0, vertex_count * 2, 2)
        ]

    normals = None
    normal_values = _unpack_packed_float(compressed_text, "m_Normals")
    if len(normal_values) >= vertex_count * 2:
        signs = _unpack_packed_int(compressed_text, "m_NormalSigns")
        normals = []
        for vertex_index in range(vertex_count):
            x = normal_values[vertex_index * 2]
            y = normal_values[vertex_index * 2 + 1]
            z_squared = 1.0 - x * x - y * y
            if z_squared < 0.0:
                length = math.sqrt(x * x + y * y)
                x, y = (x / length, y / length) if length > 1e-12 else (0.0, 0.0)
                z = 0.0
            else:
                z = math.sqrt(z_squared)
            if vertex_index < len(signs) and signs[vertex_index] == 0:
                z = -z
            normals.append((x, y, z))

    all_indices = _unpack_packed_int(compressed_text, "m_Triangles")
    index_size = 4 if _find_scalar(text, "m_IndexFormat", 0) == 1 else 2
    for submesh_number, submesh in enumerate(submeshes):
        if submesh.topology != 0:
            raise ConversionError(
                f"{path}: submesh {submesh_number} uses topology {submesh.topology}; only triangles are supported"
            )
        if submesh.index_count % 3:
            raise ConversionError(f"{path}: submesh {submesh_number} index count is not divisible by three")
        first_index = submesh.first_byte // index_size
        end_index = first_index + submesh.index_count
        if first_index < 0 or end_index > len(all_indices):
            raise ConversionError(f"{path}: submesh {submesh_number} indexes overrun compressed triangles")
        submesh.indices = [index + submesh.base_vertex for index in all_indices[first_index:end_index]]
        if any(index < 0 or index >= vertex_count for index in submesh.indices):
            raise ConversionError(f"{path}: submesh {submesh_number} references an invalid vertex")
    return MeshData(name, positions, normals, uvs, submeshes, path)


def parse_mesh(path: Path) -> MeshData:
    text = path.read_text(encoding="utf-8-sig")
    if not re.search(r"^--- !u!43\s+&", text, re.MULTILINE):
        raise ConversionError(f"{path} is not a text-serialized Unity Mesh asset")
    # Asset recovery tools do not always emit serializedVersion immediately
    # after the Mesh header (static-batch meshes commonly keep ObjectHideFlags
    # and prefab fields first), so accept the field anywhere in the Mesh body.
    version_match = re.search(r"^\s+serializedVersion:\s*(\d+)\s*$", text, re.MULTILINE)
    if not version_match or int(version_match.group(1)) != 8:
        actual = version_match.group(1) if version_match else "unknown"
        raise ConversionError(f"{path}: only Mesh serializedVersion 8 is supported (found {actual})")
    mesh_compression = _find_scalar(text, "m_MeshCompression", 0)

    name_match = re.search(r"^\s+m_Name:\s*(.*?)\s*$", text, re.MULTILINE)
    name = name_match.group(1) if name_match else path.stem
    lines = text.splitlines()

    submesh_start = _line_index(lines, "  m_SubMeshes:") + 1
    submesh_end = _line_index(lines, "  m_Shapes:", submesh_start)
    raw_submeshes = _parse_sequence_items(lines, submesh_start, submesh_end, "serializedVersion")
    submeshes = [
        SubMesh(
            first_byte=item.get("firstByte", 0),
            index_count=item.get("indexCount", 0),
            topology=item.get("topology", 0),
            base_vertex=item.get("baseVertex", 0),
            first_vertex=item.get("firstVertex", 0),
            vertex_count=item.get("vertexCount", 0),
        )
        for item in raw_submeshes
    ]
    if not submeshes:
        raise ConversionError(f"{path}: mesh has no submeshes")
    if mesh_compression != 0:
        return _parse_compressed_mesh(path, text, name, submeshes)

    index_match = re.search(r"^\s+m_IndexBuffer:\s*([0-9a-fA-F]*)\s*$", text, re.MULTILINE)
    if not index_match:
        raise ConversionError(f"{path}: missing m_IndexBuffer")
    index_data = bytes.fromhex(index_match.group(1))
    index_format = _find_scalar(text, "m_IndexFormat", 0)
    index_size = 4 if index_format == 1 else 2
    index_code = "<I" if index_size == 4 else "<H"

    vertex_data_start = _line_index(lines, "  m_VertexData:")
    compressed_start = _line_index(lines, "  m_CompressedMesh:", vertex_data_start)
    vertex_text = "\n".join(lines[vertex_data_start:compressed_start])
    vertex_count = _find_scalar(vertex_text, "m_VertexCount")

    channels_start = _line_index(lines, "    m_Channels:", vertex_data_start) + 1
    streams_start = next(
        (i for i in range(channels_start, compressed_start) if lines[i] == "    m_Streams:"),
        -1,
    )
    data_search_start = streams_start if streams_start >= 0 else channels_start
    data_size_line = next(
        (i for i in range(data_search_start, compressed_start) if lines[i].startswith("    m_DataSize:")),
        -1,
    )
    if data_size_line < 0:
        raise ConversionError(f"{path}: missing m_DataSize")
    raw_channels = _parse_sequence_items(
        lines,
        channels_start,
        streams_start if streams_start >= 0 else data_size_line,
        "stream",
    )
    channels = [
        Channel(item["stream"], item.get("offset", 0), item.get("format", 0), item.get("dimension", 0))
        for item in raw_channels
    ]
    if streams_start >= 0:
        raw_streams = _parse_sequence_items(lines, streams_start + 1, data_size_line, "channelMask")
        streams = [
            Stream(item.get("channelMask", 0), item.get("offset", 0), item.get("stride", 0))
            for item in raw_streams
        ]
    else:
        # Unity's static-batch serialization may omit m_Streams. Reconstruct
        # each stream from channel offsets and formats; its byte blocks are
        # stored consecutively in _typelessdata.
        stream_count = max((channel.stream for channel in channels), default=-1) + 1
        streams = []
        stream_offset = 0
        for stream_index in range(stream_count):
            channel_mask = 0
            stride = 0
            for channel_index, channel in enumerate(channels):
                if channel.stream != stream_index or channel.dimension <= 0:
                    continue
                channel_mask |= 1 << channel_index
                stride = max(
                    stride,
                    channel.offset + _component_size(channel.format) * channel.dimension,
                )
            stride = (stride + 3) & ~3
            streams.append(Stream(channel_mask, stream_offset, stride))
            stream_offset += stride * vertex_count
    data_size = _find_scalar("\n".join(lines[data_size_line:compressed_start]), "m_DataSize")
    data_match = re.search(r"^\s+_typelessdata:\s*([0-9a-fA-F]*)\s*$", vertex_text, re.MULTILINE)
    if not data_match:
        raise ConversionError(f"{path}: missing m_VertexData._typelessdata")
    vertex_bytes = bytes.fromhex(data_match.group(1))
    if len(vertex_bytes) != data_size:
        raise ConversionError(
            f"{path}: m_DataSize says {data_size}, but _typelessdata contains {len(vertex_bytes)} bytes"
        )
    if not channels or channels[0].dimension < 3:
        raise ConversionError(f"{path}: mesh has no 3D position channel")

    decoded: dict[str, list[tuple[float, ...]]] = {}
    for channel_index, channel in enumerate(channels):
        if channel.dimension <= 0:
            continue
        semantic = CHANNEL_NAMES[channel_index] if channel_index < len(CHANNEL_NAMES) else f"channel{channel_index}"
        decoded[semantic] = _decode_channel(vertex_bytes, vertex_count, channel, streams)

    positions = [tuple(value[:3]) for value in decoded["position"]]
    normals = [tuple(value[:3]) for value in decoded.get("normal", [])] or None
    uvs = [tuple(value[:2]) for value in decoded.get("uv0", [])] or None

    for submesh_number, submesh in enumerate(submeshes):
        if submesh.topology != 0:
            raise ConversionError(
                f"{path}: submesh {submesh_number} uses topology {submesh.topology}; only triangles are supported"
            )
        if submesh.index_count % 3:
            raise ConversionError(f"{path}: submesh {submesh_number} index count is not divisible by three")
        end = submesh.first_byte + submesh.index_count * index_size
        if submesh.first_byte < 0 or end > len(index_data):
            raise ConversionError(f"{path}: submesh {submesh_number} indexes overrun m_IndexBuffer")
        submesh.indices = [
            struct.unpack_from(index_code, index_data, submesh.first_byte + i * index_size)[0]
            + submesh.base_vertex
            for i in range(submesh.index_count)
        ]
        if any(index < 0 or index >= vertex_count for index in submesh.indices):
            raise ConversionError(f"{path}: submesh {submesh_number} references an invalid vertex")

    return MeshData(name, positions, normals, uvs, submeshes, path)


def identity_matrix() -> tuple[tuple[float, ...], ...]:
    return (
        (1.0, 0.0, 0.0, 0.0),
        (0.0, 1.0, 0.0, 0.0),
        (0.0, 0.0, 1.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    )


def matrix_multiply(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> tuple[tuple[float, ...], ...]:
    return tuple(
        tuple(sum(a[row][k] * b[k][column] for k in range(4)) for column in range(4))
        for row in range(4)
    )


def local_matrix(
    position: tuple[float, float, float],
    rotation: tuple[float, float, float, float],
    scale: tuple[float, float, float],
) -> tuple[tuple[float, ...], ...]:
    x, y, z, w = rotation
    length = math.sqrt(x * x + y * y + z * z + w * w)
    if length > 1e-12:
        x, y, z, w = x / length, y / length, z / length, w / length
    sx, sy, sz = scale
    return (
        ((1 - 2 * (y * y + z * z)) * sx, (2 * (x * y - z * w)) * sy, (2 * (x * z + y * w)) * sz, position[0]),
        ((2 * (x * y + z * w)) * sx, (1 - 2 * (x * x + z * z)) * sy, (2 * (y * z - x * w)) * sz, position[1]),
        ((2 * (x * z - y * w)) * sx, (2 * (y * z + x * w)) * sy, (1 - 2 * (x * x + y * y)) * sz, position[2]),
        (0.0, 0.0, 0.0, 1.0),
    )


def _yaml_vector(text: str, key: str, count: int, default: tuple[float, ...]) -> tuple[float, ...]:
    match = re.search(rf"^\s*{re.escape(key)}:\s*\{{([^}}]+)\}}", text, re.MULTILINE)
    if not match:
        return default
    values: dict[str, float] = {}
    for field_name, raw in re.findall(r"([xyzw]):\s*([-+0-9.eE]+)", match.group(1)):
        values[field_name] = float(raw)
    names = "xyzw"[:count]
    return tuple(values.get(name, default[index]) for index, name in enumerate(names))


def _documents(text: str) -> list[tuple[int, int, str]]:
    header = re.compile(r"^--- !u!(\d+) &(\d+)\s*$", re.MULTILINE)
    matches = list(header.finditer(text))
    return [
        (
            int(match.group(1)),
            int(match.group(2)),
            text[match.end() : matches[index + 1].start() if index + 1 < len(matches) else len(text)],
        )
        for index, match in enumerate(matches)
    ]


def _reference_guid(text: str, key: str) -> str | None:
    match = re.search(rf"^\s*{re.escape(key)}:\s*\{{[^}}]*guid:\s*([0-9a-f]{{32}})", text, re.MULTILINE)
    return match.group(1) if match else None


def _material_guids(renderer_text: str) -> list[str]:
    match = re.search(r"^\s*m_Materials:\s*$", renderer_text, re.MULTILINE)
    if not match:
        return []
    guids: list[str] = []
    for line in renderer_text[match.end() :].splitlines():
        if not re.match(r"^\s+-\s+\{", line):
            if line.strip():
                break
            continue
        guid_match = re.search(r"guid:\s*([0-9a-f]{32})", line)
        if guid_match:
            guids.append(guid_match.group(1))
    return guids


def parse_prefab_renderers(path: Path) -> list[PrefabRenderer]:
    text = path.read_text(encoding="utf-8-sig")
    documents = _documents(text)
    game_names: dict[int, str] = {}
    transforms: dict[int, tuple[int, int, tuple[tuple[float, ...], ...]]] = {}
    transform_for_game_object: dict[int, int] = {}
    mesh_filters: dict[int, str] = {}
    renderers: list[tuple[str, int, str, list[str]]] = []

    for class_id, file_id, body in documents:
        game_match = re.search(r"m_GameObject:\s*\{fileID:\s*(\d+)\}", body)
        game_object = int(game_match.group(1)) if game_match else 0
        if class_id == 1:
            name_match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", body, re.MULTILINE)
            if name_match:
                game_names[file_id] = name_match.group(1)
        elif class_id == 4:
            father_match = re.search(r"m_Father:\s*\{fileID:\s*(\d+)\}", body)
            father = int(father_match.group(1)) if father_match else 0
            position = _yaml_vector(body, "m_LocalPosition", 3, (0.0, 0.0, 0.0))
            rotation = _yaml_vector(body, "m_LocalRotation", 4, (0.0, 0.0, 0.0, 1.0))
            scale = _yaml_vector(body, "m_LocalScale", 3, (1.0, 1.0, 1.0))
            transforms[file_id] = (game_object, father, local_matrix(position, rotation, scale))
            transform_for_game_object[game_object] = file_id
        elif class_id == 33:
            mesh_guid = _reference_guid(body, "m_Mesh")
            if mesh_guid:
                mesh_filters[game_object] = mesh_guid
        elif class_id in (23, 137):
            enabled_match = re.search(r"^\s*m_Enabled:\s*(\d+)", body, re.MULTILINE)
            if enabled_match and int(enabled_match.group(1)) == 0:
                continue
            mesh_guid = _reference_guid(body, "m_Mesh") if class_id == 137 else None
            renderers.append(("SkinnedMeshRenderer" if class_id == 137 else "MeshRenderer", game_object, mesh_guid or "", _material_guids(body)))

    def world_transform(game_object: int) -> tuple[tuple[float, ...], ...]:
        transform_id = transform_for_game_object.get(game_object, 0)
        result = identity_matrix()
        visited: set[int] = set()
        while transform_id:
            if transform_id in visited or transform_id not in transforms:
                raise ConversionError(f"{path}: broken/cyclic Transform hierarchy at fileID {transform_id}")
            visited.add(transform_id)
            _, father, local = transforms[transform_id]
            result = matrix_multiply(local, result)
            transform_id = father
        return result

    result: list[PrefabRenderer] = []
    for kind, game_object, direct_mesh, materials in renderers:
        mesh_guid = direct_mesh or mesh_filters.get(game_object, "")
        if not mesh_guid:
            continue
        result.append(
            PrefabRenderer(
                game_names.get(game_object, f"GameObject_{game_object}"),
                kind,
                mesh_guid,
                materials,
                world_transform(game_object),
            )
        )
    return result


class GuidIndex:
    def __init__(self, assets_root: Path):
        self.assets_root = assets_root
        self._paths: dict[str, Path] = {}
        for meta_path in assets_root.rglob("*.meta"):
            try:
                with meta_path.open("r", encoding="utf-8-sig", errors="replace") as stream:
                    for line in stream:
                        if line.startswith("guid:"):
                            guid = line.split(":", 1)[1].strip()
                            if re.fullmatch(r"[0-9a-f]{32}", guid):
                                self._paths[guid] = Path(str(meta_path)[:-5])
                            break
            except OSError:
                continue

    def resolve(self, guid: str) -> Path:
        try:
            return self._paths[guid]
        except KeyError as error:
            raise ConversionError(f"Could not resolve Unity GUID {guid} beneath {self.assets_root}") from error


def _shader_state(
    shader_guid: str | None,
    guid_index: GuidIndex,
) -> tuple[str, str, bool, bool, float, str]:
    if not shader_guid or shader_guid == "0000000000000000f000000000000000":
        return ("builtin", "opaque", False, True, 0.5, "")
    try:
        shader_path = guid_index.resolve(shader_guid)
        shader_text = shader_path.read_text(encoding="utf-8-sig", errors="replace")
    except (ConversionError, OSError):
        return (shader_guid, "opaque", False, True, 0.5, "")

    name_match = re.search(r'^\s*Shader\s+"([^"]+)"', shader_text, re.MULTILINE)
    shader_name = name_match.group(1) if name_match else shader_path.stem
    blend_mode = "opaque"
    if re.search(r"\bBlend\s+(?:SrcAlpha|One)\s+One\b", shader_text, re.IGNORECASE):
        blend_mode = "additive"
    elif re.search(r"\bBlend\s+SrcAlpha\s+OneMinusSrcAlpha\b", shader_text, re.IGNORECASE):
        blend_mode = "alpha"
    elif re.search(r"\bAlphaTest\b", shader_text, re.IGNORECASE):
        blend_mode = "cutout"
    elif re.search(r'"(?:Queue|QUEUE)"\s*=\s*"Transparent', shader_text, re.IGNORECASE):
        blend_mode = "alpha"
    cutoff_match = re.search(
        r"\bAlphaTest\s+Greater\s+([-+0-9.eE]+)",
        shader_text,
        re.IGNORECASE,
    )
    cutoff = float(cutoff_match.group(1)) if cutoff_match else 0.5
    return (
        shader_name,
        blend_mode,
        bool(re.search(r"\bCull\s+Off\b", shader_text, re.IGNORECASE)),
        not bool(re.search(r"\bZWrite\s+Off\b", shader_text, re.IGNORECASE)),
        cutoff,
        shader_text,
    )


def _material_colors(text: str) -> dict[str, tuple[float, float, float, float]]:
    result: dict[str, tuple[float, float, float, float]] = {}
    modern_pattern = re.compile(
        r"name:\s*([^\s]+)\s*\r?\n\s+second:\s*\{r:\s*([-+0-9.eE]+),\s*"
        r"g:\s*([-+0-9.eE]+),\s*b:\s*([-+0-9.eE]+),\s*a:\s*([-+0-9.eE]+)\}"
    )
    for match in modern_pattern.finditer(text):
        result[match.group(1)] = tuple(float(value) for value in match.groups()[1:])
    legacy_pattern = re.compile(
        r"-\s+([^\s:]+):\s*\{r:\s*([-+0-9.eE]+),\s*g:\s*([-+0-9.eE]+),\s*"
        r"b:\s*([-+0-9.eE]+),\s*a:\s*([-+0-9.eE]+)\}"
    )
    for match in legacy_pattern.finditer(text):
        result[match.group(1)] = tuple(float(value) for value in match.groups()[1:])
    return result


def parse_material(path: Path, guid_index: GuidIndex) -> MaterialInfo:
    text = path.read_text(encoding="utf-8-sig")
    name_match = re.search(r"^\s*m_Name:\s*(.*?)\s*$", text, re.MULTILINE)
    name = name_match.group(1) if name_match else path.stem
    texture_entries: dict[str, str] = {}
    entry_pattern = re.compile(
        r"-\s+first:\s*\r?\n\s+name:\s*([^\s]+).*?"
        r"m_Texture:\s*\{[^}]*guid:\s*([0-9a-f]{32})",
        re.DOTALL,
    )
    for property_name, texture_guid in entry_pattern.findall(text):
        texture_entries[property_name] = texture_guid
    # Unity 2017 also serializes material dictionaries directly as
    # ``- _MainTex:`` / ``- _texBase:`` instead of the newer first/second
    # pair representation above.  Most recovered late-game lightmapped
    # levels use this layout; ignoring it produced valid OBJ geometry whose
    # materials were all flat grey.
    legacy_entry_pattern = re.compile(
        r"^\s*-\s+([^\s:]+):\s*\r?\n"
        r"\s+m_Texture:\s*\{[^}]*guid:\s*([0-9a-f]{32})",
        re.MULTILINE,
    )
    for property_name, texture_guid in legacy_entry_pattern.findall(text):
        texture_entries[property_name] = texture_guid
    chosen_property = next((key for key in TEXTURE_PRIORITY if key in texture_entries), None)
    chosen_guid = texture_entries.get(chosen_property) if chosen_property else None
    diffuse_source = guid_index.resolve(chosen_guid) if chosen_guid else None

    shader_match = re.search(
        r"^\s*m_Shader:\s*\{[^}]*guid:\s*([0-9a-f]{32})",
        text,
        re.MULTILINE,
    )
    shader_guid = shader_match.group(1) if shader_match else None
    shader_name, blend_mode, cull_disabled, depth_write, cutoff, shader_text = _shader_state(
        shader_guid,
        guid_index,
    )
    colors = _material_colors(text)
    if shader_text and re.search(r"\b_TintColor\b", shader_text):
        color = colors.get("_TintColor", (1.0, 1.0, 1.0, 1.0))
    elif shader_text and re.search(r"\b_Color\b", shader_text):
        color = colors.get("_Color", (1.0, 1.0, 1.0, 1.0))
    elif not shader_text:
        color = colors.get("_Color", (1.0, 1.0, 1.0, 1.0))
    else:
        color = (1.0, 1.0, 1.0, 1.0)
    return MaterialInfo(
        name,
        path,
        diffuse_source,
        chosen_guid,
        color,
        chosen_property,
        None,
        shader_guid,
        shader_name,
        blend_mode,
        cull_disabled,
        depth_write,
        cutoff,
    )


def fallback_material(name: str) -> MaterialInfo:
    return MaterialInfo(name, None, None, None, (0.8, 0.8, 0.8, 1.0))


def _sanitize_name(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    return cleaned or "unnamed"


def _transform_point(matrix: Sequence[Sequence[float]], value: Sequence[float]) -> tuple[float, float, float]:
    x, y, z = value[:3]
    return (
        matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z + matrix[0][3],
        matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z + matrix[1][3],
        matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z + matrix[2][3],
    )


def _determinant3(matrix: Sequence[Sequence[float]]) -> float:
    return (
        matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
        - matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0])
        + matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
    )


def _normal_matrix(matrix: Sequence[Sequence[float]]) -> tuple[tuple[float, ...], ...]:
    determinant = _determinant3(matrix)
    if abs(determinant) < 1e-12:
        raise ConversionError("A prefab renderer has a singular transform")
    a, b, c = matrix[0][:3]
    d, e, f = matrix[1][:3]
    g, h, i = matrix[2][:3]
    inverse = (
        ((e * i - f * h) / determinant, (c * h - b * i) / determinant, (b * f - c * e) / determinant),
        ((f * g - d * i) / determinant, (a * i - c * g) / determinant, (c * d - a * f) / determinant),
        ((d * h - e * g) / determinant, (b * g - a * h) / determinant, (a * e - b * d) / determinant),
    )
    return tuple(tuple(inverse[column][row] for column in range(3)) for row in range(3))


def _normalize(value: Sequence[float]) -> tuple[float, float, float]:
    length = math.sqrt(sum(component * component for component in value[:3]))
    if length < 1e-15:
        return (0.0, 1.0, 0.0)
    return tuple(component / length for component in value[:3])


def _transform_direction(matrix: Sequence[Sequence[float]], value: Sequence[float]) -> tuple[float, float, float]:
    x, y, z = value[:3]
    return _normalize(
        (
            matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z,
            matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z,
            matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z,
        )
    )


def _cross(a: Sequence[float], b: Sequence[float]) -> tuple[float, float, float]:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _generated_normals(
    positions: Sequence[Sequence[float]], faces: Sequence[tuple[int, int, int]]
) -> list[tuple[float, float, float]]:
    accumulators = [[0.0, 0.0, 0.0] for _ in positions]
    for first, second, third in faces:
        a, b, c = positions[first], positions[second], positions[third]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        normal = _cross(ab, ac)
        for vertex_index in (first, second, third):
            for component in range(3):
                accumulators[vertex_index][component] += normal[component]
    return [_normalize(value) for value in accumulators]


def _godot_transform(prefab_transform: Sequence[Sequence[float]]) -> tuple[tuple[float, ...], ...]:
    # Unity is left-handed with +Z forward; Godot is right-handed with -Z forward.
    mirror_z = (
        (1.0, 0.0, 0.0, 0.0),
        (0.0, 1.0, 0.0, 0.0),
        (0.0, 0.0, -1.0, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    )
    return matrix_multiply(mirror_z, prefab_transform)


def _copy_material_textures(materials: Iterable[MaterialInfo], output_dir: Path) -> None:
    claimed: dict[str, Path] = {}
    for material in materials:
        source = material.diffuse_source
        if source is None:
            continue
        if not source.is_file():
            raise ConversionError(f"Referenced diffuse texture is missing: {source}")
        # Spaces are legal in many MTL readers but not handled consistently by
        # importers. Keep copied names portable across Godot and DCC tools.
        destination_name = _sanitize_name(source.name)
        if destination_name.casefold() in claimed and claimed[destination_name.casefold()] != source:
            destination_name = f"{source.stem}_{(material.diffuse_guid or 'texture')[:8]}{source.suffix}"
        claimed[destination_name.casefold()] = source
        destination = output_dir / destination_name
        if source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
        material.copied_name = destination_name


def _material_identity(material: MaterialInfo) -> tuple[object, ...]:
    """Return the render state that makes two OBJ materials interchangeable.

    Unity static batches repeat the same source material for many submeshes.
    Emitting a new MTL entry for every occurrence can exceed Godot's 256
    surfaces-per-mesh limit and silently discard the tail of a restored level.
    Keep genuinely different source assets separate, including basename
    collisions that were assigned different copied texture names.
    """

    return (
        material.name,
        str(material.source_path.resolve()) if material.source_path else "",
        str(material.diffuse_source.resolve()) if material.diffuse_source else "",
        material.diffuse_guid or "",
        material.color,
        material.texture_property or "",
        material.copied_name or "",
        material.shader_guid or "",
        material.shader_name,
        material.blend_mode,
        material.cull_disabled,
        material.depth_write,
        material.alpha_scissor_threshold,
    )


def write_obj(
    output_path: Path,
    pieces: Sequence[ObjPiece],
    *,
    group_faces_by_material: bool = False,
) -> dict[str, object]:
    if not pieces:
        raise ConversionError("No renderable mesh pieces were selected")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    material_list: list[MaterialInfo] = []
    for piece in pieces:
        material_list.extend(piece.materials)
    _copy_material_textures(material_list, output_path.parent)

    material_names: dict[int, str] = {}
    canonical_materials: list[MaterialInfo] = []
    canonical_by_identity: dict[tuple[object, ...], MaterialInfo] = {}
    used_names: set[str] = set()
    for material in material_list:
        if group_faces_by_material:
            identity = _material_identity(material)
            canonical = canonical_by_identity.get(identity)
            if canonical is not None:
                material_names[id(material)] = material_names[id(canonical)]
                continue
        base_name = _sanitize_name(material.name)
        unique_name = base_name
        suffix = 2
        while unique_name in used_names:
            unique_name = f"{base_name}_{suffix}"
            suffix += 1
        used_names.add(unique_name)
        material_names[id(material)] = unique_name
        if group_faces_by_material:
            canonical_by_identity[identity] = material
            canonical_materials.append(material)

    if not group_faces_by_material:
        emitted_material_ids: set[int] = set()
        canonical_materials = []
        for material in material_list:
            if id(material) in emitted_material_ids:
                continue
            emitted_material_ids.add(id(material))
            canonical_materials.append(material)

    obj_lines = ["# Generated from legacy Unity YAML Mesh assets without Unity."]
    if group_faces_by_material:
        obj_lines.append("# Material schema 4: Unity shader state and grouped diffuse materials.")
    obj_lines.append(f"mtllib {output_path.with_suffix('.mtl').name}")
    if group_faces_by_material:
        obj_lines.extend(("", f"o {_sanitize_name(output_path.stem)}"))
    face_lines_by_material: dict[str, list[str]] = {}
    vertex_base = 0
    uv_base = 0
    normal_base = 0
    total_faces = 0
    source_normals = 0
    generated_normals = 0

    for piece in pieces:
        transform = _godot_transform(piece.transform)
        positions = [_transform_point(transform, position) for position in piece.mesh.positions]
        reverse_winding = _determinant3(transform) < 0.0
        faces_by_submesh: list[list[tuple[int, int, int]]] = []
        flat_faces: list[tuple[int, int, int]] = []
        for submesh in piece.mesh.submeshes:
            faces: list[tuple[int, int, int]] = []
            for offset in range(0, len(submesh.indices), 3):
                face = tuple(submesh.indices[offset : offset + 3])
                if reverse_winding:
                    face = (face[0], face[2], face[1])
                # Recovered static-batch meshes occasionally retain zero-area
                # padding triangles. Godot and strict OBJ validators reject
                # those, and removing them has no visible or physical effect.
                if len(set(face)) < 3:
                    continue
                first, second, third = (positions[index] for index in face)
                ab = tuple(second[i] - first[i] for i in range(3))
                ac = tuple(third[i] - first[i] for i in range(3))
                cross = _cross(ab, ac)
                if sum(component * component for component in cross) <= 1e-20:
                    continue
                faces.append(face)
                flat_faces.append(face)
            faces_by_submesh.append(faces)

        if piece.mesh.normals is not None:
            normal_transform = _normal_matrix(transform)
            normals = [_transform_direction(normal_transform, normal) for normal in piece.mesh.normals]
            source_normals += len(normals)
        else:
            normals = _generated_normals(positions, flat_faces)
            generated_normals += len(normals)

        if not group_faces_by_material:
            obj_lines.extend(("", f"o {_sanitize_name(piece.name)}"))
        obj_lines.extend(f"v {x:.9g} {y:.9g} {z:.9g}" for x, y, z in positions)
        if piece.mesh.uvs is not None:
            obj_lines.extend(f"vt {u:.9g} {v:.9g}" for u, v in piece.mesh.uvs)
        obj_lines.extend(f"vn {x:.9g} {y:.9g} {z:.9g}" for x, y, z in normals)

        for submesh_index, faces in enumerate(faces_by_submesh):
            material = (
                piece.materials[submesh_index]
                if submesh_index < len(piece.materials)
                else piece.materials[-1]
            )
            material_name = material_names[id(material)]
            if group_faces_by_material:
                if not faces:
                    continue
                material_faces = face_lines_by_material.setdefault(material_name, [])
            else:
                obj_lines.extend(
                    (
                        "",
                        f"g {_sanitize_name(piece.name)}_submesh_{submesh_index}",
                        f"usemtl {material_name}",
                    )
                )
            for face in faces:
                fields: list[str] = []
                for local_index in face:
                    vertex_index = vertex_base + local_index + 1
                    normal_index = normal_base + local_index + 1
                    if piece.mesh.uvs is not None:
                        texture_index = uv_base + local_index + 1
                        fields.append(f"{vertex_index}/{texture_index}/{normal_index}")
                    else:
                        fields.append(f"{vertex_index}//{normal_index}")
                face_line = "f " + " ".join(fields)
                if group_faces_by_material:
                    material_faces.append(face_line)
                else:
                    obj_lines.append(face_line)
                total_faces += 1

        vertex_base += len(positions)
        normal_base += len(normals)
        if piece.mesh.uvs is not None:
            uv_base += len(piece.mesh.uvs)

    if group_faces_by_material:
        if len(face_lines_by_material) > 256:
            raise ConversionError(
                f"{output_path}: {len(face_lines_by_material)} rendered materials exceed "
                "Godot's 256 surfaces-per-mesh limit"
            )
        for material_name, face_lines in face_lines_by_material.items():
            obj_lines.extend(("", f"g material_{material_name}", f"usemtl {material_name}"))
            obj_lines.extend(face_lines)

    output_path.write_text("\n".join(obj_lines) + "\n", encoding="utf-8", newline="\n")

    mtl_lines = ["# Materials resolved from the source Unity prefabs."]
    for material in canonical_materials:
        red, green, blue, alpha = material.color
        mtl_lines.extend(
            (
                "",
                f"newmtl {material_names[id(material)]}",
                f"Ka {red * 0.1:.6g} {green * 0.1:.6g} {blue * 0.1:.6g}",
                f"Kd {red:.6g} {green:.6g} {blue:.6g}",
                "Ks 0.2 0.2 0.2",
                "Ns 32",
                f"d {alpha:.6g}",
                "illum 2",
            )
        )
        if material.copied_name:
            mtl_lines.append(f"map_Kd {material.copied_name}")
    output_path.with_suffix(".mtl").write_text("\n".join(mtl_lines) + "\n", encoding="utf-8", newline="\n")

    material_states = {
        material_names[id(material)]: {
            "shader": material.shader_name,
            "blend": material.blend_mode,
            "cull_disabled": material.cull_disabled,
            "depth_write": material.depth_write,
            "unshaded": material.blend_mode != "opaque",
            "alpha_scissor_threshold": material.alpha_scissor_threshold,
        }
        for material in canonical_materials
    }

    return {
        "output": str(output_path),
        "vertices": vertex_base,
        "uvs": uv_base,
        "normals": normal_base,
        "faces": total_faces,
        "source_normals": source_normals,
        "generated_normals": generated_normals,
        "materials": (
            len(face_lines_by_material)
            if group_faces_by_material
            else len(canonical_materials)
        ),
        "material_states": material_states,
        "pieces": [piece.name for piece in pieces],
        "source_meshes": [str(piece.mesh.source_path) for piece in pieces],
        "textures": sorted({material.copied_name for material in material_list if material.copied_name}),
    }


def validate_obj(path: Path) -> dict[str, object]:
    vertices: list[tuple[float, float, float]] = []
    uvs: list[tuple[float, float]] = []
    normals: list[tuple[float, float, float]] = []
    faces: list[list[tuple[int, int | None, int | None]]] = []
    material_libraries: list[str] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if fields[0] == "v":
            if len(fields) != 4:
                raise ConversionError(f"{path}:{line_number}: vertex must have exactly three components")
            value = tuple(float(component) for component in fields[1:])
            if not all(math.isfinite(component) for component in value):
                raise ConversionError(f"{path}:{line_number}: non-finite vertex")
            vertices.append(value)
        elif fields[0] == "vt":
            if len(fields) < 3:
                raise ConversionError(f"{path}:{line_number}: incomplete texture coordinate")
            value = tuple(float(component) for component in fields[1:3])
            if not all(math.isfinite(component) for component in value):
                raise ConversionError(f"{path}:{line_number}: non-finite texture coordinate")
            uvs.append(value)
        elif fields[0] == "vn":
            if len(fields) != 4:
                raise ConversionError(f"{path}:{line_number}: normal must have exactly three components")
            value = tuple(float(component) for component in fields[1:])
            if not all(math.isfinite(component) for component in value):
                raise ConversionError(f"{path}:{line_number}: non-finite normal")
            normals.append(value)
        elif fields[0] == "f":
            if len(fields) != 4:
                raise ConversionError(f"{path}:{line_number}: converter output must contain triangular faces")
            face: list[tuple[int, int | None, int | None]] = []
            for field_value in fields[1:]:
                indices = field_value.split("/")
                vertex_index = int(indices[0])
                uv_index = int(indices[1]) if len(indices) > 1 and indices[1] else None
                normal_index = int(indices[2]) if len(indices) > 2 and indices[2] else None
                if vertex_index <= 0 or (uv_index is not None and uv_index <= 0) or (normal_index is not None and normal_index <= 0):
                    raise ConversionError(f"{path}:{line_number}: only positive OBJ indexes are accepted")
                face.append((vertex_index, uv_index, normal_index))
            faces.append(face)
        elif fields[0] == "mtllib":
            material_libraries.extend(fields[1:])

    if not vertices or not faces:
        raise ConversionError(f"{path}: OBJ contains no playable geometry")
    for face_number, face in enumerate(faces, 1):
        for vertex_index, uv_index, normal_index in face:
            if vertex_index > len(vertices):
                raise ConversionError(f"{path}: face {face_number} references missing vertex {vertex_index}")
            if uv_index is not None and uv_index > len(uvs):
                raise ConversionError(f"{path}: face {face_number} references missing UV {uv_index}")
            if normal_index is None or normal_index > len(normals):
                raise ConversionError(f"{path}: face {face_number} has a missing/invalid normal")
        a, b, c = (vertices[item[0] - 1] for item in face)
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        if sum(value * value for value in _cross(ab, ac)) < 1e-24:
            raise ConversionError(f"{path}: face {face_number} is degenerate")
    for library in material_libraries:
        material_path = path.parent / library
        if not material_path.is_file():
            raise ConversionError(f"{path}: missing material library {library}")
        for texture_name in re.findall(r"^map_Kd\s+(.+?)\s*$", material_path.read_text(encoding="utf-8-sig"), re.MULTILINE):
            if not (material_path.parent / texture_name).is_file():
                raise ConversionError(f"{material_path}: missing diffuse texture {texture_name}")
    mins = tuple(min(value[axis] for value in vertices) for axis in range(3))
    maxs = tuple(max(value[axis] for value in vertices) for axis in range(3))
    return {
        "path": str(path),
        "vertices": len(vertices),
        "uvs": len(uvs),
        "normals": len(normals),
        "faces": len(faces),
        "bounds_min": mins,
        "bounds_max": maxs,
        "material_libraries": material_libraries,
    }


def _renderer_to_piece(renderer: PrefabRenderer, guid_index: GuidIndex) -> ObjPiece:
    mesh_path = guid_index.resolve(renderer.mesh_guid)
    materials = [parse_material(guid_index.resolve(guid), guid_index) for guid in renderer.material_guids]
    if not materials:
        materials = [fallback_material(renderer.name)]
    return ObjPiece(renderer.name, parse_mesh(mesh_path), renderer.transform, materials)


def convert_prefab(prefab_path: Path, output_path: Path, assets_root: Path) -> dict[str, object]:
    guid_index = GuidIndex(assets_root)
    renderers = parse_prefab_renderers(prefab_path)
    pieces = [_renderer_to_piece(renderer, guid_index) for renderer in renderers]
    return write_obj(output_path, pieces)


def convert_selected(project_root: Path) -> dict[str, object]:
    assets_root = project_root / "Assets"
    godot_root = project_root / "Godot"
    guid_index = GuidIndex(assets_root)
    results: dict[str, object] = {}

    bug_prefab = assets_root / "Resources" / "enemy" / "bug01.prefab"
    bug_renderers = parse_prefab_renderers(bug_prefab)
    bug_candidates = [renderer for renderer in bug_renderers if renderer.kind == "SkinnedMeshRenderer"]
    if not bug_candidates:
        raise ConversionError(f"{bug_prefab}: did not find the skinned bug renderer")
    bug_output = godot_root / "assets" / "models" / "enemies" / "bug01.obj"
    results["bug01"] = write_obj(bug_output, [_renderer_to_piece(bug_candidates[0], guid_index)])

    gun_prefab = assets_root / "Resources" / "weapon" / "gun00.prefab"
    gun_renderers = parse_prefab_renderers(gun_prefab)
    if not gun_renderers:
        raise ConversionError(f"{gun_prefab}: did not find a mesh renderer")
    gun_output = godot_root / "assets" / "models" / "weapons" / "gun00.obj"
    results["gun00"] = write_obj(gun_output, [_renderer_to_piece(gun_renderers[0], guid_index)])

    player_pieces: list[ObjPiece] = []
    avatar_root = assets_root / "Resources" / "avatar" / "01"
    for part_name in ("Body", "Foot", "Hand", "Head", "Bag"):
        prefab_path = avatar_root / f"{part_name}.prefab"
        renderers = parse_prefab_renderers(prefab_path)
        if not renderers:
            raise ConversionError(f"{prefab_path}: did not find a mesh renderer")
        player_pieces.extend(_renderer_to_piece(renderer, guid_index) for renderer in renderers)
    player_output = godot_root / "assets" / "models" / "player" / "player.obj"
    results["player"] = write_obj(player_output, player_pieces)

    validation = {
        name: validate_obj(Path(result["output"]))
        for name, result in results.items()
        if isinstance(result, dict)
    }
    report = {
        "converter": "Unity YAML Mesh serializedVersion 8 fallback",
        "coordinate_conversion": "Prefab transforms baked; Unity +Z mirrored to Godot -Z; winding corrected",
        "outputs": results,
        "validation": validation,
        "limitations": [
            "OBJ is a static bind/default-pose export; skin weights, skeletons, and animation clips are not represented.",
            "Legacy custom shaders are represented by diffuse MTL materials only.",
            "For two-texture legacy light shaders, _texBase is copied as diffuse and _tex2 is intentionally omitted.",
            "Source meshes without normal channels receive area-weighted smooth normals.",
        ],
    }
    report_path = Path(__file__).with_name("conversion_report.json")
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    selected = subparsers.add_parser("selected", help="convert bug01, gun00, and avatar/01 to the Godot paths")
    selected.add_argument("--project-root", type=Path, required=True, help="directory containing Assets and Godot")

    prefab = subparsers.add_parser("prefab", help="convert every enabled mesh renderer in one prefab")
    prefab.add_argument("prefab", type=Path)
    prefab.add_argument("output", type=Path)
    prefab.add_argument("--assets-root", type=Path, required=True)

    mesh = subparsers.add_parser("mesh", help="convert one raw YAML Mesh without resolving materials")
    mesh.add_argument("mesh", type=Path)
    mesh.add_argument("output", type=Path)

    validate = subparsers.add_parser("validate", help="strictly validate one or more generated OBJ files")
    validate.add_argument("objects", type=Path, nargs="+")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "selected":
            result = convert_selected(args.project_root.resolve())
        elif args.command == "prefab":
            result = convert_prefab(args.prefab.resolve(), args.output.resolve(), args.assets_root.resolve())
        elif args.command == "mesh":
            mesh_data = parse_mesh(args.mesh.resolve())
            piece = ObjPiece(mesh_data.name, mesh_data, identity_matrix(), [fallback_material(mesh_data.name)])
            result = write_obj(args.output.resolve(), [piece])
            result["validation"] = validate_obj(args.output.resolve())
        else:
            result = {str(path): validate_obj(path.resolve()) for path in args.objects}
    except (ConversionError, OSError, ValueError) as error:
        parser.exit(1, f"error: {error}\n")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
