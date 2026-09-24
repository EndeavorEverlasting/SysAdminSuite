#!/usr/bin/env python3
"""Verify CLR strong-name integrity for managed PE assemblies without executing them.

This producer re-verifies source hashes from a static package inventory, locates managed
PE/CLR assemblies, extracts the Assembly public-key blob, and cryptographically verifies
the strong-name signature. It does not evaluate Authenticode publisher trust, online
revocation, or managed runtime behavior.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA_VERSION = "sas-package-strong-name-verification/v1"
ANALYZER_VERSION = "0.1.0"
BASE_SCHEMA_VERSION = "sas-package-static-analysis/v1"
DEFAULT_MAX_FILES = 50000

CALG_RSA_SIGN = 0x00002400
CALG_SHA1 = 0x00008004
CALG_SHA_256 = 0x0000800C
CALG_RSA_KEYX = 0x0000A400
CLI_FLAG_STRONG_NAME_SIGNED = 0x00000008

# Fixture-only RSA-1024 keypair for contract generation. Not a production signing key.
_FIXTURE_N = int(
    "d2ebcee1b05e817a6c7d32532294d8c5392eab812c8b6bde4429a0fdb8dcacc6"
    "e7ab7146cfe624ee57d0debcb9841ac78616d2b5578bf29bf324281d63c7f5d0"
    "230b55c5b3c3b4a8e49a19e02e056bbd356dd7d51d9ddad99205d7cef31a6c4d"
    "4d400195282d2803b9a04a6f276e6f6988ced3f37e245e850d9742d9975d3913",
    16,
)
_FIXTURE_E = 65537
_FIXTURE_D = int(
    "69548943fba7b65144cc60cd537fb1a10c255a506fc6505ff6fa330381c5f222"
    "829f033ab1a7e4d981d134ea5a5ab664dd7998502720244fece4298443c81fe0"
    "a040b9862a588455f21fb12970910771be7d8f81d50153c0ceea35aade2f0e34"
    "f24e3f6ba33ce4eeca7801be6fa988f8811d0a42508b9c0d34137f47b2fcddc1",
    16,
)
_FIXTURE_MOD_LEN = 128

_SHA1_DIGEST_INFO_PREFIX = bytes.fromhex("3021300906052b0e03021a05000414")
_SHA256_DIGEST_INFO_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", delete=False, dir=path.parent) as tmp:
        tmp.write(content)
        temp_path = Path(tmp.name)
    os.replace(temp_path, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compressed_uint(value: int) -> bytes:
    if value <= 0x7F:
        return bytes([value])
    if value <= 0x3FFF:
        return bytes([0x80 | (value >> 8), value & 0xFF])
    return bytes([0xC0 | ((value >> 24) & 0x1F), (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


def read_compressed_uint(data: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(data):
        raise ValueError("compressed_uint_truncated")
    first = data[offset]
    if (first & 0x80) == 0:
        return first, offset + 1
    if (first & 0xC0) == 0x80:
        if offset + 1 >= len(data):
            raise ValueError("compressed_uint_truncated")
        return ((first & 0x3F) << 8) | data[offset + 1], offset + 2
    if offset + 3 >= len(data):
        raise ValueError("compressed_uint_truncated")
    value = ((first & 0x1F) << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]
    return value, offset + 4


def encode_blob(data: bytes) -> bytes:
    return compressed_uint(len(data)) + data


def pad4(data: bytes) -> bytes:
    return data + b"\0" * ((4 - (len(data) % 4)) % 4)


def _i2osp(value: int, length: int) -> bytes:
    return value.to_bytes(length, "big")


def _os2ip(data: bytes) -> int:
    return int.from_bytes(data, "big")


def _pkcs1_v15_digest_info(digest: bytes, hash_alg: str) -> bytes:
    if hash_alg == "sha1":
        if len(digest) != 20:
            raise ValueError("sha1_digest_length")
        return _SHA1_DIGEST_INFO_PREFIX + digest
    if hash_alg == "sha256":
        if len(digest) != 32:
            raise ValueError("sha256_digest_length")
        return _SHA256_DIGEST_INFO_PREFIX + digest
    raise ValueError(f"unsupported_hash_alg:{hash_alg}")


def _pkcs1_v15_encode(digest: bytes, hash_alg: str, modulus_len: int) -> bytes:
    digest_info = _pkcs1_v15_digest_info(digest, hash_alg)
    if len(digest_info) + 11 > modulus_len:
        raise ValueError("rsa_key_too_small_for_digest")
    ps = b"\xff" * (modulus_len - len(digest_info) - 3)
    return b"\x00\x01" + ps + b"\x00" + digest_info


def rsa_public_verify(digest: bytes, signature_be: bytes, modulus: int, exponent: int, hash_alg: str) -> bool:
    modulus_len = (modulus.bit_length() + 7) // 8
    if len(signature_be) != modulus_len:
        return False
    signature = _os2ip(signature_be)
    if signature >= modulus:
        return False
    try:
        expected = _pkcs1_v15_encode(digest, hash_alg, modulus_len)
    except ValueError:
        return False
    return _i2osp(pow(signature, exponent, modulus), modulus_len) == expected


def fixture_public_key_blob(hash_alg: str = "sha1") -> bytes:
    hash_alg_id = CALG_SHA1 if hash_alg == "sha1" else CALG_SHA_256
    blob_header = struct.pack("<BBHI", 0x06, 0x02, 0, CALG_RSA_KEYX)
    rsa_pubkey = struct.pack("<III", 0x31415352, _FIXTURE_MOD_LEN * 8, _FIXTURE_E)
    public_key = blob_header + rsa_pubkey + _FIXTURE_N.to_bytes(_FIXTURE_MOD_LEN, "little")
    return struct.pack("<III", CALG_RSA_SIGN, hash_alg_id, len(public_key)) + public_key


def fixture_sign(digest: bytes, hash_alg: str = "sha1") -> bytes:
    encoded = _pkcs1_v15_encode(digest, hash_alg, _FIXTURE_MOD_LEN)
    return _i2osp(pow(_os2ip(encoded), _FIXTURE_D, _FIXTURE_N), _FIXTURE_MOD_LEN)


def public_key_token(public_key_blob: bytes) -> str:
    digest = hashlib.sha1(public_key_blob).digest()
    return digest[-8:][::-1].hex()


def parse_public_key_blob(blob: bytes) -> dict[str, Any]:
    if len(blob) < 12:
        raise ValueError("public_key_blob_truncated")
    sig_alg, hash_alg_id, cb_public_key = struct.unpack_from("<III", blob, 0)
    if 12 + cb_public_key > len(blob):
        raise ValueError("public_key_blob_length_mismatch")
    public_key = blob[12 : 12 + cb_public_key]
    if len(public_key) < 20:
        raise ValueError("csp_public_key_truncated")
    b_type, b_version, _reserved, ai_key_alg = struct.unpack_from("<BBHI", public_key, 0)
    magic, bitlen, pubexp = struct.unpack_from("<III", public_key, 8)
    if b_type != 0x06 or b_version != 0x02 or magic != 0x31415352:
        raise ValueError("unsupported_public_key_format")
    if ai_key_alg not in (CALG_RSA_KEYX, CALG_RSA_SIGN) and sig_alg != CALG_RSA_SIGN:
        raise ValueError("unsupported_public_key_algorithm")
    modulus_len = bitlen // 8
    if len(public_key) < 20 + modulus_len:
        raise ValueError("public_key_modulus_truncated")
    modulus = int.from_bytes(public_key[20 : 20 + modulus_len], "little")
    if hash_alg_id == CALG_SHA1:
        hash_alg = "sha1"
    elif hash_alg_id == CALG_SHA_256:
        hash_alg = "sha256"
    else:
        raise ValueError(f"unsupported_hash_alg_id:0x{hash_alg_id:08x}")
    if sig_alg != CALG_RSA_SIGN:
        raise ValueError(f"unsupported_sig_alg_id:0x{sig_alg:08x}")
    return {
        "hash_algorithm": hash_alg,
        "modulus": modulus,
        "exponent": pubexp,
        "modulus_len": modulus_len,
        "public_key_token": public_key_token(blob),
    }


def _rva_to_offset(rva: int, sections: list[dict[str, int]], size_of_headers: int) -> int | None:
    if rva <= 0:
        return None
    if rva < size_of_headers:
        return rva
    for section in sections:
        span = max(section["virtual_size"], section["raw_size"])
        if section["virtual_address"] <= rva < section["virtual_address"] + span:
            return section["raw_pointer"] + (rva - section["virtual_address"])
    return None


def parse_pe_clr(data: bytes) -> dict[str, Any] | None:
    if len(data) < 0x40 or data[:2] != b"MZ":
        return None
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        return None
    _machine, section_count, _ts, _sym, _nsym, optional_size, _chars = struct.unpack_from("<HHIIIHH", data, pe_offset + 4)
    optional_offset = pe_offset + 24
    if optional_offset + optional_size > len(data) or optional_size < 2:
        return None
    magic = struct.unpack_from("<H", data, optional_offset)[0]
    if magic == 0x10B:
        directory_offset, count_offset, checksum_offset = 96, 92, 64
        pe_format = "pe32"
    elif magic == 0x20B:
        directory_offset, count_offset, checksum_offset = 112, 108, 64
        pe_format = "pe32plus"
    else:
        return None
    if optional_size < count_offset + 4:
        return None
    directory_count = struct.unpack_from("<I", data, optional_offset + count_offset)[0]
    clr_entry = directory_offset + 14 * 8
    if directory_count <= 14 or optional_size < clr_entry + 8:
        return None
    clr_rva, clr_size = struct.unpack_from("<II", data, optional_offset + clr_entry)
    if not clr_rva or not clr_size:
        return None
    size_of_headers = struct.unpack_from("<I", data, optional_offset + 60)[0] if optional_size >= 64 else 0
    sections: list[dict[str, int]] = []
    section_table = optional_offset + optional_size
    for index in range(min(section_count, 256)):
        start = section_table + index * 40
        if start + 40 > len(data):
            break
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", data, start + 8)
        sections.append(
            {
                "virtual_size": virtual_size,
                "virtual_address": virtual_address,
                "raw_size": raw_size,
                "raw_pointer": raw_pointer,
            }
        )
    cli_offset = _rva_to_offset(clr_rva, sections, size_of_headers)
    if cli_offset is None or cli_offset + 24 > len(data):
        return None
    cb = struct.unpack_from("<I", data, cli_offset)[0]
    metadata_rva, metadata_size = struct.unpack_from("<II", data, cli_offset + 8)
    flags = struct.unpack_from("<I", data, cli_offset + 16)[0]
    strong_name_rva, strong_name_size = struct.unpack_from("<II", data, cli_offset + 32) if cli_offset + 40 <= len(data) else (0, 0)
    cert_rva = cert_size = 0
    cert_dir_file_offset = optional_offset + directory_offset + 4 * 8
    if directory_count > 4 and optional_size >= directory_offset + 5 * 8:
        cert_rva, cert_size = struct.unpack_from("<II", data, optional_offset + directory_offset + 4 * 8)
    return {
        "pe_format": pe_format,
        "optional_offset": optional_offset,
        "checksum_offset": optional_offset + checksum_offset,
        "cert_dir_file_offset": cert_dir_file_offset,
        "cert_file_offset": cert_rva if cert_rva and cert_size else None,
        "cert_size": cert_size if cert_rva and cert_size else 0,
        "sections": sections,
        "size_of_headers": size_of_headers,
        "cli_offset": cli_offset,
        "cli_cb": cb,
        "metadata_rva": metadata_rva,
        "metadata_size": metadata_size,
        "cli_flags": flags,
        "strong_name_signed_flag": bool(flags & CLI_FLAG_STRONG_NAME_SIGNED),
        "strong_name_rva": strong_name_rva,
        "strong_name_size": strong_name_size,
        "strong_name_offset": _rva_to_offset(strong_name_rva, sections, size_of_headers) if strong_name_rva and strong_name_size else None,
    }


def _read_blob_heap(blob_heap: bytes, index: int) -> bytes:
    if index <= 0:
        return b""
    if index >= len(blob_heap):
        raise ValueError("blob_index_out_of_range")
    length, cursor = read_compressed_uint(blob_heap, index)
    end = cursor + length
    if end > len(blob_heap):
        raise ValueError("blob_truncated")
    return blob_heap[cursor:end]


def extract_assembly_public_key(data: bytes, pe: dict[str, Any]) -> bytes | None:
    meta_offset = _rva_to_offset(pe["metadata_rva"], pe["sections"], pe["size_of_headers"])
    if meta_offset is None or pe["metadata_size"] <= 0:
        raise ValueError("metadata_missing")
    end = min(len(data), meta_offset + pe["metadata_size"])
    meta = data[meta_offset:end]
    if len(meta) < 20 or meta[:4] != b"BSJB":
        raise ValueError("metadata_signature_invalid")
    version_length = struct.unpack_from("<I", meta, 12)[0]
    cursor = 16 + version_length
    cursor = (cursor + 3) & ~3
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
        name = meta[name_start:cursor].decode("ascii", errors="replace")
        cursor += 1
        cursor = (cursor + 3) & ~3
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
    row_counts: list[int] = []
    pos = 24
    for bit in range(64):
        if valid & (1 << bit):
            if pos + 4 > len(tables):
                raise ValueError("table_row_count_truncated")
            row_counts.append(struct.unpack_from("<I", tables, pos)[0])
            pos += 4
        else:
            row_counts.append(0)
    string_index_size = 4 if heap_sizes & 0x01 else 2
    guid_index_size = 4 if heap_sizes & 0x02 else 2
    blob_index_size = 4 if heap_sizes & 0x04 else 2

    def coded_index_size(tables_bits: list[int], tag_bits: int) -> int:
        max_rows = max((row_counts[index] for index in tables_bits if index < 64), default=0)
        return 4 if max_rows >= (1 << (16 - tag_bits)) else 2

    # Walk preceding tables to reach Assembly (0x20).
    table_row_sizes = {
        0x00: 2 + string_index_size + 3 * guid_index_size,  # Module
        0x01: coded_index_size([0x02, 0x01], 1) + string_index_size + blob_index_size,  # TypeRef rough
    }

    def row_size_for(table: int) -> int:
        if table in table_row_sizes:
            return table_row_sizes[table]
        # Conservative fallback sizes are not used; only Module and Assembly are required here.
        raise ValueError(f"unsupported_preceding_table:0x{table:02x}")

    # Only Module (0x00) is required before Assembly when TypeRef/etc. are absent.
    for table in range(0x20):
        rows = row_counts[table]
        if rows == 0:
            continue
        if table != 0x00:
            raise ValueError(f"unexpected_table_before_assembly:0x{table:02x}")
        pos += rows * row_size_for(table)
    assembly_rows = row_counts[0x20]
    if assembly_rows <= 0:
        return None
    assembly_row_size = 4 + 8 + 4 + blob_index_size + string_index_size + string_index_size
    if pos + assembly_row_size > len(tables):
        raise ValueError("assembly_table_truncated")
    row = tables[pos : pos + assembly_row_size]
    # HashAlgId(4) Version(8) Flags(4) PublicKey blob Name Culture
    blob_index_offset = 16
    if blob_index_size == 2:
        public_key_index = struct.unpack_from("<H", row, blob_index_offset)[0]
    else:
        public_key_index = struct.unpack_from("<I", row, blob_index_offset)[0]
    if public_key_index == 0:
        return None
    return _read_blob_heap(blob_heap, public_key_index)


def strong_name_hash(data: bytes, pe: dict[str, Any], hash_alg: str) -> bytes:
    """Hash a PE image using the CLR strong-name exclusion rules."""
    hasher = hashlib.sha1() if hash_alg == "sha1" else hashlib.sha256()
    sn_offset = pe["strong_name_offset"]
    sn_size = pe["strong_name_size"]
    if sn_offset is None or sn_size <= 0:
        raise ValueError("strong_name_blob_missing")

    view = bytearray(data)
    view[pe["checksum_offset"] : pe["checksum_offset"] + 4] = b"\0\0\0\0"
    view[pe["cert_dir_file_offset"] : pe["cert_dir_file_offset"] + 8] = b"\0" * 8
    view[sn_offset : sn_offset + sn_size] = b"\0" * sn_size

    cert_start = pe["cert_file_offset"]
    cert_size = pe["cert_size"]
    if cert_start is None or cert_size <= 0:
        hasher.update(view)
        return hasher.digest()

    # Authenticode certificate bytes are omitted from the digest entirely.
    hasher.update(view[:cert_start])
    if cert_start + cert_size < len(view):
        hasher.update(view[cert_start + cert_size :])
    return hasher.digest()


def verify_assembly_bytes(data: bytes) -> dict[str, Any]:
    pe = parse_pe_clr(data)
    if pe is None:
        return {
            "managed_clr_present": False,
            "strong_name_flag_present": False,
            "strong_name_blob_present": False,
            "public_key_present": False,
            "hash_algorithm": None,
            "public_key_token": None,
            "status": "not_applicable",
            "reasons": ["not_managed_clr_pe"],
        }
    flag_present = pe["strong_name_signed_flag"]
    blob_present = bool(pe["strong_name_offset"] is not None and pe["strong_name_size"] > 0)
    try:
        public_key_blob = extract_assembly_public_key(data, pe)
    except ValueError as exc:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": blob_present,
            "public_key_present": False,
            "hash_algorithm": None,
            "public_key_token": None,
            "status": "failed",
            "reasons": [str(exc)[:80]],
        }
    public_key_present = bool(public_key_blob)
    if not flag_present and not blob_present and not public_key_present:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": False,
            "strong_name_blob_present": False,
            "public_key_present": False,
            "hash_algorithm": None,
            "public_key_token": None,
            "status": "unsigned",
            "reasons": ["managed_assembly_without_strong_name"],
        }
    if flag_present and blob_present:
        sn_offset = pe["strong_name_offset"]
        assert sn_offset is not None
        signature = data[sn_offset : sn_offset + pe["strong_name_size"]]
        if all(byte == 0 for byte in signature):
            return {
                "managed_clr_present": True,
                "strong_name_flag_present": True,
                "strong_name_blob_present": True,
                "public_key_present": public_key_present,
                "hash_algorithm": None,
                "public_key_token": public_key_token(public_key_blob) if public_key_blob else None,
                "status": "delay_signed",
                "reasons": ["strong_name_signature_all_zeros"],
            }
    if not public_key_blob:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": blob_present,
            "public_key_present": False,
            "hash_algorithm": None,
            "public_key_token": None,
            "status": "invalid",
            "reasons": ["strong_name_public_key_missing"],
        }
    if not blob_present:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": False,
            "public_key_present": True,
            "hash_algorithm": None,
            "public_key_token": public_key_token(public_key_blob),
            "status": "delay_signed" if flag_present else "unsigned",
            "reasons": ["strong_name_blob_missing"],
        }
    try:
        key = parse_public_key_blob(public_key_blob)
    except ValueError as exc:
        reason = str(exc)
        status = "unsupported" if reason.startswith("unsupported_") else "failed"
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": blob_present,
            "public_key_present": True,
            "hash_algorithm": None,
            "public_key_token": None,
            "status": status,
            "reasons": [reason[:80]],
        }
    sn_offset = pe["strong_name_offset"]
    assert sn_offset is not None
    signature_stored = data[sn_offset : sn_offset + pe["strong_name_size"]]
    if len(signature_stored) != key["modulus_len"]:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": True,
            "public_key_present": True,
            "hash_algorithm": key["hash_algorithm"],
            "public_key_token": key["public_key_token"],
            "status": "invalid",
            "reasons": ["strong_name_signature_length_mismatch"],
        }
    try:
        digest = strong_name_hash(data, pe, key["hash_algorithm"])
    except ValueError as exc:
        return {
            "managed_clr_present": True,
            "strong_name_flag_present": flag_present,
            "strong_name_blob_present": True,
            "public_key_present": True,
            "hash_algorithm": key["hash_algorithm"],
            "public_key_token": key["public_key_token"],
            "status": "failed",
            "reasons": [str(exc)[:80]],
        }
    signature_be = signature_stored[::-1]
    valid = rsa_public_verify(digest, signature_be, key["modulus"], key["exponent"], key["hash_algorithm"])
    return {
        "managed_clr_present": True,
        "strong_name_flag_present": flag_present,
        "strong_name_blob_present": True,
        "public_key_present": True,
        "hash_algorithm": key["hash_algorithm"],
        "public_key_token": key["public_key_token"],
        "status": "verified" if valid else "invalid",
        "reasons": ["strong_name_signature_valid"] if valid else ["strong_name_signature_mismatch"],
    }


def build_managed_fixture(
    *,
    mode: str = "signed",
    assembly_name: str = "Fixture",
    hash_alg: str = "sha1",
) -> bytes:
    """Build a minimal managed PE for contract fixtures.

    Modes: signed, unsigned, delay_signed, tampered, malformed.
    """
    if mode == "malformed":
        return b"MZ" + b"\0" * 40 + b"not-a-pe"

    sn_size = _FIXTURE_MOD_LEN
    data = bytearray(0x800)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    pe = 0x80
    data[pe : pe + 4] = b"PE\0\0"
    opt_size = 0xE0
    struct.pack_into("<HHIIIHH", data, pe + 4, 0x014C, 1, 0, 0, 0, opt_size, 0x0102)
    opt = pe + 24
    struct.pack_into("<H", data, opt, 0x10B)
    struct.pack_into("<I", data, opt + 16, 0x2000)
    struct.pack_into("<I", data, opt + 28, 0x400000)
    struct.pack_into("<I", data, opt + 32, 0x2000)
    struct.pack_into("<I", data, opt + 36, 0x200)
    struct.pack_into("<H", data, opt + 40, 6)
    struct.pack_into("<I", data, opt + 56, 0x4000)
    struct.pack_into("<I", data, opt + 60, 0x200)
    struct.pack_into("<H", data, opt + 68, 3)
    struct.pack_into("<I", data, opt + 72, 0x100000)
    struct.pack_into("<I", data, opt + 76, 0x1000)
    struct.pack_into("<I", data, opt + 80, 0x100000)
    struct.pack_into("<I", data, opt + 84, 0x1000)
    struct.pack_into("<I", data, opt + 92, 16)

    text_va = 0x2000
    text_raw = 0x200
    text_raw_size = 0x600
    cli_rva = text_va
    meta_rva = text_va + 0x80
    sn_rva = text_va + 0x400
    struct.pack_into("<II", data, opt + 96 + 14 * 8, cli_rva, 72)

    sec = opt + opt_size
    data[sec : sec + 8] = b".text\0\0\0"
    struct.pack_into("<IIII", data, sec + 8, 0x600, text_va, text_raw_size, text_raw)
    struct.pack_into("<I", data, sec + 36, 0x60000020)

    cli_off = text_raw
    struct.pack_into("<I", data, cli_off, 72)
    struct.pack_into("<HH", data, cli_off + 4, 2, 5)
    struct.pack_into("<II", data, cli_off + 8, meta_rva, 0x200)
    flags = 0x00000001  # il_only
    include_key = mode in {"signed", "delay_signed", "tampered", "unsupported"}
    include_sn = mode in {"signed", "delay_signed", "tampered", "unsupported"}
    if mode in {"signed", "delay_signed", "tampered", "unsupported"}:
        flags |= CLI_FLAG_STRONG_NAME_SIGNED
    struct.pack_into("<I", data, cli_off + 16, flags)
    struct.pack_into("<I", data, cli_off + 20, 0x06000001)
    if include_sn:
        struct.pack_into("<II", data, cli_off + 32, sn_rva, sn_size)

    pk = fixture_public_key_blob("sha1" if mode != "unsupported" else "sha1")
    if mode == "unsupported":
        # Force an unsupported hash algorithm id inside an otherwise well-formed blob.
        pk = bytearray(pk)
        struct.pack_into("<I", pk, 4, 0x0000800D)  # CALG_SHA_384 / unsupported here
        pk = bytes(pk)

    blob_heap = bytearray(b"\x00")
    pk_index = 0
    if include_key:
        pk_index = len(blob_heap)
        blob_heap += encode_blob(pk)
    strings = bytearray(b"\x00")
    name_idx = len(strings)
    strings.extend(assembly_name.encode("utf-8") + b"\0")
    guid_heap = bytearray(16)
    us_heap = bytearray(b"\x00")
    module_row = struct.pack("<HHHHH", 0, name_idx, 1, 0, 0)
    asm_flags = 0x0001 if include_key else 0
    assembly_row = struct.pack("<IHHHHIHHH", 0x8004, 1, 0, 0, 0, asm_flags, pk_index, name_idx, 0)
    tables_stream = bytearray()
    tables_stream += struct.pack("<IBBBB", 0, 2, 0, 0, 0)
    tables_stream += struct.pack("<Q", (1 << 0) | (1 << 0x20))
    tables_stream += struct.pack("<Q", 0)
    tables_stream += struct.pack("<II", 1, 1)
    tables_stream += module_row
    tables_stream += assembly_row

    version = pad4(b"v4.0.30319\0")
    stream_bodies = [
        ("#~", bytes(tables_stream)),
        ("#Strings", pad4(bytes(strings))),
        ("#US", pad4(bytes(us_heap))),
        ("#GUID", bytes(guid_heap)),
        ("#Blob", pad4(bytes(blob_heap))),
    ]
    ver_len = len(version)
    fixed = 16 + ver_len + 4
    headers = []
    for name, body in stream_bodies:
        nm = pad4(name.encode("ascii") + b"\0")
        headers.append((nm, body))
    headers_len = sum(8 + len(nm) for nm, _ in headers)
    bodies_start = (fixed + headers_len + 3) & ~3
    meta = bytearray()
    meta += b"BSJB"
    meta += struct.pack("<HH", 1, 1)
    meta += struct.pack("<I", 0)
    meta += struct.pack("<I", ver_len)
    meta += version
    meta += struct.pack("<HH", 0, len(stream_bodies))
    cur = bodies_start
    body_blobs = []
    for nm, body in headers:
        meta += struct.pack("<II", cur, len(body))
        meta += nm
        body_blobs.append((cur, body))
        cur = (cur + len(body) + 3) & ~3
    meta.extend(b"\0" * (cur - len(meta)))
    for offset, body in body_blobs:
        meta[offset : offset + len(body)] = body

    meta_raw = text_raw + (meta_rva - text_va)
    struct.pack_into("<I", data, cli_off + 12, len(meta))
    data[meta_raw : meta_raw + len(meta)] = meta
    file_bytes = data[: text_raw + text_raw_size]
    if mode in {"unsigned", "delay_signed"}:
        return bytes(file_bytes)

    pe_info = parse_pe_clr(bytes(file_bytes))
    assert pe_info is not None and pe_info["strong_name_offset"] is not None
    sn_offset = pe_info["strong_name_offset"]
    file_bytes = bytearray(file_bytes)
    if mode == "unsupported":
        # Non-zero placeholder signature forces public-key parsing before crypto verify.
        file_bytes[sn_offset : sn_offset + sn_size] = b"\x01" * sn_size
        return bytes(file_bytes)

    digest = strong_name_hash(bytes(file_bytes), pe_info, hash_alg)
    file_bytes[sn_offset : sn_offset + sn_size] = fixture_sign(digest, hash_alg)[::-1]
    if mode == "tampered":
        # Flip a payload byte outside checksum/cert/strong-name regions.
        file_bytes[meta_raw + 20] ^= 0x5A
    return bytes(file_bytes)


def resolve_record_path(input_path: Path, relative_path: str) -> Path:
    relative = PurePosixPath(relative_path.replace("\\", "/"))
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("invalid_relative_path")
    if input_path.is_file():
        if relative.name != input_path.name and str(relative) != input_path.name:
            raise ValueError("relative_path_mismatch_for_file_input")
        return input_path
    candidate = (input_path / Path(*relative.parts)).resolve()
    root = input_path.resolve()
    if root not in candidate.parents and candidate != root:
        raise ValueError("path_escapes_input_root")
    return candidate


def overall_status_for(statuses: list[str]) -> str:
    if not statuses:
        return "not_applicable"
    priority = ["failed", "invalid", "unsupported", "delay_signed", "unsigned", "verified", "not_applicable"]
    present = set(statuses)
    for status in priority:
        if status in present:
            if status in {"unsigned", "delay_signed"}:
                return "unproven"
            return status
    return "unproven"


def build_result(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    input_path = Path(args.input).expanduser().resolve()
    base_path = Path(args.base_result).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"input does not exist: {input_path}")
    if not base_path.is_file():
        raise FileNotFoundError(f"base result missing: {base_path}")
    base = json.loads(base_path.read_text(encoding="utf-8"))
    if base.get("schema_version") != BASE_SCHEMA_VERSION:
        raise ValueError(f"unsupported base schema: {base.get('schema_version')}")
    if base.get("proof", {}).get("proof_level") != "static_only":
        raise ValueError("base_proof_must_be_static_only")
    base_files = base.get("files") or []
    if len(base_files) > args.max_files:
        raise ValueError("max_files_exceeded")

    records: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for base_record in base_files:
        relative_path = str(base_record.get("relative_path") or "")
        try:
            candidate = resolve_record_path(input_path, relative_path)
            if candidate.is_symlink():
                raise ValueError("symlink_not_followed")
            if not candidate.is_file():
                raise FileNotFoundError("source_file_missing")
            actual_hash = sha256_file(candidate)
            if actual_hash != base_record.get("sha256"):
                raise ValueError("hash_mismatch_since_base_analysis")
            verification = verify_assembly_bytes(candidate.read_bytes())
            records.append(
                {
                    "relative_path": relative_path,
                    "sha256": actual_hash,
                    "hash_verified": True,
                    "managed_clr_present": verification["managed_clr_present"],
                    "strong_name_flag_present": verification["strong_name_flag_present"],
                    "strong_name_blob_present": verification["strong_name_blob_present"],
                    "public_key_present": verification["public_key_present"],
                    "hash_algorithm": verification["hash_algorithm"],
                    "public_key_token": verification["public_key_token"],
                    "status": verification["status"],
                    "reasons": verification["reasons"],
                    "package_execution_performed": False,
                }
            )
        except Exception as exc:
            errors.append(
                {
                    "relative_path": relative_path or "<missing>",
                    "error_type": type(exc).__name__,
                    "message": str(exc)[:300],
                }
            )

    status_counts = Counter(item["status"] for item in records)
    managed_statuses = [item["status"] for item in records if item["managed_clr_present"]]
    result = {
        "schema_version": SCHEMA_VERSION,
        "analyzer_version": ANALYZER_VERSION,
        "generated_at": utc_now(),
        "base_result": {
            "schema_version": BASE_SCHEMA_VERSION,
            "sha256": sha256_file(base_path),
            "hash_verified_source_files": len(records),
        },
        "input": {
            "kind": "directory" if input_path.is_dir() else "file",
            "display_name": input_path.name,
            "absolute_path_emitted": False,
        },
        "limits": {
            "max_files": args.max_files,
            "package_execution_allowed": False,
            "network_activity_allowed": False,
        },
        "proof": {
            "proof_level": "clr_strong_name_integrity",
            "file_execution_performed": False,
            "archive_payload_extracted": False,
            "network_activity_performed": False,
            "target_mutation_performed": False,
            "host_mutation_performed": False,
            "authenticode_trust_evaluated": False,
            "online_revocation_checked": False,
            "strong_name_cryptographic_validation_performed": True,
            "runtime_behavior_validated": False,
        },
        "summary": {
            "base_files": len(base_files),
            "files_examined": len(records),
            "managed_assemblies": sum(1 for item in records if item["managed_clr_present"]),
            "verified_count": status_counts.get("verified", 0),
            "unsigned_count": status_counts.get("unsigned", 0),
            "delay_signed_count": status_counts.get("delay_signed", 0),
            "invalid_count": status_counts.get("invalid", 0),
            "unsupported_count": status_counts.get("unsupported", 0),
            "failed_count": status_counts.get("failed", 0),
            "not_applicable_count": status_counts.get("not_applicable", 0),
            "error_count": len(errors),
            "overall_status": overall_status_for(managed_statuses),
        },
        "files": records,
        "errors": errors,
    }
    return result, 1 if errors else 0


def render_english(result: dict[str, Any]) -> str:
    summary = result["summary"]
    lines = [
        "PACKAGE STRONG-NAME VERIFICATION",
        f"Base files: {summary['base_files']}",
        f"Files examined: {summary['files_examined']}",
        f"Managed assemblies: {summary['managed_assemblies']}",
        f"Overall status: {summary['overall_status']}",
        f"Errors: {summary['error_count']}",
        "",
        "Counts:",
        f"- verified: {summary['verified_count']}",
        f"- unsigned: {summary['unsigned_count']}",
        f"- delay_signed: {summary['delay_signed_count']}",
        f"- invalid: {summary['invalid_count']}",
        f"- unsupported: {summary['unsupported_count']}",
        f"- failed: {summary['failed_count']}",
        f"- not_applicable: {summary['not_applicable_count']}",
        "",
        "Proof: clr_strong_name_integrity",
        "- source hashes were re-verified before strong-name inspection",
        "- CLR strong-name cryptographic validation was performed where applicable",
        "- Authenticode publisher trust was not evaluated",
        "- online revocation was not checked",
        "- no package code executed",
        "- runtime behavior remains unproven",
        "",
        "Artifacts:",
        "- package_strong_name_verification.json",
        "- package_strong_name_verification.txt",
    ]
    return "\n".join(lines) + "\n"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--base-result", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--max-files", type=int, default=DEFAULT_MAX_FILES)
    args = parser.parse_args(argv)
    if args.max_files <= 0:
        parser.error("max-files must be a positive integer")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        result, exit_code = build_result(args)
    except (FileNotFoundError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2
    atomic_write(output_dir / "package_strong_name_verification.json", json.dumps(result, indent=2, sort_keys=True) + "\n")
    atomic_write(output_dir / "package_strong_name_verification.txt", render_english(result))
    print(render_english(result), end="")
    print(f"Evidence: {output_dir}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
