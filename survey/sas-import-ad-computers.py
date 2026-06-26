#!/usr/bin/env python3
"""Normalize exported Active Directory computer inventory for SysAdminSuite.

This tool is read-only. It expects a CSV export created by an authorized admin,
for example:

Get-ADComputer -Filter * -Properties DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description |
  Select Name,DNSHostName,OperatingSystem,LastLogonDate,Enabled,Description,DistinguishedName |
  Export-Csv .\\ad_computers.csv -NoTypeInformation

It does not query AD directly or mutate any objects.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Iterable

FIELDS = [
    "HostName",
    "DNSHostName",
    "ADStatus",
    "Enabled",
    "OperatingSystem",
    "LastLogonDate",
    "Description",
    "DistinguishedName",
    "SourceFile",
    "PopulationAuthority",
    "ReconcileBucket",
]


def clean(value: object) -> str:
    return str(value or "").strip()


def norm_host(value: object) -> str:
    value = clean(value).upper()
    return value.split(".", 1)[0] if value else ""


def first(row: dict[str, str], names: Iterable[str]) -> str:
    lowered = {str(k).lower(): clean(v) for k, v in row.items()}
    for name in names:
        value = lowered.get(name.lower())
        if value:
            return value
    return ""


def status_from_enabled(enabled: str) -> str:
    value = clean(enabled).lower()
    if value in {"false", "0", "no", "disabled"}:
        return "AD_DISABLED"
    if value in {"true", "1", "yes", "enabled"}:
        return "AD_REGISTERED"
    return "AD_REGISTERED"


def normalize_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    out: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()

    for row in rows:
        dns_host = first(row, ["DNSHostName", "DNS Host Name", "FQDN"])
        host = first(row, ["Name", "HostName", "Hostname", "ComputerName", "Computer", "CN"])
        if not host and dns_host:
            host = dns_host

        host_norm = norm_host(host)
        dns_host = clean(dns_host)
        enabled = first(row, ["Enabled", "AccountEnabled", "ADEnabled"])
        ad_status = status_from_enabled(enabled)
        key = (host_norm, dns_host.upper())
        if not host_norm or key in seen:
            continue
        seen.add(key)

        out.append(
            {
                "HostName": host_norm,
                "DNSHostName": dns_host,
                "ADStatus": ad_status,
                "Enabled": enabled,
                "OperatingSystem": first(row, ["OperatingSystem", "OS", "Operating System"]),
                "LastLogonDate": first(row, ["LastLogonDate", "LastLogonTimestamp", "LastLogon", "Last Seen", "LastSeen"]),
                "Description": first(row, ["Description", "Comment", "Notes"]),
                "DistinguishedName": first(row, ["DistinguishedName", "DN", "CanonicalName"]),
                "SourceFile": str(path),
                "PopulationAuthority": "ad_registered",
                "ReconcileBucket": "disabled" if ad_status == "AD_DISABLED" else "registered",
            }
        )

    return out


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize exported AD computer CSV inventory for SysAdminSuite")
    parser.add_argument("--input", required=True, help="AD computer CSV export")
    parser.add_argument("--output", default="survey/output/ad_computers_normalized.csv", help="Normalized AD evidence CSV")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input not found: {input_path}", file=sys.stderr)
        return 2

    rows = normalize_rows(input_path)
    write_csv(Path(args.output), rows)
    print(f"Wrote {len(rows)} AD evidence row(s) to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
