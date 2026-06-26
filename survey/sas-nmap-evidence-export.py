#!/usr/bin/env python3
"""Convert Nmap output into SysAdminSuite identity evidence CSV.

Supported inputs:
- Nmap XML: nmap -oX scan.xml ...
- Nmap normal text output: nmap -oN scan.txt ...

This helper does not run Nmap. It only converts an existing Nmap artifact into a
public-safe resolver evidence format. Generated output may contain hostnames,
IPs, and MACs from the local environment; do not commit generated files.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

FIELDS = [
    "Target",
    "observed_hostname",
    "observed_serial",
    "observed_mac",
    "reachability_status",
    "serial_probe_status",
    "ProbeMethod",
    "EvidenceSource",
    "Notes",
]


def clean(value: object) -> str:
    return str(value or "").strip()


def short_hostname(value: str) -> str:
    """Return the short computer name used by tracker manifests.

    Nmap commonly returns an FQDN such as HOST001.example.internal while the
    approved manifest contains HOST001. Keeping the FQDN only in Notes avoids a
    false hostname-drift result while preserving the original DNS evidence.
    """
    value = clean(value).rstrip(".")
    return value.split(".", 1)[0] if value else ""


def mac_norm(value: str) -> str:
    value = clean(value)
    if value.upper().startswith("SAMPLEMAC"):
        return value.upper()
    hx = re.sub(r"[^0-9A-Fa-f]", "", value).upper()
    if len(hx) == 12:
        return ":".join(hx[i : i + 2] for i in range(0, 12, 2))
    return value.upper()


def parse_xml(path: Path) -> list[dict[str, str]]:
    root = ET.parse(path).getroot()
    rows: list[dict[str, str]] = []
    for host in root.findall("host"):
        status = host.find("status")
        state = clean(status.get("state")) if status is not None else "unknown"
        addresses = host.findall("address")
        ip = ""
        mac = ""
        for addr in addresses:
            addr_type = clean(addr.get("addrtype")).lower()
            addr_value = clean(addr.get("addr"))
            if addr_type in {"ipv4", "ipv6"} and not ip:
                ip = addr_value
            elif addr_type == "mac" and not mac:
                mac = mac_norm(addr_value)
        fqdn = ""
        hostnames = host.find("hostnames")
        if hostnames is not None:
            for hn in hostnames.findall("hostname"):
                fqdn = clean(hn.get("name"))
                if fqdn:
                    break
        hostname = short_hostname(fqdn)
        target = hostname or ip or mac
        if not target:
            continue
        notes = f"ip={ip}; state={state}"
        if fqdn and fqdn.rstrip(".").upper() != hostname.upper():
            notes += f"; fqdn={fqdn.rstrip('.')}"
        rows.append(
            {
                "Target": target,
                "observed_hostname": hostname,
                "observed_serial": "",
                "observed_mac": mac,
                "reachability_status": "reachable" if state == "up" else "unreachable",
                "serial_probe_status": "nmap_identity_observed" if hostname or mac else "nmap_no_identity",
                "ProbeMethod": "nmap_reverse_dns" if hostname else "nmap_mac_or_ip_observed" if mac or ip else "nmap_no_identity",
                "EvidenceSource": "nmap_xml",
                "Notes": notes,
            }
        )
    return rows


def parse_normal_text(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    report_re = re.compile(r"^Nmap scan report for\s+(.+)$", re.IGNORECASE)
    host_up_re = re.compile(r"Host is up", re.IGNORECASE)
    mac_re = re.compile(r"MAC Address:\s+([0-9A-Fa-f:.-]+)(?:\s+\((.*?)\))?", re.IGNORECASE)
    ip_in_paren_re = re.compile(r"^(.*?)\s+\(([^)]+)\)$")

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = report_re.match(line.strip())
        if m:
            if current:
                rows.append(current)
            raw = clean(m.group(1))
            fqdn = ""
            ip = raw
            p = ip_in_paren_re.match(raw)
            if p:
                fqdn = clean(p.group(1))
                ip = clean(p.group(2))
            hostname = short_hostname(fqdn)
            notes = f"ip={ip}"
            if fqdn and fqdn.rstrip(".").upper() != hostname.upper():
                notes += f"; fqdn={fqdn.rstrip('.')}"
            current = {
                "Target": hostname or ip,
                "observed_hostname": hostname,
                "observed_serial": "",
                "observed_mac": "",
                "reachability_status": "unknown",
                "serial_probe_status": "nmap_identity_observed" if hostname else "nmap_ip_observed",
                "ProbeMethod": "nmap_reverse_dns" if hostname else "nmap_ip_observed",
                "EvidenceSource": "nmap_normal",
                "Notes": notes,
            }
            continue
        if not current:
            continue
        if host_up_re.search(line):
            current["reachability_status"] = "reachable"
        mac = mac_re.search(line)
        if mac:
            current["observed_mac"] = mac_norm(mac.group(1))
            if current["ProbeMethod"] == "nmap_ip_observed":
                current["ProbeMethod"] = "nmap_mac_or_ip_observed"
            current["serial_probe_status"] = "nmap_identity_observed"
            vendor = clean(mac.group(2))
            if vendor:
                current["Notes"] = (current.get("Notes", "") + f"; vendor={vendor}").strip("; ")
    if current:
        rows.append(current)
    return rows


def infer_format(path: Path, explicit: str) -> str:
    if explicit != "auto":
        return explicit
    suffix = path.suffix.lower()
    if suffix == ".xml":
        return "xml"
    return "normal"


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Nmap output into SysAdminSuite identity evidence CSV")
    parser.add_argument("--input", required=True, help="Nmap XML or normal text output")
    parser.add_argument("--output", required=True, help="Evidence CSV output path")
    parser.add_argument("--format", choices=["auto", "xml", "normal"], default="auto")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    if not input_path.exists():
        print(f"ERROR: input not found: {input_path}", file=sys.stderr)
        return 2

    fmt = infer_format(input_path, args.format)
    rows = parse_xml(input_path) if fmt == "xml" else parse_normal_text(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} Nmap evidence row(s) to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
