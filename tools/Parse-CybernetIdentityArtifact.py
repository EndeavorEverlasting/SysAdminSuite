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
from collections import Counter
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
    if record.IdentityArtifactStatus == "IdentityArtifactPresent" and (
        ping in {"failed", "failure", "timeout"} or ("failed" in ping and "succeed" in ping)
    ):
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


def _counter(records: Sequence[IdentityRecord], field: str) -> Counter[str]:
    return Counter(str(asdict(record).get(field) or UNKNOWN) for record in records)


def _badge_class(value: str) -> str:
    lowered = value.lower()
    if "ok" in lowered or "present" in lowered or "resolved" in lowered:
        return "good"
    if "transient" in lowered or "inconclusive" in lowered or "failedthen" in lowered:
        return "warn"
    if "blocked" in lowered or "failed" in lowered or "down" in lowered:
        return "bad"
    return "neutral"


def _render_badge(value: str) -> str:
    safe = html.escape(value or UNKNOWN)
    return f'<span class="badge {_badge_class(value)}">{safe}</span>'


def _render_bar_chart(title: str, counts: Counter[str]) -> str:
    total = sum(counts.values()) or 1
    bars: List[str] = []
    for label, count in counts.most_common():
        width = max(4, round((count / total) * 100))
        safe_label = html.escape(label)
        bars.append(
            f"""
            <div class="bar-row">
              <div class="bar-label">{safe_label}</div>
              <div class="bar-track"><div class="bar-fill {_badge_class(label)}" style="width:{width}%"></div></div>
              <div class="bar-count">{count}</div>
            </div>
            """
        )
    return f"""
    <section class="panel">
      <h2>{html.escape(title)}</h2>
      <div class="bars">{''.join(bars)}</div>
    </section>
    """


def _render_metric(label: str, value: str, tone: str = "neutral") -> str:
    return f"""
    <div class="metric {tone}">
      <div class="metric-label">{html.escape(label)}</div>
      <div class="metric-value">{html.escape(value)}</div>
    </div>
    """


def write_html(records: Sequence[IdentityRecord], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    total_hosts = len(records)
    identity_present = sum(1 for r in records if r.IdentityArtifactStatus == "IdentityArtifactPresent")
    transient = sum(1 for r in records if "TRANSIENT" in r.Classification)
    blocked = sum(1 for r in records if "BLOCKED" in r.Classification)
    ok = sum(1 for r in records if r.Classification.startswith("OK"))
    unique_vendors = len({r.MacVendor for r in records if r.MacVendor})
    source_artifacts = sorted({r.SourceArtifact for r in records if r.SourceArtifact})

    rows = []
    for record in records:
        data = asdict(record)
        cells = []
        for field in FIELDNAMES:
            value = str(data[field])
            if field in {"Classification", "IdentityArtifactStatus", "CmdPingStatus", "NameResolutionStatus"}:
                cells.append(f"<td>{_render_badge(value)}</td>")
            else:
                cells.append(f"<td>{html.escape(value)}</td>")
        rows.append(f"<tr>{''.join(cells)}</tr>")

    header = "".join(f"<th>{html.escape(field)}</th>" for field in FIELDNAMES)
    classification_panel = _render_bar_chart("Classification Mix", _counter(records, "Classification"))
    ping_panel = _render_bar_chart("Ping Evidence", _counter(records, "CmdPingStatus"))
    identity_panel = _render_bar_chart("Identity Artifact Status", _counter(records, "IdentityArtifactStatus"))
    posture_panel = _render_bar_chart("Network Posture", _counter(records, "NetworkPosture"))
    artifact_list = "".join(f"<li>{html.escape(item)}</li>" for item in source_artifacts) or "<li>Unknown</li>"

    doc = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cybernet Identity Deploy Axis</title>
<style>
:root {{
  --bg: #071014;
  --panel: rgba(12, 28, 34, 0.88);
  --panel-strong: rgba(18, 42, 50, 0.96);
  --text: #e8fbff;
  --muted: #8fb6c0;
  --grid: rgba(111, 238, 255, 0.13);
  --cyan: #49e6ff;
  --green: #72ff9d;
  --amber: #ffd166;
  --red: #ff6b7a;
  --violet: #b68cff;
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  color: var(--text);
  background:
    radial-gradient(circle at top left, rgba(73, 230, 255, 0.24), transparent 32rem),
    radial-gradient(circle at bottom right, rgba(114, 255, 157, 0.14), transparent 30rem),
    linear-gradient(135deg, #04080a 0%, var(--bg) 48%, #0c141a 100%);
  font-family: Inter, Segoe UI, Arial, sans-serif;
}}
body::before {{
  content: "";
  position: fixed;
  inset: 0;
  pointer-events: none;
  background-image:
    linear-gradient(var(--grid) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid) 1px, transparent 1px);
  background-size: 42px 42px;
  mask-image: linear-gradient(to bottom, rgba(0,0,0,0.75), transparent);
}}
.page {{ padding: 32px; position: relative; z-index: 1; }}
.hero {{
  border: 1px solid rgba(73, 230, 255, 0.28);
  border-radius: 28px;
  padding: 28px;
  background: linear-gradient(135deg, rgba(11, 30, 36, 0.96), rgba(6, 18, 24, 0.9));
  box-shadow: 0 0 32px rgba(73, 230, 255, 0.16), inset 0 0 28px rgba(73, 230, 255, 0.05);
}}
.kicker {{
  color: var(--cyan);
  letter-spacing: 0.22em;
  text-transform: uppercase;
  font-size: 12px;
  font-weight: 800;
}}
h1 {{ margin: 8px 0 8px; font-size: clamp(32px, 5vw, 58px); line-height: 1; }}
.subtitle {{ max-width: 920px; color: var(--muted); font-size: 16px; line-height: 1.55; }}
.metrics {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 16px; margin: 22px 0; }}
.metric {{
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 22px;
  padding: 18px;
  background: rgba(255, 255, 255, 0.045);
  box-shadow: inset 0 0 16px rgba(255,255,255,0.03);
}}
.metric.good {{ box-shadow: 0 0 18px rgba(114, 255, 157, 0.18), inset 0 0 14px rgba(114, 255, 157, 0.04); }}
.metric.warn {{ box-shadow: 0 0 18px rgba(255, 209, 102, 0.16), inset 0 0 14px rgba(255, 209, 102, 0.04); }}
.metric.bad {{ box-shadow: 0 0 18px rgba(255, 107, 122, 0.16), inset 0 0 14px rgba(255, 107, 122, 0.04); }}
.metric-label {{ color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em; }}
.metric-value {{ margin-top: 8px; font-size: 30px; font-weight: 850; }}
.notice {{
  border-left: 4px solid var(--amber);
  border-radius: 16px;
  padding: 16px;
  background: rgba(255, 209, 102, 0.08);
  color: #fff6d6;
  margin-top: 18px;
}}
.dashboard {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 18px; margin: 24px 0; }}
.panel {{
  border: 1px solid rgba(73, 230, 255, 0.18);
  border-radius: 24px;
  padding: 20px;
  background: var(--panel);
  box-shadow: 0 0 22px rgba(73, 230, 255, 0.09);
}}
.panel h2 {{ margin: 0 0 16px; font-size: 18px; }}
.bar-row {{ display: grid; grid-template-columns: minmax(120px, 1fr) 2fr 42px; gap: 10px; align-items: center; margin: 12px 0; }}
.bar-label {{ color: var(--muted); overflow-wrap: anywhere; font-size: 12px; }}
.bar-track {{ height: 12px; border-radius: 999px; background: rgba(255,255,255,0.08); overflow: hidden; }}
.bar-fill {{ height: 100%; border-radius: 999px; box-shadow: 0 0 14px currentColor; }}
.bar-fill.good {{ background: var(--green); color: var(--green); }}
.bar-fill.warn {{ background: var(--amber); color: var(--amber); }}
.bar-fill.bad {{ background: var(--red); color: var(--red); }}
.bar-fill.neutral {{ background: var(--cyan); color: var(--cyan); }}
.bar-count {{ text-align: right; font-weight: 800; }}
.badge {{
  display: inline-flex;
  align-items: center;
  border-radius: 999px;
  padding: 5px 10px;
  font-size: 11px;
  font-weight: 800;
  letter-spacing: 0.04em;
  white-space: nowrap;
}}
.badge.good {{ color: #031b0d; background: var(--green); box-shadow: 0 0 14px rgba(114,255,157,0.42); }}
.badge.warn {{ color: #251900; background: var(--amber); box-shadow: 0 0 14px rgba(255,209,102,0.42); }}
.badge.bad {{ color: #2b0007; background: var(--red); box-shadow: 0 0 14px rgba(255,107,122,0.42); }}
.badge.neutral {{ color: #001a20; background: var(--cyan); box-shadow: 0 0 14px rgba(73,230,255,0.38); }}
.table-wrap {{ overflow-x: auto; border-radius: 24px; border: 1px solid rgba(73,230,255,0.18); box-shadow: 0 0 24px rgba(73,230,255,0.08); }}
table {{ border-collapse: collapse; min-width: 1900px; width: 100%; font-size: 12px; background: rgba(5, 16, 22, 0.92); }}
th, td {{ border-bottom: 1px solid rgba(255,255,255,0.08); padding: 11px 12px; vertical-align: top; }}
th {{
  background: var(--panel-strong);
  color: var(--cyan);
  position: sticky;
  top: 0;
  z-index: 2;
  text-align: left;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  font-size: 11px;
}}
tr:hover td {{ background: rgba(73, 230, 255, 0.055); }}
.artifacts ul {{ margin: 0; padding-left: 18px; color: var(--muted); }}
.footer {{ color: var(--muted); margin-top: 18px; font-size: 12px; }}
code {{ color: var(--green); }}
</style>
</head>
<body>
<div class="page">
  <section class="hero">
    <div class="kicker">Deploy Axis / Cybernet Identity</div>
    <h1>Artifact Intelligence Dashboard</h1>
    <div class="subtitle">
      Identity artifact evidence and cmd ping evidence are separate signals. This report must not be read as proof that ping succeeded unless <code>CmdPingStatus</code> says so.
    </div>
    <div class="metrics">
      {_render_metric("Total Hosts", str(total_hosts), "neutral")}
      {_render_metric("Identity Present", str(identity_present), "good")}
      {_render_metric("Clean OK", str(ok), "good")}
      {_render_metric("Transient", str(transient), "warn")}
      {_render_metric("Blocked", str(blocked), "bad")}
      {_render_metric("Vendors", str(unique_vendors), "neutral")}
    </div>
    <div class="notice">
      OPR338 rule: a device can provide identity evidence while cmd ping is failed, missing, delayed, or later successful. The dashboard keeps those facts apart.
    </div>
  </section>

  <section class="dashboard">
    {classification_panel}
    {ping_panel}
    {identity_panel}
    {posture_panel}
  </section>

  <section class="panel artifacts">
    <h2>Source Artifacts</h2>
    <ul>{artifact_list}</ul>
  </section>

  <section class="panel">
    <h2>Detailed Records</h2>
    <div class="table-wrap">
      <table>
        <thead><tr>{header}</tr></thead>
        <tbody>{''.join(rows)}</tbody>
      </table>
    </div>
  </section>

  <div class="footer">Generated {html.escape(generated_at)} UTC by parser version {html.escape(PARSER_VERSION)}.</div>
</div>
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
