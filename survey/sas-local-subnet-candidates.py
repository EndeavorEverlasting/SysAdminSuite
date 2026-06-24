#!/usr/bin/env python3
"""Build approved IPv4 subnet candidates from Windows ipconfig output or explicit CIDRs.

This read-only helper does not contact remote hosts. It only normalizes local
adapter configuration into candidate CIDRs for authorized asset inventory work.
Generated files may contain operational network details and should stay local.
"""
from __future__ import annotations

import argparse
import csv
import ipaddress
import re
import sys
from pathlib import Path

FIELDS = ["Adapter", "IPv4Address", "SubnetMask", "DirectCIDR", "CandidateCIDR", "Source", "Notes"]


def usable_ipv4(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(str(value).strip())
    except ValueError:
        return False
    return isinstance(ip, ipaddress.IPv4Address) and not (
        ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_unspecified
    )


def direct_network(ip: str, mask: str) -> ipaddress.IPv4Network:
    prefix = ipaddress.IPv4Network(f"0.0.0.0/{mask}").prefixlen
    return ipaddress.ip_network(f"{ip}/{prefix}", strict=False)


def parse_ipconfig(path: Path) -> list[dict[str, str]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    adapter = "Unknown Adapter"
    pending_ip = ""
    rows: list[dict[str, str]] = []

    adapter_re = re.compile(r"^[^\s].*:\s*$")
    ipv4_re = re.compile(r"IPv4 Address[^:]*:\s*([^\r\n(]+)", re.IGNORECASE)
    mask_re = re.compile(r"Subnet Mask[^:]*:\s*([^\r\n]+)", re.IGNORECASE)

    for raw in text.splitlines():
        line = raw.rstrip()
        if adapter_re.match(line):
            adapter = line.strip().rstrip(":")
            pending_ip = ""
            continue
        ip_match = ipv4_re.search(line)
        if ip_match:
            value = ip_match.group(1).split("(")[0].strip()
            pending_ip = value if usable_ipv4(value) else ""
            continue
        mask_match = mask_re.search(line)
        if mask_match and pending_ip:
            mask = mask_match.group(1).split("(")[0].strip()
            if usable_ipv4(mask):
                try:
                    net = direct_network(pending_ip, mask)
                except Exception:
                    pending_ip = ""
                    continue
                rows.append(
                    {
                        "Adapter": adapter,
                        "IPv4Address": pending_ip,
                        "SubnetMask": mask,
                        "DirectCIDR": str(net),
                        "Source": f"ipconfig:{path}",
                    }
                )
            pending_ip = ""
    return rows


def explicit_rows(cidrs: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for cidr in cidrs:
        try:
            net = ipaddress.ip_network(cidr, strict=False)
        except ValueError as exc:
            raise SystemExit(f"ERROR: invalid --cidr value {cidr!r}: {exc}") from exc
        if not isinstance(net, ipaddress.IPv4Network):
            raise SystemExit(f"ERROR: IPv6 is not supported by this field helper: {cidr}")
        if net.is_loopback or net.is_link_local or net.is_multicast or net.is_unspecified:
            raise SystemExit(f"ERROR: special-use CIDR is not valid field scope: {cidr}")
        rows.append(
            {
                "Adapter": "ExplicitCIDR",
                "IPv4Address": str(net.network_address),
                "SubnetMask": str(net.netmask),
                "DirectCIDR": str(net),
                "Source": "explicit_cidr",
            }
        )
    return rows


def candidate_networks(net: ipaddress.IPv4Network, local_ip: str, chunk_prefix: int, max_chunks: int) -> list[tuple[str, str]]:
    if net.prefixlen >= chunk_prefix:
        return [(str(net), "direct")]
    chunks = list(net.subnets(new_prefix=chunk_prefix))
    if len(chunks) <= max_chunks:
        return [(str(chunk), f"chunked_from={net}") for chunk in chunks]
    local = ipaddress.ip_address(local_ip)
    for chunk in chunks:
        if local in chunk:
            return [(str(chunk), f"wide_network_local_chunk_only; original={net}; chunks={len(chunks)}")]
    return [(str(net), "direct")]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build IPv4 subnet candidates for authorized SysAdminSuite inventory surveys")
    parser.add_argument("--ipconfig", help="Saved ipconfig /all text")
    parser.add_argument("--cidr", action="append", default=[], help="Approved IPv4 CIDR. Can be repeated.")
    parser.add_argument("--output", required=True, help="Candidate CSV output path")
    parser.add_argument("--list-output", required=True, help="Plain CIDR list output path")
    parser.add_argument("--chunk-prefix", type=int, default=24, help="Chunk wider networks to this prefix. Default: 24")
    parser.add_argument("--max-chunks-per-network", type=int, default=16, help="Maximum chunks emitted from one direct network")
    args = parser.parse_args()

    if args.chunk_prefix < 24 or args.chunk_prefix > 30:
        print("ERROR: --chunk-prefix must be between 24 and 30", file=sys.stderr)
        return 2

    base: list[dict[str, str]] = []
    if args.ipconfig:
        path = Path(args.ipconfig)
        if not path.exists():
            print(f"ERROR: ipconfig file not found: {path}", file=sys.stderr)
            return 2
        base.extend(parse_ipconfig(path))
    base.extend(explicit_rows(args.cidr))
    if not base:
        print("ERROR: no candidate CIDRs found. Provide --cidr or usable --ipconfig.", file=sys.stderr)
        return 2

    seen: set[str] = set()
    out: list[dict[str, str]] = []
    for row in base:
        net = ipaddress.ip_network(row["DirectCIDR"], strict=False)
        for candidate, note in candidate_networks(net, row.get("IPv4Address", str(net.network_address)), args.chunk_prefix, args.max_chunks_per_network):
            if candidate in seen:
                continue
            seen.add(candidate)
            out.append({**row, "CandidateCIDR": candidate, "Notes": note})

    output = Path(args.output)
    list_output = Path(args.list_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    list_output.parent.mkdir(parents=True, exist_ok=True)

    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(out)
    with list_output.open("w", encoding="utf-8") as handle:
        for row in out:
            handle.write(row["CandidateCIDR"] + "\n")

    print(f"Wrote {len(out)} candidate CIDR(s) to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
