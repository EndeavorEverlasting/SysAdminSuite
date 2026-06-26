#!/usr/bin/env python3
"""Resolve Cybernet manifest hostnames through local DNS.

This tool is read-only. It does not scan networks, authenticate to remote
systems, or mutate workstations. It converts a normalized SysAdminSuite manifest
into DNS evidence that can be correlated with AD, DHCP, Nmap, and tracker data.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import ipaddress
import socket
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable


def _load_classifier():
    module_path = Path(__file__).with_name("sas-survey-device-classify.py")
    spec = importlib.util.spec_from_file_location("sas_survey_device_classify", module_path)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load classifier module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_CLASSIFY = _load_classifier()
CLASSIFICATION_FIELDS = _CLASSIFY.CLASSIFICATION_FIELDS
classify_from_dns_row = _CLASSIFY.classify_from_dns_row
classify_from_unresolved_manifest_row = _CLASSIFY.classify_from_unresolved_manifest_row

OUTPUT_FIELDS = [
    "Status",
    "HostName",
    "Identifier",
    "Serial",
    "MACAddress",
    "DeviceType",
    "FQDN",
    "IPAddresses",
    "ReverseNames",
    "Subnets24",
    "ResolvedBy",
    "Error",
    "Source",
    *CLASSIFICATION_FIELDS,
]


def clean(value: object) -> str:
    return str(value or "").strip()


def norm(value: object) -> str:
    return clean(value).upper()


def first(row: dict[str, str], names: Iterable[str]) -> str:
    lowered = {str(k).lower(): clean(v) for k, v in row.items()}
    for name in names:
        value = lowered.get(name.lower())
        if value:
            return value
    return ""


def is_probable_hostname(value: str) -> bool:
    value = clean(value)
    if not value:
        return False
    if " " in value or "," in value:
        return False
    if value.count(".") == 3:
        try:
            ipaddress.ip_address(value)
            return False
        except ValueError:
            pass
    return any(c.isalpha() for c in value) and len(value) <= 253


def subnet24(ip: str) -> str:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return ""
    if addr.version != 4:
        return ""
    parts = ip.split(".")
    return ".".join(parts[:3]) + ".0/24"


def candidate_names(hostname: str, suffixes: list[str]) -> list[tuple[str, str]]:
    host = clean(hostname).rstrip(".")
    out: list[tuple[str, str]] = []
    if not host:
        return out
    out.append((host, "system_dns"))
    if "." not in host:
        for suffix in suffixes:
            suffix = suffix.strip().strip(".")
            if suffix:
                out.append((f"{host}.{suffix}", f"suffix:{suffix}"))
    # Deduplicate while preserving order.
    seen: set[str] = set()
    unique: list[tuple[str, str]] = []
    for name, source in out:
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append((name, source))
    return unique


def resolve_host(hostname: str, suffixes: list[str]) -> tuple[str, str, list[str], str, str]:
    errors: list[str] = []
    for name, resolved_by in candidate_names(hostname, suffixes):
        try:
            fqdn, _aliases, ips = socket.gethostbyname_ex(name)
            ips = sorted(set(clean(ip) for ip in ips if clean(ip)))
            if ips:
                return "DNS_RESOLVED", fqdn, ips, resolved_by, ""
        except OSError as exc:
            errors.append(f"{name}: {exc}")
    return "DNS_NOT_FOUND", "", [], "", " | ".join(errors)


def reverse_lookup(ips: list[str]) -> list[str]:
    names: set[str] = set()
    for ip in ips:
        try:
            name, aliases, _ = socket.gethostbyaddr(ip)
        except OSError:
            continue
        for item in [name, *aliases]:
            item = clean(item)
            if item:
                names.add(item)
    return sorted(names)


def manifest_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def build_rows(input_rows: list[dict[str, str]], suffixes: list[str]) -> list[dict[str, str]]:
    output: list[dict[str, str]] = []
    seen: set[tuple[str, str, str, str]] = set()

    for row in input_rows:
        identifier = first(row, ["Identifier", "Target", "KnownIdentifier", "LookupValue"])
        identifier_type = first(row, ["IdentifierType", "Type"])
        host = first(row, ["HostName", "Hostname", "Host", "ComputerName", "Computer", "Name"])
        serial = first(row, ["Serial", "SerialNumber", "ServiceTag", "AssetSerial"])
        mac = first(row, ["MACAddress", "MacAddress", "MAC", "Mac", "EthernetMAC", "WifiMAC"])
        dtype = first(row, ["DeviceType", "DeviceClass"]) or "Cybernet"
        source = first(row, ["Source", "SourceFile", "EvidenceSource"])

        if not host and identifier_type.lower() == "hostname":
            host = identifier
        if not host and is_probable_hostname(identifier):
            host = identifier

        host = norm(host)
        identifier = norm(identifier)
        serial = norm(serial)
        mac = norm(mac)

        key = (host, identifier, serial, mac)
        if key in seen:
            continue
        seen.add(key)

        if not host:
            row_out = {
                "Status": "NO_HOSTNAME",
                "HostName": "",
                "Identifier": identifier,
                "Serial": serial,
                "MACAddress": mac,
                "DeviceType": dtype,
                "IdentifierType": identifier_type,
                "FQDN": "",
                "IPAddresses": "",
                "ReverseNames": "",
                "Subnets24": "",
                "ResolvedBy": "",
                "Error": "No hostname-like value was present in the manifest row.",
                "Source": source,
            }
            row_out.update(classify_from_unresolved_manifest_row(row_out, survey_lane="cybernet_manifest"))
            output.append(row_out)
            continue

        status, fqdn, ips, resolved_by, error = resolve_host(host, suffixes)
        reverse_names = reverse_lookup(ips) if ips else []
        subnets = sorted(set(filter(None, (subnet24(ip) for ip in ips))))

        row_out = {
            "Status": status,
            "HostName": host,
            "Identifier": identifier,
            "Serial": serial,
            "MACAddress": mac,
            "DeviceType": dtype,
            "FQDN": fqdn,
            "IPAddresses": ";".join(ips),
            "ReverseNames": ";".join(reverse_names),
            "Subnets24": ";".join(subnets),
            "ResolvedBy": resolved_by,
            "Error": error,
            "Source": source,
        }
        row_out.update(classify_from_dns_row(row_out, survey_lane="cybernet_manifest"))
        output.append(row_out)

    return output


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_subnet_summary(path: Path, rows: list[dict[str, str]]) -> None:
    counts: Counter[str] = Counter()
    for row in rows:
        if row.get("Status") != "DNS_RESOLVED":
            continue
        for subnet in clean(row.get("Subnets24")).split(";"):
            subnet = clean(subnet)
            if subnet:
                counts[subnet] += 1
    out_rows = [{"Subnet24": subnet, "Count": str(count)} for subnet, count in counts.most_common()]
    write_csv(path, ["Subnet24", "Count"], out_rows)


def write_resolved_ips(path: Path, rows: list[dict[str, str]]) -> None:
    ips: set[str] = set()
    for row in rows:
        if row.get("Status") != "DNS_RESOLVED":
            continue
        for ip in clean(row.get("IPAddresses")).split(";"):
            ip = clean(ip)
            if ip:
                ips.add(ip)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(sorted(ips)) + ("\n" if ips else ""), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve Cybernet manifest hostnames into DNS evidence")
    parser.add_argument("--manifest", default="survey/output/cybernet_targets_resolved.csv", help="Cybernet manifest CSV")
    parser.add_argument("--output", default="survey/output/cybernet_dns_resolution_report.csv", help="DNS evidence CSV")
    parser.add_argument("--subnet-summary", default="survey/output/cybernet_dns_subnet_summary.csv", help="/24 subnet summary CSV")
    parser.add_argument("--resolved-ips", default="survey/output/cybernet_resolved_ips.txt", help="Text file of resolved IPs for approved targeted scans")
    parser.add_argument("--fqdn-suffix", action="append", default=[], help="Optional DNS suffix to try for short hostnames; can be repeated")
    parser.add_argument("--timeout", type=float, default=5.0, help="Socket default timeout in seconds")
    args = parser.parse_args()

    socket.setdefaulttimeout(args.timeout)

    manifest_path = Path(args.manifest)
    if not manifest_path.exists():
        print(f"ERROR: manifest not found: {manifest_path}", file=sys.stderr)
        return 2

    rows = build_rows(manifest_rows(manifest_path), args.fqdn_suffix)
    write_csv(Path(args.output), OUTPUT_FIELDS, rows)
    write_subnet_summary(Path(args.subnet_summary), rows)
    write_resolved_ips(Path(args.resolved_ips), rows)

    resolved = sum(1 for row in rows if row.get("Status") == "DNS_RESOLVED")
    not_found = sum(1 for row in rows if row.get("Status") == "DNS_NOT_FOUND")
    no_host = sum(1 for row in rows if row.get("Status") == "NO_HOSTNAME")
    print(f"Wrote {len(rows)} DNS evidence row(s) to {args.output}")
    print(f"DNS resolved: {resolved}; DNS not found: {not_found}; no hostname: {no_host}")
    print(f"Wrote subnet summary to {args.subnet_summary}")
    print(f"Wrote resolved IP list to {args.resolved_ips}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
