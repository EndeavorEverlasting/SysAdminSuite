#!/usr/bin/env python3
"""Hardened CLR strong-name verifier with complete pre-Assembly metadata traversal.

The committed producer remains in a private compatibility module so this entrypoint can
stay stable while the metadata walker is extended independently and contract-tested.
"""
from __future__ import annotations

import importlib.util
import struct
from pathlib import Path
from typing import Any

_CORE_PATH = Path(__file__).with_name("_verify_dotnet_strong_name_legacy.py")
_SPEC = importlib.util.spec_from_file_location("sas_strong_name_core", _CORE_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"unable to load strong-name core: {_CORE_PATH}")
_CORE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_CORE)


def metadata_table_index_size(row_counts: list[int], table: int) -> int:
    """Return the ECMA-335 width of a simple metadata-table index."""
    if not 0 <= table < len(row_counts):
        raise ValueError(f"metadata_table_out_of_range:0x{table:02x}")
    return 4 if row_counts[table] >= (1 << 16) else 2


def metadata_coded_index_size(row_counts: list[int], tables: tuple[int, ...], tag_bits: int) -> int:
    """Return the ECMA-335 width of a coded metadata index."""
    if tag_bits <= 0 or tag_bits >= 16:
        raise ValueError("metadata_coded_index_tag_bits_invalid")
    max_rows = max((row_counts[table] for table in tables if 0 <= table < len(row_counts)), default=0)
    return 4 if max_rows >= (1 << (16 - tag_bits)) else 2


_CODED_INDEXES: dict[str, tuple[tuple[int, ...], int]] = {
    "TypeDefOrRef": ((0x02, 0x01, 0x1B), 2),
    "HasConstant": ((0x04, 0x08, 0x17), 2),
    "HasCustomAttribute": (
        (0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00, 0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B,
         0x20, 0x23, 0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B),
        5,
    ),
    "HasFieldMarshal": ((0x04, 0x08), 1),
    "HasDeclSecurity": ((0x02, 0x06, 0x20), 2),
    "MemberRefParent": ((0x02, 0x01, 0x1A, 0x06, 0x1B), 3),
    "HasSemantics": ((0x14, 0x17), 1),
    "MethodDefOrRef": ((0x06, 0x0A), 1),
    "MemberForwarded": ((0x04, 0x06), 1),
    "Implementation": ((0x26, 0x23, 0x27), 2),
    "CustomAttributeType": ((0x06, 0x0A), 3),
    "ResolutionScope": ((0x00, 0x1A, 0x23, 0x01), 2),
    "TypeOrMethodDef": ((0x02, 0x06), 1),
}


def metadata_table_row_size(table: int, row_counts: list[int], heap_sizes: int) -> int:
    """Return an ECMA-335 metadata row width for tables preceding Assembly (0x20)."""
    string_index = 4 if heap_sizes & 0x01 else 2
    guid_index = 4 if heap_sizes & 0x02 else 2
    blob_index = 4 if heap_sizes & 0x04 else 2

    def simple(target: int) -> int:
        return metadata_table_index_size(row_counts, target)

    def coded(name: str) -> int:
        tables, tag_bits = _CODED_INDEXES[name]
        return metadata_coded_index_size(row_counts, tables, tag_bits)

    sizes = {
        0x00: 2 + string_index + 3 * guid_index,
        0x01: coded("ResolutionScope") + 2 * string_index,
        0x02: 4 + 2 * string_index + coded("TypeDefOrRef") + simple(0x04) + simple(0x06),
        0x03: simple(0x04),
        0x04: 2 + string_index + blob_index,
        0x05: simple(0x06),
        0x06: 8 + string_index + blob_index + simple(0x08),
        0x07: simple(0x08),
        0x08: 4 + string_index,
        0x09: simple(0x02) + coded("TypeDefOrRef"),
        0x0A: coded("MemberRefParent") + string_index + blob_index,
        0x0B: 2 + coded("HasConstant") + blob_index,
        0x0C: coded("HasCustomAttribute") + coded("CustomAttributeType") + blob_index,
        0x0D: coded("HasFieldMarshal") + blob_index,
        0x0E: 2 + coded("HasDeclSecurity") + blob_index,
        0x0F: 6 + simple(0x02),
        0x10: 4 + simple(0x04),
        0x11: blob_index,
        0x12: simple(0x02) + simple(0x14),
        0x13: simple(0x14),
        0x14: 2 + string_index + coded("TypeDefOrRef"),
        0x15: simple(0x02) + simple(0x17),
        0x16: simple(0x17),
        0x17: 2 + string_index + blob_index,
        0x18: 2 + simple(0x06) + coded("HasSemantics"),
        0x19: simple(0x02) + 2 * coded("MethodDefOrRef"),
        0x1A: string_index,
        0x1B: blob_index,
        0x1C: 2 + coded("MemberForwarded") + string_index + simple(0x1A),
        0x1D: 4 + simple(0x04),
        0x1E: 8,
        0x1F: 4,
    }
    try:
        return sizes[table]
    except KeyError as exc:
        raise ValueError(f"unsupported_preceding_table:0x{table:02x}") from exc


def extract_assembly_public_key(data: bytes, pe: dict[str, Any]) -> bytes | None:
    """Extract Assembly.PublicKey after walking every standard preceding metadata table."""
    meta_offset = _CORE._rva_to_offset(pe["metadata_rva"], pe["sections"], pe["size_of_headers"])
    if meta_offset is None or pe["metadata_size"] <= 0:
        raise ValueError("metadata_missing")
    end = min(len(data), meta_offset + pe["metadata_size"])
    meta = data[meta_offset:end]
    if len(meta) < 20 or meta[:4] != b"BSJB":
        raise ValueError("metadata_signature_invalid")
    version_length = struct.unpack_from("<I", meta, 12)[0]
    cursor = (16 + version_length + 3) & ~3
    if cursor + 4 > len(meta):
        raise ValueError("metadata_header_truncated")
    _flags, stream_count = struct.unpack_from("<HH", meta, cursor)
    cursor += 4
    streams: dict[str, tuple[int, int]] = {}
    for _ in range(stream_count):
        if cursor + 8 > len(meta):
            raise ValueError("metadata_stream_header_truncated")
        offset, size = struct.unpack_from("<II", meta, cursor)
        cursor += 8
        name_start = cursor
        while cursor < len(meta) and meta[cursor] != 0:
            cursor += 1
        if cursor >= len(meta):
            raise ValueError("metadata_stream_name_unterminated")
        name = meta[name_start:cursor].decode("ascii", errors="replace")
        cursor = (cursor + 4) & ~3
        streams[name] = (offset, size)
    if "#~" not in streams or "#Blob" not in streams:
        raise ValueError("metadata_required_streams_missing")
    tables_off, tables_size = streams["#~"]
    blob_off, blob_size = streams["#Blob"]
    if tables_off + tables_size > len(meta) or blob_off + blob_size > len(meta):
        raise ValueError("metadata_stream_bounds")
    tables = meta[tables_off : tables_off + tables_size]
    blob_heap = meta[blob_off : blob_off + blob_size]
    if len(tables) < 24:
        raise ValueError("tables_stream_truncated")
    heap_sizes = tables[6]
    valid = struct.unpack_from("<Q", tables, 8)[0]
    row_counts = [0] * 64
    pos = 24
    for table in range(64):
        if valid & (1 << table):
            if pos + 4 > len(tables):
                raise ValueError("table_row_count_truncated")
            row_counts[table] = struct.unpack_from("<I", tables, pos)[0]
            pos += 4

    for table in range(0x20):
        rows = row_counts[table]
        if rows == 0:
            continue
        row_size = metadata_table_row_size(table, row_counts, heap_sizes)
        table_end = pos + rows * row_size
        if table_end > len(tables):
            raise ValueError(f"metadata_table_truncated:0x{table:02x}")
        pos = table_end

    assembly_rows = row_counts[0x20]
    if assembly_rows <= 0:
        return None
    string_index_size = 4 if heap_sizes & 0x01 else 2
    blob_index_size = 4 if heap_sizes & 0x04 else 2
    assembly_row_size = 16 + blob_index_size + 2 * string_index_size
    if pos + assembly_rows * assembly_row_size > len(tables):
        raise ValueError("assembly_table_truncated")
    blob_index_offset = pos + 16
    public_key_index = (
        struct.unpack_from("<H", tables, blob_index_offset)[0]
        if blob_index_size == 2
        else struct.unpack_from("<I", tables, blob_index_offset)[0]
    )
    if public_key_index == 0:
        return None
    return _CORE._read_blob_heap(blob_heap, public_key_index)


_CORE.extract_assembly_public_key = extract_assembly_public_key
_CORE.metadata_table_index_size = metadata_table_index_size
_CORE.metadata_coded_index_size = metadata_coded_index_size
_CORE.metadata_table_row_size = metadata_table_row_size
_CORE.ANALYZER_VERSION = "0.2.0"

for _name, _value in vars(_CORE).items():
    if not _name.startswith("__") and _name not in globals():
        globals()[_name] = _value

if __name__ == "__main__":
    raise SystemExit(_CORE.main())
