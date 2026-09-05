#!/usr/bin/env python3
"""Filter existing Naabu evidence to dual-port Windows-PC signature candidates.

This script performs no network activity. It accepts Naabu JSON/JSONL or host:port text,
aggregates observed ports per host, and emits only hosts with both TCP 135 and TCP 445.
That two-port posture is a candidate gate only; it is not proof of Cybernet identity or
Windows workstation class.
"""
from __future__ import annotations

import argparse
import csv
import ipaddress
import json
from pathlib import Path
from typing import Iterable

REQUIRED_PORTS = {135, 445}


def split_host_port(value: str) -> tuple[str, int | None]:
    text = value.strip()
    if not text:
        return "", None
    if text.startswith("[") and "]:" in text:
        host, port_text = text.rsplit(":", 1)
        host = host.strip("[]")
    elif ":" in text:
        try:
            ipaddress.ip_address(text)
            return text, None
        except ValueError:
            host, port_text = text.rsplit(":", 1)
    else:
        return text, None
    try:
        return host.strip(), int(port_text)
    except ValueError:
        return host.strip(), None


def iter_json_items(text: str) -> Iterable[dict]:
    stripped = text.strip()
    if not stripped:
        return []
    try:
        data = json.loads(stripped)
    except json.JSONDecodeError:
        items = []
        for line in stripped.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                items.append(item)
        return items
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    return [data] if isinstance(data, dict) else []


def read_observations(path: Path) -> list[tuple[str, int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    observations: list[tuple[str, int]] = []
    if path.suffix.lower() in {".json", ".jsonl"}:
        for item in iter_json_items(text):
            host = str(item.get("host") or item.get("ip") or "").strip().strip("[]")
            try:
                port = int(item.get("port"))
            except (TypeError, ValueError):
                continue
            if host:
                observations.append((host, port))
        return observations

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        host, port = split_host_port(line)
        if host and port is not None:
            observations.append((host, port))
    return observations


def classify(ports: set[int]) -> str:
    if REQUIRED_PORTS.issubset(ports):
        return "WINDOWS_PC_SIGNATURE_MATCH"
    if 135 in ports:
        return "RPC_ONLY"
    if 445 in ports:
        return "SMB_ONLY"
    return "NO_WINDOWS_PC_SIGNATURE"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Filter existing Naabu evidence to hosts with both TCP 135 and 445."
    )
    parser.add_argument("--input", required=True, type=Path, help="Naabu JSON/JSONL or host:port text")
    parser.add_argument("--candidates-out", required=True, type=Path, help="One matched host per line")
    parser.add_argument("--report-out", required=True, type=Path, help="Local CSV classification report")
    args = parser.parse_args()

    if not args.input.is_file():
        parser.error(f"input does not exist: {args.input}")

    ports_by_host: dict[str, set[int]] = {}
    display_by_key: dict[str, str] = {}
    order: list[str] = []
    for host, port in read_observations(args.input):
        key = host.lower()
        if key not in ports_by_host:
            ports_by_host[key] = set()
            display_by_key[key] = host
            order.append(key)
        ports_by_host[key].add(port)

    matched = [display_by_key[key] for key in order if REQUIRED_PORTS.issubset(ports_by_host[key])]

    args.candidates_out.parent.mkdir(parents=True, exist_ok=True)
    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    args.candidates_out.write_text("".join(f"{host}\n" for host in matched), encoding="utf-8")

    with args.report_out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["Host", "Port135", "Port445", "SignatureStatus", "ObservedPorts"],
        )
        writer.writeheader()
        for key in order:
            ports = ports_by_host[key]
            writer.writerow(
                {
                    "Host": display_by_key[key],
                    "Port135": "Open" if 135 in ports else "NotObserved",
                    "Port445": "Open" if 445 in ports else "NotObserved",
                    "SignatureStatus": classify(ports),
                    "ObservedPorts": ";".join(str(port) for port in sorted(ports)),
                }
            )

    print(
        f"PC signature filter: {len(matched)} matched / {len(order)} observed hosts; "
        f"candidates={args.candidates_out}; report={args.report_out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
