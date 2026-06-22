#!/usr/bin/env python3
"""Normalize exported DHCP leases for SysAdminSuite evidence correlation.

This tool is read-only. It expects a CSV export created by an authorized admin,
for example:

Get-DhcpServerv4Scope | ForEach-Object {
  Get-DhcpServerv4Lease -ScopeId $_.ScopeId
} | Select HostName,IPAddress,ClientId,AddressState,LeaseExpiryTime,ScopeId |
  Export-Csv .\\dhcp_leases.csv -NoTypeInformation

It does not query DHCP directly or mutate leases.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from typing import Iterable

FIELDS = [
    "HostName",
    "IPAddress",
    "MACAddress",
    "AddressState",
    "LeaseExpiryTime",
    "ScopeId",
    "DHCPStatus",
    "SourceFile",
]


def clean(value: object) -> str:
    return str(value or "").strip()


def norm_host(value: object) -> str:
    value = clean(value).upper()
    return value.split(".", 1)[0] if value else ""


def norm_mac(value: object) -> str:
    raw = clean(value)
    hx = re.sub(r"[^0-9A-Fa-f]", "", raw).upper()
    if len(hx) >= 12:
        hx = hx[:12]
        return ":".join(hx[i : i + 2] for i in range(0, 12, 2))
    return raw.upper()


def first(row: dict[str, str], names: Iterable[str]) -> str:
    lowered = {str(k).lower(): clean(v) for k, v in row.items()}
    for name in names:
        value = lowered.get(name.lower())
        if value:
            return value
    return ""


def normalize_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    out: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()

    for row in rows:
        host = first(row, ["HostName", "Hostname", "Name", "ClientName", "Client Host Name", "DNSHostName"])
        ip = first(row, ["IPAddress", "IP Address", "Address", "ClientIPAddress"])
        mac = first(row, ["ClientId", "ClientID", "MACAddress", "MacAddress", "MAC", "UniqueID"])
        state = first(row, ["AddressState", "State", "LeaseState", "Status"])
        expiry = first(row, ["LeaseExpiryTime", "LeaseExpires", "Expires", "ExpirationTime", "LeaseEndTime"])
        scope = first(row, ["ScopeId", "ScopeID", "Scope", "Subnet"])

        host_norm = norm_host(host)
        mac_norm = norm_mac(mac)
        key = (host_norm, ip, mac_norm)
        if key in seen:
            continue
        seen.add(key)

        dhcp_status = "DHCP_LEASED" if ip else "DHCP_ROW_NO_IP"
        if state:
            dhcp_status = f"DHCP_{state.upper().replace(' ', '_')}"

        out.append(
            {
                "HostName": host_norm,
                "IPAddress": ip,
                "MACAddress": mac_norm,
                "AddressState": state,
                "LeaseExpiryTime": expiry,
                "ScopeId": scope,
                "DHCPStatus": dhcp_status,
                "SourceFile": str(path),
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
    parser = argparse.ArgumentParser(description="Normalize exported DHCP lease CSV inventory for SysAdminSuite")
    parser.add_argument("--input", required=True, help="DHCP lease CSV export")
    parser.add_argument("--output", default="survey/output/dhcp_leases_normalized.csv", help="Normalized DHCP evidence CSV")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input not found: {input_path}", file=sys.stderr)
        return 2

    rows = normalize_rows(input_path)
    write_csv(Path(args.output), rows)
    print(f"Wrote {len(rows)} DHCP evidence row(s) to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
