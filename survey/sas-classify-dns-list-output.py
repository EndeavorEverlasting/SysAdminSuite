#!/usr/bin/env python3
"""Classify Nmap -sL (dns-list-only) output into infrastructure vs discovery rows.

Read-only local enrichment for subnet discovery lane. Does not scan networks.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import re
import sys
from pathlib import Path


def _load_classifier():
    module_path = Path(__file__).with_name("sas-survey-device-classify.py")
    spec = importlib.util.spec_from_file_location("sas_survey_device_classify", module_path)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load classifier module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_CLASSIFY = _load_classifier()

OUTPUT_FIELDS = [
    "HostName",
    "IPAddress",
    "Subnet",
    "SurveyLane",
    "IdentifierType",
    "SurveyAuthority",
    "DeviceRole",
    "RoleConfidence",
    "RoleSignals",
    "CountsTowardCybernetPopulation",
    "NextAction",
    "SourceFile",
]

REPORT_RE = re.compile(r"^Nmap scan report for\s+(.+)$", re.IGNORECASE)
IP_PAREN_RE = re.compile(r"^(.*?)\s+\(([^)]+)\)$")


def clean(value: object) -> str:
    return str(value or "").strip()


def parse_nmap_list_file(path: Path, subnet: str = "") -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = REPORT_RE.match(line.strip())
        if not m:
            continue
        raw = clean(m.group(1))
        hostname = ""
        ip = raw
        p = IP_PAREN_RE.match(raw)
        if p:
            hostname = clean(p.group(1))
            ip = clean(p.group(2))
        host = hostname or ip
        if not host or host.lower() in {"localhost", "(none)"}:
            continue
        cls = _CLASSIFY.classify_device(
            hostname=host,
            reverse_dns_names=hostname,
            survey_lane="subnet_discovery",
            in_manifest=False,
        )
        row = {
            "HostName": hostname or ip,
            "IPAddress": ip if ip != hostname else "",
            "Subnet": subnet,
            "SourceFile": path.name,
            **cls.as_dict(),
        }
        rows.append(row)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify Nmap -sL dns-list output for subnet discovery lane")
    parser.add_argument("--input", action="append", required=True, help="Nmap -sL text output; repeatable")
    parser.add_argument("--subnet", action="append", default=[], help="Subnet label per input file (optional)")
    parser.add_argument("--output", default="survey/output/dns_infrastructure_classification.csv", help="Classification CSV")
    args = parser.parse_args()

    inputs = [Path(p) for p in args.input]
    subnets = list(args.subnet)
    while len(subnets) < len(inputs):
        subnets.append("")

    all_rows: list[dict[str, str]] = []
    for path, subnet in zip(inputs, subnets):
        if not path.exists():
            print(f"WARN: input not found: {path}", file=sys.stderr)
            continue
        all_rows.extend(parse_nmap_list_file(path, subnet=subnet))

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(all_rows)

    infra = sum(1 for r in all_rows if r.get("DeviceRole", "").startswith("infrastructure_"))
    print(f"Wrote {len(all_rows)} classification row(s) to {out} ({infra} infrastructure)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
