#!/usr/bin/env python3
"""
SysAdminSuite Neuron MAC/Subnet Resolver

Reads:
  - Neuron manifest CSV, usually GetInfo/Config/NeuronTargets.unresolved.csv
  - One or more nmap XML artifacts from approved subnet discovery

Writes:
  - A Neuron target CSV compatible with GetInfo/Get-NeuronNetworkInventory.ps1
  - A review CSV for unresolved, serial-only, or conflicting rows
  - Optional HTML dashboard for operator review

This script does not run nmap. It parses saved nmap XML evidence.
Generated outputs may contain operational identifiers. Do not commit them.
"""
from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


TARGET_FIELDS = [
    "NeuronHost",
    "ExpectedMAC",
    "ExpectedSerial",
    "Site",
    "Room",
    "Notes",
]

REVIEW_FIELDS = [
    "Site",
    "Room",
    "ExpectedMAC",
    "ExpectedSerial",
    "CandidateIP",
    "ObservedHostname",
    "ObservedMAC",
    "MatchStatus",
    "EvidenceSource",
    "Notes",
]


def clean(value: object) -> str:
    return str(value or "").strip()


def norm_mac(value: str) -> str:
    """Normalize common MAC address shapes to AA:BB:CC:DD:EE:FF."""
    value = clean(value)
    if not value:
        return ""
    hx = re.sub(r"[^0-9A-Fa-f]", "", value).upper()
    if len(hx) == 12:
        return ":".join(hx[i : i + 2] for i in range(0, 12, 2))
    return value.upper()


def first(row: dict[str, str], names: list[str]) -> str:
    lowered = {str(k).strip().lower(): clean(v) for k, v in row.items() if k is not None}
    for name in names:
        value = lowered.get(name.lower(), "")
        if value:
            return value
    return ""


def parse_expected_macs(value: str) -> list[str]:
    parts = re.split(r"[;, \n\r\t]+", clean(value))
    macs: list[str] = []
    for part in parts:
        mac = norm_mac(part)
        if mac and mac not in macs:
            macs.append(mac)
    return macs


def parse_nmap_xml(path: Path) -> list[dict[str, str]]:
    root = ET.parse(path).getroot()
    rows: list[dict[str, str]] = []

    for host in root.findall("host"):
        status = host.find("status")
        state = clean(status.get("state")) if status is not None else "unknown"

        ip = ""
        mac = ""

        for addr in host.findall("address"):
            addr_type = clean(addr.get("addrtype")).lower()
            addr_value = clean(addr.get("addr"))

            if addr_type in {"ipv4", "ipv6"} and not ip:
                ip = addr_value
            elif addr_type == "mac" and not mac:
                mac = norm_mac(addr_value)

        hostname = ""
        hostnames = host.find("hostnames")
        if hostnames is not None:
            for hn in hostnames.findall("hostname"):
                hostname = clean(hn.get("name"))
                if hostname:
                    break

        if not ip and not mac:
            continue

        rows.append(
            {
                "ip": ip,
                "mac": mac,
                "hostname": hostname,
                "state": state,
                "source": str(path),
            }
        )

    return rows


def load_nmap_index(paths: list[Path]) -> dict[str, list[dict[str, str]]]:
    index: dict[str, list[dict[str, str]]] = {}

    for path in paths:
        for row in parse_nmap_xml(path):
            mac = row["mac"]
            if not mac:
                continue
            index.setdefault(mac, []).append(row)

    return index


def review_row(
    *,
    site: str,
    room: str,
    expected_mac: str,
    expected_serial: str,
    candidate_ip: str,
    observed_hostname: str,
    observed_mac: str,
    match_status: str,
    evidence_source: str,
    notes: str,
) -> dict[str, str]:
    return {
        "Site": site,
        "Room": room,
        "ExpectedMAC": expected_mac,
        "ExpectedSerial": expected_serial,
        "CandidateIP": candidate_ip,
        "ObservedHostname": observed_hostname,
        "ObservedMAC": observed_mac,
        "MatchStatus": match_status,
        "EvidenceSource": evidence_source,
        "Notes": notes,
    }


def render_dashboard(review_csv: Path, dashboard_path: Path) -> None:
    renderer = Path(__file__).resolve().parents[1] / "deployment-audit" / "sas-render-neuron-nmap-dashboard.py"
    if not renderer.exists():
        print(f"WARNING: dashboard renderer not found: {renderer}", file=sys.stderr)
        return
    subprocess.run(
        [sys.executable, str(renderer), "--input", str(review_csv), "--output", str(dashboard_path)],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Resolve Neuron targets by matching expected MACs against nmap XML evidence."
    )
    parser.add_argument("--manifest", required=True, help="Neuron manifest CSV, often NeuronTargets.unresolved.csv")
    parser.add_argument("--nmap-xml", required=True, nargs="+", help="One or more nmap XML artifacts")
    parser.add_argument(
        "--output",
        default="survey/output/neuron_resolved_targets.csv",
        help="PowerShell-compatible Neuron target CSV",
    )
    parser.add_argument(
        "--review-output",
        default="survey/output/neuron_probe_review.csv",
        help="Review CSV for unresolved/conflict rows",
    )
    parser.add_argument(
        "--dashboard",
        default="",
        help="Optional HTML dashboard output path for review CSV",
    )
    parser.add_argument(
        "--prefer-hostname",
        action="store_true",
        help="Use observed hostname instead of IP when nmap returns one",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    nmap_paths = [Path(p) for p in args.nmap_xml]
    output_path = Path(args.output)
    review_path = Path(args.review_output)

    if not manifest_path.exists():
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        return 2

    missing = [p for p in nmap_paths if not p.exists()]
    if missing:
        print(f"ERROR: nmap XML artifact(s) not found: {', '.join(str(p) for p in missing)}", file=sys.stderr)
        return 2

    nmap_index = load_nmap_index(nmap_paths)

    targets: list[dict[str, str]] = []
    review: list[dict[str, str]] = []

    with manifest_path.open(newline="", encoding="utf-8-sig") as handle:
        for source_row, row in enumerate(csv.DictReader(handle), start=2):
            site = first(row, ["Site", "Building", "Facility"])
            room = first(row, ["Room", "Location", "Area"])
            expected_mac_raw = first(row, ["ExpectedMAC", "ExpectedMac", "NeuronMAC", "MACAddress", "MAC"])
            expected_serial = first(row, ["ExpectedSerial", "NeuronSerial", "SerialNumber", "Serial", "Neuron S/N"])
            notes = first(row, ["Notes", "Comment", "Comments"])

            expected_macs = parse_expected_macs(expected_mac_raw)

            if not expected_macs and not expected_serial:
                review.append(
                    review_row(
                        site=site,
                        room=room,
                        expected_mac="",
                        expected_serial="",
                        candidate_ip="",
                        observed_hostname="",
                        observed_mac="",
                        match_status="NO_USABLE_IDENTIFIER",
                        evidence_source=str(manifest_path),
                        notes=f"Row={source_row}; no MAC or serial available for Neuron probe. {notes}".strip(),
                    )
                )
                continue

            if not expected_macs:
                review.append(
                    review_row(
                        site=site,
                        room=room,
                        expected_mac="",
                        expected_serial=expected_serial,
                        candidate_ip="",
                        observed_hostname="",
                        observed_mac="",
                        match_status="SERIAL_ONLY_NO_MAC",
                        evidence_source=str(manifest_path),
                        notes=(
                            f"Row={source_row}; serial present but nmap cannot match BIOS serial by itself. "
                            f"Use AD, vendor evidence, or WMI after IP resolution. {notes}"
                        ).strip(),
                    )
                )
                continue

            matched_any = False

            for expected_mac in expected_macs:
                hits = nmap_index.get(expected_mac, [])

                if len(hits) == 1:
                    hit = hits[0]
                    target = hit["hostname"] if args.prefer_hostname and hit["hostname"] else hit["ip"]

                    targets.append(
                        {
                            "NeuronHost": target,
                            "ExpectedMAC": expected_mac,
                            "ExpectedSerial": expected_serial,
                            "Site": site,
                            "Room": room,
                            "Notes": (
                                f"ResolvedBy=nmap_mac_match; SourceRow={source_row}; "
                                f"CandidateIP={hit['ip']}; ObservedHostname={hit['hostname']}; "
                                f"Evidence={hit['source']}; {notes}"
                            ).strip(),
                        }
                    )

                    review.append(
                        review_row(
                            site=site,
                            room=room,
                            expected_mac=expected_mac,
                            expected_serial=expected_serial,
                            candidate_ip=hit["ip"],
                            observed_hostname=hit["hostname"],
                            observed_mac=hit["mac"],
                            match_status="MAC_MATCH_RESOLVED",
                            evidence_source=hit["source"],
                            notes=f"Row={source_row}; target={target}",
                        )
                    )
                    matched_any = True

                elif len(hits) > 1:
                    ips = ";".join(clean(h["ip"]) for h in hits if clean(h["ip"]))
                    hostnames = ";".join(clean(h["hostname"]) for h in hits if clean(h["hostname"]))
                    sources = ";".join(sorted({h["source"] for h in hits}))

                    review.append(
                        review_row(
                            site=site,
                            room=room,
                            expected_mac=expected_mac,
                            expected_serial=expected_serial,
                            candidate_ip=ips,
                            observed_hostname=hostnames,
                            observed_mac=expected_mac,
                            match_status="MAC_CONFLICT_MULTIPLE_IPS",
                            evidence_source=sources,
                            notes=f"Row={source_row}; MAC appeared on multiple IPs. Manual review required.",
                        )
                    )
                    matched_any = True

            if not matched_any:
                review.append(
                    review_row(
                        site=site,
                        room=room,
                        expected_mac=expected_mac_raw,
                        expected_serial=expected_serial,
                        candidate_ip="",
                        observed_hostname="",
                        observed_mac="",
                        match_status="MAC_NOT_FOUND_IN_NMAP",
                        evidence_source=";".join(str(p) for p in nmap_paths),
                        notes=(
                            f"Row={source_row}; no nmap XML MAC match. "
                            f"Check subnet, VLAN, local segment, device power, or network state. {notes}"
                        ).strip(),
                    )
                )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    review_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=TARGET_FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(targets)

    with review_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=REVIEW_FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(review)

    print(f"Wrote {len(targets)} resolved Neuron target row(s) to {output_path}")
    print(f"Wrote {len(review)} review row(s) to {review_path}")

    if args.dashboard:
        render_dashboard(review_path, Path(args.dashboard))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
