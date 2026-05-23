#!/usr/bin/env python3
"""Analyze Neuron naming conventions from saved network/name evidence.

This tool does not scan the network. It consumes saved evidence such as nmap XML,
text lists, or CSV exports, then reports occupied names, sequence gaps, and next
available candidates for site naming conventions such as LIJ-MACH-A or CCMC-MACH-AA.

Generated outputs may contain operational hostnames and should not be committed.
"""
from __future__ import annotations

import argparse
import csv
import html
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


SUMMARY_FIELDS = [
    "ConventionPrefix",
    "UsedCount",
    "HighestUsedName",
    "HighestUsedSuffix",
    "HighestUsedOrdinal",
    "FirstGapName",
    "FirstGapSuffix",
    "FirstGapOrdinal",
    "NextAfterHighestName",
    "NextAfterHighestSuffix",
    "NextAfterHighestOrdinal",
    "GapCandidates",
    "NextCandidates",
    "EvidenceSources",
    "Notes",
]

DETAIL_FIELDS = [
    "ConventionPrefix",
    "RecordType",
    "Name",
    "Suffix",
    "Ordinal",
    "ObservedAs",
    "EvidenceSource",
    "Notes",
]


@dataclass(frozen=True)
class NameEvidence:
    convention_prefix: str
    name: str
    suffix: str
    ordinal: int
    observed_as: str
    evidence_source: str


def clean(value: object) -> str:
    return str(value or "").strip()


def normalize_prefix(value: str) -> str:
    value = clean(value).upper()
    if not value:
        raise ValueError("Convention prefix cannot be blank")
    return value


def suffix_to_ordinal(suffix: str) -> int:
    suffix = clean(suffix).upper()
    if not suffix or not re.fullmatch(r"[A-Z]+", suffix):
        raise ValueError(f"Invalid alphabetic suffix: {suffix!r}")
    value = 0
    for char in suffix:
        value = value * 26 + (ord(char) - ord("A") + 1)
    return value


def ordinal_to_suffix(value: int) -> str:
    if value < 1:
        raise ValueError("Ordinal must be >= 1")
    chars: list[str] = []
    while value:
        value, rem = divmod(value - 1, 26)
        chars.append(chr(ord("A") + rem))
    return "".join(reversed(chars))


def find_convention_names(text: str, prefixes: list[str], source: str) -> list[NameEvidence]:
    observed = clean(text)
    upper = observed.upper()
    rows: list[NameEvidence] = []
    for prefix in prefixes:
        pattern = re.compile(rf"(?<![A-Z0-9])({re.escape(prefix)})([A-Z]+)(?![A-Z0-9])")
        for match in pattern.finditer(upper):
            suffix = match.group(2)
            ordinal = suffix_to_ordinal(suffix)
            name = f"{prefix}{suffix}"
            rows.append(
                NameEvidence(
                    convention_prefix=prefix,
                    name=name,
                    suffix=suffix,
                    ordinal=ordinal,
                    observed_as=observed,
                    evidence_source=source,
                )
            )
    return rows


def parse_nmap_xml(path: Path, prefixes: list[str]) -> list[NameEvidence]:
    root = ET.parse(path).getroot()
    rows: list[NameEvidence] = []
    for host in root.findall("host"):
        hostnames = host.find("hostnames")
        if hostnames is None:
            continue
        for hostname in hostnames.findall("hostname"):
            value = clean(hostname.get("name"))
            if value:
                rows.extend(find_convention_names(value, prefixes, str(path)))
    return rows


def parse_textish(path: Path, prefixes: list[str]) -> list[NameEvidence]:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    return find_convention_names(text, prefixes, str(path))


def parse_csv(path: Path, prefixes: list[str]) -> list[NameEvidence]:
    rows: list[NameEvidence] = []
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames:
            for row in reader:
                for value in row.values():
                    rows.extend(find_convention_names(clean(value), prefixes, str(path)))
        else:
            handle.seek(0)
            for raw in handle:
                rows.extend(find_convention_names(raw, prefixes, str(path)))
    return rows


def load_evidence(prefixes: list[str], nmap_xml: list[Path], used_names: list[Path]) -> list[NameEvidence]:
    rows: list[NameEvidence] = []
    for path in nmap_xml:
        if not path.exists():
            raise FileNotFoundError(f"nmap XML not found: {path}")
        rows.extend(parse_nmap_xml(path, prefixes))
    for path in used_names:
        if not path.exists():
            raise FileNotFoundError(f"used-name evidence not found: {path}")
        if path.suffix.lower() == ".csv":
            rows.extend(parse_csv(path, prefixes))
        else:
            rows.extend(parse_textish(path, prefixes))
    return rows


def first_missing(used_ordinals: set[int], start: int = 1) -> int:
    value = start
    while value in used_ordinals:
        value += 1
    return value


def build_outputs(
    *,
    prefixes: list[str],
    evidence: list[NameEvidence],
    candidate_count: int,
    max_gap_scan: int,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    by_prefix: dict[str, dict[int, list[NameEvidence]]] = {prefix: defaultdict(list) for prefix in prefixes}
    for row in evidence:
        by_prefix[row.convention_prefix][row.ordinal].append(row)

    summaries: list[dict[str, str]] = []
    details: list[dict[str, str]] = []

    for prefix in prefixes:
        ordinal_map = by_prefix[prefix]
        used = set(ordinal_map.keys())
        highest = max(used) if used else 0
        highest_suffix = ordinal_to_suffix(highest) if highest else ""
        highest_name = f"{prefix}{highest_suffix}" if highest else ""
        first_gap = first_missing(used, 1)
        first_gap_suffix = ordinal_to_suffix(first_gap)
        next_after_highest = highest + 1 if highest else 1
        next_after_highest_suffix = ordinal_to_suffix(next_after_highest)

        gap_candidates: list[int] = []
        scan_limit = max(highest, first_gap)
        if max_gap_scan > 0:
            scan_limit = min(scan_limit, max_gap_scan)
        for value in range(1, scan_limit + 1):
            if value not in used:
                gap_candidates.append(value)
            if len(gap_candidates) >= candidate_count:
                break

        next_candidates = list(range(next_after_highest, next_after_highest + candidate_count))
        sources = sorted({item.evidence_source for items in ordinal_map.values() for item in items})

        summaries.append(
            {
                "ConventionPrefix": prefix,
                "UsedCount": str(len(used)),
                "HighestUsedName": highest_name,
                "HighestUsedSuffix": highest_suffix,
                "HighestUsedOrdinal": str(highest) if highest else "",
                "FirstGapName": f"{prefix}{first_gap_suffix}",
                "FirstGapSuffix": first_gap_suffix,
                "FirstGapOrdinal": str(first_gap),
                "NextAfterHighestName": f"{prefix}{next_after_highest_suffix}",
                "NextAfterHighestSuffix": next_after_highest_suffix,
                "NextAfterHighestOrdinal": str(next_after_highest),
                "GapCandidates": ";".join(f"{prefix}{ordinal_to_suffix(value)}" for value in gap_candidates),
                "NextCandidates": ";".join(f"{prefix}{ordinal_to_suffix(value)}" for value in next_candidates),
                "EvidenceSources": ";".join(sources),
                "Notes": "FirstGap preserves naming continuity. NextAfterHighest avoids reuse when stale AD/DNS objects may exist.",
            }
        )

        for ordinal in sorted(used):
            suffix = ordinal_to_suffix(ordinal)
            for item in ordinal_map[ordinal]:
                details.append(
                    {
                        "ConventionPrefix": prefix,
                        "RecordType": "OCCUPIED",
                        "Name": f"{prefix}{suffix}",
                        "Suffix": suffix,
                        "Ordinal": str(ordinal),
                        "ObservedAs": item.observed_as,
                        "EvidenceSource": item.evidence_source,
                        "Notes": "Observed in supplied evidence",
                    }
                )

        for ordinal in gap_candidates:
            suffix = ordinal_to_suffix(ordinal)
            details.append(
                {
                    "ConventionPrefix": prefix,
                    "RecordType": "AVAILABLE_GAP",
                    "Name": f"{prefix}{suffix}",
                    "Suffix": suffix,
                    "Ordinal": str(ordinal),
                    "ObservedAs": "",
                    "EvidenceSource": "computed",
                    "Notes": "Available within observed sequence gap",
                }
            )

        for ordinal in next_candidates:
            suffix = ordinal_to_suffix(ordinal)
            details.append(
                {
                    "ConventionPrefix": prefix,
                    "RecordType": "AVAILABLE_AFTER_HIGHEST",
                    "Name": f"{prefix}{suffix}",
                    "Suffix": suffix,
                    "Ordinal": str(ordinal),
                    "ObservedAs": "",
                    "EvidenceSource": "computed",
                    "Notes": "Available after highest observed suffix",
                }
            )

    return summaries, details


def write_csv(path: Path, rows: list[dict[str, str]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def e(value: object) -> str:
    return html.escape(str(value or ""))


def render_dashboard(summary_rows: list[dict[str, str]], detail_rows: list[dict[str, str]], source_note: str) -> str:
    cards = []
    for row in summary_rows:
        cards.append(
            f"""
<article class="card">
  <h2>{e(row['ConventionPrefix'])}</h2>
  <p><span>Used</span><strong>{e(row['UsedCount'])}</strong></p>
  <p><span>First gap</span><b class="good">{e(row['FirstGapName'])}</b></p>
  <p><span>Next after highest</span><b class="info">{e(row['NextAfterHighestName'])}</b></p>
  <p><span>Highest observed</span><b>{e(row['HighestUsedName'])}</b></p>
</article>"""
        )
    head = "".join(f"<th>{e(col)}</th>" for col in DETAIL_FIELDS)
    body = []
    for row in detail_rows:
        cls = row.get("RecordType", "").lower().replace("_", "-")
        cells = "".join(f"<td>{e(row.get(col, ''))}</td>" for col in DETAIL_FIELDS)
        body.append(f'<tr class="{cls}">{cells}</tr>')
    return f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SysAdminSuite Neuron Name Availability</title>
<style>
:root{{--bg:#020617;--panel:#0f172a;--text:#e5e7eb;--muted:#94a3b8;--green:#22c55e;--cyan:#22d3ee;--yellow:#facc15;--red:#f87171;}}
*{{box-sizing:border-box}} body{{margin:0;background:radial-gradient(circle at top left,rgba(34,211,238,.18),transparent 34%),linear-gradient(180deg,#020617,#111827,#020617);color:var(--text);font-family:Segoe UI,Arial,sans-serif}}
header{{padding:28px 34px;background:rgba(2,6,23,.92);border-bottom:1px solid rgba(96,165,250,.3)}} main{{padding:24px 34px 70px}}
h1{{margin:0}} header p{{color:var(--muted)}} .cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px;margin-bottom:18px}}
.card,.panel,.notice{{border:1px solid rgba(96,165,250,.28);background:rgba(15,23,42,.88);border-radius:18px;padding:16px;box-shadow:0 0 28px rgba(34,211,238,.09)}}
.card h2{{margin:0 0 12px}} .card p{{display:flex;justify-content:space-between;gap:12px;color:var(--muted)}} .card strong{{font-size:28px;color:var(--text)}} .good{{color:#bbf7d0}} .info{{color:#cffafe}}
.notice{{margin-bottom:18px;color:#dbeafe}} .filter{{width:100%;margin:0 0 12px;padding:10px;border-radius:12px;background:#020617;color:var(--text);border:1px solid rgba(96,165,250,.28)}}
.table-wrap{{overflow:auto;max-height:650px;border:1px solid rgba(51,65,85,.8);border-radius:14px}} table{{width:100%;min-width:1400px;border-collapse:collapse}} th,td{{padding:9px 10px;border-bottom:1px solid rgba(51,65,85,.75);text-align:left;vertical-align:top;font-size:13px}} th{{position:sticky;top:0;background:#020617;color:#bfdbfe}}
.available-gap td:first-child,.available-gap td:nth-child(3){{color:#bbf7d0}} .available-after-highest td:first-child,.available-after-highest td:nth-child(3){{color:#cffafe}} .occupied td:first-child,.occupied td:nth-child(3){{color:#fef3c7}}
</style>
</head>
<body>
<header><h1>SysAdminSuite Neuron Name Availability</h1><p>{e(source_note)}</p></header>
<main>
<div class="notice">Local operational artifact. Validate against AD/DNS before renaming production devices. Network survey evidence can miss stale objects.</div>
<section class="cards">{''.join(cards)}</section>
<section class="panel"><h2>Name Detail</h2><input class="filter" placeholder="Filter names, sites, statuses, sources"><div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table></div></section>
</main>
<script>const input=document.querySelector('.filter');const rows=document.querySelectorAll('tbody tr');input.addEventListener('input',()=>{{const n=input.value.toLowerCase();for(const r of rows)r.style.display=r.innerText.toLowerCase().includes(n)?'':'none';}});</script>
</body>
</html>"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze Neuron naming convention availability from saved evidence.")
    parser.add_argument("--convention", action="append", required=True, help="Naming prefix, e.g. LIJ-MACH- or CCMC-MACH-. Repeatable.")
    parser.add_argument("--nmap-xml", action="append", default=[], help="Saved nmap XML artifact. Repeatable.")
    parser.add_argument("--used-names", action="append", default=[], help="Text or CSV evidence containing known used names. Repeatable.")
    parser.add_argument("--summary-output", default="survey/output/neuron_name_availability_summary.csv")
    parser.add_argument("--detail-output", default="survey/output/neuron_name_availability_detail.csv")
    parser.add_argument("--dashboard", default="", help="Optional HTML dashboard output path")
    parser.add_argument("--candidate-count", type=int, default=10, help="How many gap/next candidates to report per convention")
    parser.add_argument("--max-gap-scan", type=int, default=5000, help="Max ordinal to scan for gaps. Use 0 to scan through highest observed.")
    args = parser.parse_args()

    prefixes = []
    for value in args.convention:
        prefix = normalize_prefix(value)
        if prefix not in prefixes:
            prefixes.append(prefix)

    if args.candidate_count < 1:
        print("ERROR: --candidate-count must be >= 1", file=sys.stderr)
        return 2

    if not args.nmap_xml and not args.used_names:
        print("ERROR: supply at least one --nmap-xml or --used-names evidence file", file=sys.stderr)
        return 2

    evidence = load_evidence(prefixes, [Path(p) for p in args.nmap_xml], [Path(p) for p in args.used_names])
    summaries, details = build_outputs(
        prefixes=prefixes,
        evidence=evidence,
        candidate_count=args.candidate_count,
        max_gap_scan=args.max_gap_scan,
    )

    summary_path = Path(args.summary_output)
    detail_path = Path(args.detail_output)
    write_csv(summary_path, summaries, SUMMARY_FIELDS)
    write_csv(detail_path, details, DETAIL_FIELDS)

    print(f"Wrote naming summary: {summary_path}")
    print(f"Wrote naming detail: {detail_path}")

    if args.dashboard:
        dashboard_path = Path(args.dashboard)
        dashboard_path.parent.mkdir(parents=True, exist_ok=True)
        source_note = "Evidence: " + "; ".join(args.nmap_xml + args.used_names)
        dashboard_path.write_text(render_dashboard(summaries, details, source_note), encoding="utf-8")
        print(f"Wrote naming dashboard: {dashboard_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
