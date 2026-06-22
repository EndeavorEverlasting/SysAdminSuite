#!/usr/bin/env python3
"""Merge Cybernet manifest, DNS, AD, DHCP, and Nmap evidence.

This tool is read-only and local-output-only. It does not scan networks or
query remote systems. It correlates CSV evidence files that were already
generated or exported by approved workflows.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from typing import Iterable

FIELDS = [
    "OverallStatus",
    "Confidence",
    "ReviewReason",
    "HostName",
    "Identifier",
    "Serial",
    "MACAddress",
    "DeviceType",
    "DNSStatus",
    "DNSIPs",
    "DNSSubnets24",
    "ADStatus",
    "ADLastLogonDate",
    "DHCPStatus",
    "DHCPIPs",
    "DHCPMACs",
    "NmapStatus",
    "NmapTargets",
    "NmapEvidence",
    "EvidenceSources",
    "Source",
]

REVIEW_STATUSES = {"REVIEW_CONFLICT", "MANIFEST_ONLY", "DNS_ONLY", "AD_ONLY"}


def clean(value: object) -> str:
    return str(value or "").strip()


def norm(value: object) -> str:
    return clean(value).upper()


def norm_host(value: object) -> str:
    value = norm(value)
    return value.split(".", 1)[0] if value else ""


def norm_mac(value: object) -> str:
    raw = clean(value)
    hx = re.sub(r"[^0-9A-Fa-f]", "", raw).upper()
    if len(hx) == 12:
        return ":".join(hx[i : i + 2] for i in range(0, 12, 2))
    return raw.upper()


def first(row: dict[str, str], names: Iterable[str]) -> str:
    lowered = {str(k).lower(): clean(v) for k, v in row.items()}
    for name in names:
        value = lowered.get(name.lower())
        if value:
            return value
    return ""


def read_csv_optional(path_value: str | None) -> list[dict[str, str]]:
    if not path_value:
        return []
    path = Path(path_value)
    if not path.exists():
        print(f"WARN: optional evidence file not found: {path}", file=sys.stderr)
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def read_csv_required(path_value: str) -> list[dict[str, str]]:
    path = Path(path_value)
    if not path.exists():
        raise FileNotFoundError(str(path))
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def split_values(value: object) -> set[str]:
    text = clean(value)
    if not text:
        return set()
    parts = re.split(r"[;,| ]+", text)
    return {clean(part) for part in parts if clean(part)}


def extract_ip_from_notes(notes: str) -> set[str]:
    ips = set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", notes or ""))
    return ips


def host_keys_for_manifest(row: dict[str, str]) -> set[str]:
    identifier = first(row, ["Identifier", "Target", "KnownIdentifier", "LookupValue"])
    identifier_type = first(row, ["IdentifierType", "Type"])
    host = first(row, ["HostName", "Hostname", "Host", "ComputerName", "Computer", "Name"])
    if not host and identifier_type.lower() == "hostname":
        host = identifier
    keys = {norm_host(host)}
    if identifier and any(c.isalpha() for c in identifier):
        keys.add(norm_host(identifier))
    return {k for k in keys if k}


def build_dns_index(rows: list[dict[str, str]]) -> tuple[dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]]]:
    by_host: dict[str, list[dict[str, str]]] = {}
    by_ip: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        host = norm_host(first(row, ["HostName", "Hostname", "Identifier"]))
        if host:
            by_host.setdefault(host, []).append(row)
        for ip in split_values(first(row, ["IPAddresses", "DNSIPs", "IPAddress"])):
            by_ip.setdefault(ip, []).append(row)
    return by_host, by_ip


def build_ad_index(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    by_host: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        for host in [first(row, ["HostName", "Name"]), first(row, ["DNSHostName", "FQDN"])]:
            host_norm = norm_host(host)
            if host_norm:
                by_host.setdefault(host_norm, []).append(row)
    return by_host


def build_dhcp_index(rows: list[dict[str, str]]) -> tuple[dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]]]:
    by_host: dict[str, list[dict[str, str]]] = {}
    by_ip: dict[str, list[dict[str, str]]] = {}
    by_mac: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        host = norm_host(first(row, ["HostName", "Hostname", "Name", "ClientName"]))
        ip = first(row, ["IPAddress", "IP Address", "Address"])
        mac = norm_mac(first(row, ["MACAddress", "ClientId", "ClientID", "MAC"]))
        if host:
            by_host.setdefault(host, []).append(row)
        if ip:
            by_ip.setdefault(ip, []).append(row)
        if mac:
            by_mac.setdefault(mac, []).append(row)
    return by_host, by_ip, by_mac


def build_nmap_index(rows: list[dict[str, str]]) -> tuple[dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]]]:
    by_host: dict[str, list[dict[str, str]]] = {}
    by_ip: dict[str, list[dict[str, str]]] = {}
    by_mac: dict[str, list[dict[str, str]]] = {}

    for row in rows:
        target = first(row, ["Target", "HostName", "Hostname"])
        observed_host = first(row, ["observed_hostname", "ObservedHostName", "HostName", "Hostname"])
        observed_mac = norm_mac(first(row, ["observed_mac", "MACAddress", "MacAddress", "MAC"]))
        notes = first(row, ["Notes", "Evidence", "NmapEvidence"])
        candidate_hosts = {norm_host(target), norm_host(observed_host)}
        for host in candidate_hosts:
            if host:
                by_host.setdefault(host, []).append(row)
        for ip in extract_ip_from_notes(notes) | split_values(first(row, ["IPAddress", "IP", "Address"])):
            if ip:
                by_ip.setdefault(ip, []).append(row)
        if observed_mac:
            by_mac.setdefault(observed_mac, []).append(row)

    return by_host, by_ip, by_mac


def dedup_rows(rows: Iterable[dict[str, str]]) -> list[dict[str, str]]:
    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for row in rows:
        key = "|".join(clean(v) for v in row.values())
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def joined(values: Iterable[str]) -> str:
    return ";".join(sorted({clean(v) for v in values if clean(v)}))


def summarize_nmap(rows: list[dict[str, str]]) -> tuple[str, str, str]:
    if not rows:
        return "NMAP_NOT_SEEN", "", ""
    targets = joined(first(row, ["Target", "observed_hostname", "IPAddress"]) for row in rows)
    previews = []
    for row in rows[:5]:
        target = first(row, ["Target"])
        host = first(row, ["observed_hostname", "HostName"])
        mac = first(row, ["observed_mac", "MACAddress"])
        reach = first(row, ["reachability_status", "Status"])
        notes = first(row, ["Notes"])
        previews.append(f"target={target}; host={host}; mac={mac}; reach={reach}; {notes}".strip("; "))
    return "NMAP_SEEN", targets, " || ".join(previews)


def classify(
    dns_rows: list[dict[str, str]],
    ad_rows: list[dict[str, str]],
    dhcp_rows: list[dict[str, str]],
    nmap_rows: list[dict[str, str]],
    conflict_reasons: list[str],
) -> tuple[str, str, str]:
    dns_resolved = any(first(r, ["Status", "DNSStatus"]) == "DNS_RESOLVED" for r in dns_rows)
    has_ad = bool(ad_rows)
    has_dhcp = bool(dhcp_rows)
    has_nmap = bool(nmap_rows)

    if conflict_reasons:
        return "REVIEW_CONFLICT", "LOW", joined(conflict_reasons)
    if has_nmap and (dns_resolved or has_dhcp or has_ad):
        return "CONFIRMED_ON_NETWORK", "HIGH", "Nmap evidence matched another identity source."
    if has_dhcp and (dns_resolved or has_ad):
        return "CONFIRMED_BY_INFRASTRUCTURE", "HIGH", "DHCP evidence matched DNS or AD."
    if has_nmap:
        return "NMAP_ONLY", "MEDIUM", "Observed in Nmap evidence, but not confirmed by DNS/AD/DHCP inputs."
    if has_dhcp:
        return "DHCP_ONLY", "MEDIUM", "DHCP lease evidence exists, but no DNS/AD/Nmap confirmation was supplied."
    if dns_resolved:
        return "DNS_ONLY", "MEDIUM", "DNS resolved, but no Nmap/DHCP/AD confirmation was supplied."
    if has_ad:
        return "AD_ONLY", "MEDIUM", "AD object exists, but no DNS/DHCP/Nmap confirmation was supplied."
    return "MANIFEST_ONLY", "LOW", "No matching DNS, AD, DHCP, or Nmap evidence was supplied."


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge Cybernet manifest evidence from DNS, AD, DHCP, and Nmap CSVs")
    parser.add_argument("--manifest", default="survey/output/cybernet_targets_resolved.csv", help="Cybernet target manifest CSV")
    parser.add_argument("--dns", default="survey/output/cybernet_dns_resolution_report.csv", help="DNS evidence CSV")
    parser.add_argument("--ad", default=None, help="Normalized AD evidence CSV from sas-import-ad-computers.py")
    parser.add_argument("--dhcp", default=None, help="Normalized DHCP evidence CSV from sas-import-dhcp-leases.py")
    parser.add_argument("--nmap", default=None, help="Nmap evidence CSV from sas-nmap-evidence-export.py")
    parser.add_argument("--output", default="survey/output/cybernet_master_presence_report.csv", help="Merged Cybernet evidence report CSV")
    parser.add_argument("--manual-review", default="survey/output/cybernet_manual_review.csv", help="Manual review subset CSV")
    args = parser.parse_args()

    try:
        manifest_rows = read_csv_required(args.manifest)
    except FileNotFoundError:
        print(f"ERROR: manifest not found: {args.manifest}", file=sys.stderr)
        return 2

    dns_rows = read_csv_optional(args.dns)
    ad_rows_all = read_csv_optional(args.ad)
    dhcp_rows_all = read_csv_optional(args.dhcp)
    nmap_rows_all = read_csv_optional(args.nmap)

    dns_by_host, dns_by_ip = build_dns_index(dns_rows)
    ad_by_host = build_ad_index(ad_rows_all)
    dhcp_by_host, dhcp_by_ip, dhcp_by_mac = build_dhcp_index(dhcp_rows_all)
    nmap_by_host, nmap_by_ip, nmap_by_mac = build_nmap_index(nmap_rows_all)

    report: list[dict[str, str]] = []

    for row in manifest_rows:
        identifier = norm(first(row, ["Identifier", "Target", "KnownIdentifier", "LookupValue"]))
        serial = norm(first(row, ["Serial", "SerialNumber", "ServiceTag", "AssetSerial"]))
        mac = norm_mac(first(row, ["MACAddress", "MacAddress", "MAC", "Mac"]))
        dtype = first(row, ["DeviceType", "DeviceClass"]) or "Cybernet"
        source = first(row, ["Source", "SourceFile", "EvidenceSource"])
        host_keys = host_keys_for_manifest(row)
        host = sorted(host_keys)[0] if host_keys else ""

        matched_dns = dedup_rows(r for h in host_keys for r in dns_by_host.get(h, []))
        dns_ips = set()
        dns_subnets = set()
        dns_status_values = set()
        for dns_row in matched_dns:
            dns_status_values.add(first(dns_row, ["Status", "DNSStatus"]))
            dns_ips |= split_values(first(dns_row, ["IPAddresses", "DNSIPs", "IPAddress"]))
            dns_subnets |= split_values(first(dns_row, ["Subnets24", "DNSSubnets24"]))

        matched_ad = dedup_rows(r for h in host_keys for r in ad_by_host.get(h, []))

        matched_dhcp = []
        for h in host_keys:
            matched_dhcp.extend(dhcp_by_host.get(h, []))
        for ip in dns_ips:
            matched_dhcp.extend(dhcp_by_ip.get(ip, []))
        if mac:
            matched_dhcp.extend(dhcp_by_mac.get(mac, []))
        matched_dhcp = dedup_rows(matched_dhcp)

        matched_nmap = []
        for h in host_keys:
            matched_nmap.extend(nmap_by_host.get(h, []))
        for ip in dns_ips:
            matched_nmap.extend(nmap_by_ip.get(ip, []))
        if mac:
            matched_nmap.extend(nmap_by_mac.get(mac, []))
        matched_nmap = dedup_rows(matched_nmap)

        dhcp_ips = {first(r, ["IPAddress", "IP Address", "Address"]) for r in matched_dhcp}
        dhcp_macs = {norm_mac(first(r, ["MACAddress", "ClientId", "ClientID", "MAC"])) for r in matched_dhcp}
        dhcp_status = joined(first(r, ["DHCPStatus", "AddressState", "Status"]) for r in matched_dhcp)

        ad_status = joined(first(r, ["ADStatus", "Status", "Enabled"]) for r in matched_ad)
        ad_last = joined(first(r, ["LastLogonDate", "LastSeen", "Last Seen"]) for r in matched_ad)

        conflict_reasons: list[str] = []
        if mac and dhcp_macs and mac not in dhcp_macs:
            conflict_reasons.append("Manifest MAC did not match DHCP MAC evidence.")
        if matched_dns and matched_dhcp and dns_ips and dhcp_ips and not (dns_ips & dhcp_ips):
            conflict_reasons.append("DNS IPs and DHCP IPs did not overlap.")

        nmap_status, nmap_targets, nmap_evidence = summarize_nmap(matched_nmap)
        overall, confidence, review_reason = classify(matched_dns, matched_ad, matched_dhcp, matched_nmap, conflict_reasons)

        evidence_sources = []
        if matched_dns:
            evidence_sources.append("DNS")
        if matched_ad:
            evidence_sources.append("AD")
        if matched_dhcp:
            evidence_sources.append("DHCP")
        if matched_nmap:
            evidence_sources.append("NMAP")

        report.append(
            {
                "OverallStatus": overall,
                "Confidence": confidence,
                "ReviewReason": review_reason,
                "HostName": host,
                "Identifier": identifier,
                "Serial": serial,
                "MACAddress": mac,
                "DeviceType": dtype,
                "DNSStatus": joined(dns_status_values),
                "DNSIPs": joined(dns_ips),
                "DNSSubnets24": joined(dns_subnets),
                "ADStatus": ad_status,
                "ADLastLogonDate": ad_last,
                "DHCPStatus": dhcp_status,
                "DHCPIPs": joined(dhcp_ips),
                "DHCPMACs": joined(dhcp_macs),
                "NmapStatus": nmap_status,
                "NmapTargets": nmap_targets,
                "NmapEvidence": nmap_evidence,
                "EvidenceSources": joined(evidence_sources),
                "Source": source,
            }
        )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(report)

    manual = [r for r in report if r["OverallStatus"] in REVIEW_STATUSES or r["Confidence"] == "LOW"]
    manual_path = Path(args.manual_review)
    manual_path.parent.mkdir(parents=True, exist_ok=True)
    with manual_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(manual)

    print(f"Wrote {len(report)} merged Cybernet row(s) to {args.output}")
    print(f"Wrote {len(manual)} manual-review row(s) to {args.manual_review}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
