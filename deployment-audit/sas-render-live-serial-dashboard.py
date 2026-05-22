#!/usr/bin/env python3
"""Render a glowing SysAdminSuite live serial/MAC probe dashboard.

Input: live_serial_probe_results.csv
Output: standalone HTML dashboard
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
from collections import Counter
from pathlib import Path

CLASS_ORDER = [
    "live_serial_confirmed",
    "reachable_no_serial",
    "unreachable_mark_off",
    "needs_ad_lookup",
    "needs_vision_lookup",
    "manual_review",
]

CLASS_LABELS = {
    "live_serial_confirmed": "Live Confirmed",
    "reachable_no_serial": "Reachable, Missing Serial",
    "unreachable_mark_off": "Unreachable, Mark Off",
    "needs_ad_lookup": "Needs AD Lookup",
    "needs_vision_lookup": "Needs Vision Lookup",
    "manual_review": "Manual Review",
}

CLASS_DESCRIPTIONS = {
    "live_serial_confirmed": "Live probe returned serial or MAC evidence. Use these rows to confirm existing tracker data or populate missing fields.",
    "reachable_no_serial": "Target responds, but serial/MAC evidence was not collected. Use an approved stronger identity path or Vision.",
    "unreachable_mark_off": "Target did not respond. Mark off for now and route to AD/Vision before treating it as a deployment error.",
    "needs_ad_lookup": "Input is missing or weak. Use AD to locate hostname, OU posture, or disabled/stale object state.",
    "needs_vision_lookup": "Use Northwell Vision or equivalent asset inventory to locate serial/MAC/ownership details.",
    "manual_review": "Observed evidence conflicts with tracker expectation or is too ambiguous for automation.",
}

ROW_CLASS = {
    "live_serial_confirmed": "good",
    "reachable_no_serial": "warn",
    "unreachable_mark_off": "off",
    "needs_ad_lookup": "info",
    "needs_vision_lookup": "info",
    "manual_review": "bad",
}

DISPLAY_COLUMNS = [
    "classification",
    "target",
    "device_type",
    "expected_hostname",
    "expected_cybernet_serial",
    "expected_neuron_serial",
    "expected_mac",
    "observed_hostname",
    "observed_serial",
    "observed_mac",
    "reachability_status",
    "serial_probe_status",
    "follow_up_system",
    "already_had_serial",
    "already_had_mac",
    "can_populate_serial",
    "can_populate_mac",
    "log_status",
    "notes",
]


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def esc(value: object) -> str:
    return html.escape(str(value or ""))


def count_yes(rows: list[dict[str, str]], column: str) -> int:
    return sum(1 for row in rows if (row.get(column) or "").strip().lower() == "yes")


def render_badge(value: str) -> str:
    value = value or ""
    safe = esc(value)
    if value.lower() == "yes":
        return f'<span class="pill good-pill">{safe}</span>'
    if value.lower() == "no":
        return f'<span class="pill muted-pill">{safe}</span>'
    return f'<span class="pill">{safe}</span>'


def render_table(rows: list[dict[str, str]], table_id: str, title: str, description: str) -> str:
    if not rows:
        return f"""
        <section class="panel empty-panel">
          <div class="panel-head">
            <div>
              <h2>{esc(title)}</h2>
              <p>{esc(description)}</p>
            </div>
            <span class="count-chip">0 rows</span>
          </div>
          <p class="muted">No rows in this category.</p>
        </section>
        """

    header = "".join(f"<th>{esc(col)}</th>" for col in DISPLAY_COLUMNS)
    body = []
    for row in rows:
        cls = ROW_CLASS.get(row.get("classification", ""), "")
        cells = []
        for col in DISPLAY_COLUMNS:
            value = row.get(col, "")
            if col in {"already_had_serial", "already_had_mac", "can_populate_serial", "can_populate_mac"}:
                cells.append(f"<td>{render_badge(value)}</td>")
            elif col == "classification":
                label = CLASS_LABELS.get(value, value)
                cells.append(f'<td><span class="status-label {esc(cls)}">{esc(label)}</span></td>')
            else:
                cells.append(f"<td>{esc(value)}</td>")
        body.append(f'<tr class="{esc(cls)}">' + "".join(cells) + "</tr>")

    return f"""
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>{esc(title)}</h2>
          <p>{esc(description)}</p>
        </div>
        <span class="count-chip">{len(rows)} rows</span>
      </div>
      <input class="filter" data-table="{esc(table_id)}" placeholder="Filter {esc(title)}..." />
      <div class="table-wrap">
        <table id="{esc(table_id)}">
          <thead><tr>{header}</tr></thead>
          <tbody>{''.join(body)}</tbody>
        </table>
      </div>
    </section>
    """


def render_dashboard(rows: list[dict[str, str]], source: Path) -> str:
    total = len(rows)
    class_counts = Counter(row.get("classification", "manual_review") or "manual_review" for row in rows)
    follow_counts = Counter(row.get("follow_up_system", "") or "None" for row in rows)
    can_serial = count_yes(rows, "can_populate_serial")
    can_mac = count_yes(rows, "can_populate_mac")
    had_serial = count_yes(rows, "already_had_serial")
    had_mac = count_yes(rows, "already_had_mac")
    confirmed = class_counts.get("live_serial_confirmed", 0)
    off = class_counts.get("unreachable_mark_off", 0)
    manual = class_counts.get("manual_review", 0)

    category_panels = []
    for classification in CLASS_ORDER:
        subset = [row for row in rows if row.get("classification") == classification]
        category_panels.append(
            render_table(
                subset,
                f"table_{classification}",
                CLASS_LABELS[classification],
                CLASS_DESCRIPTIONS[classification],
            )
        )

    dashboard_json = json.dumps(
        {
            "source": str(source),
            "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
            "total_rows": total,
            "classification_counts": dict(class_counts),
            "follow_up_counts": dict(follow_counts),
            "can_populate_serial": can_serial,
            "can_populate_mac": can_mac,
            "already_had_serial": had_serial,
            "already_had_mac": had_mac,
        },
        indent=2,
    )

    follow_items = "".join(
        f"<li><span>{esc(name)}</span><strong>{count}</strong></li>" for name, count in follow_counts.most_common()
    )

    class_cards = "".join(
        f"""
        <article class="metric class-metric {esc(ROW_CLASS.get(name, ''))}">
          <span>{esc(CLASS_LABELS.get(name, name))}</span>
          <strong>{class_counts.get(name, 0)}</strong>
          <em>{esc(CLASS_DESCRIPTIONS.get(name, ''))}</em>
        </article>
        """
        for name in CLASS_ORDER
    )

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SysAdminSuite Live Serial Probe Dashboard</title>
<style>
:root {{
  --bg:#050816; --panel:#0f172a; --panel2:#111827; --card:#111827; --line:#334155;
  --text:#e5e7eb; --muted:#94a3b8; --cyan:#22d3ee; --blue:#60a5fa; --green:#22c55e;
  --yellow:#facc15; --orange:#fb923c; --red:#f87171; --purple:#c084fc;
}}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:radial-gradient(circle at top left, rgba(34,211,238,.18), transparent 34%), linear-gradient(180deg,#020617,#0f172a 42%,#020617); color:var(--text); font-family:Segoe UI, Arial, sans-serif; }}
header {{ position:sticky; top:0; z-index:20; padding:26px 34px; background:rgba(2,6,23,.88); backdrop-filter:blur(12px); border-bottom:1px solid rgba(96,165,250,.32); box-shadow:0 0 34px rgba(34,211,238,.12); }}
h1 {{ margin:0; font-size:30px; letter-spacing:.01em; }}
header p {{ margin:8px 0 0; color:var(--muted); }}
main {{ padding:24px 34px 70px; }}
.notice {{ border:1px solid rgba(250,204,21,.42); background:linear-gradient(135deg,rgba(250,204,21,.13),rgba(15,23,42,.68)); border-radius:16px; padding:14px 16px; color:#fde68a; box-shadow:0 0 28px rgba(250,204,21,.12); margin-bottom:22px; }}
.metrics {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:14px; margin-bottom:18px; }}
.metric {{ border:1px solid rgba(96,165,250,.28); background:linear-gradient(145deg,rgba(15,23,42,.96),rgba(17,24,39,.9)); border-radius:18px; padding:16px; min-height:128px; box-shadow:0 0 24px rgba(96,165,250,.08), inset 0 0 18px rgba(255,255,255,.02); }}
.metric span {{ display:block; color:var(--muted); text-transform:uppercase; font-size:12px; letter-spacing:.09em; }}
.metric strong {{ display:block; font-size:34px; margin:8px 0 6px; }}
.metric em {{ color:var(--muted); font-style:normal; font-size:13px; line-height:1.35; }}
.metric.good {{ border-color:rgba(34,197,94,.55); box-shadow:0 0 28px rgba(34,197,94,.12); }}
.metric.warn {{ border-color:rgba(250,204,21,.55); box-shadow:0 0 28px rgba(250,204,21,.12); }}
.metric.off {{ border-color:rgba(148,163,184,.42); box-shadow:0 0 24px rgba(148,163,184,.08); }}
.metric.bad {{ border-color:rgba(248,113,113,.6); box-shadow:0 0 30px rgba(248,113,113,.14); }}
.metric.info {{ border-color:rgba(34,211,238,.5); box-shadow:0 0 28px rgba(34,211,238,.12); }}
.dashboard-grid {{ display:grid; grid-template-columns:minmax(260px,1fr) minmax(260px,1fr); gap:16px; margin-bottom:18px; }}
.panel {{ background:rgba(15,23,42,.86); border:1px solid rgba(96,165,250,.26); border-radius:20px; padding:18px; box-shadow:0 0 36px rgba(2,132,199,.09); margin-bottom:18px; }}
.panel-head {{ display:flex; justify-content:space-between; gap:18px; align-items:flex-start; margin-bottom:14px; }}
.panel h2 {{ margin:0 0 6px; font-size:21px; }}
.panel p {{ margin:0; color:var(--muted); max-width:960px; }}
.count-chip, .pill, .status-label {{ display:inline-block; border-radius:999px; padding:6px 10px; font-size:12px; border:1px solid rgba(148,163,184,.35); background:#020617; color:var(--text); white-space:nowrap; }}
.status-label.good {{ border-color:rgba(34,197,94,.65); color:#bbf7d0; box-shadow:0 0 14px rgba(34,197,94,.16); }}
.status-label.warn {{ border-color:rgba(250,204,21,.65); color:#fef3c7; box-shadow:0 0 14px rgba(250,204,21,.16); }}
.status-label.off {{ border-color:rgba(148,163,184,.5); color:#cbd5e1; }}
.status-label.info {{ border-color:rgba(34,211,238,.65); color:#cffafe; box-shadow:0 0 14px rgba(34,211,238,.16); }}
.status-label.bad {{ border-color:rgba(248,113,113,.7); color:#fecaca; box-shadow:0 0 14px rgba(248,113,113,.18); }}
.good-pill {{ border-color:rgba(34,197,94,.6); color:#bbf7d0; }}
.muted-pill {{ color:var(--muted); }}
.follow-list {{ list-style:none; padding:0; margin:0; }}
.follow-list li {{ display:flex; justify-content:space-between; border-bottom:1px solid rgba(51,65,85,.7); padding:10px 0; }}
.follow-list span {{ color:var(--muted); }}
.filter {{ width:100%; margin:0 0 12px; padding:11px 13px; border-radius:12px; border:1px solid rgba(96,165,250,.28); background:#020617; color:var(--text); outline:none; }}
.filter:focus {{ border-color:var(--cyan); box-shadow:0 0 0 3px rgba(34,211,238,.14); }}
.table-wrap {{ overflow:auto; max-height:580px; border:1px solid rgba(51,65,85,.8); border-radius:14px; }}
table {{ width:100%; border-collapse:collapse; min-width:1500px; }}
th, td {{ padding:9px 10px; border-bottom:1px solid rgba(51,65,85,.75); text-align:left; vertical-align:top; font-size:13px; }}
th {{ position:sticky; top:0; background:#020617; z-index:2; color:#bfdbfe; }}
tr.good td {{ background:rgba(34,197,94,.08); }}
tr.warn td {{ background:rgba(250,204,21,.08); }}
tr.off td {{ background:rgba(148,163,184,.06); }}
tr.info td {{ background:rgba(34,211,238,.07); }}
tr.bad td {{ background:rgba(248,113,113,.1); }}
.muted {{ color:var(--muted); }}
details {{ margin-top:18px; }}
summary {{ cursor:pointer; color:#bfdbfe; }}
pre {{ white-space:pre-wrap; overflow:auto; background:#020617; border:1px solid rgba(96,165,250,.24); border-radius:14px; padding:14px; color:#cbd5e1; }}
@media (max-width:900px) {{ .dashboard-grid {{ grid-template-columns:1fr; }} header, main {{ padding-left:18px; padding-right:18px; }} }}
@media print {{ body, header, .panel, .metric {{ background:white; color:black; box-shadow:none; }} .filter {{ display:none; }} header {{ position:static; }} }}
</style>
</head>
<body>
<header>
  <h1>SysAdminSuite Live Serial Probe Dashboard</h1>
  <p>Generated {esc(dt.datetime.now().strftime('%Y-%m-%d %H:%M:%S'))} from {esc(source)}</p>
</header>
<main>
  <div class="notice">Local operational artifact. Do not commit dashboards or CSVs containing Northwell hostnames, MACs, serials, or locations.</div>
  <section class="metrics">
    <article class="metric"><span>Total Rows</span><strong>{total}</strong><em>Targets analyzed from live probe output.</em></article>
    <article class="metric good"><span>Live Confirmed</span><strong>{confirmed}</strong><em>Serial or MAC observed from live evidence.</em></article>
    <article class="metric warn"><span>Can Populate Serials</span><strong>{can_serial}</strong><em>Tracker is missing serial and live evidence found one.</em></article>
    <article class="metric info"><span>Can Populate MACs</span><strong>{can_mac}</strong><em>Tracker is missing MAC and live evidence found one.</em></article>
    <article class="metric"><span>Already Had Serials</span><strong>{had_serial}</strong><em>Rows that already had serial data before probing.</em></article>
    <article class="metric"><span>Already Had MACs</span><strong>{had_mac}</strong><em>Rows that already had MAC data before probing.</em></article>
    <article class="metric off"><span>Marked Off</span><strong>{off}</strong><em>Unreachable until AD or Vision locates them.</em></article>
    <article class="metric bad"><span>Manual Review</span><strong>{manual}</strong><em>Conflicts or ambiguous evidence.</em></article>
  </section>
  <section class="metrics">
    {class_cards}
  </section>
  <section class="dashboard-grid">
    <article class="panel">
      <div class="panel-head"><div><h2>Follow-Up Routing</h2><p>Where each row should go next when live probe evidence is insufficient.</p></div></div>
      <ul class="follow-list">{follow_items}</ul>
    </article>
    <article class="panel">
      <div class="panel-head"><div><h2>Operating Rule</h2><p>Unreachable does not mean duplicate error. It means mark off and route to AD or Vision until located.</p></div></div>
      <p class="muted">Use live confirmed rows to populate missing serials and MACs. Use manual review only where observed values conflict with tracker values.</p>
    </article>
  </section>
  {''.join(category_panels)}
  <details class="panel">
    <summary>Dashboard Summary JSON</summary>
    <pre>{esc(dashboard_json)}</pre>
  </details>
</main>
<script>
for (const input of document.querySelectorAll('.filter')) {{
  input.addEventListener('input', () => {{
    const table = document.getElementById(input.dataset.table);
    if (!table) return;
    const needle = input.value.toLowerCase();
    for (const row of table.querySelectorAll('tbody tr')) {{
      row.style.display = row.innerText.toLowerCase().includes(needle) ? '' : 'none';
    }}
  }});
}}
</script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Render live serial probe dashboard")
    parser.add_argument("--input", required=True, help="live_serial_probe_results.csv")
    parser.add_argument("--output", required=True, help="dashboard HTML path")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)
    rows = read_rows(input_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(render_dashboard(rows, input_path), encoding="utf-8")
    print(f"Wrote live serial probe dashboard: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
