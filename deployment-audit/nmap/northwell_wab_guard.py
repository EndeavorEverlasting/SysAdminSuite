#!/usr/bin/env python3
"""
Network guard for the Cybernet / Neuron Nmap probe.

The workbook analysis can run anywhere, but the live Nmap probe must only run
from an approved Northwell WAB network segment. This guard blocks Guest or
unknown networks before Nmap is launched.

No third-party Python packages are required.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

DEFAULT_BLOCK_TERMS = [
    "guest",
    "northwell guest",
    "nh guest",
    "public wifi",
    "visitor",
]

DEFAULT_ALLOW_TERMS = [
    "wab",
]

DEFAULT_CONFIG = {
    "allowed_terms": DEFAULT_ALLOW_TERMS,
    "blocked_terms": DEFAULT_BLOCK_TERMS,
    "allowed_ipv4_cidrs": [],
    "require_allowed_indicator": True,
}


def run_command(args: Sequence[str]) -> str:
    try:
        completed = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=15,
            shell=False,
        )
    except Exception as exc:
        return f"[command failed: {' '.join(args)}] {exc}"
    return (completed.stdout or "") + "\n" + (completed.stderr or "")


def load_config(path: Path | None) -> Dict[str, object]:
    config = dict(DEFAULT_CONFIG)
    if path and path.exists():
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(loaded, dict):
            raise ValueError("Network guard config must be a JSON object")
        config.update(loaded)
    return config


def collect_evidence() -> Dict[str, str]:
    return {
        "computername": os.environ.get("COMPUTERNAME", ""),
        "userdnsdomain": os.environ.get("USERDNSDOMAIN", ""),
        "userdomain": os.environ.get("USERDOMAIN", ""),
        "ipconfig_all": run_command(["ipconfig", "/all"]),
        "wlan_interfaces": run_command(["netsh", "wlan", "show", "interfaces"]),
    }


def flatten_evidence(evidence: Dict[str, str]) -> str:
    return "\n".join(f"[{key}]\n{value}" for key, value in evidence.items()).lower()


def extract_ipv4s(text: str) -> List[str]:
    candidates = re.findall(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)", text)
    out: List[str] = []
    for candidate in candidates:
        try:
            ipaddress.ip_address(candidate)
        except ValueError:
            continue
        out.append(candidate)
    return out


def ip_in_allowed_cidr(text: str, cidrs: Iterable[str]) -> bool:
    networks = []
    for cidr in cidrs:
        cidr = str(cidr).strip()
        if not cidr:
            continue
        try:
            networks.append(ipaddress.ip_network(cidr, strict=False))
        except ValueError:
            continue
    if not networks:
        return False
    for ip_text in extract_ipv4s(text):
        ip = ipaddress.ip_address(ip_text)
        if any(ip in network for network in networks):
            return True
    return False


def term_found(text: str, terms: Iterable[str]) -> bool:
    for term in terms:
        term = str(term).strip().lower()
        if term and term in text:
            return True
    return False


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Block Nmap probe unless running from an approved WAB network.")
    parser.add_argument("--config", default="", help="Optional local JSON config with approved WAB indicators")
    parser.add_argument("--write-evidence", default="", help="Optional local evidence file for troubleshooting")
    args = parser.parse_args(argv)

    config_path = Path(args.config) if args.config else None
    config = load_config(config_path)
    evidence = collect_evidence()
    text = flatten_evidence(evidence)

    if args.write_evidence:
        out = Path(args.write_evidence)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("\n\n".join(f"## {k}\n{v}" for k, v in evidence.items()), encoding="utf-8")

    blocked_terms = config.get("blocked_terms", DEFAULT_BLOCK_TERMS)
    allowed_terms = config.get("allowed_terms", DEFAULT_ALLOW_TERMS)
    allowed_cidrs = config.get("allowed_ipv4_cidrs", [])
    require_allowed_indicator = bool(config.get("require_allowed_indicator", True))

    if not isinstance(blocked_terms, list) or not isinstance(allowed_terms, list) or not isinstance(allowed_cidrs, list):
        print("Network guard config is invalid: blocked_terms, allowed_terms, and allowed_ipv4_cidrs must be lists.")
        return 2

    if term_found(text, blocked_terms):
        print("BLOCKED: Guest/visitor/public network indicator was detected. Nmap probe will not run.")
        print("Offline workbook duplicate analysis already completed; live probe requires approved Northwell WAB.")
        return 10

    allowed_by_term = term_found(text, allowed_terms)
    allowed_by_cidr = ip_in_allowed_cidr(text, allowed_cidrs)

    if require_allowed_indicator and not (allowed_by_term or allowed_by_cidr):
        print("BLOCKED: Approved Northwell WAB indicator was not detected. Nmap probe will not run.")
        print("Add approved local WAB indicators to northwell_wab_guard.local.json or run from the correct WAB segment.")
        return 11

    print("Network guard passed: approved WAB indicator detected and no Guest indicator found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
