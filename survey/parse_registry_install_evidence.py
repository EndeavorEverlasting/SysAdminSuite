#!/usr/bin/env python3
"""Parse CMD/reg.exe software installation evidence.

This parser is intentionally read-only. It consumes raw evidence files and a
public-safe software evidence catalog, then emits normalized CSV/JSON results.
"""
from __future__ import annotations

import argparse
import csv
import fnmatch
import json
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any


@dataclass
class EvidenceResult:
    target: str
    software_id: str
    status: str
    evidence_strength: str
    evidence_source: str
    display_name: str = ""
    display_version: str = ""
    publisher: str = ""
    detail: str = ""
    revisit_recommendation: str = ""


def load_catalog(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def find_software(catalog: dict[str, Any], software_id: str) -> dict[str, Any]:
    for item in catalog.get("software", []):
        if item.get("software_id") == software_id:
            return item
    raise SystemExit(f"software_id not found in catalog: {software_id}")


def parse_reg_blocks(text: str) -> list[dict[str, str]]:
    blocks: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in text.splitlines():
        line = raw.rstrip("\r\n")
        if re.match(r"^(HKEY_|HKLM|\\\\[^\\]+\\HKLM)", line.strip(), re.IGNORECASE):
            if current:
                blocks.append(current)
            current = {"__key": line.strip()}
            continue
        if current is None:
            continue
        match = re.match(r"^\s{2,}([^\s].*?)\s+REG_\w+\s+(.*)$", line)
        if match:
            current[match.group(1).strip()] = match.group(2).strip()
    if current:
        blocks.append(current)
    return blocks


def any_pattern(value: str, patterns: list[str]) -> bool:
    normalized = value or ""
    for pattern in patterns:
        if fnmatch.fnmatch(normalized.lower(), pattern.lower()):
            return True
        if pattern.lower() in normalized.lower():
            return True
    return False


def registry_match(blocks: list[dict[str, str]], software: dict[str, Any]) -> tuple[str, dict[str, str] | None, str]:
    registry = software.get("registry", {})
    name_patterns = registry.get("uninstall_display_name_patterns", [])
    publisher_patterns = registry.get("uninstall_publisher_patterns", [])

    partial: dict[str, str] | None = None
    for block in blocks:
        name = block.get("DisplayName", "")
        publisher = block.get("Publisher", "")
        name_ok = bool(name_patterns) and any_pattern(name, name_patterns)
        publisher_ok = not publisher_patterns or any_pattern(publisher, publisher_patterns)
        if name_ok and publisher_ok:
            return "confirmed", block, "registry_uninstall_key"
        if name_ok or (publisher_patterns and any_pattern(publisher, publisher_patterns)):
            partial = block
    if partial:
        return "partial", partial, "registry_uninstall_key"
    return "none", None, "none"


def is_local_target(target: str) -> bool:
    normalized = (target or "").strip().lower()
    return normalized in {"", "localhost", ".", "127.0.0.1"}


def target_from_raw_header(text: str) -> str | None:
    for line in text.splitlines()[:30]:
        match = re.match(r"^#\s*target=(.+)$", line.strip(), re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return None


def fallback_file_check(software: dict[str, Any], *, allow_local_fallback: bool) -> tuple[bool, str]:
    if not allow_local_fallback:
        return False, ""
    for item in software.get("fallback", {}).get("files", []):
        path = item.get("path", "")
        if path and Path(path).exists():
            return True, path
    return False, ""


def classify(default_target: str, software_id: str, software: dict[str, Any], raw_path: Path) -> EvidenceResult:
    try:
        text = raw_path.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:
        return EvidenceResult(
            target=default_target,
            software_id=software_id,
            status="verification_failed",
            evidence_strength="none",
            evidence_source=str(raw_path),
            detail=str(exc),
            revisit_recommendation="Verify raw evidence path and permissions.",
        )

    target = target_from_raw_header(text) or default_target
    allow_local_fallback = is_local_target(target)

    lower = text.lower()
    if "access is denied" in lower or "network path was not found" in lower or "unable to find" in lower:
        return EvidenceResult(
            target=target,
            software_id=software_id,
            status="environment_blocked",
            evidence_strength="none",
            evidence_source=str(raw_path),
            detail="Registry evidence collection was blocked by environment, access, network, or policy.",
            revisit_recommendation="Retry only from an authorized segment with approved access. Do not reclassify as product failure.",
        )

    blocks = parse_reg_blocks(text)
    match_state, block, strength = registry_match(blocks, software)
    if match_state == "confirmed" and block:
        return EvidenceResult(
            target=target,
            software_id=software_id,
            status="installed_registry_confirmed",
            evidence_strength=strength,
            evidence_source=block.get("__key", str(raw_path)),
            display_name=block.get("DisplayName", ""),
            display_version=block.get("DisplayVersion", ""),
            publisher=block.get("Publisher", ""),
            detail="Registry uninstall evidence matched catalog patterns.",
            revisit_recommendation="None.",
        )
    if match_state == "partial" and block:
        return EvidenceResult(
            target=target,
            software_id=software_id,
            status="installed_registry_partial",
            evidence_strength=strength,
            evidence_source=block.get("__key", str(raw_path)),
            display_name=block.get("DisplayName", ""),
            display_version=block.get("DisplayVersion", ""),
            publisher=block.get("Publisher", ""),
            detail="Registry evidence partially matched catalog patterns.",
            revisit_recommendation="Review catalog patterns or product naming.",
        )

    fallback_ok, fallback_path = fallback_file_check(software, allow_local_fallback=allow_local_fallback)
    if fallback_ok:
        return EvidenceResult(
            target=target,
            software_id=software_id,
            status="installed_fallback_confirmed",
            evidence_strength="fallback_file",
            evidence_source=fallback_path,
            detail="Registry proof missing; configured fallback file exists on the local operator machine.",
            revisit_recommendation="Treat as fallback evidence; confirm registry catalog if possible.",
        )

    return EvidenceResult(
        target=target,
        software_id=software_id,
        status="not_installed",
        evidence_strength="none",
        evidence_source=str(raw_path),
        detail="No registry or fallback evidence matched catalog.",
        revisit_recommendation="Install through approved deployment process, then re-run verification.",
    )


def write_csv(rows: list[EvidenceResult], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--software-id", required=True)
    parser.add_argument("--raw", required=True, nargs="+", help="Raw reg.exe evidence files")
    parser.add_argument("--output", required=True)
    parser.add_argument("--json", required=True)
    parser.add_argument("--target", default="localhost", help="Default target when raw header omits # target=")
    args = parser.parse_args()

    catalog = load_catalog(Path(args.catalog))
    software = find_software(catalog, args.software_id)
    rows = [
        classify(args.target, args.software_id, software, Path(raw))
        for raw in args.raw
    ]

    out_csv = Path(args.output)
    out_json = Path(args.json)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    write_csv(rows, out_csv)
    out_json.write_text(json.dumps([asdict(row) for row in rows], indent=2), encoding="utf-8")
    print(str(out_csv))
    print(str(out_json))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
