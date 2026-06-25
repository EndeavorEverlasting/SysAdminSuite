#!/usr/bin/env python3
"""
Render an HTML artifact delivery dashboard from reconciliation and review queue CSVs.

Read-only behavior: reads CSVs and writes one standalone HTML file.
"""

from __future__ import annotations

import argparse
import csv
import html
import sys
from collections import Counter
from pathlib import Path


WARNING_TEXT = "Local operational artifact. Do not commit dashboards or CSVs containing real hostnames, IPs, MACs, serials, locations, or tracker data."


def clean(value: object) -> str:
    return "" if value is None else str(value).strip()


def get(row: dict[str, str], *names: str) -> str:
    lowered = {key.lower(): key for key in row.keys() if key}
    for name in names:
        if name in row:
            return clean(row.get(name))
        key = lowered.get(name.lower())
        if key:
            return clean(row.get(key))
    return ""


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"Required dashboard input not found: {path.name}")
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def count_issue(rows: list[dict[str, str]], text: str) -> int:
    needle = text.lower()
    return sum(1 for row in rows if needle in get(row, "IssueType").lower())


def count_severity(rows: list[dict[str, str]], severity: str) -> int:
    return sum(1 for row in rows if get(row, "Severity").lower() == severity.lower())


def confidence_low_count(rows: list[dict[str, str]]) -> int:
    return sum(
        1
        for row in rows
        if get(row, "Confidence", "MatchConfidence", "ResultConfidence", "ReconciliationConfidence").lower() in {"low", "conflict", "none"}
    )


def summary_by(rows: list[dict[str, str]], *fields: str) -> Counter[str]:
    counter: Counter[str] = Counter()
    for row in rows:
        value = ""
        for field in fields:
            value = get(row, field)
            if value:
                break
        counter[value or "(blank)"] += 1
    return counter


def h(value: object) -> str:
    return html.escape(clean(value))


def metric_card(label: str, value: int) -> str:
    return f'<div class="card"><div class="metric">{value}</div><div class="label">{h(label)}</div></div>'


def render_summary_table(title: str, counter: Counter[str]) -> str:
    rows = "\n".join(f"<tr><td>{h(key)}</td><td>{value}</td></tr>" for key, value in counter.most_common())
    if not rows:
        rows = '<tr><td colspan="2">(none)</td></tr>'
    return f"""
    <section>
      <h2>{h(title)}</h2>
      <table>
        <thead><tr><th>Value</th><th>Count</th></tr></thead>
        <tbody>
          {rows}
        </tbody>
      </table>
    </section>
    """


def render_review_table(rows: list[dict[str, str]]) -> str:
    preferred = [
        "ReviewID",
        "SourceFile",
        "SourceRow",
        "Severity",
        "IssueType",
        "SiteCode",
        "Location",
        "Room",
        "Workstation",
        "Hostname",
        "IPAddress",
        "MACAddress",
        "SerialNumber",
        "EvidenceSummary",
        "RecommendedAction",
        "Owner",
        "ReviewStatus",
        "Notes",
    ]

    body_rows = []
    for row in rows:
        cells = "".join(f"<td>{h(get(row, col))}</td>" for col in preferred)
        body_rows.append(f"<tr>{cells}</tr>")

    if not body_rows:
        body_rows.append(f'<tr><td colspan="{len(preferred)}">(none)</td></tr>')

    headers = "".join(f"<th>{h(col)}</th>" for col in preferred)
    return f"""
    <section>
      <h2>Full review queue table</h2>
      <table>
        <thead><tr>{headers}</tr></thead>
        <tbody>
          {"".join(body_rows)}
        </tbody>
      </table>
    </section>
    """


def render_dashboard(review_rows: list[dict[str, str]], reconciliation_rows: list[dict[str, str]]) -> str:
    total_artifact_rows = len(reconciliation_rows)
    review_items = len(review_rows)
    critical = count_severity(review_rows, "critical")
    high = count_severity(review_rows, "high")
    missing_serial = count_issue(review_rows, "missing serial evidence")
    needs_field_capture = count_issue(review_rows, "needs field capture")
    unreachable = count_issue(review_rows, "surveyed unreachable")
    low_confidence = confidence_low_count(reconciliation_rows) if reconciliation_rows else count_issue(review_rows, "low confidence")

    site_counter = summary_by(reconciliation_rows or review_rows, "SiteCode", "SiteName")
    issue_counter = summary_by(review_rows, "IssueType")

    cards = "\n".join(
        [
            metric_card("Total artifact rows", total_artifact_rows),
            metric_card("Review items", review_items),
            metric_card("Critical items", critical),
            metric_card("High severity items", high),
            metric_card("Missing serial evidence", missing_serial),
            metric_card("Needs field capture", needs_field_capture),
            metric_card("Unreachable targets", unreachable),
            metric_card("Low confidence rows", low_confidence),
        ]
    )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SAS Artifact Delivery Dashboard</title>
  <style>
    body {{
      font-family: Arial, sans-serif;
      margin: 24px;
      color: #1f2933;
      background: #f8fafc;
    }}
    .banner {{
      padding: 12px 16px;
      border: 1px solid #92400e;
      background: #fffbeb;
      color: #78350f;
      font-weight: bold;
      margin-bottom: 18px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
      gap: 12px;
      margin-bottom: 24px;
    }}
    .card {{
      background: white;
      border: 1px solid #d9e2ec;
      border-radius: 6px;
      padding: 14px;
    }}
    .metric {{
      font-size: 30px;
      font-weight: bold;
    }}
    .label {{
      color: #52606d;
      margin-top: 4px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: white;
      margin-bottom: 24px;
    }}
    th, td {{
      border: 1px solid #d9e2ec;
      padding: 8px;
      text-align: left;
      vertical-align: top;
      font-size: 13px;
    }}
    th {{
      background: #edf2f7;
    }}
    h1, h2 {{
      margin-bottom: 10px;
    }}
  </style>
</head>
<body>
  <div class="banner">{h(WARNING_TEXT)}</div>
  <h1>SAS Artifact Delivery Dashboard</h1>
  <section class="grid">
    {cards}
  </section>
  {render_summary_table("Site summary", site_counter)}
  {render_summary_table("Issue type summary", issue_counter)}
  {render_review_table(review_rows)}
</body>
</html>
"""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render artifact delivery HTML dashboard.")
    parser.add_argument("--review-queue", required=True, help="Review queue CSV path.")
    parser.add_argument("--reconciliation", required=True, help="Reconciliation CSV path.")
    parser.add_argument("--output", required=True, help="Dashboard HTML output path.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        review_rows = read_csv(Path(args.review_queue))
        reconciliation_rows = read_csv(Path(args.reconciliation))
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(render_dashboard(review_rows, reconciliation_rows), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
