#!/usr/bin/env python3
"""Match selected local files against an operator-pinned SHA-256 list."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import stat
import sys
import time
from pathlib import Path

SIGNATURE_SCHEMA = "sas-antivirus-sha256-signatures/v1"
MAX_REQUEST_BYTES = 64 * 1024
MAX_SIGNATURE_BYTES = 2 * 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_SCAN_BYTES = 512 * 1024 * 1024
MAX_ENTRIES = 10_000
SCAN_SECONDS = 60
BLOCK_BYTES = 1024 * 1024
OPEN_FLAGS = (os.O_RDONLY | getattr(os, "O_BINARY", 0) |
              getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOFOLLOW", 0))
DIGEST = re.compile(r"[a-f0-9]{64}")

NO_MATCH = 0
MATCH = 1
INCOMPLETE = 10
MATCH_INCOMPLETE = 11
POLICY_REJECTED = 12


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("Duplicate policy key")
    return result


def load_signatures(path: Path, expected: str) -> frozenset[str]:
    if not DIGEST.fullmatch(expected) or not local_path(path):
        raise ValueError("Invalid signature pin or file")
    checked_directory(path.parent)
    if not regular_file(path.lstat()):
        raise ValueError("Signature policy must be a regular file")
    with open_readonly(path) as stream:
        if not regular_file(os.fstat(stream.fileno())):
            raise ValueError("Signature policy must be a regular file")
        document = stream.read(MAX_SIGNATURE_BYTES + 1)
    if (len(document) > MAX_SIGNATURE_BYTES or
            not hmac.compare_digest(hashlib.sha256(document).hexdigest(), expected)):
        raise ValueError("Signature policy size or pin did not match")
    policy = json.loads(document, object_pairs_hook=unique_object)
    if (not isinstance(policy, dict) or set(policy) != {"schema_version", "sha256"}
            or policy["schema_version"] != SIGNATURE_SCHEMA):
        raise ValueError("Unknown signature policy")
    digests = policy["sha256"]
    if (not isinstance(digests, list) or not digests or
            any(not isinstance(item, str) or not DIGEST.fullmatch(item) for item in digests) or
            len(set(digests)) != len(digests)):
        raise ValueError("Expected unique SHA-256 digests")
    return frozenset(digests)


def outcome(matched: bool, incomplete: bool) -> int:
    if incomplete:
        return MATCH_INCOMPLETE if matched else INCOMPLETE
    return MATCH if matched else NO_MATCH


def is_link(info: os.stat_result) -> bool:
    return stat.S_ISLNK(info.st_mode) or bool(
        getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT
    )


def regular_file(info: os.stat_result) -> bool:
    return stat.S_ISREG(info.st_mode) and not is_link(info) and info.st_nlink == 1


def local_path(path: Path) -> bool:
    if not path.is_absolute() or ".." in path.parts or path.drive.startswith("\\\\"):
        return False
    if os.name == "nt":
        import ctypes
        drive_type = ctypes.windll.kernel32.GetDriveTypeW
        drive_type.argtypes = (ctypes.c_wchar_p,)
        drive_type.restype = ctypes.c_uint
        return drive_type(path.anchor) in (2, 3, 5, 6)
    return True


def checked_directory(path: Path) -> os.stat_result:
    if not local_path(path):
        raise ValueError("Select an absolute local directory")
    for directory in (*reversed(path.parents), path):
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or is_link(info):
            raise ValueError("Scan scope must use ordinary directories")
    return info


def validate_scope(scope: Path) -> os.stat_result:
    if scope == Path(scope.anchor):
        raise ValueError("Select a subdirectory for scanning")
    return checked_directory(scope)


def identity(info: os.stat_result) -> tuple[int, int]:
    return info.st_dev, info.st_ino


def snapshot(info: os.stat_result) -> tuple[int, ...]:
    return (*identity(info), info.st_mode, info.st_nlink, info.st_size, info.st_mtime_ns)


def same_opened_file(before: os.stat_result, opened: os.stat_result) -> bool:
    # Cross-API NTFS ctime can differ even for the same file. Compare ctime
    # again below using two samples from the same open handle.
    return snapshot(before) == snapshot(opened) and (
        os.name == "nt" or before.st_ctime_ns == opened.st_ctime_ns
    )


def same_directory(before: os.stat_result, after: os.stat_result) -> bool:
    return snapshot(before) == snapshot(after) and before.st_ctime_ns == after.st_ctime_ns


def open_readonly(path: Path | str, dir_fd: int | None = None):
    descriptor = os.open(path, OPEN_FLAGS, dir_fd=dir_fd)
    return os.fdopen(descriptor, "rb")


def digest_file(entry: os.DirEntry, before: os.stat_result, scope: Path,
                scope_identity: tuple[int, int], root_fd: int | None, deadline: float) -> str:
    if root_fd is None and identity(validate_scope(scope)) != scope_identity:
        raise ValueError("Scan scope changed")
    with open_readonly(entry.name if root_fd is not None else scope / entry.name, root_fd) as stream:
        opened = os.fstat(stream.fileno())
        if not regular_file(opened) or not same_opened_file(before, opened):
            raise ValueError("File changed before scan")
        if root_fd is None and identity(validate_scope(scope)) != scope_identity:
            raise ValueError("Scan scope changed")
        digest = hashlib.sha256()
        remaining = before.st_size
        while remaining:
            if time.monotonic() >= deadline:
                raise ValueError("Scan time budget exhausted")
            block = stream.read(min(BLOCK_BYTES, remaining))
            if not block:
                raise ValueError("File changed during scan")
            digest.update(block)
            remaining -= len(block)
        # Size alone is insufficient for pseudo-files and live mutations.
        if stream.read(1):
            raise ValueError("File exceeds its recorded size")
        after = os.fstat(stream.fileno())
        if snapshot(after) != snapshot(opened) or after.st_ctime_ns != opened.st_ctime_ns:
            raise ValueError("File changed during scan")
        return digest.hexdigest()


def scan_directory(scope: Path, scope_info: os.stat_result, signatures: frozenset[str]) -> int:
    root_fd = None
    expected_root = identity(scope_info)
    matched = incomplete = False
    spent = 0
    deadline = time.monotonic() + SCAN_SECONDS
    try:
        if os.scandir in os.supports_fd and hasattr(os, "O_DIRECTORY"):
            root_fd = os.open(scope, OPEN_FLAGS | os.O_DIRECTORY)
            if identity(os.fstat(root_fd)) != expected_root:
                return INCOMPLETE
        scan_root = root_fd if root_fd is not None else scope
        with os.scandir(scan_root) as listing:
            current = os.fstat(root_fd) if root_fd is not None else validate_scope(scope)
            if not same_directory(scope_info, current):
                return INCOMPLETE
            for index, entry in enumerate(listing):
                if index >= MAX_ENTRIES or spent >= MAX_SCAN_BYTES or time.monotonic() >= deadline:
                    return outcome(matched, True)
                try:
                    # Windows DirEntry.stat omits device and inode identity.
                    location = entry.name if root_fd is not None else scope / entry.name
                    info = os.stat(location, dir_fd=root_fd, follow_symlinks=False)
                    if is_link(info) or stat.S_ISDIR(info.st_mode):
                        continue
                    if (not regular_file(info) or info.st_dev != scope_info.st_dev or
                            info.st_size > MAX_FILE_BYTES or info.st_size + 1 > MAX_SCAN_BYTES - spent):
                        incomplete = True
                        continue
                    spent += info.st_size + 1
                    digest = digest_file(entry, info, scope, expected_root, root_fd, deadline)
                    matched = matched or digest in signatures
                except (OSError, ValueError):
                    incomplete = True
        final_root = validate_scope(scope)
        incomplete = incomplete or not same_directory(scope_info, final_root)
    except (OSError, ValueError):
        incomplete = True
    finally:
        if root_fd is not None:
            os.close(root_fd)
    return outcome(matched, incomplete)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    try:
        raw = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
        if len(raw) > MAX_REQUEST_BYTES:
            return POLICY_REJECTED
        request = json.loads(raw, object_pairs_hook=unique_object)
        if (not isinstance(request, dict) or set(request) != {"scan_directory", "signatures", "signature_sha256"}
                or any(not isinstance(value, str) or "\0" in value for value in request.values())):
            return POLICY_REJECTED
        signatures = load_signatures(Path(request["signatures"]), request["signature_sha256"])
        scope = Path(request["scan_directory"])
        scope_info = validate_scope(scope)
    except (OSError, ValueError, RecursionError):
        return POLICY_REJECTED
    return NO_MATCH if args.validate_only else scan_directory(scope, scope_info, signatures)


if __name__ == "__main__":
    raise SystemExit(main())
