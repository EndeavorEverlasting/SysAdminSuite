#!/usr/bin/env python3
"""Strong-name producer contracts plus complete CLR metadata-table traversal coverage."""
from __future__ import annotations

import importlib.util
import struct
from pathlib import Path

_LEGACY_PATH = Path(__file__).with_name("_test_package_strong_name_verification_contracts_legacy.py")
_SPEC = importlib.util.spec_from_file_location("strong_name_contracts_core", _LEGACY_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"unable to load strong-name contract core: {_LEGACY_PATH}")
_CORE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_CORE)

_EXPECTED_SMALL_ROW_SIZES = [
    10, 6, 14, 2, 6, 2, 14, 2,
    6, 4, 6, 6, 6, 4, 6, 8,
    6, 2, 4, 2, 6, 4, 2, 6,
    6, 6, 2, 2, 8, 6, 8, 4,
]


def _metadata_root(module, public_key: bytes) -> tuple[bytes, dict]:
    blob_heap = b"\0" + module.encode_blob(public_key)
    valid = sum(1 << table for table in range(0x21))
    tables = bytearray(struct.pack("<IBBBBQQ", 0, 2, 0, 0, 0, valid, 0))
    tables += b"".join(struct.pack("<I", 1) for _ in range(0x21))
    for row_size in _EXPECTED_SMALL_ROW_SIZES:
        tables += b"\0" * row_size
    tables += struct.pack("<IHHHHIHHH", 0x8004, 1, 0, 0, 0, 1, 1, 0, 0)

    version = module.pad4(b"v4.0.30319\0")
    bodies = [("#~", bytes(tables)), ("#Blob", module.pad4(blob_heap))]
    fixed = 16 + len(version) + 4
    headers = [(module.pad4(name.encode("ascii") + b"\0"), body) for name, body in bodies]
    cursor = (fixed + sum(8 + len(name) for name, _ in headers) + 3) & ~3
    metadata = bytearray(b"BSJB" + struct.pack("<HHII", 1, 1, 0, len(version)))
    metadata += version
    metadata += struct.pack("<HH", 0, len(headers))
    body_offsets: list[tuple[int, bytes]] = []
    for name, body in headers:
        metadata += struct.pack("<II", cursor, len(body)) + name
        body_offsets.append((cursor, body))
        cursor = (cursor + len(body) + 3) & ~3
    metadata.extend(b"\0" * (cursor - len(metadata)))
    for offset, body in body_offsets:
        metadata[offset : offset + len(body)] = body

    metadata_rva = 0x20
    data = b"\0" * metadata_rva + bytes(metadata)
    pe = {
        "metadata_rva": metadata_rva,
        "metadata_size": len(metadata),
        "sections": [],
        "size_of_headers": 0x1000,
    }
    return data, pe


def test_all_standard_preceding_tables_are_walked() -> None:
    module = _CORE.load_module()
    row_counts = [1] * 64
    actual_sizes = [module.metadata_table_row_size(table, row_counts, 0) for table in range(0x20)]
    assert actual_sizes == _EXPECTED_SMALL_ROW_SIZES
    public_key = module.fixture_public_key_blob()
    data, pe = _metadata_root(module, public_key)
    assert module.extract_assembly_public_key(data, pe) == public_key


def test_metadata_index_thresholds_are_fail_closed() -> None:
    module = _CORE.load_module()
    row_counts = [0] * 64
    assert module.metadata_table_index_size(row_counts, 0x02) == 2
    row_counts[0x02] = 1 << 16
    assert module.metadata_table_index_size(row_counts, 0x02) == 4

    row_counts = [0] * 64
    row_counts[0x02] = (1 << (16 - 2)) - 1
    assert module.metadata_coded_index_size(row_counts, (0x02, 0x01, 0x1B), 2) == 2
    row_counts[0x02] += 1
    assert module.metadata_coded_index_size(row_counts, (0x02, 0x01, 0x1B), 2) == 4


def main() -> int:
    result = _CORE.main()
    if result != 0:
        return result
    tests = [
        test_all_standard_preceding_tables_are_walked,
        test_metadata_index_thresholds_are_fail_closed,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
    print(f"PASS: {len(tests)} CLR metadata-table walker contract groups")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
