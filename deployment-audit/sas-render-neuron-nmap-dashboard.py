#!/usr/bin/env python3
"""Render a polished SysAdminSuite dashboard for Neuron nmap MAC match review output."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
from collections import Counter
from pathlib import Path

DISPLAY_COLS = [
    "MatchStatus",
    "Site",
    "Room",
    "ExpectedMAC",
    "ExpectedSerial",
    "CandidateIP",
    "ObservedHostname",
    "ObservedMAC",
    "EvidenceSource",
    "Notes",
]

STATUS_LABELS = {
    "MAC_MATCH_RESOLVED": "MAC Match Resolved",
    "MAC_NOT_FOUND_IN_NMAP": "MAC Not Found",
    "MAC_CONFLICT_MULTIPLE_IPS": "MAC Conflict",
    "SERIAL_ONLY_NO_MAC": "Serial Only",
    "NO_USABLE_IDENTIFIER": "No Usable Identifier",
}

STATUS_CLASS = {
    "MAC_MATCH_RESOLVED": "good",
    "MAC_NOT_FOUND_IN_NMAP": "warn",
    "MAC_CONFLICT_MULTIPLE_IPS": "bad",
    "SERIAL_ONLY_NO_MAC": "info",
    "NO_USABLE_IDENTIFIER": "off",
}

ORDER = [
    "MAC_MATCH_RESOLVED",
    "MAC_CONFLICT_MULTIPLE_IPS",
    "MAC_NOT_FOUND_IN_NMAP",
    "SERIAL_ONLY_NO_MAC",
    "NO_USABLE_IDENTIFIER",
]


def e(value: object) -> str:
    return html.escape(str(value or ""))


def load_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def chip(value: object, cls: str = "chip") -> str:
    raw = str(value or "")
    slug = e(raw).replace("_", "-").lower()
    return f'<span class="{cls} {slug}">{e(raw)}</span>'


def status_chip(status: str) -> str:
    return f'<span class="status-chip {e(status).replace("_", "-").lower()}">{e(STATUS_LABELS.get(status, status))}</span>'


def table(rows: list[dict[str, str]], title: str, table_id: str) -> str:
    head = "".join(f"<th>{e(col)}</th>" for col in DISPLAY_COLS)
    body = []
    for row in rows:
        status = row.get("MatchStatus", "")
        cells = []
        for col in DISPLAY_COLS:
            value = row.get(col, "")
            if col == "MatchStatus":
                cells.append(f"<td>{status_chip(value)}</td>")
            elif col in {"ExpectedMAC", "ObservedMAC", "CandidateIP"}:
                cells.append(f"<td>{chip(value, 'evidence-chip')}</td>")
            else:
                cells.append(f"<td>{e(value)}</td>")
        body.append(f'<tr class="{STATUS_CLASS.get(status, "")}">' + "".join(cells) + "</tr>")
    return f'''
<section class="panel">
  <div class="panel-head"><h2>{e(title)}</h2><span class="count-chip">{len(rows)} rows</span></div>
  <input class="filter" data-table="{e(table_id)}" placeholder="Filter {e(title)}">
  <div class="table-wrap"><table id="{e(table_id)}"><thead><tr>{head}</tr></thead><tbody>{''.join(body)}</tbody></table></div>
</section>'''


def evidence_cards(rows: list[dict[str, str]]) -> str:
    chosen = [r for r in rows if r.get("MatchStatus") in {"MAC_MATCH_RESOLVED", "MAC_CONFLICT_MULTIPLE_IPS"}][:8]
    cards = []
    for row in chosen:
        status = row.get("MatchStatus", "")
        cls = STATUS_CLASS.get(status, "info")
        cards.append(
            f'''
<article class="identity-card {cls}">
  <div>{status_chip(status)}</div>
  <h3>{e(row.get('CandidateIP') or row.get('ObservedHostname') or row.get('ExpectedMAC'))}</h3>
  <p><b>Site:</b> {e(row.get('Site'))}</p>
  <p><b>Room:</b> {e(row.get('Room'))}</p>
  <p><b>Expected MAC:</b> {chip(row.get('ExpectedMAC'), 'evidence-chip')}</p>
  <p><b>Observed MAC:</b> {chip(row.get('ObservedMAC'), 'evidence-chip')}</p>
  <p><b>Observed Host:</b> {e(row.get('ObservedHostname'))}</p>
  <p><b>Serial:</b> {e(row.get('ExpectedSerial'))}</p>
</article>'''
        )
    return f'''
<section class="panel">
  <div class="panel-head"><h2>Neuron Identity Evidence Cards</h2><span class="count-chip">{len(cards)} cards</span></div>
  <div class="identity-grid">{''.join(cards)}</div>
</section>'''


def render(rows: list[dict[str, str]], source: Path) -> str:
    counts = Counter(row.get("MatchStatus", "NO_USABLE_IDENTIFIER") or "NO_USABLE_IDENTIFIER" for row in rows)
    total = len(rows)
    resolved = counts.get("MAC_MATCH_RESOLVED", 0)
    review_count = total - resolved
    sites = Counter(row.get("Site", "Unknown") or "Unknown" for row in rows)
    generated = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    metrics = f'''
<section class="metrics">
  <article class="metric"><span>Total Rows</span><strong>{total}</strong></article>
  <article class="metric good"><span>Resolved by MAC</span><strong>{resolved}</strong></article>
  <article class="metric bad"><span>MAC Conflicts</span><strong>{counts.get('MAC_CONFLICT_MULTIPLE_IPS', 0)}</strong></article>
  <article class="metric warn"><span>Review Items</span><strong>{review_count}</strong></article>
  <article class="metric info"><span>Serial Only</span><strong>{counts.get('SERIAL_ONLY_NO_MAC', 0)}</strong></article>
</section>'''

    status_list = "".join(
        f"<li>{status_chip(status)}<b>{counts.get(status, 0)}</b></li>"
        for status in ORDER
        if counts.get(status, 0) or status == "MAC_MATCH_RESOLVED"
    )
    site_list = "".join(f"<li><span>{e(site)}</span><b>{count}</b></li>" for site, count in sites.most_common())

    panels = f'''
<section class="dashboard-grid">
  <article class="panel"><h2>Match Status</h2><ul>{status_list}</ul></article>
  <article class="panel"><h2>Sites Seen</h2><ul>{site_list}</ul></article>
  <article class="panel"><h2>Operating Rule</h2><p>MAC resolves network location. Serial confirms hardware identity later. Hostname is only a hint because renamed Neurons cannot be trusted by label alone.</p></article>
</section>'''

    sections = [evidence_cards(rows)]
    for status in ORDER:
        grouped = [row for row in rows if row.get("MatchStatus") == status]
        if grouped:
            sections.append(table(grouped, STATUS_LABELS.get(status, status), "t_" + status.lower()))

    summary = e(
        json.dumps(
            {
                "source": str(source),
                "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
                "status_counts": dict(counts),
                "site_counts": dict(sites),
            },
            indent=2,
        )
    )

    return f'''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SysAdminSuite Neuron MAC/Subnet Dashboard</title>
<style>
:root{{--bg:#050816;--panel:#0f172a;--text:#e5e7eb;--muted:#94a3b8;--cyan:#22d3ee;--green:#22c55e;--yellow:#facc15;--red:#f87171;--violet:#a78bfa;--blue:#60a5fa}}
*{{box-sizing:border-box}}
body{{margin:0;background:radial-gradient(circle at top left,rgba(34,211,238,.18),transparent 34%),radial-gradient(circle at top right,rgba(167,139,250,.14),transparent 28%),linear-gradient(180deg,#020617,#0f172a,#020617);color:var(--text);font-family:Segoe UI,Arial,sans-serif}}
header{{padding:28px 34px;background:rgba(2,6,23,.92);border-bottom:1px solid rgba(96,165,250,.32);box-shadow:0 0 34px rgba(34,211,238,.14)}}
header h1{{margin:0;font-size:30px;letter-spacing:.3px}}
header p{{color:var(--muted);margin:8px 0 0}}
main{{padding:24px 34px 70px}}
.notice,.panel,.metric,.identity-card{{border:1px solid rgba(96,165,250,.28);background:rgba(15,23,42,.88);border-radius:18px;padding:16px;box-shadow:0 0 28px rgba(34,211,238,.09)}}
.notice{{margin-bottom:18px;color:#dbeafe}}
.metrics,.identity-grid,.dashboard-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px;margin-bottom:18px}}
.metric span{{color:var(--muted);font-size:13px;text-transform:uppercase;letter-spacing:.08em}}
.metric strong{{font-size:34px;display:block;margin-top:5px}}
.panel{{margin-bottom:18px}}
.panel-head{{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px}}
.panel h2{{margin:0;font-size:19px}}
.identity-card h3{{margin:12px 0;font-size:20px;color:#bfdbfe}}
.identity-card p{{margin:8px 0;color:#dbeafe}}
.good{{border-color:rgba(34,197,94,.6);box-shadow:0 0 30px rgba(34,197,94,.14)}}
.warn{{border-color:rgba(250,204,21,.6);box-shadow:0 0 30px rgba(250,204,21,.14)}}
.bad{{border-color:rgba(248,113,113,.65);box-shadow:0 0 30px rgba(248,113,113,.16)}}
.info{{border-color:rgba(34,211,238,.55);box-shadow:0 0 30px rgba(34,211,238,.14)}}
.off{{opacity:.75;border-color:rgba(148,163,184,.42)}}
.chip,.evidence-chip,.status-chip,.count-chip{{display:inline-block;border-radius:999px;padding:6px 10px;border:1px solid rgba(148,163,184,.35);background:#020617;color:var(--text);font-size:12px;white-space:nowrap}}
.mac-match-resolved{{border-color:rgba(34,197,94,.7);color:#bbf7d0;box-shadow:0 0 14px rgba(34,197,94,.2)}}
.mac-not-found-in-nmap,.serial-only-no-mac{{border-color:rgba(250,204,21,.7);color:#fef3c7;box-shadow:0 0 14px rgba(250,204,21,.18)}}
.mac-conflict-multiple-ips{{border-color:rgba(248,113,113,.75);color:#fecaca;box-shadow:0 0 14px rgba(248,113,113,.2)}}
.no-usable-identifier{{border-color:rgba(148,163,184,.55);color:#cbd5e1}}
.evidence-chip{{border-color:rgba(96,165,250,.6);color:#dbeafe}}
.filter{{width:100%;margin:0 0 12px;padding:10px;border-radius:12px;background:#020617;color:var(--text);border:1px solid rgba(96,165,250,.28)}}
.table-wrap{{overflow:auto;max-height:580px;border:1px solid rgba(51,65,85,.8);border-radius:14px}}
table{{width:100%;min-width:1450px;border-collapse:collapse}}
th,td{{padding:9px 10px;border-bottom:1px solid rgba(51,65,85,.75);text-align:left;vertical-align:top;font-size:13px}}
th{{position:sticky;top:0;background:#020617;color:#bfdbfe;z-index:1}}
ul{{list-style:none;padding:0;margin:0}}
li{{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid rgba(51,65,85,.7)}}
pre{{white-space:pre-wrap;overflow:auto;background:#020617;border-radius:12px;padding:14px}}
</style>
</head>
<body>
<header><h1>SysAdminSuite Neuron MAC/Subnet Dashboard</h1><p>Generated {e(generated)} from {e(source)}</p></header>
<main>
<div class="notice">Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, MACs, serials, locations, or tracker data.</div>
{metrics}
{panels}
{''.join(sections)}
<details class="panel"><summary>Dashboard Summary JSON</summary><pre>{summary}</pre></details>
</main>
<script>
for (const input of document.querySelectorAll('.filter')) {{
  input.addEventListener('input', () => {{
    const table = document.getElementById(input.dataset.table);
    const needle = input.value.toLowerCase();
    for (const row of table.querySelectorAll('tbody tr')) {{
      row.style.display = row.innerText.toLowerCase().includes(needle) ? '' : 'none';
    }}
  }});
}}
</script>
</body>
</html>'''


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Neuron nmap MAC matcher review CSV as HTML dashboard.")
    parser.add_argument("--input", required=True, help="neuron_probe_review.csv")
    parser.add_argument("--output", required=True, help="HTML dashboard output path")
    args = parser.parse_args()

    source = Path(args.input)
    output = Path(args.output)
    rows = load_rows(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(rows, source), encoding="utf-8")
    print(f"Wrote Neuron MAC/Subnet dashboard: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
