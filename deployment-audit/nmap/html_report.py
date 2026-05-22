#!/usr/bin/env python3
"""
Standalone HTML report generator for Cybernet / Neuron audit outputs.

The report is intentionally dependency-free and self-contained. It reads the
CSV/JSON artifacts already produced by the workbook audit and optional Nmap
probe, then writes a human-readable dashboard that can be opened locally in a
browser.

Generated report is local-only output under the ignored output folder; do not
commit real reports containing MACs, serials, hostnames, or locations.
"""
from __future__ import annotations

import argparse
import csv
import html
import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

REPORT_NAME = "audit_report.html"
MAX_ROWS_DEFAULT = 750

REPORT_TABLES = [
    {
        "title": "Real Deployed Duplicates",
        "file": "real_deployed_duplicates.csv",
        "priority": "high",
        "description": "Confirmed duplicate candidates using the workbook formula: same MAC, serial, or hostname, Dupe Deployed marked Yes, and different locations.",
        "columns": [
            "duplicate_type",
            "duplicate_value",
            "source_row",
            "source_column",
            "dupe_deployed_yes",
            "location_signature",
            "Neuron Hostname",
            "Cybernet Hostname",
            "Neuron MAC",
            "Cybernet MAC",
            "Cybernet Serial",
            "Neuron S/N",
            "Room",
            "Bay",
        ],
    },
    {
        "title": "False Positive Duplicate Candidates",
        "file": "duplicate_false_positive_candidates.csv",
        "priority": "medium",
        "description": "Repeated values that do not meet the real deployed duplicate formula. These are useful for QA but should not be treated as confirmed deployed duplicates by default.",
        "columns": [
            "duplicate_type",
            "duplicate_value",
            "duplicate_class",
            "duplicate_reason",
            "source_row",
            "dupe_deployed_yes",
            "location_signature",
            "Neuron Hostname",
            "Cybernet Hostname",
            "Neuron MAC",
            "Cybernet MAC",
            "Cybernet Serial",
            "Neuron S/N",
        ],
    },
    {
        "title": "Live Probe Status",
        "file": "probe_status.csv",
        "priority": "high",
        "description": "Per-target probe lifecycle. Use this when a run is completed, interrupted, or terminated to see exactly what happened.",
        "columns": [
            "index",
            "total",
            "percent",
            "target",
            "status",
            "started_at",
            "ended_at",
            "duration_seconds",
            "return_code",
            "error",
        ],
    },
    {
        "title": "Nmap Probe Matches",
        "file": "nmap_probe_matches.csv",
        "priority": "high",
        "description": "Observed Nmap results matched back to workbook rows by MAC, IP, or hostname when possible.",
        "columns": [
            "match_type",
            "source_row",
            "nmap_status",
            "nmap_reason",
            "nmap_ipv4",
            "nmap_mac",
            "nmap_vendor",
            "nmap_hostname",
            "dupe_deployed_yes",
            "location_signature",
            "Neuron Hostname",
            "Cybernet Hostname",
            "Neuron MAC",
            "Cybernet MAC",
        ],
    },
    {
        "title": "Duplicate MACs",
        "file": "duplicate_macs.csv",
        "priority": "medium",
        "description": "Raw repeated MAC values, classified as real deployed duplicates or false-positive candidates.",
        "columns": [
            "duplicate_value",
            "duplicate_class",
            "duplicate_reason",
            "source_row",
            "dupe_deployed_yes",
            "location_signature",
            "Neuron MAC",
            "Cybernet MAC",
            "Neuron Hostname",
            "Cybernet Hostname",
        ],
    },
    {
        "title": "Duplicate Serials",
        "file": "duplicate_serials.csv",
        "priority": "medium",
        "description": "Raw repeated serial values, classified as real deployed duplicates or false-positive candidates.",
        "columns": [
            "duplicate_value",
            "duplicate_class",
            "duplicate_reason",
            "source_row",
            "dupe_deployed_yes",
            "location_signature",
            "Cybernet Serial",
            "Neuron S/N",
            "Anesthesia S/N",
            "Medical Device S/N",
            "Dialysis S/N",
        ],
    },
    {
        "title": "Duplicate Hostnames",
        "file": "duplicate_hostnames.csv",
        "priority": "medium",
        "description": "Raw repeated hostname values, classified as real deployed duplicates or false-positive candidates.",
        "columns": [
            "duplicate_value",
            "duplicate_class",
            "duplicate_reason",
            "source_row",
            "dupe_deployed_yes",
            "location_signature",
            "Neuron Hostname",
            "Cybernet Hostname",
        ],
    },
    {
        "title": "Nmap Targets",
        "file": "nmap_targets.csv",
        "priority": "low",
        "description": "Unique targets generated from workbook hostname/IP columns before live probing.",
        "columns": ["target", "source_column", "first_source_row", "source_rows"],
    },
]


def esc(value: object) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def read_json(path: Path) -> Dict[str, object]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"read_error": str(exc)}


def read_csv_rows(path: Path, limit: int) -> Tuple[List[Dict[str, str]], int, List[str]]:
    if not path.exists():
        return [], 0, []
    rows: List[Dict[str, str]] = []
    total = 0
    fields: List[str] = []
    try:
        with path.open("r", newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            fields = list(reader.fieldnames or [])
            for row in reader:
                total += 1
                if len(rows) < limit:
                    rows.append(row)
    except Exception as exc:
        return [{"error": str(exc)}], 1, ["error"]
    return rows, total, fields


def status_counts(rows: Sequence[Dict[str, str]], field: str) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for row in rows:
        key = row.get(field, "") or "blank"
        counts[key] = counts.get(key, 0) + 1
    return counts


def pick_columns(rows: Sequence[Dict[str, str]], preferred: Sequence[str], available: Sequence[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for col in preferred:
        if col in available and col not in seen:
            out.append(col)
            seen.add(col)
    if not out:
        for col in available[:12]:
            if col not in seen:
                out.append(col)
                seen.add(col)
    return out


def card(title: str, value: object, subtitle: str = "", severity: str = "") -> str:
    return f"""
    <div class="card {esc(severity)}">
      <div class="card-title">{esc(title)}</div>
      <div class="card-value">{esc(value)}</div>
      <div class="card-subtitle">{esc(subtitle)}</div>
    </div>
    """


def render_summary_cards(out_dir: Path) -> str:
    audit = read_json(out_dir / "audit_summary.json")
    probe = read_json(out_dir / "probe_run_summary.json")
    final_state = read_json(out_dir / "probe_final_state.json")

    real_rows, real_total, _ = read_csv_rows(out_dir / "real_deployed_duplicates.csv", 1)
    false_rows, false_total, _ = read_csv_rows(out_dir / "duplicate_false_positive_candidates.csv", 1)
    status_rows, status_total, _ = read_csv_rows(out_dir / "probe_status.csv", 5000)
    match_rows, match_total, _ = read_csv_rows(out_dir / "nmap_probe_matches.csv", 1)

    counts = status_counts(status_rows, "status")
    state = final_state.get("state", "not_run")
    state_reason = final_state.get("reason", "")

    cards = [
        card("Run State", state, state_reason, "warn" if state == "incomplete" else "good" if state == "completed" else ""),
        card("Inventory Rows", audit.get("inventory_rows", "n/a"), "Workbook rows analyzed"),
        card("Unique Probe Targets", audit.get("unique_nmap_targets", "n/a"), "Generated from hostname/IP columns"),
        card("Real Deployed Duplicate Rows", audit.get("real_deployed_duplicate_rows", real_total), "Dupe Deployed Yes + different locations", "bad" if real_total else "good"),
        card("False Positive Candidate Rows", audit.get("false_positive_candidate_rows", false_total), "Repeated values that failed real-dupe formula"),
        card("Probe Status Rows", status_total, "Rows in probe_status.csv"),
        card("Completed", counts.get("completed", 0) + counts.get("resumed_completed", 0), "Completed or resumed-completed targets", "good"),
        card("Failed / Interrupted", counts.get("failed", 0) + counts.get("interrupted", 0) + counts.get("not_run_interrupted", 0), "Needs review", "bad" if counts.get("failed", 0) else ""),
        card("Nmap Matches", probe.get("nmap_matches", match_total), "Probe observations matched to inventory"),
    ]
    return "\n".join(cards)


def render_json_block(title: str, payload: Dict[str, object]) -> str:
    if not payload:
        return ""
    return f"""
    <details class="json-block">
      <summary>{esc(title)}</summary>
      <pre>{esc(json.dumps(payload, indent=2, ensure_ascii=False))}</pre>
    </details>
    """


def render_table(out_dir: Path, table: Dict[str, object], limit: int) -> str:
    file_name = str(table["file"])
    rows, total, available = read_csv_rows(out_dir / file_name, limit)
    title = str(table["title"])
    description = str(table.get("description", ""))
    priority = str(table.get("priority", ""))
    preferred = list(table.get("columns", []))
    columns = pick_columns(rows, preferred, available)
    table_id = safe_name(file_name.replace(".csv", ""))

    if not available:
        return f"""
        <section class="table-section {esc(priority)}">
          <div class="section-header">
            <div>
              <h2>{esc(title)}</h2>
              <p>{esc(description)}</p>
            </div>
            <span class="badge muted">missing</span>
          </div>
          <p class="muted">{esc(file_name)} was not found in this output folder.</p>
        </section>
        """

    header = "".join(f"<th>{esc(col)}</th>" for col in columns)
    body_rows = []
    for row in rows:
        klass = ""
        joined = " ".join(row.values()).lower()
        if "real_deployed_duplicate" in joined or "failed" in joined or "interrupted" in joined:
            klass = " class='flag'"
        elif "false_positive" in joined or "resumed_completed" in joined:
            klass = " class='soft'"
        cells = "".join(f"<td>{esc(row.get(col, ''))}</td>" for col in columns)
        body_rows.append(f"<tr{klass}>{cells}</tr>")

    truncated = "" if total <= limit else f"Showing first {limit} of {total} rows. Open the CSV for the full data."
    return f"""
    <section class="table-section {esc(priority)}">
      <div class="section-header">
        <div>
          <h2>{esc(title)}</h2>
          <p>{esc(description)}</p>
        </div>
        <div class="section-actions">
          <span class="badge">{total} rows</span>
          <a class="csv-link" href="{esc(file_name)}">Open CSV</a>
        </div>
      </div>
      <input class="filter" data-table="{esc(table_id)}" placeholder="Filter {esc(title)}..." />
      <div class="table-wrap">
        <table id="{esc(table_id)}">
          <thead><tr>{header}</tr></thead>
          <tbody>{''.join(body_rows)}</tbody>
        </table>
      </div>
      <p class="muted">{esc(truncated)}</p>
    </section>
    """


def render_timeline(out_dir: Path, limit: int = 80) -> str:
    path = out_dir / "probe_progress.jsonl"
    if not path.exists():
        return """
        <section class="table-section low">
          <div class="section-header"><h2>Event Timeline</h2><span class="badge muted">missing</span></div>
          <p class="muted">probe_progress.jsonl was not found.</p>
        </section>
        """
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    recent = lines[-limit:]
    items = []
    for line in recent:
        try:
            event = json.loads(line)
        except Exception:
            event = {"event": "parse_error", "raw": line}
        label = event.get("event", "event")
        time = event.get("time", "")
        target = event.get("target", "")
        summary = event.get("summary", {}) if isinstance(event.get("summary", {}), dict) else {}
        detail = target or summary.get("percent_accounted_for", "")
        items.append(f"<li><b>{esc(time)}</b> <span>{esc(label)}</span> <em>{esc(detail)}</em></li>")
    return f"""
    <section class="table-section low">
      <div class="section-header">
        <div><h2>Event Timeline</h2><p>Most recent probe events from probe_progress.jsonl.</p></div>
        <span class="badge">last {len(recent)}</span>
      </div>
      <ol class="timeline">{''.join(items)}</ol>
    </section>
    """


def build_html(out_dir: Path, max_rows: int = MAX_ROWS_DEFAULT) -> str:
    generated = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    audit = read_json(out_dir / "audit_summary.json")
    probe = read_json(out_dir / "probe_run_summary.json")
    final_state = read_json(out_dir / "probe_final_state.json")
    sections = [render_table(out_dir, table, max_rows) for table in REPORT_TABLES]
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Cybernet / Neuron Audit Report</title>
<style>
:root {{ --bg:#0f172a; --panel:#111827; --card:#1f2937; --text:#e5e7eb; --muted:#9ca3af; --line:#374151; --good:#16a34a; --bad:#dc2626; --warn:#f59e0b; --soft:#1d4ed8; }}
* {{ box-sizing:border-box; }}
body {{ margin:0; font-family:Segoe UI, Arial, sans-serif; background:var(--bg); color:var(--text); }}
header {{ padding:28px 32px; background:linear-gradient(135deg,#111827,#1e293b); border-bottom:1px solid var(--line); position:sticky; top:0; z-index:10; }}
h1 {{ margin:0 0 8px 0; font-size:28px; }}
header p {{ margin:0; color:var(--muted); }}
main {{ padding:24px 32px 60px; }}
.cards {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:14px; margin-bottom:24px; }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; box-shadow:0 8px 18px rgba(0,0,0,.18); }}
.card.good {{ border-color:rgba(22,163,74,.7); }} .card.bad {{ border-color:rgba(220,38,38,.8); }} .card.warn {{ border-color:rgba(245,158,11,.8); }}
.card-title {{ color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.08em; }}
.card-value {{ font-size:28px; font-weight:700; margin:8px 0; }}
.card-subtitle {{ color:var(--muted); font-size:13px; }}
.table-section {{ background:var(--panel); border:1px solid var(--line); border-radius:16px; padding:18px; margin:18px 0; }}
.table-section.high {{ border-color:rgba(245,158,11,.45); }}
.section-header {{ display:flex; align-items:flex-start; justify-content:space-between; gap:16px; margin-bottom:12px; }}
.section-header h2 {{ margin:0 0 6px; font-size:20px; }}
.section-header p {{ margin:0; color:var(--muted); max-width:900px; }}
.section-actions {{ display:flex; gap:8px; align-items:center; white-space:nowrap; }}
.badge, .csv-link {{ display:inline-block; border:1px solid var(--line); border-radius:999px; padding:6px 10px; color:var(--text); text-decoration:none; font-size:12px; background:#0b1220; }}
.badge.muted {{ color:var(--muted); }} .csv-link:hover {{ border-color:#60a5fa; }}
.filter {{ width:100%; padding:10px 12px; border-radius:10px; border:1px solid var(--line); background:#020617; color:var(--text); margin-bottom:12px; }}
.table-wrap {{ overflow:auto; border:1px solid var(--line); border-radius:12px; max-height:560px; }}
table {{ width:100%; border-collapse:collapse; min-width:900px; }}
th, td {{ padding:9px 10px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; font-size:13px; }}
th {{ position:sticky; top:0; background:#020617; z-index:2; color:#cbd5e1; }}
tr.flag td {{ background:rgba(220,38,38,.12); }} tr.soft td {{ background:rgba(37,99,235,.09); }}
.muted {{ color:var(--muted); }}
.json-block {{ background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:12px; margin:12px 0; }}
.json-block summary {{ cursor:pointer; font-weight:600; }} pre {{ white-space:pre-wrap; overflow:auto; color:#cbd5e1; }}
.timeline {{ margin:0; padding-left:20px; }} .timeline li {{ padding:6px 0; border-bottom:1px solid rgba(55,65,81,.5); }} .timeline span {{ color:#93c5fd; margin:0 8px; }} .timeline em {{ color:var(--muted); font-style:normal; }}
.notice {{ border-left:4px solid var(--warn); background:rgba(245,158,11,.08); padding:12px 14px; border-radius:10px; margin-bottom:18px; color:#fde68a; }}
@media print {{ header {{ position:static; }} .filter, .csv-link {{ display:none; }} body {{ background:white; color:black; }} .table-section, .card, header {{ background:white; color:black; }} }}
</style>
</head>
<body>
<header>
  <h1>Cybernet / Neuron Audit Report</h1>
  <p>Generated {esc(generated)} from local audit artifacts in {esc(str(out_dir))}</p>
</header>
<main>
  <div class="notice">This report is generated locally from ignored output files. Do not commit reports containing Northwell MACs, serials, hostnames, or locations.</div>
  <section class="cards">{render_summary_cards(out_dir)}</section>
  {render_json_block('Audit Summary JSON', audit)}
  {render_json_block('Probe Summary JSON', probe)}
  {render_json_block('Final State JSON', final_state)}
  {''.join(sections)}
  {render_timeline(out_dir)}
</main>
<script>
document.querySelectorAll('.filter').forEach(input => {{
  input.addEventListener('input', () => {{
    const table = document.getElementById(input.dataset.table);
    const needle = input.value.toLowerCase();
    table.querySelectorAll('tbody tr').forEach(row => {{
      row.style.display = row.innerText.toLowerCase().includes(needle) ? '' : 'none';
    }});
  }});
}});
</script>
</body>
</html>"""


def generate_report(out_dir: Path, max_rows: int = MAX_ROWS_DEFAULT, output_name: str = REPORT_NAME) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / output_name
    report_path.write_text(build_html(out_dir, max_rows=max_rows), encoding="utf-8")
    return report_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a human-readable HTML dashboard from Cybernet audit outputs.")
    parser.add_argument("--out-dir", required=True, help="Audit output directory")
    parser.add_argument("--max-rows", type=int, default=MAX_ROWS_DEFAULT, help="Max rows to embed per table")
    parser.add_argument("--output-name", default=REPORT_NAME, help="Output HTML filename")
    args = parser.parse_args()

    report = generate_report(Path(args.out_dir), max_rows=args.max_rows, output_name=args.output_name)
    print(json.dumps({"html_report": str(report)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
