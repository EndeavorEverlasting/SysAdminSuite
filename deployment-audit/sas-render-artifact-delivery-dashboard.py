#!/usr/bin/env python3
"""Render an HTML artifact delivery dashboard from reconciliation and review queue CSVs."""

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
        return []
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def h(value: object) -> str:
    return html.escape(clean(value))


def count_issue(rows: list[dict[str, str]], text: str) -> int:
    needle = text.lower()
    return sum(1 for row in rows if needle in get(row, "IssueType").lower())


def count_severity(rows: list[dict[str, str]], severity: str) -> int:
    return sum(1 for row in rows if get(row, "Severity").lower() == severity)


def low_confidence_count(rows: list[dict[str, str]]) -> int:
    return sum(1 for row in rows if get(row, "Confidence", "MatchConfidence", "ResultConfidence", "ReconciliationConfidence").lower() in {"low", "conflict", "none"})


def summary(rows: list[dict[str, str]], *fields: str) -> Counter[str]:
    values: Counter[str] = Counter()
    for row in rows:
        value = ""
        for field in fields:
            value = get(row, field)
            if value:
                break
        values[value or "(blank)"] += 1
    return values


def card(label: str, value: int) -> str:
    return f'<div class="card"><div class="metric">{value}</div><div class="label">{h(label)}</div></div>'


def summary_table(title: str, values: Counter[str]) -> str:
    body = "".join(f"<tr><td>{h(key)}</td><td>{count}</td></tr>" for key, count in values.most_common())
    body = body or '<tr><td colspan="2">(none)</td></tr>'
    return f"<section><h2>{h(title)}</h2><table><thead><tr><th>Value</th><th>Count</th></tr></thead><tbody>{body}</tbody></table></section>"


def review_table(rows: list[dict[str, str]]) -> str:
    columns = ["ReviewID", "Severity", "IssueType", "SiteCode", "Location", "Room", "Workstation", "Hostname", "IPAddress", "MACAddress", "SerialNumber", "EvidenceSummary", "RecommendedAction", "ReviewStatus", "Notes"]
    headers = "".join(f"<th>{h(col)}</th>" for col in columns)
    body = "".join("<tr>" + "".join(f"<td>{h(get(row, col))}</td>" for col in columns) + "</tr>" for row in rows)
    body = body or f'<tr><td colspan="{len(columns)}">(none)</td></tr>'
    return f"<section><h2>Full review queue table</h2><table><thead><tr>{headers}</tr></thead><tbody>{body}</tbody></table></section>"


def render(review_rows: list[dict[str, str]], reconciliation_rows: list[dict[str, str]]) -> str:
    metrics = [
        ("Total artifact rows", len(reconciliation_rows)),
        ("Review items", len(review_rows)),
        ("Critical items", count_severity(review_rows, "critical")),
        ("High severity items", count_severity(review_rows, "high")),
        ("Missing serial evidence", count_issue(review_rows, "missing serial evidence")),
        ("Needs field capture", count_issue(review_rows, "needs field capture")),
        ("Unreachable targets", count_issue(review_rows, "surveyed unreachable")),
        ("Low confidence rows", low_confidence_count(reconciliation_rows) or count_issue(review_rows, "low confidence")),
    ]
    cards = "".join(card(label, value) for label, value in metrics)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SAS Artifact Delivery Dashboard</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 24px; color: #1f2933; background: #f8fafc; }}
    .banner {{ padding: 12px 16px; border: 1px solid #92400e; background: #fffbeb; color: #78350f; font-weight: bold; margin-bottom: 18px; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 12px; margin-bottom: 24px; }}
    .card {{ background: white; border: 1px solid #d9e2ec; border-radius: 6px; padding: 14px; }}
    .metric {{ font-size: 30px; font-weight: bold; }}
    .label {{ color: #52606d; margin-top: 4px; }}
    table {{ width: 100%; border-collapse: collapse; background: white; margin-bottom: 24px; }}
    th, td {{ border: 1px solid #d9e2ec; padding: 8px; text-align: left; vertical-align: top; font-size: 13px; }}
    th {{ background: #edf2f7; }}
  </style>
</head>
<body>
  <div class="banner">{h(WARNING_TEXT)}</div>
  <h1>SAS Artifact Delivery Dashboard</h1>
  <section class="grid">{cards}</section>
  {summary_table('Site summary', summary(reconciliation_rows or review_rows, 'SiteCode', 'SiteName'))}
  {summary_table('Issue type summary', summary(review_rows, 'IssueType'))}
  {review_table(review_rows)}
</body>
</html>
"""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render artifact delivery HTML dashboard.")
    parser.add_argument("--review-queue", required=True)
    parser.add_argument("--reconciliation", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(read_csv(Path(args.review_queue)), read_csv(Path(args.reconciliation))), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
