#!/usr/bin/env python3
"""
Create a local SysAdminSuite artifact delivery package.

Read-only behavior: source files are copied into a new delivery folder. Inputs are
never edited, and raw Nmap output is excluded unless explicitly requested.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import ipaddress
import re
import shutil
import sys
import zipfile
from pathlib import Path


WARNING_TEXT = "Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, IPs, MACs, serials, locations, or tracker data."


def read_text_safe(path: Path, limit: int = 2_000_000) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            return handle.read(limit)
    except OSError:
        return ""


def is_documentation_ip(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False

    if ip.version != 4:
        return False

    return (
        ip in ipaddress.ip_network("192.0.2.0/24")
        or ip in ipaddress.ip_network("198.51.100.0/24")
        or ip in ipaddress.ip_network("203.0.113.0/24")
    )


def data_warnings(path: Path) -> list[str]:
    text = read_text_safe(path)
    warnings: list[str] = []
    if not text:
        return warnings

    mac_hits = re.findall(r"\b[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}\b", text)
    if mac_hits:
        warnings.append(f"{path.name}: possible MAC address values found.")

    ip_hits = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text)
    realish_ips = [ip for ip in ip_hits if not is_documentation_ip(ip)]
    if realish_ips:
        warnings.append(f"{path.name}: possible non-documentation IPv4 values found.")

    hostname_hits = re.findall(r"\b(?:W[A-Z]{2}\d{3}[A-Z]{2,4}\d{2,4}|[A-Z]{2,8}-[A-Z0-9]{2,20}-\d{2,6})\b", text)
    if hostname_hits:
        warnings.append(f"{path.name}: possible operational hostname-like values found.")

    serial_hits = re.findall(r"\b(?:CYB|CN|SN|SERIAL)[A-Z0-9]{5,}\b", text, flags=re.IGNORECASE)
    serial_hits = [hit for hit in serial_hits if "FAKE" not in hit.upper() and "SAMPLE" not in hit.upper()]
    if serial_hits:
        warnings.append(f"{path.name}: possible serial-like values found.")

    return warnings


def looks_like_raw_nmap(path: Path) -> bool:
    name = path.name.lower()
    suffix = path.suffix.lower()
    if "raw" in name or "nmap_output" in name or "nmap-output" in name:
        return True
    if suffix in {".xml", ".gnmap", ".nmap", ".txt"}:
        return True
    text = read_text_safe(path, limit=4096).lower()
    return "<nmaprun" in text or "nmap scan report for" in text


def row_count(path: Path) -> int:
    if not path.exists() or path.suffix.lower() != ".csv":
        return 0
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return max(sum(1 for _ in csv.DictReader(handle)), 0)


def raw_nmap_destination(package_dir: Path, src: Path) -> Path:
    suffix = src.suffix if src.suffix else ".txt"
    safe_suffix = re.sub(r"[^A-Za-z0-9.]", "", suffix) or ".txt"
    return package_dir / f"02_nmap_workstation_evidence_raw{safe_suffix}"


def copy_present(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def write_index(package_dir: Path, copied: list[tuple[str, Path]], warnings: list[str], excluded: list[str]) -> None:
    lines = [
        "# Artifact Delivery Index",
        "",
        WARNING_TEXT,
        "",
        "## Files",
        "",
    ]

    if copied:
        for label, path in copied:
            lines.append(f"- `{path.name}` - {label}")
    else:
        lines.append("- No files copied.")

    lines.extend(["", "## Safety warnings", ""])
    if warnings:
        for item in warnings:
            lines.append(f"- {item}")
    else:
        lines.append("- No obvious operational data patterns detected by the local heuristic.")

    lines.extend(["", "## Excluded files", ""])
    if excluded:
        for item in excluded:
            lines.append(f"- {item}")
    else:
        lines.append("- None.")

    lines.append("")
    (package_dir / "ARTIFACT_INDEX.md").write_text("\n".join(lines), encoding="utf-8")


def write_handoff(package_dir: Path, copied_paths: dict[str, Path], warnings: list[str]) -> None:
    manifest_rows = row_count(copied_paths.get("manifest", Path()))
    evidence_rows = row_count(copied_paths.get("nmap_evidence", Path()))
    reconciliation_rows = row_count(copied_paths.get("reconciliation", Path()))
    review_rows = row_count(copied_paths.get("review_queue", Path()))

    lines = [
        "# Handoff Summary",
        "",
        WARNING_TEXT,
        "",
        "## Row counts",
        "",
        f"- Workstation target manifest rows: {manifest_rows}",
        f"- Nmap workstation evidence rows: {evidence_rows}",
        f"- Cybernet workstation reconciliation rows: {reconciliation_rows}",
        f"- Review queue rows: {review_rows}",
        "",
        "## Operator handoff",
        "",
        "- Validate that all included CSVs are fake/sample-safe before committing anything upstream.",
        "- Treat review queue rows as questions for the operator, not automatic workbook edits.",
        "- Update the workbook manually after reviewing evidence.",
        "- Keep raw Nmap output outside the delivery package unless explicitly needed.",
        "",
        "## Warnings",
        "",
    ]

    if warnings:
        lines.extend(f"- {warning}" for warning in warnings)
    else:
        lines.append("- No obvious operational data patterns detected by the local heuristic.")

    lines.append("")
    (package_dir / "handoff_summary.md").write_text("\n".join(lines), encoding="utf-8")


def write_workbook_notes(package_dir: Path) -> None:
    lines = [
        "# Workbook Import Notes",
        "",
        WARNING_TEXT,
        "",
        "## Manual import posture",
        "",
        "This package does not update tracker or workbook files automatically. Import is manual by design.",
        "",
        "## Suggested sequence",
        "",
        "1. Open `03_cybernet_workstation_reconciliation.csv` in Excel.",
        "2. Filter for rows with strong confidence and no conflict flags.",
        "3. Open `04_review_queue.csv` next to the workbook.",
        "4. Resolve critical and high-severity rows before updating workbook values.",
        "5. Paste only reviewed columns into the working workbook.",
        "6. Preserve `SourceFile` and `SourceRow` when importing notes or exceptions.",
        "7. Do not import raw Nmap output into the tracker.",
        "",
        "## Columns to protect",
        "",
        "- Hostname",
        "- IPAddress",
        "- MACAddress",
        "- SerialNumber",
        "- Location",
        "- Room",
        "- Workstation",
        "- AssociatedNeuron",
        "",
        "## Do not automate",
        "",
        "- Do not auto-update workbook files.",
        "- Do not use this package to mutate AD, DNS, registry, SCCM, Intune, or endpoints.",
        "- Do not treat operator-provided files as final truth without review.",
        "",
    ]
    (package_dir / "workbook_import_notes.md").write_text("\n".join(lines), encoding="utf-8")


def make_zip(package_dir: Path) -> Path:
    zip_path = package_dir.with_suffix(".zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in package_dir.rglob("*"):
            if path.is_file():
                archive.write(path, path.relative_to(package_dir.parent))
    return zip_path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a local artifact delivery package.")
    parser.add_argument("--manifest", required=True, help="Workstation target manifest CSV.")
    parser.add_argument("--nmap-evidence", required=True, help="Processed Nmap evidence CSV, not raw output unless --include-raw is passed.")
    parser.add_argument("--reconciliation", required=True, help="Cybernet workstation reconciliation CSV.")
    parser.add_argument("--dashboard", required=True, help="Dashboard HTML.")
    parser.add_argument("--review-queue", required=True, help="Review queue CSV.")
    parser.add_argument("--output-dir", required=True, help="Delivery output directory.")
    parser.add_argument("--package-name", required=True, help="Base package folder name.")
    parser.add_argument("--include-raw", action="store_true", help="Allow raw Nmap output into the package.")
    parser.add_argument("--zip", action="store_true", help="Also create a ZIP archive of the package folder.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    inputs = {
        "manifest": Path(args.manifest),
        "nmap_evidence": Path(args.nmap_evidence),
        "reconciliation": Path(args.reconciliation),
        "review_queue": Path(args.review_queue),
        "dashboard": Path(args.dashboard),
    }
    missing = [path.name for path in inputs.values() if not path.exists()]
    if missing:
        for name in missing:
            print(f"Missing required input: {name}", file=sys.stderr)
        return 1

    timestamp = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", args.package_name).strip("_") or "artifact_delivery"
    output_dir = Path(args.output_dir)
    package_dir = output_dir / f"{safe_name}_{timestamp}"
    package_dir.mkdir(parents=True, exist_ok=False)

    nmap_src = inputs["nmap_evidence"]
    nmap_is_raw = looks_like_raw_nmap(nmap_src)
    nmap_dest = raw_nmap_destination(package_dir, nmap_src) if nmap_is_raw and args.include_raw else package_dir / "02_nmap_workstation_evidence.csv"
    nmap_label = "Raw Nmap workstation evidence" if nmap_is_raw and args.include_raw else "Processed Nmap workstation evidence"

    file_plan = [
        ("manifest", inputs["manifest"], package_dir / "01_workstation_target_manifest.csv", "Survey-ready workstation target manifest"),
        ("nmap_evidence", nmap_src, nmap_dest, nmap_label),
        ("reconciliation", inputs["reconciliation"], package_dir / "03_cybernet_workstation_reconciliation.csv", "Workbook-ready reconciliation import"),
        ("review_queue", inputs["review_queue"], package_dir / "04_review_queue.csv", "Operator review queue"),
        ("dashboard", inputs["dashboard"], package_dir / "05_dashboard.html", "HTML dashboard"),
    ]

    copied: list[tuple[str, Path]] = []
    copied_paths: dict[str, Path] = {}
    warnings: list[str] = []
    excluded: list[str] = []

    for key, src, dest, label in file_plan:
        if key == "nmap_evidence" and nmap_is_raw and not args.include_raw:
            excluded.append(f"{src.name} looked like raw Nmap output and was excluded. Pass --include-raw to include it.")
            continue

        copy_present(src, dest)
        copied.append((label, dest))
        copied_paths[key] = dest
        warnings.extend(data_warnings(dest))

    write_index(package_dir, copied, warnings, excluded)
    write_handoff(package_dir, copied_paths, warnings)
    write_workbook_notes(package_dir)

    if args.zip:
        zip_path = make_zip(package_dir)
        print(f"Package created: {package_dir}")
        print(f"ZIP created: {zip_path}")
    else:
        print(f"Package created: {package_dir}")

    if warnings or excluded:
        print("Warnings:")
        for item in warnings + excluded:
            print(f"- {item}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
