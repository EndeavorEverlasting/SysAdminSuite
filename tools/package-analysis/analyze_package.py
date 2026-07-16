#!/usr/bin/env python3
"""Fail-closed, static-only package analyzer for installers and application bundles.

The analyzer hashes and classifies local files, inspects safe container/header metadata,
and emits machine-readable plus English evidence. It never executes package code,
extracts archive payloads, follows shortcuts, contacts endpoints, or mutates the host.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import struct
import sys
import tempfile
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

SCHEMA_VERSION = "sas-package-static-analysis/v1"
ANALYZER_VERSION = "0.1.0"
DEFAULT_MAX_FILES = 50000
DEFAULT_MAX_TOTAL_BYTES = 100 * 1024**3
DEFAULT_MAX_CONTENT_BYTES = 8 * 1024**2

INSTALLER_EXTENSIONS = {".exe", ".msi", ".msix", ".msixbundle", ".appx", ".appxbundle", ".msp", ".mst"}
SCRIPT_EXTENSIONS = {".ps1", ".psm1", ".bat", ".cmd", ".vbs", ".js", ".jse", ".wsf", ".sh", ".py"}
CONFIG_EXTENSIONS = {".xml", ".json", ".ini", ".cfg", ".config", ".manifest", ".inf", ".reg", ".properties", ".yaml", ".yml"}
ARCHIVE_EXTENSIONS = {".zip", ".jar", ".whl", ".nupkg", ".docx", ".xlsx", ".pptx"}
SHORTCUT_EXTENSIONS = {".lnk", ".url"}
TEXT_EXTENSIONS = SCRIPT_EXTENSIONS | CONFIG_EXTENSIONS | {".txt", ".md", ".log"}

INDICATOR_PATTERNS: dict[str, re.Pattern[str]] = {
    "registry_changes": re.compile(r"\b(reg(?:\.exe)?\s+(?:add|delete|import)|new-itemproperty|set-itemproperty|remove-itemproperty|registry)\b", re.I),
    "services": re.compile(r"\b(sc(?:\.exe)?\s+(?:create|delete|config|start|stop)|new-service|set-service|start-service|stop-service|delete-service)\b", re.I),
    "scheduled_tasks": re.compile(r"\b(schtasks|register-scheduledtask|unregister-scheduledtask|new-scheduledtask)\b", re.I),
    "reboot": re.compile(r"\b(reboot|requiredrestart|restart-computer|shutdown(?:\.exe)?|forcerestart|norestart|3010|1641)\b", re.I),
    "autologon": re.compile(r"\b(autologon|autoadminlogon|defaultpassword|defaultusername|winlogon)\b", re.I),
    "account_changes": re.compile(r"\b(net\s+user|net\s+localgroup|new-localuser|add-localgroupmember|credentialprovider)\b", re.I),
    "firewall_changes": re.compile(r"\b(netsh\s+advfirewall|new-netfirewallrule|set-netfirewallrule|firewall)\b", re.I),
    "broad_deletion": re.compile(r"\b(rmdir\s+/s|remove-item\s+[^\r\n]*-recurse|del\s+/[fsq]|rm\s+-rf)\b", re.I),
    "self_removal": re.compile(r"\b(del\s+%0|del\s+\"%~f0\"|self[-_ ]?delete|self[-_ ]?removal)\b", re.I),
    "silent_switches": re.compile(r"(?:^|\s)/(?:q|qn|qb|quiet|silent|s)(?:\s|$)|--silent\b|--quiet\b", re.I),
    "process_execution": re.compile(r"\b(start-process|process\.start|subprocess\.|createprocess|shellexecute|cmd(?:\.exe)?\s+/c|powershell(?:\.exe)?)\b", re.I),
    "download_or_network": re.compile(r"\b(invoke-webrequest|invoke-restmethod|curl(?:\.exe)?|wget(?:\.exe)?|bitsadmin|start-bitstransfer|downloadstring|webclient)\b", re.I),
    "browser_policy": re.compile(r"\b(extensionforcelist|extensioninstallforcelist|extensionallowlist|google\\chrome\\extensions|microsoft\\edge\\extensions)\b", re.I),
    "driver_changes": re.compile(r"\b(pnputil|devcon|setupapi|driverstore|add-driver|dism(?:\.exe)?)\b", re.I),
    "group_policy": re.compile(r"\b(gpupdate|group policy|policies\\google|policies\\microsoft)\b", re.I),
    "encoded_powershell": re.compile(r"(?:-encodedcommand|-enc\s+[A-Za-z0-9+/=]{20,})", re.I),
    "secret_like_material": re.compile(r"\b(password|passwd|api[_-]?key|client[_-]?secret|bearer\s+[A-Za-z0-9._~+/-]+|token)\b", re.I),
}

ENDPOINT_PATTERN = re.compile(
    r"(?P<url>https?://[^\s\"'<>]+)|(?P<unc>\\\\[A-Za-z0-9._-]+\\[^\s\"'<>]+)", re.I
)

MACHINE_TYPES = {
    0x014C: "x86",
    0x8664: "x64",
    0x01C0: "arm",
    0xAA64: "arm64",
}
SUBSYSTEMS = {
    1: "native",
    2: "windows_gui",
    3: "windows_console",
    9: "windows_ce_gui",
    10: "efi_application",
    14: "xbox",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", delete=False, dir=path.parent) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


def classify_file(path: Path, magic: bytes) -> tuple[str, str]:
    ext = path.suffix.lower()
    if magic.startswith(b"MZ"):
        return "installer" if ext == ".exe" else "portable_executable", "pe"
    if magic.startswith(bytes.fromhex("d0cf11e0a1b11ae1")):
        return "installer" if ext in {".msi", ".msp", ".mst"} else "compound_file", "ole_cfb"
    if magic.startswith(b"PK\x03\x04") or ext in ARCHIVE_EXTENSIONS:
        return "archive", "zip"
    if ext in INSTALLER_EXTENSIONS:
        return "installer", "extension_only"
    if ext in SCRIPT_EXTENSIONS:
        return "script", "text_or_script"
    if ext in CONFIG_EXTENSIONS:
        return "configuration", "text_or_config"
    if ext in SHORTCUT_EXTENSIONS:
        return "shortcut", "shortcut"
    return "other", "unknown"


def entropy(path: Path, max_bytes: int = 1024 * 1024) -> float | None:
    with path.open("rb") as handle:
        data = handle.read(max_bytes)
    if not data:
        return 0.0
    counts = Counter(data)
    length = len(data)
    return round(-sum((count / length) * math.log2(count / length) for count in counts.values()), 4)


def inspect_pe(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "valid_pe_header": False,
        "machine": None,
        "section_count": None,
        "compile_timestamp": None,
        "optional_header_magic": None,
        "subsystem": None,
        "authenticode_certificate_table_present": False,
        "optional_pefile_available": False,
        "imported_dlls": [],
        "section_names": [],
    }
    try:
        with path.open("rb") as handle:
            head = handle.read(4096)
            if len(head) < 64 or head[:2] != b"MZ":
                return result
            pe_offset = struct.unpack_from("<I", head, 0x3C)[0]
            if pe_offset + 24 > len(head):
                handle.seek(0)
                head = handle.read(min(path.stat().st_size, pe_offset + 512))
            if pe_offset + 24 > len(head) or head[pe_offset : pe_offset + 4] != b"PE\0\0":
                return result
            machine, section_count, timestamp, _, _, optional_size, _ = struct.unpack_from("<HHIIIHH", head, pe_offset + 4)
            optional_offset = pe_offset + 24
            magic = struct.unpack_from("<H", head, optional_offset)[0] if optional_size >= 2 else None
            subsystem_offset = optional_offset + 68
            subsystem = struct.unpack_from("<H", head, subsystem_offset)[0] if subsystem_offset + 2 <= len(head) else None
            data_dir_offset = optional_offset + (112 if magic == 0x20B else 96)
            security_offset = data_dir_offset + (8 * 4)
            cert_size = 0
            if security_offset + 8 <= len(head):
                _, cert_size = struct.unpack_from("<II", head, security_offset)
            result.update(
                {
                    "valid_pe_header": True,
                    "machine": MACHINE_TYPES.get(machine, f"0x{machine:04x}"),
                    "section_count": section_count,
                    "compile_timestamp": timestamp,
                    "optional_header_magic": "pe32_plus" if magic == 0x20B else "pe32" if magic == 0x10B else f"0x{magic:04x}" if magic else None,
                    "subsystem": SUBSYSTEMS.get(subsystem, subsystem),
                    "authenticode_certificate_table_present": cert_size > 0,
                }
            )
    except (OSError, struct.error, ValueError):
        return result

    try:
        import pefile  # type: ignore

        result["optional_pefile_available"] = True
        pe = pefile.PE(str(path), fast_load=True)
        directories = [pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
        pe.parse_data_directories(directories=directories)
        result["section_names"] = [section.Name.rstrip(b"\0").decode("ascii", "replace") for section in pe.sections[:128]]
        if hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
            result["imported_dlls"] = sorted(
                {
                    entry.dll.decode("ascii", "replace")
                    for entry in pe.DIRECTORY_ENTRY_IMPORT[:256]
                    if getattr(entry, "dll", None)
                }
            )
        pe.close()
    except ImportError:
        pass
    except Exception as exc:
        result["pefile_error"] = type(exc).__name__
    return result


def inspect_compound_file(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "valid_compound_file_header": True,
        "optional_olefile_available": False,
        "stream_count": None,
        "stream_name_fingerprints": [],
    }
    try:
        import olefile  # type: ignore

        result["optional_olefile_available"] = True
        if olefile.isOleFile(str(path)):
            with olefile.OleFileIO(str(path)) as ole:
                streams = ole.listdir(streams=True, storages=False)
            result["stream_count"] = len(streams)
            result["stream_name_fingerprints"] = [
                hashlib.sha256("/".join(parts).encode("utf-8", "replace")).hexdigest()
                for parts in streams[:256]
            ]
    except ImportError:
        pass
    except Exception as exc:
        result["olefile_error"] = type(exc).__name__
    return result


def safe_member_name(name: str) -> dict[str, Any]:
    posix = PurePosixPath(name.replace("\\", "/"))
    parts = [part for part in posix.parts if part not in {"", ".", ".."}]
    basename = parts[-1] if parts else ""
    return {
        "basename": basename[:200],
        "extension": Path(basename).suffix.lower(),
        "depth": max(0, len(parts) - 1),
        "path_sha256": hashlib.sha256("/".join(parts).encode("utf-8", "replace")).hexdigest(),
    }


def inspect_zip(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "valid_zip": False,
        "member_count": None,
        "encrypted_member_count": 0,
        "compressed_bytes": 0,
        "uncompressed_bytes": 0,
        "member_samples": [],
        "nested_installer_extensions": [],
        "payload_extracted": False,
    }
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            result["valid_zip"] = True
            result["member_count"] = len(infos)
            result["encrypted_member_count"] = sum(1 for info in infos if info.flag_bits & 0x1)
            result["compressed_bytes"] = sum(info.compress_size for info in infos)
            result["uncompressed_bytes"] = sum(info.file_size for info in infos)
            result["member_samples"] = [safe_member_name(info.filename) for info in infos[:200]]
            result["nested_installer_extensions"] = sorted(
                {
                    Path(info.filename).suffix.lower()
                    for info in infos
                    if Path(info.filename).suffix.lower() in INSTALLER_EXTENSIONS | SCRIPT_EXTENSIONS
                }
            )
    except (OSError, zipfile.BadZipFile, RuntimeError):
        pass
    return result


def endpoint_fingerprints(text: str) -> list[dict[str, str]]:
    output: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for match in ENDPOINT_PATTERN.finditer(text):
        raw = match.group(0)
        kind = "url" if match.group("url") else "unc"
        fingerprint = hashlib.sha256(raw.encode("utf-8", "replace")).hexdigest()
        key = (kind, fingerprint)
        if key in seen:
            continue
        seen.add(key)
        output.append({"kind": kind, "sha256": fingerprint})
        if len(output) >= 50:
            break
    return output


def scan_content(path: Path, max_bytes: int, is_text: bool) -> dict[str, Any]:
    with path.open("rb") as handle:
        data = handle.read(max_bytes + 1)
    truncated = len(data) > max_bytes
    data = data[:max_bytes]
    text = data.decode("utf-8", "replace") if is_text else data.decode("latin-1", "ignore")
    indicators = sorted(name for name, pattern in INDICATOR_PATTERNS.items() if pattern.search(text))
    return {
        "status": "scanned_truncated" if truncated else "scanned",
        "bytes_scanned": len(data),
        "truncated": truncated,
        "indicators": indicators,
        "endpoint_fingerprints": endpoint_fingerprints(text),
        "raw_strings_emitted": False,
    }


def relative_display(path: Path, input_path: Path) -> str:
    base = input_path if input_path.is_dir() else input_path.parent
    try:
        value = path.relative_to(base).as_posix()
    except ValueError:
        value = path.name
    return value or path.name


def enumerate_files(input_path: Path, output_dir: Path, max_files: int, max_total_bytes: int) -> tuple[list[Path], list[dict[str, str]], int]:
    skipped: list[dict[str, str]] = []
    files: list[Path] = []
    total_bytes = 0
    candidates: Iterable[Path] = [input_path] if input_path.is_file() else input_path.rglob("*")
    for candidate in sorted(candidates, key=lambda item: item.as_posix().lower()):
        try:
            resolved = candidate.resolve(strict=False)
            if output_dir == resolved or output_dir in resolved.parents:
                continue
            if candidate.is_symlink():
                skipped.append({"path": relative_display(candidate, input_path), "reason": "symlink_not_followed"})
                continue
            if not candidate.is_file():
                continue
            size = candidate.stat().st_size
        except OSError:
            skipped.append({"path": relative_display(candidate, input_path), "reason": "metadata_unavailable"})
            continue
        files.append(candidate)
        total_bytes += size
        if len(files) > max_files:
            raise ValueError(f"file limit exceeded: {len(files)} > {max_files}")
        if total_bytes > max_total_bytes:
            raise ValueError(f"byte limit exceeded: {total_bytes} > {max_total_bytes}")
    return files, skipped, total_bytes


def analyze_file(path: Path, input_path: Path, max_content_bytes: int) -> dict[str, Any]:
    with path.open("rb") as handle:
        magic = handle.read(16)
    file_class, magic_type = classify_file(path, magic)
    ext = path.suffix.lower()
    record: dict[str, Any] = {
        "relative_path": relative_display(path, input_path),
        "file_name": path.name,
        "extension": ext,
        "file_class": file_class,
        "magic_type": magic_type,
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "entropy_first_mib": entropy(path),
        "content_scan": scan_content(path, max_content_bytes, ext in TEXT_EXTENSIONS),
        "pe": None,
        "compound_file": None,
        "archive": None,
    }
    if magic_type == "pe":
        record["pe"] = inspect_pe(path)
    elif magic_type == "ole_cfb":
        record["compound_file"] = inspect_compound_file(path)
    elif magic_type == "zip":
        record["archive"] = inspect_zip(path)
    return record


def render_english(result: dict[str, Any]) -> str:
    summary = result["summary"]
    lines = [
        "PACKAGE STATIC ANALYSIS",
        f"Input type: {result['input']['kind']}",
        f"Files analyzed: {summary['analyzed_files']}",
        f"Files skipped: {summary['skipped_files']}",
        f"Errors: {summary['error_count']}",
        "",
        "Proof: static_only",
        "- no package code executed",
        "- no archive payload extracted",
        "- no network activity",
        "- no target or host mutation",
        "- Authenticode certificate-table presence is not trust validation",
        "",
        "File classes:",
    ]
    for name, count in sorted(summary["file_classes"].items()):
        lines.append(f"- {name}: {count}")
    lines.append("")
    lines.append("Indicators:")
    if summary["indicator_counts"]:
        for name, count in sorted(summary["indicator_counts"].items(), key=lambda item: (-item[1], item[0])):
            lines.append(f"- {name}: {count}")
    else:
        lines.append("- none observed in bounded content scan")
    lines.append("")
    lines.append("Optional enrichments:")
    lines.append(f"- pefile: {'available' if result['tools']['pefile_available'] else 'not installed'}")
    lines.append(f"- olefile: {'available' if result['tools']['olefile_available'] else 'not installed'}")
    lines.append("")
    lines.append("Result artifacts:")
    lines.append("- package_analysis.json")
    lines.append("- package_analysis.txt")
    return "\n".join(lines) + "\n"


def optional_module_available(name: str) -> bool:
    try:
        __import__(name)
        return True
    except ImportError:
        return False


def build_result(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    input_path = Path(args.input).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"input path does not exist: {input_path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    files, skipped, total_bytes = enumerate_files(input_path, output_dir, args.max_files, args.max_total_bytes)
    records: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for path in files:
        try:
            records.append(analyze_file(path, input_path, args.max_content_bytes))
        except Exception as exc:
            errors.append(
                {
                    "relative_path": relative_display(path, input_path),
                    "error_type": type(exc).__name__,
                    "message": str(exc)[:500],
                }
            )
    classes = Counter(record["file_class"] for record in records)
    indicators = Counter(
        indicator
        for record in records
        for indicator in record["content_scan"]["indicators"]
    )
    result: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "analyzer_version": ANALYZER_VERSION,
        "generated_at": utc_now(),
        "input": {
            "kind": "directory" if input_path.is_dir() else "file",
            "display_name": input_path.name,
            "absolute_path_emitted": False,
            "total_bytes": total_bytes,
        },
        "limits": {
            "max_files": args.max_files,
            "max_total_bytes": args.max_total_bytes,
            "max_content_bytes_per_file": args.max_content_bytes,
            "archive_payload_extraction_allowed": False,
            "symlink_following_allowed": False,
        },
        "tools": {
            "python_version": platform.python_version(),
            "platform": platform.system().lower(),
            "pefile_available": optional_module_available("pefile"),
            "olefile_available": optional_module_available("olefile"),
        },
        "proof": {
            "proof_level": "static_only",
            "file_execution_performed": False,
            "archive_payload_extracted": False,
            "network_activity_performed": False,
            "target_mutation_performed": False,
            "host_mutation_performed": False,
            "signature_trust_validated": False,
            "runtime_behavior_validated": False,
        },
        "summary": {
            "discovered_files": len(files),
            "analyzed_files": len(records),
            "skipped_files": len(skipped),
            "error_count": len(errors),
            "file_classes": dict(sorted(classes.items())),
            "indicator_counts": dict(sorted(indicators.items())),
        },
        "files": records,
        "skipped": skipped,
        "errors": errors,
    }
    return result, 1 if errors else 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Local file or directory to analyze. The package is never executed.")
    parser.add_argument("--output-dir", required=True, help="Local output directory for JSON and English evidence.")
    parser.add_argument("--max-files", type=int, default=DEFAULT_MAX_FILES)
    parser.add_argument("--max-total-bytes", type=int, default=DEFAULT_MAX_TOTAL_BYTES)
    parser.add_argument("--max-content-bytes", type=int, default=DEFAULT_MAX_CONTENT_BYTES)
    args = parser.parse_args(argv)
    if args.max_files <= 0 or args.max_total_bytes <= 0 or args.max_content_bytes <= 0:
        parser.error("all limits must be positive integers")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).expanduser().resolve()
    try:
        result, exit_code = build_result(args)
    except (FileNotFoundError, ValueError, OSError) as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2
    atomic_write(output_dir / "package_analysis.json", json.dumps(result, indent=2, sort_keys=True) + "\n")
    atomic_write(output_dir / "package_analysis.txt", render_english(result))
    print(render_english(result), end="")
    print(f"Evidence: {output_dir}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
