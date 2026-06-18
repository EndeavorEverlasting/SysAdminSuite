#!/usr/bin/env python3
"""
Extract workstation source rows from CSV exports of messy operator artifacts.

This is intentionally CSV-first. Export a workbook tab, paste an OpenAI Chat
extraction, or save screenshot/PDF extraction output as CSV, then run this
script to reshape it into workstation_source_template.csv columns.

Read-only behavior: reads the input CSV and writes a new output CSV. It never
edits the source artifact, workbook, endpoint, AD, DNS, registry, or tracker.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


WORKSTATION_HEADERS = [
    "SourceFile",
    "SourceRow",
    "SiteCode",
    "SiteName",
    "Location",
    "Room",
    "Workstation",
    "Hostname",
    "IPAddress",
    "MACAddress",
    "SerialNumber",
    "DeviceType",
    "AssociatedNeuron",
    "Notes",
]

PROFILE_ALIASES = {
    "deployment-tracker": {
        "SiteCode": ["Current Building", "Install Building", "Site", "SiteCode"],
        "SiteName": ["Install Building", "Current Building", "SiteName"],
        "Location": ["Area/Unit/Dept", "Location", "Department"],
        "Room": ["Room", "OR", "Bay"],
        "Workstation": ["Cybernet Hostname", "PC Name", "Hostname", "Workstation"],
        "Hostname": ["Cybernet Hostname", "PC Name", "Hostname", "ComputerName"],
        "IPAddress": ["Cybernet IP", "PC IP", "IPAddress", "IP Address", "IP"],
        "MACAddress": ["Cybernet MAC", "PC MAC", "MACAddress", "MAC Address", "MAC"],
        "SerialNumber": ["Cybernet Serial", "PC / Cybernet Serial No", "SerialNumber", "Serial Number", "Serial"],
        "DeviceType": ["Device Type", "DeviceType"],
        "AssociatedNeuron": ["Neuron Hostname", "Neuron Name", "AssociatedNeuron"],
    },
    "all-wave-neuron-cybernet": {
        "SiteCode": ["Site", "SiteCode"],
        "SiteName": ["Site", "SiteName"],
        "Location": ["Location", "Design Blue Print/Deployment Note"],
        "Room": ["Room", "Location"],
        "Workstation": ["PC Name", "Cybernet Hostname", "Hostname", "Workstation"],
        "Hostname": ["PC Name", "Cybernet Hostname", "Hostname", "ComputerName"],
        "IPAddress": ["PC IP", "Cybernet IP", "IPAddress", "IP Address", "IP"],
        "MACAddress": ["Cybernet MAC", "PC MAC", "MACAddress", "MAC Address", "MAC"],
        "SerialNumber": ["PC / Cybernet Serial No", "Cybernet Serial", "SerialNumber", "Serial Number", "Serial"],
        "DeviceType": ["Device Type", "DeviceType"],
        "AssociatedNeuron": ["Neuron Name", "Neuron Hostname", "AssociatedNeuron"],
    },
    "ticket-tracker": {
        "SiteCode": ["Location", "SiteCode"],
        "SiteName": ["Location", "SiteName"],
        "Location": ["Location", "Department"],
        "Room": ["Department", "Room"],
        "Workstation": ["Hostname Used", "Hostname", "ComputerName"],
        "Hostname": ["Hostname Used", "Hostname", "ComputerName"],
        "IPAddress": ["IPAddress", "IP Address", "IP"],
        "MACAddress": ["MACAddress", "MAC Address", "MAC"],
        "SerialNumber": ["SerialNumber", "Serial Number", "Serial"],
        "DeviceType": ["Ticket Type", "Device Type", "DeviceType"],
        "AssociatedNeuron": ["AssociatedNeuron", "Neuron Hostname", "Neuron Name"],
    },
    "generic-workstation": {
        "SiteCode": ["SiteCode", "Site", "Current Building", "Install Building"],
        "SiteName": ["SiteName", "Site", "Install Building", "Current Building"],
        "Location": ["Location", "Area/Unit/Dept", "Department"],
        "Room": ["Room", "OR", "Bay"],
        "Workstation": ["Workstation", "Cybernet Hostname", "PC Name", "Hostname", "ComputerName", "Computer"],
        "Hostname": ["Hostname", "HostName", "Cybernet Hostname", "PC Name", "ComputerName", "Computer"],
        "IPAddress": ["IPAddress", "IP Address", "IP", "Cybernet IP", "PC IP"],
        "MACAddress": ["MACAddress", "MAC Address", "MAC", "Cybernet MAC", "PC MAC"],
        "SerialNumber": ["SerialNumber", "Serial Number", "Serial", "Cybernet Serial", "PC / Cybernet Serial No"],
        "DeviceType": ["DeviceType", "Device Type", "Ticket Type"],
        "AssociatedNeuron": ["AssociatedNeuron", "Neuron Hostname", "Neuron Name"],
    },
}

NOTE_FIELDS = {
    "deployment-tracker": ["Epic TDR", "PI_Result", "PI_Rejection_Reason", "Notes", "Comments"],
    "all-wave-neuron-cybernet": ["TDR", "TDR Note", "Comments", "Design Blue Print/Deployment Note"],
    "ticket-tracker": ["REQ #", "Ticket State", "Host to Copy", "Notes", "Linked Tickets"],
    "generic-workstation": ["Notes", "Comments", "Finding", "Status"],
}


def clean(value: object) -> str:
    return "" if value is None else str(value).strip()


def keymap(row: dict[str, str]) -> dict[str, str]:
    return {clean(key).lower(): key for key in row.keys() if clean(key)}


def get(row: dict[str, str], aliases: list[str]) -> str:
    keys = keymap(row)
    for alias in aliases:
        if alias in row:
            return clean(row.get(alias))
        matched = keys.get(alias.lower())
        if matched:
            return clean(row.get(matched))
    return ""


def normalize_hostname(value: str) -> str:
    return clean(value).upper()


def normalize_serial(value: str) -> str:
    return re.sub(r"\s+", "", clean(value)).upper()


def normalize_mac(value: str) -> str:
    raw = clean(value)
    compact = re.sub(r"[^0-9A-Fa-f]", "", raw)
    if len(compact) == 12 and re.fullmatch(r"[0-9A-Fa-f]{12}", compact):
        compact = compact.upper()
        return ":".join(compact[i : i + 2] for i in range(0, 12, 2))
    return raw.upper()


def split_cell_values(value: str) -> list[str]:
    raw = clean(value)
    if not raw:
        return [""]
    pieces = [piece.strip() for piece in re.split(r"[\r\n;,]+", raw) if piece.strip()]
    return pieces or [raw]


def looks_like_header_noise(row: dict[str, str]) -> bool:
    values = [clean(value) for value in row.values() if clean(value)]
    if not values:
        return True
    joined = " ".join(values).lower()
    if "wave" in joined and "total" in joined and len(values) <= 6:
        return True
    if joined in {"null", "none"}:
        return True
    return False


def note_text(row: dict[str, str], profile: str) -> str:
    parts = []
    for field in NOTE_FIELDS.get(profile, NOTE_FIELDS["generic-workstation"]):
        value = get(row, [field])
        if value:
            parts.append(f"{field}: {value}")
    return " | ".join(parts)


def extract_rows(rows: list[dict[str, str]], input_path: Path, profile: str, source_file: str | None) -> list[dict[str, str]]:
    aliases = PROFILE_ALIASES[profile]
    output: list[dict[str, str]] = []

    for physical_row, row in enumerate(rows, start=2):
        if looks_like_header_noise(row):
            continue

        base = {header: "" for header in WORKSTATION_HEADERS}
        base["SourceFile"] = source_file or input_path.name
        base["SourceRow"] = clean(row.get("SourceRow")) or str(physical_row)

        for field, field_aliases in aliases.items():
            base[field] = get(row, field_aliases)

        base["Notes"] = note_text(row, profile)

        host_values = split_cell_values(base["Hostname"])
        for host in host_values:
            out = dict(base)
            if host:
                out["Hostname"] = normalize_hostname(host)
                if not out["Workstation"] or "\n" in out["Workstation"] or ";" in out["Workstation"] or "," in out["Workstation"]:
                    out["Workstation"] = out["Hostname"]
            else:
                out["Hostname"] = ""

            out["MACAddress"] = normalize_mac(out["MACAddress"])
            out["SerialNumber"] = normalize_serial(out["SerialNumber"])
            output.append(out)

    return output


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=WORKSTATION_HEADERS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract workstation source rows from exported source artifact CSVs.")
    parser.add_argument("--input", required=True, help="CSV export or extracted source artifact CSV.")
    parser.add_argument("--profile", required=True, choices=sorted(PROFILE_ALIASES), help="Source artifact shape to map.")
    parser.add_argument("--output", required=True, help="workstation_source_template-shaped CSV output path.")
    parser.add_argument("--source-file", help="Original source evidence name to preserve in SourceFile.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    input_path = Path(args.input)
    rows = read_csv(input_path)
    output_rows = extract_rows(rows, input_path, args.profile, args.source_file)
    write_csv(Path(args.output), output_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
