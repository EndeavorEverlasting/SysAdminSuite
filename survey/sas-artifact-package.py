#!/usr/bin/env python3
"""Create a local SysAdminSuite artifact delivery package."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import ipaddress
import re
import shutil
import sys
import zipfile
from pathlib import Path

WARNING_TEXT = "Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, IPs, MACs, serials, locations, or tracker data."


def read_text(path: Path, limit: int = 2_000_000) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")[:limit]
    except OSError:
        return ""


def doc_ip(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False
    return ip.version == 4 and any(ip in ipaddress.ip_network(net) for net in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24"))


def data_warnings(path: Path) -> list[str]:
    text = read_text(path)
    warnings: list[str] = []
    if re.search(r"\b[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}(?::|-)[0-9A-Fa-f]{2}\b", text):
        warnings.append(f"{path.name}: possible MAC address values found.")
    ips = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text)
    if any(not doc_ip(ip) for ip in ips):
        warnings.append(f"{path.name}: possible non-documentation IPv4 values found.")
    if re.search(r"\bW[A-Z]{2}\d{3}[A-Z]{2,4}\d{2,4}\b", text):
        warnings.append(f"{path.name}: possible operational hostname-like values found.")
    if re.search(r"\b(?:CN|SN|SERIAL)[A-Z0-9]{5,}\b", text, flags=re.I):
        warnings.append(f"{path.name}: possible serial-like values found.")
    return warnings


def looks_raw_nmap(path: Path) -> bool:
    name = path.name.lower()
    if "raw" in name or "nmap_output" in name or path.suffix.lower() in {".xml", ".gnmap", ".nmap", ".txt"}:
        return True
    text = read_text(path, 4096).lower()
    return "<nmaprun" in text or "nmap scan report for" in text


def row_count(path: Path) -> int:
    if not path.exists() or path.suffix.lower() != ".csv":
        return 0
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return sum(1 for _ in csv.DictReader(handle))


def write_index(package_dir: Path, copied: list[tuple[str, Path]], warnings: list[str], excluded: list[str]) -> None:
    lines = ["# Artifact Delivery Index", "", WARNING_TEXT, "", "## Files", ""]
    lines += [f"- `{path.name}` - {label}" for label, path in copied] or ["- No files copied."]
    lines += ["", "## Safety warnings", ""]
    lines += [f"- {item}" for item in warnings] or ["- No obvious operational data patterns detected by the local heuristic."]
    lines += ["", "## Excluded files", ""]
    lines += [f"- {item}" for item in excluded] or ["- None."]
    lines.append("")
    (package_dir / "ARTIFACT_INDEX.md").write_text("\n".join(lines), encoding="utf-8")


def write_handoff(package_dir: Path, copied_paths: dict[str, Path], warnings: list[str]) -> None:
    lines = [
        "# Handoff Summary",
        "",
        WARNING_TEXT,
        "",
        "## Row counts",
        "",
        f"- Workstation target manifest rows: {row_count(copied_paths.get('manifest', Path()))}",
        f"- Nmap workstation evidence rows: {row_count(copied_paths.get('nmap_evidence', Path()))}",
        f"- Cybernet workstation reconciliation rows: {row_count(copied_paths.get('reconciliation', Path()))}",
        f"- Review queue rows: {row_count(copied_paths.get('review_queue', Path()))}",
        "",
        "## Operator handoff",
        "",
        "- Treat review queue rows as operator questions, not automatic workbook edits.",
        "- Update workbooks manually after reviewing evidence.",
        "- Keep raw Nmap output out of the package unless explicitly needed.",
        "",
        "## Warnings",
        "",
    ]
    lines += [f"- {item}" for item in warnings] or ["- No obvious operational data patterns detected by the local heuristic."]
    lines.append("")
    (package_dir / "handoff_summary.md").write_text("\n".join(lines), encoding="utf-8")


def write_workbook_notes(package_dir: Path) -> None:
    lines = [
        "# Workbook Import Notes",
        "",
        WARNING_TEXT,
        "",
        "This package does not update tracker or workbook files automatically. Import is manual by design.",
        "",
        "1. Open `03_cybernet_workstation_reconciliation.csv` in Excel.",
        "2. Filter for strong confidence and no conflict flags.",
        "3. Open `04_review_queue.csv` next to the workbook.",
        "4. Resolve critical and high severity rows first.",
        "5. Paste only reviewed values into the working workbook.",
        "6. Preserve `SourceFile` and `SourceRow` where possible.",
        "7. Do not import raw Nmap output into the tracker.",
        "",
        "Do not use this package to mutate AD, DNS, registry, SCCM, Intune, endpoints, or workbook files.",
        "",
    ]
    (package_dir / "workbook_import_notes.md").write_text("\n".join(lines), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a local artifact delivery package.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--nmap-evidence", required=True)
    parser.add_argument("--reconciliation", required=True)
    parser.add_argument("--dashboard", required=True)
    parser.add_argument("--review-queue", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--include-raw", action="store_true")
    parser.add_argument("--zip", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", args.package_name).strip("_") or "artifact_delivery"
    package_dir = Path(args.output_dir) / f"{safe_name}_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}"
    package_dir.mkdir(parents=True, exist_ok=False)

    plan = [
        ("manifest", Path(args.manifest), package_dir / "01_workstation_target_manifest.csv", "Survey-ready workstation target manifest"),
        ("nmap_evidence", Path(args.nmap_evidence), package_dir / "02_nmap_workstation_evidence.csv", "Processed Nmap workstation evidence"),
        ("reconciliation", Path(args.reconciliation), package_dir / "03_cybernet_workstation_reconciliation.csv", "Workbook-ready reconciliation import"),
        ("review_queue", Path(args.review_queue), package_dir / "04_review_queue.csv", "Operator review queue"),
        ("dashboard", Path(args.dashboard), package_dir / "05_dashboard.html", "HTML dashboard"),
    ]
    copied: list[tuple[str, Path]] = []
    copied_paths: dict[str, Path] = {}
    warnings: list[str] = []
    excluded: list[str] = []

    for key, src, dest, label in plan:
        if key == "nmap_evidence" and looks_raw_nmap(src) and not args.include_raw:
            excluded.append(f"{src} looked like raw Nmap output and was excluded. Pass --include-raw to include it.")
            continue
        if not src.exists():
            warnings.append(f"Missing input: {src}")
            continue
        shutil.copy2(src, dest)
        copied.append((label, dest))
        copied_paths[key] = dest
        warnings.extend(data_warnings(dest))

    write_index(package_dir, copied, warnings, excluded)
    write_handoff(package_dir, copied_paths, warnings)
    write_workbook_notes(package_dir)

    if args.zip:
        zip_path = package_dir.with_suffix(".zip")
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in package_dir.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(package_dir.parent))
        print(f"ZIP created: {zip_path}")
    print(f"Package created: {package_dir}")
    for item in warnings + excluded:
        print(f"- {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
