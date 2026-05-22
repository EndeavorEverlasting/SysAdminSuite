#!/usr/bin/env python3
"""
Parse saved Cybernet identity artifacts into CSV, JSON, and optional HTML.

This tool is read-only. It does not perform live network actions.

Supported primary input:
- Nmap XML-style saved artifact files

Optional secondary input:
- A JSON file containing ping/status evidence keyed by host/IP/name

The parser intentionally separates identity artifact evidence from ping evidence.
A host can have identity evidence while ping is failed, missing, or later successful.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence

PARSER_VERSION = "0.1.0"
UNKNOWN = "Unknown"

FIELDNAMES = [
    "HostAddress",
    "MacAddress",
    "MacVendor",
    "DnsName",
    "HostIdentity",
    "DomainOrWorkgroup",
    "DetectedOs",
    "OpenPorts",
    "ServiceSummary",
    "IdentityArtifactStatus",
    "CmdPingStatus",
    "PingAttemptCount",
    "FirstPingTimestamp",
    "LastPingTimestamp",
    "NameResolutionStatus",
    "SourceArtifactTimestamp",
    "NetworkPosture",
    "Classification",
    "SourceArtifact",
    "ParserVersion",
    "Notes",
]


@dataclass
class IdentityRecord:
    HostAddress: str = UNKNOWN
    MacAddress: str = ""
    MacVendor: str = ""
    DnsName: str = ""
    HostIdentity: str = ""
    DomainOrWorkgroup: str = ""
    DetectedOs: str = ""
    OpenPorts: str = ""
    ServiceSummary: str = ""
    IdentityArtifactStatus: str = "IdentityArtifactPresent"
    CmdPingStatus: str = "NotProvided"
    PingAttemptCount: str = "0"
    FirstPingTimestamp: str = ""
    LastPingTimestamp: str = ""
    NameResolutionStatus: str = "NotProvided"
    SourceArtifactTimestamp: str = ""
    NetworkPosture: str = "Unknown"
    Classification: str = "INCONCLUSIVE"
    SourceArtifact: str = ""
    ParserVersion: str = PARSER_VERSION
    Notes: str = ""


def _text(value: Optional[str]) -> str:
    return value.strip() if value else ""


def _safe_join(values: Iterable[str]) -> str:
    cleaned: List[str] = []
    for value in values:
        v = _text(value)
        if v and v not in cleaned:
            cleaned.append(v)
    return "; ".join(cleaned)


def _parse_epoch(value: Optional[str]) -> str:
    if not value:
        return ""
    try:
        return datetime.fromtimestamp(int(value), tz=timezone.utc).isoformat()
    except (TypeError, ValueError, OSError):
        return ""


def _load_ping_evidence(path: Optional[Path]) -> Dict[str, Dict[str, Any]]:
    if not path:
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        return {str(k).lower(): v for k, v in data.items() if isinstance(v, dict)}
    if isinstance(data, list):
        out: Dict[str, Dict[str, Any]] = {}
        for item in data:
            if not isinstance(item, dict):
                continue
            keys = [
                item.get("HostAddress"),
                item.get("Host"),
                item.get("DnsName"),
                item.get("HostIdentity"),
            ]
            for key in keys:
                if key:
                    out[str(key).lower()] = item
        return out
    raise ValueError("Ping evidence must be a JSON object or list of objects")


def _find_ping(record: IdentityRecord, ping_evidence: Dict[str, Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    for key in [record.HostAddress, record.DnsName, record.HostIdentity]:
        if key and key.lower() in ping_evidence:
            return ping_evidence[key.lower()]
    return None


def _apply_ping_evidence(record: IdentityRecord, evidence: Optional[Dict[str, Any]]) -> None:
    if not evidence:
        return
    record.CmdPingStatus = str(evidence.get("CmdPingStatus") or evidence.get("PingStatus") or UNKNOWN)
    record.PingAttemptCount = str(evidence.get("PingAttemptCount") or evidence.get("Attempts") or "")
    record.FirstPingTimestamp = str(evidence.get("FirstPingTimestamp") or "")
    record.LastPingTimestamp = str(evidence.get("LastPingTimestamp") or "")
    record.NameResolutionStatus = str(evidence.get("NameResolutionStatus") or record.NameResolutionStatus)
    notes = evidence.get("Notes")
    if notes:
        record.Notes = _safe_join([record.Notes, str(notes)])


def _classify(record: IdentityRecord, network_posture: str) -> str:
    posture = network_posture.lower()
    ping = record.CmdPingStatus.lower()

    if "guest" in posture:
        return "ENVIRONMENT_BLOCKED_GUEST_NETWORK"
    if "blocked" in posture or "policy" in posture:
        return "ENVIRONMENT_BLOCKED_POLICY"
    if record.IdentityArtifactStatus == "IdentityArtifactPresent" and ping in {"failed", "failure", "timeout"}:
        return "INCONCLUSIVE_TRANSIENT_REACHABILITY"
    if record.IdentityArtifactStatus == "IdentityArtifactPresent":
        return "OK_IDENTITY_ARTIFACT_PARSED"
    return "INCONCLUSIVE"


def _extract_host_identity_from_scripts(host: ET.Element) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for script in host.findall("ports/port/script") + host.findall("hostscript/script"):
        script_id = script.attrib.get("id", "")
        output = script.attrib.get("output", "")
        if script_id in {"nbstat", "smb-os-discovery"} and output:
            lines = [line.strip() for line in output.splitlines() if line.strip()]
            for line in lines:
                lower = line.lower()
                if "computer name" in lower and "HostIdentity" not in values:
                    values["HostIdentity"] = line.split(":", 1)[-1].strip()
                elif ("workgroup" in lower or "domain" in lower) and "DomainOrWorkgroup" not in values:
                    values["DomainOrWorkgroup"] = line.split(":", 1)[-1].strip()
    return values


def parse_artifact(path: Path, network_posture: str, ping_evidence: Dict[str, Dict[str, Any]]) -> List[IdentityRecord]:
    tree = ET.parse(path)
    root = tree.getroot()
    source_timestamp = _parse_epoch(root.attrib.get("start"))
    records: List[IdentityRecord] = []

    for host in root.findall("host"):
        status = host.find("status")
        if status is not None and status.attrib.get("state") == "down":
            identity_status = "HostDownInArtifact"
        else:
            identity_status = "IdentityArtifactPresent"

        ipv4 = ""
        mac = ""
        vendor = ""
        for address in host.findall("address"):
            addr_type = address.attrib.get("addrtype")
            if addr_type == "ipv4" and not ipv4:
                ipv4 = address.attrib.get("addr", "")
            elif addr_type == "mac" and not mac:
                mac = address.attrib.get("addr", "")
                vendor = address.attrib.get("vendor", "")

        hostnames = [h.attrib.get("name", "") for h in host.findall("hostnames/hostname")]
        dns_name = _safe_join(hostnames)

        open_ports: List[str] = []
        services: List[str] = []
        for port in host.findall("ports/port"):
            state = port.find("state")
            if state is None or state.attrib.get("state") != "open":
                continue
            proto = port.attrib.get("protocol", "tcp")
            port_id = port.attrib.get("portid", "")
            open_ports.append(f"{proto}/{port_id}")
            service = port.find("service")
            if service is not None:
                svc_name = service.attrib.get("name", "")
                product = service.attrib.get("product", "")
                version = service.attrib.get("version", "")
                services.append(_safe_join([f"{proto}/{port_id}", svc_name, product, version]))

        os_matches = [m.attrib.get("name", "") for m in host.findall("os/osmatch")]
        script_identity = _extract_host_identity_from_scripts(host)

        record = IdentityRecord(
            HostAddress=ipv4 or UNKNOWN,
            MacAddress=mac,
            MacVendor=vendor,
            DnsName=dns_name,
            HostIdentity=script_identity.get("HostIdentity", ""),
            DomainOrWorkgroup=script_identity.get("DomainOrWorkgroup", ""),
            DetectedOs=_safe_join(os_matches[:3]),
            OpenPorts=_safe_join(open_ports),
            ServiceSummary=_safe_join(services),
            IdentityArtifactStatus=identity_status,
            SourceArtifactTimestamp=source_timestamp,
            NetworkPosture=network_posture,
            SourceArtifact=str(path),
        )
        _apply_ping_evidence(record, _find_ping(record, ping_evidence))
        record.Classification = _classify(record, network_posture)
        records.append(record)

    return records


def write_csv(records: Sequence[IdentityRecord], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        for record in records:
            writer.writerow(asdict(record))


def write_json(records: Sequence[IdentityRecord], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([asdict(r) for r in records], indent=2), encoding="utf-8")


def write_html(records: Sequence[IdentityRecord], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for record in records:
        row = "".join(f"<td>{html.escape(str(asdict(record)[field]))}</td>" for field in FIELDNAMES)
        rows.append(f"<tr>{row}</tr>")
    header = "".join(f"<th>{html.escape(field)}</th>" for field in FIELDNAMES)
    doc = f"""<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<title>Cybernet Identity Artifact Report</title>
<style>
body {{ font-family: Arial, sans-serif; margin: 24px; }}
table {{ border-collapse: collapse; width: 100%; font-size: 12px; }}
th, td {{ border: 1px solid #bbb; padding: 6px; vertical-align: top; }}
th {{ background: #f2f2f2; position: sticky; top: 0; }}
.note {{ margin-bottom: 16px; padding: 12px; border-left: 4px solid #555; background: #fafafa; }}
</style>
</head>
<body>
<h1>Cybernet Identity Artifact Report</h1>
<div class=\"note\">
<strong>Important:</strong> Identity artifact evidence and cmd ping evidence are separate signals.
This report must not be read as proof that ping succeeded unless <code>CmdPingStatus</code> says so.
</div>
<table>
<thead><tr>{header}</tr></thead>
<tbody>{''.join(rows)}</tbody>
</table>
</body>
</html>
"""
    path.write_text(doc, encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Parse saved Cybernet identity artifacts.")
    parser.add_argument("--input", required=True, type=Path, help="Saved identity artifact XML file")
    parser.add_argument("--out-csv", required=True, type=Path, help="CSV output path")
    parser.add_argument("--out-json", required=True, type=Path, help="JSON output path")
    parser.add_argument("--out-html", type=Path, help="Optional HTML report output path")
    parser.add_argument("--ping-evidence", type=Path, help="Optional JSON ping evidence file")
    parser.add_argument("--network-posture", default="Unknown", help="guest, enterprise, vpn, lab, blocked-policy, etc.")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)
    if not args.input.exists():
        print(f"Input artifact not found: {args.input}", file=sys.stderr)
        return 2
    try:
        ping_evidence = _load_ping_evidence(args.ping_evidence)
        records = parse_artifact(args.input, args.network_posture, ping_evidence)
        write_csv(records, args.out_csv)
        write_json(records, args.out_json)
        if args.out_html:
            write_html(records, args.out_html)
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"Failed to parse artifact: {exc}", file=sys.stderr)
        return 1
    print(f"Parsed {len(records)} host record(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
