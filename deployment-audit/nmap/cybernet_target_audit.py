#!/usr/bin/env python3
"""
Cybernet / Neuron target audit for Nmap workflows.

This script does not use PowerShell. It reads the deployment workbook as the
source of truth, creates a unique Nmap target list, detects duplicate identity
records by MAC/serial, and optionally matches Nmap XML results back to inventory.

No third-party Python packages are required.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple
import xml.etree.ElementTree as ET

TARGET_COLUMNS = ["Neuron IP", "Neuron Hostname", "Cybernet Hostname"]
MAC_COLUMNS = ["Neuron MAC", "Cybernet MAC"]
SERIAL_COLUMNS = [
    "Cybernet Serial",
    "Neuron S/N",
    "Anesthesia S/N",
    "Medical Device S/N",
    "Dialysis S/N",
]
CONTEXT_COLUMNS = [
    "Device Type",
    "Current Building",
    "Install Building",
    "Area/Unit/Dept",
    "Room",
    "Bay",
    "Asset Tag",
    "Medical Device Manufacturer",
    "Medical Device Model",
    "IT Device Status",
    "Ready for Deployment",
    "Readiness (Auto)",
]
EMPTY = {"", "N/A", "NA", "NONE", "NULL", "-", "--", "TBD", "UNKNOWN"}
MAC_RE = re.compile(r"(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}|[0-9a-f]{12}")
TARGET_RE = re.compile(r"^[A-Za-z0-9_.:-]+$")


def clean(value: object) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if text.upper() in EMPTY:
        return ""
    return text


def normalize_mac(value: str) -> str:
    value = clean(value)
    if not value:
        return ""
    match = MAC_RE.search(value)
    if not match:
        return ""
    raw = re.sub(r"[^0-9A-Fa-f]", "", match.group(0)).upper()
    if len(raw) != 12:
        return ""
    return ":".join(raw[i:i + 2] for i in range(0, 12, 2))


def normalize_serial(value: str) -> str:
    value = clean(value)
    if not value:
        return ""
    value = re.sub(r"\s+", "", value).upper()
    value = value.strip(";:,|/")
    if value.upper() in EMPTY or len(value) < 3:
        return ""
    return value


def is_target(value: str) -> bool:
    value = clean(value)
    if not value:
        return False

    # Nmap treats slash as CIDR/netmask syntax. Values like
    # AKBARANATOR/WMH300OPR378 are workbook notes or combined labels, not a
    # single scannable hostname, so keep them out of targets.txt.
    if any(ch in value for ch in " ;,|/\\\"'<>[]{}()"):
        return False

    # Avoid malformed hostnames that Nmap will reject or misinterpret.
    if value.startswith(("-", ".", ":")) or value.endswith(("-", ".", ":")):
        return False

    return bool(TARGET_RE.fullmatch(value))


def col_letter_to_index(ref: str) -> int:
    letters = re.sub(r"[^A-Z]", "", ref.upper())
    total = 0
    for ch in letters:
        total = total * 26 + ord(ch) - ord("A") + 1
    return total - 1


def read_shared_strings(zf: zipfile.ZipFile) -> List[str]:
    try:
        data = zf.read("xl/sharedStrings.xml")
    except KeyError:
        return []
    root = ET.fromstring(data)
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    strings: List[str] = []
    for si in root.findall("x:si", ns):
        parts = [t.text or "" for t in si.findall(".//x:t", ns)]
        strings.append("".join(parts))
    return strings


def get_sheet_path(zf: zipfile.ZipFile, requested: str) -> str:
    wb = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    ns = {
        "x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
        "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
    }
    rel_map = {rel.attrib["Id"]: rel.attrib["Target"] for rel in rels.findall("rel:Relationship", ns)}
    sheets = wb.findall("x:sheets/x:sheet", ns)
    chosen = None
    for sheet in sheets:
        if sheet.attrib.get("name", "").strip().lower() == requested.lower():
            chosen = sheet
            break
    if chosen is None:
        if not sheets:
            raise ValueError("Workbook has no worksheets")
        chosen = sheets[0]
    rid = chosen.attrib[f"{{{ns['r']}}}id"]
    target = rel_map[rid]
    if target.startswith("/"):
        return target.lstrip("/")
    if target.startswith("xl/"):
        return target
    return "xl/" + target


def read_xlsx_rows(path: Path, sheet_name: str) -> List[Dict[str, str]]:
    with zipfile.ZipFile(path) as zf:
        shared = read_shared_strings(zf)
        sheet_path = get_sheet_path(zf, sheet_name)
        root = ET.fromstring(zf.read(sheet_path))
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    rows: List[List[str]] = []
    for row in root.findall(".//x:sheetData/x:row", ns):
        cells: Dict[int, str] = {}
        for c in row.findall("x:c", ns):
            ref = c.attrib.get("r", "A1")
            idx = col_letter_to_index(ref)
            cell_type = c.attrib.get("t", "")
            value = ""
            if cell_type == "inlineStr":
                value = "".join(t.text or "" for t in c.findall(".//x:t", ns))
            else:
                v = c.find("x:v", ns)
                if v is not None and v.text is not None:
                    if cell_type == "s":
                        try:
                            value = shared[int(v.text)]
                        except Exception:
                            value = v.text
                    else:
                        value = v.text
            cells[idx] = clean(value)
        if cells:
            max_idx = max(cells)
            rows.append([cells.get(i, "") for i in range(max_idx + 1)])
    if not rows:
        return []
    headers = [clean(h) for h in rows[0]]
    output: List[Dict[str, str]] = []
    for values in rows[1:]:
        record = {headers[i]: values[i] if i < len(values) else "" for i in range(len(headers)) if headers[i]}
        if any(clean(v) for v in record.values()):
            output.append(record)
    return output


def build_inventory(rows: Sequence[Dict[str, str]]) -> List[Dict[str, str]]:
    inventory: List[Dict[str, str]] = []
    for i, row in enumerate(rows, start=2):
        rec: Dict[str, str] = {"source_row": str(i)}
        for col in TARGET_COLUMNS + MAC_COLUMNS + SERIAL_COLUMNS + CONTEXT_COLUMNS:
            rec[col] = clean(row.get(col, ""))
        rec["normalized_macs"] = ";".join(sorted({normalize_mac(rec[c]) for c in MAC_COLUMNS if normalize_mac(rec[c])}))
        rec["normalized_serials"] = ";".join(sorted({normalize_serial(rec[c]) for c in SERIAL_COLUMNS if normalize_serial(rec[c])}))
        inventory.append(rec)
    return inventory


def build_targets(inventory: Sequence[Dict[str, str]]) -> List[Dict[str, str]]:
    seen: Dict[str, Dict[str, str]] = {}
    for rec in inventory:
        for col in TARGET_COLUMNS:
            value = clean(rec.get(col, ""))
            if not is_target(value):
                continue
            key = value.lower()
            if key not in seen:
                seen[key] = {
                    "target": value,
                    "source_column": col,
                    "first_source_row": rec["source_row"],
                    "source_rows": rec["source_row"],
                }
            else:
                rows = set(seen[key]["source_rows"].split(";"))
                rows.add(rec["source_row"])
                seen[key]["source_rows"] = ";".join(sorted(rows, key=lambda x: int(x)))
    return sorted(seen.values(), key=lambda r: r["target"].lower())


def duplicate_rows(inventory: Sequence[Dict[str, str]], columns: Sequence[str], kind: str) -> List[Dict[str, str]]:
    index: Dict[str, List[Tuple[Dict[str, str], str]]] = defaultdict(list)
    for rec in inventory:
        row_values = set()
        for col in columns:
            value = normalize_mac(rec.get(col, "")) if kind == "mac" else normalize_serial(rec.get(col, ""))
            if value:
                row_values.add((value, col))
        for value, col in row_values:
            index[value].append((rec, col))
    out: List[Dict[str, str]] = []
    for value, hits in sorted(index.items()):
        unique_rows = {h[0]["source_row"] for h in hits}
        if len(unique_rows) < 2:
            continue
        for rec, col in hits:
            base = {
                "duplicate_type": kind,
                "duplicate_value": value,
                "source_column": col,
                "source_row": rec["source_row"],
            }
            for ctx in CONTEXT_COLUMNS + TARGET_COLUMNS + MAC_COLUMNS + SERIAL_COLUMNS:
                base[ctx] = rec.get(ctx, "")
            out.append(base)
    return out


def write_csv(path: Path, rows: Sequence[Dict[str, str]], fields: Optional[Sequence[str]] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fields is None:
        fields = sorted({k for row in rows for k in row}) if rows else []
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(fields), extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def parse_nmap_xml(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    root = ET.parse(path).getroot()
    hosts: List[Dict[str, str]] = []
    for host in root.findall("host"):
        status = host.find("status")
        addresses = host.findall("address")
        hostnames = host.findall("hostnames/hostname")
        rec = {
            "nmap_status": status.attrib.get("state", "") if status is not None else "",
            "nmap_reason": status.attrib.get("reason", "") if status is not None else "",
            "nmap_ipv4": "",
            "nmap_mac": "",
            "nmap_vendor": "",
            "nmap_hostname": "",
        }
        for addr in addresses:
            if addr.attrib.get("addrtype") == "ipv4":
                rec["nmap_ipv4"] = addr.attrib.get("addr", "")
            elif addr.attrib.get("addrtype") == "mac":
                rec["nmap_mac"] = normalize_mac(addr.attrib.get("addr", ""))
                rec["nmap_vendor"] = addr.attrib.get("vendor", "")
        if hostnames:
            rec["nmap_hostname"] = hostnames[0].attrib.get("name", "")
        hosts.append(rec)
    return hosts


def match_nmap(hosts: Sequence[Dict[str, str]], inventory: Sequence[Dict[str, str]]) -> List[Dict[str, str]]:
    by_mac: Dict[str, List[Dict[str, str]]] = defaultdict(list)
    by_target: Dict[str, List[Dict[str, str]]] = defaultdict(list)
    for rec in inventory:
        for mac in filter(None, rec.get("normalized_macs", "").split(";")):
            by_mac[mac].append(rec)
        for col in TARGET_COLUMNS:
            target = clean(rec.get(col, "")).lower()
            if target:
                by_target[target].append(rec)
    matches: List[Dict[str, str]] = []
    for host in hosts:
        candidates: List[Tuple[str, Dict[str, str]]] = []
        if host.get("nmap_mac"):
            candidates += [("mac", r) for r in by_mac.get(host["nmap_mac"], [])]
        for key in [host.get("nmap_ipv4", "").lower(), host.get("nmap_hostname", "").lower()]:
            if key:
                candidates += [("target", r) for r in by_target.get(key, [])]
        seen = set()
        if not candidates:
            matches.append({**host, "match_type": "unmatched", "source_row": ""})
            continue
        for match_type, rec in candidates:
            if rec["source_row"] in seen:
                continue
            seen.add(rec["source_row"])
            row = {**host, "match_type": match_type, "source_row": rec["source_row"]}
            for col in TARGET_COLUMNS + MAC_COLUMNS + SERIAL_COLUMNS + CONTEXT_COLUMNS:
                row[col] = rec.get(col, "")
            matches.append(row)
    return matches


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Build Nmap targets and duplicate identity reports from a Cybernet workbook.")
    parser.add_argument("--source-xlsx", required=True, help="Path to the source deployment workbook")
    parser.add_argument("--sheet", default="Deployments", help="Worksheet name, default: Deployments")
    parser.add_argument("--out-dir", required=True, help="Output folder")
    parser.add_argument("--nmap-xml", default="", help="Optional Nmap XML file to match back to inventory")
    parser.add_argument("--fail-on-duplicates", action="store_true", help="Exit 1 if duplicate MAC or serial values are found")
    args = parser.parse_args(argv)

    source = Path(args.source_xlsx)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = read_xlsx_rows(source, args.sheet)
    inventory = build_inventory(rows)
    targets = build_targets(inventory)
    dup_macs = duplicate_rows(inventory, MAC_COLUMNS, "mac")
    dup_serials = duplicate_rows(inventory, SERIAL_COLUMNS, "serial")

    fields = ["source_row"] + TARGET_COLUMNS + MAC_COLUMNS + SERIAL_COLUMNS + CONTEXT_COLUMNS + ["normalized_macs", "normalized_serials"]
    write_csv(out_dir / "unique_targets.csv", inventory, fields)
    write_csv(out_dir / "duplicate_macs.csv", dup_macs)
    write_csv(out_dir / "duplicate_serials.csv", dup_serials)
    write_csv(out_dir / "nmap_targets.csv", targets, ["target", "source_column", "first_source_row", "source_rows"])

    with (out_dir / "targets.txt").open("w", encoding="utf-8") as f:
        for target in targets:
            f.write(target["target"] + "\n")

    matches: List[Dict[str, str]] = []
    if args.nmap_xml:
        matches = match_nmap(parse_nmap_xml(Path(args.nmap_xml)), inventory)
        write_csv(out_dir / "nmap_probe_matches.csv", matches)

    summary = {
        "source": str(source),
        "sheet": args.sheet,
        "inventory_rows": len(inventory),
        "unique_nmap_targets": len(targets),
        "duplicate_mac_rows": len(dup_macs),
        "duplicate_serial_rows": len(dup_serials),
        "nmap_matches": len(matches),
        "outputs": {
            "targets_txt": str(out_dir / "targets.txt"),
            "unique_targets_csv": str(out_dir / "unique_targets.csv"),
            "duplicate_macs_csv": str(out_dir / "duplicate_macs.csv"),
            "duplicate_serials_csv": str(out_dir / "duplicate_serials.csv"),
            "nmap_probe_matches_csv": str(out_dir / "nmap_probe_matches.csv"),
        },
    }
    (out_dir / "audit_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))
    if args.fail_on_duplicates and (dup_macs or dup_serials):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
