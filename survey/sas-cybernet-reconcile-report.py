#!/usr/bin/env python3
"""Build an offline Cybernet reconciliation HTML report from local evidence."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import glob
import html
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any


REPORT_PAGES = [
    ("confirmations", ["ConfirmedInTracker"], "confirmations.html", "Confirmed in tracker"),
    ("duplicates", ["DuplicateObservedSerial", "TrackerDuplicateException"], "duplicates.html", "Duplicate identifiers"),
    ("conflicts", ["SerialConflict", "MACConflict"], "conflicts.html", "Serial and MAC conflicts"),
    ("drift", ["SerialMatchHostDrift"], "drift.html", "Hostname drift"),
    ("unaccounted", ["UnaccountedSerial"], "unaccounted.html", "Unaccounted observed serials"),
    ("coverage", ["ReachableNeedsIdentity", "Unreachable"], "coverage.html", "Coverage gaps"),
    ("remaining", ["TrackerSerialNotObserved", "AlejandroSerialNotObserved", "InAlejandroNotDeployed"], "remaining.html", "Remaining expected serials"),
    ("anomalies", ["HostnameAnomaly"], "anomalies.html", "Hostname anomalies"),
]
ALL_PAGE = ("overview", "AllCategories", "index.html", "Cybernet reconciliation")
REACHABLE_TOKENS = {"REACHABLE", "UP", "ONLINE", "YES", "OPEN"}
UNREACHABLE_TOKENS = {"NOPING", "UNREACHABLE", "OFFLINE", "BLOCKED", "NO", "DOWN"}


def load_tracker_diff() -> Any:
    module_path = Path(__file__).with_name("sas-cybernet-tracker-diff.py")
    spec = importlib.util.spec_from_file_location("sas_cybernet_tracker_diff", module_path)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load tracker diff module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TD = load_tracker_diff()


def clean(value: object) -> str:
    return TD.clean(value)


def norm_serial(value: object) -> str:
    return TD.norm_serial(value)


def norm_host(value: object) -> str:
    return TD.norm_host(value)


def norm_mac(value: object) -> str:
    return TD.norm_mac(value)


def joined(values: set[str]) -> str:
    return TD.joined(values)


def cell(row: dict[str, str], *names: str) -> str:
    lowered = {str(key).strip().lower(): value for key, value in row.items() if key}
    for name in names:
        value = lowered.get(name.lower())
        if value not in (None, ""):
            return clean(value)
    return ""


def status_token(value: str) -> str:
    return re.sub(r"[^A-Z0-9]+", "", value.upper())


def is_reachable(value: str) -> bool:
    return status_token(value) in REACHABLE_TOKENS


def is_unreachable(value: str) -> bool:
    return status_token(value) in UNREACHABLE_TOKENS


def is_identity_collected(value: str) -> bool:
    return "IDENTITYCOLLECTED" in status_token(value)


def parse_timestamp(value: str) -> dt.datetime:
    text = clean(value).replace("Z", "+00:00")
    if not text:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def expand_csv_paths(paths: list[str], patterns: list[str]) -> list[Path]:
    expanded: list[Path] = []
    seen: set[Path] = set()
    for value in paths:
        path = Path(value)
        if path.is_file() and path not in seen:
            expanded.append(path)
            seen.add(path)
    for pattern in patterns:
        for match in sorted(glob.glob(pattern)):
            path = Path(match)
            if path.is_file() and path not in seen:
                expanded.append(path)
                seen.add(path)
    return expanded


def split_macs(value: str) -> set[str]:
    macs: set[str] = set()
    for chunk in re.split(r"[;,| ]+", clean(value)):
        mac = norm_mac(chunk)
        if mac:
            macs.add(mac)
    whole = norm_mac(value)
    if whole:
        macs.add(whole)
    return macs


def best_identity_rows(paths: list[Path]) -> dict[str, dict[str, str]]:
    grouped: dict[str, list[dict[str, str]]] = {}
    for path in paths:
        for index, row in enumerate(read_csv(path), start=1):
            target = norm_host(cell(row, "Target", "HostName", "DnsName", "ObservedHostName"))
            if not target:
                target = clean(cell(row, "Target", "HostName")).upper()
            if not target:
                continue
            row["_source"] = f"{path.name}:R{index}"
            grouped.setdefault(target, []).append(row)

    best: dict[str, dict[str, str]] = {}
    for target, rows in grouped.items():
        best[target] = sorted(
            rows,
            key=lambda item: (
                1 if is_identity_collected(cell(item, "IdentityStatus", "EvidenceStatus")) else 0,
                parse_timestamp(cell(item, "Timestamp")),
                clean(item.get("_source", "")),
            ),
            reverse=True,
        )[0]
    return best


def best_preflight_rows(paths: list[Path]) -> dict[str, dict[str, str]]:
    best: dict[str, dict[str, str]] = {}
    for path in paths:
        for index, row in enumerate(read_csv(path), start=1):
            target = norm_host(cell(row, "Target", "HostName", "DnsName"))
            if not target:
                target = clean(cell(row, "Target", "HostName")).upper()
            if not target:
                continue
            row["_source"] = f"{path.name}:R{index}"
            current = best.get(target)
            if current is None or parse_timestamp(cell(row, "Timestamp")) >= parse_timestamp(cell(current, "Timestamp")):
                best[target] = row
    return best


def tracker_indexes(identifier_rows: list[dict[str, str]]) -> tuple[dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]]]:
    by_host: dict[str, list[dict[str, str]]] = {}
    by_mac: dict[str, list[dict[str, str]]] = {}
    for row in identifier_rows:
        if row.get("host"):
            by_host.setdefault(row["host"], []).append(row)
        if row.get("mac"):
            by_mac.setdefault(row["mac"], []).append(row)
    return by_host, by_mac


def rec_row(category: str, target: str, serial: str, host: str, status: str, details: str, source: str) -> dict[str, str]:
    return {
        "Category": category,
        "Target": target,
        "ObservedHostName": host,
        "ObservedSerial": serial,
        "Status": status,
        "Details": details,
        "Source": source,
    }


def detect_hostname_anomalies(hosts: set[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for host in sorted(h for h in hosts if h):
        if "0PR" in host:
            rows.append(rec_row(
                "HostnameAnomaly",
                host,
                "",
                host,
                "needs_site_context_review",
                "Literal 0PR sequence resembles OPR transposition; bounded review only.",
                "hostname",
            ))
    return rows


def build_reconciliation(
    alejandro: dict[str, dict[str, object]],
    tracker: dict[str, dict[str, object]],
    identifier_rows: list[dict[str, str]],
    identity_rows: dict[str, dict[str, str]],
    preflight_rows: dict[str, dict[str, str]],
) -> dict[str, list[dict[str, str]]]:
    categories: dict[str, list[dict[str, str]]] = {name: [] for _, names, _, _ in REPORT_PAGES for name in names}
    categories["MACConflict"] = []
    categories["InAlejandroNotDeployed"] = []
    categories["AlejandroSerialNotObserved"] = []
    categories["Unreachable"] = []
    categories["TrackerDuplicateException"] = []

    tracker_by_host, _tracker_by_mac = tracker_indexes(identifier_rows)
    observed_serial_hosts: dict[str, set[str]] = {}
    observed_hosts: set[str] = set()
    observed_serials: set[str] = set()

    for target, row in sorted(identity_rows.items()):
        observed_host = norm_host(cell(row, "ObservedHostName", "DnsName", "HostName")) or target
        observed_serial = norm_serial(cell(row, "ObservedSerial", "Serial", "ExpectedSerial"))
        observed_macs = split_macs(cell(row, "ObservedMACs", "ObservedMAC", "MACAddress", "ExpectedMAC"))
        ping_status = cell(row, "PingStatus", "Status")
        identity_status = cell(row, "IdentityStatus", "EvidenceStatus")
        source = row.get("_source", "")
        observed_hosts.add(observed_host)
        if observed_serial:
            observed_serials.add(observed_serial)
            observed_serial_hosts.setdefault(observed_serial, set()).add(observed_host or target)

        host_tracker_rows = tracker_by_host.get(observed_host, []) + ([] if observed_host == target else tracker_by_host.get(target, []))
        host_tracker_serials = {item.get("serial", "") for item in host_tracker_rows if item.get("serial")}
        host_tracker_macs = {item.get("mac", "") for item in host_tracker_rows if item.get("mac")}
        tracker_rec = tracker.get(observed_serial) if observed_serial else None

        if observed_serial and tracker_rec:
            tracker_hosts = {h for h in tracker_rec["hosts"] if h}
            if observed_host in tracker_hosts or target in tracker_hosts:
                categories["ConfirmedInTracker"].append(rec_row(
                    "ConfirmedInTracker",
                    target,
                    observed_serial,
                    observed_host,
                    "confirmed",
                    f"Observed serial matches tracker host {joined(tracker_hosts)}.",
                    source,
                ))
            else:
                categories["SerialMatchHostDrift"].append(rec_row(
                    "SerialMatchHostDrift",
                    target,
                    observed_serial,
                    observed_host,
                    "hostname_drift",
                    f"Serial exists in tracker but expected host is {joined(tracker_hosts)}.",
                    source,
                ))

        if observed_serial and not tracker_rec:
            if observed_serial not in alejandro:
                categories["UnaccountedSerial"].append(rec_row(
                    "UnaccountedSerial",
                    target,
                    observed_serial,
                    observed_host,
                    "missing_from_population",
                    "Observed serial is absent from both Alejandro and the deployment tracker.",
                    source,
                ))
            else:
                categories["InAlejandroNotDeployed"].append(rec_row(
                    "InAlejandroNotDeployed",
                    target,
                    observed_serial,
                    observed_host,
                    "needs_tracker_add",
                    "Observed serial is in Alejandro but absent from the deployment tracker.",
                    source,
                ))

        if observed_serial and host_tracker_serials and observed_serial not in host_tracker_serials:
            categories["SerialConflict"].append(rec_row(
                "SerialConflict",
                target,
                observed_serial,
                observed_host,
                "serial_conflict",
                f"Tracker host expects serial(s): {joined(host_tracker_serials)}.",
                source,
            ))

        if observed_macs and host_tracker_macs and observed_macs.isdisjoint(host_tracker_macs):
            categories["MACConflict"].append(rec_row(
                "MACConflict",
                target,
                observed_serial,
                observed_host,
                "mac_conflict",
                f"Observed MAC(s) {joined(observed_macs)} differ from tracker MAC(s) {joined(host_tracker_macs)}.",
                source,
            ))

        if not observed_serial and (is_reachable(ping_status) or is_identity_collected(identity_status)):
            categories["ReachableNeedsIdentity"].append(rec_row(
                "ReachableNeedsIdentity",
                target,
                "",
                observed_host,
                "reachable_needs_identity",
                "Reachability or partial identity evidence exists, but no serial was collected.",
                source,
            ))
        elif not observed_serial and is_unreachable(ping_status):
            categories["Unreachable"].append(rec_row(
                "Unreachable",
                target,
                "",
                observed_host,
                "unreachable",
                f"Identity row reports {ping_status}.",
                source,
            ))

    for serial, hosts in sorted(observed_serial_hosts.items()):
        if len(hosts) > 1:
            categories["DuplicateObservedSerial"].append(rec_row(
                "DuplicateObservedSerial",
                joined(hosts),
                serial,
                joined(hosts),
                "duplicate_observed_serial",
                "Same observed serial appeared on more than one surveyed host.",
                "identity",
            ))

    identity_targets = set(identity_rows)
    for target, row in sorted(preflight_rows.items()):
        if target in identity_targets:
            continue
        ping_status = cell(row, "PingStatus", "Reachability", "Status")
        source = row.get("_source", "")
        if is_reachable(ping_status):
            categories["ReachableNeedsIdentity"].append(rec_row(
                "ReachableNeedsIdentity",
                target,
                "",
                target,
                "reachable_needs_identity",
                "Reachable in preflight, but no identity evidence row was supplied.",
                source,
            ))
        elif is_unreachable(ping_status):
            categories["Unreachable"].append(rec_row(
                "Unreachable",
                target,
                "",
                target,
                "unreachable",
                f"Preflight reports {ping_status}.",
                source,
            ))

    for serial in sorted(set(alejandro) - set(tracker)):
        rec = alejandro[serial]
        categories["InAlejandroNotDeployed"].append(rec_row(
            "InAlejandroNotDeployed",
            joined(rec["hosts"]),
            serial,
            joined(rec["hosts"]),
            "needs_tracker_add",
            "Alejandro population serial is absent from the deployment tracker.",
            joined(rec["sources"]),
        ))

    for serial, rec in sorted(tracker.items()):
        if serial not in observed_serials:
            categories["TrackerSerialNotObserved"].append(rec_row(
                "TrackerSerialNotObserved",
                joined(rec["hosts"]),
                serial,
                joined(rec["hosts"]),
                "not_observed",
                "Deployment tracker serial was not observed in supplied identity evidence.",
                joined(rec["sources"]),
            ))

    for serial, rec in sorted(alejandro.items()):
        if serial not in observed_serials:
            categories["AlejandroSerialNotObserved"].append(rec_row(
                "AlejandroSerialNotObserved",
                joined(rec["hosts"]),
                serial,
                joined(rec["hosts"]),
                "not_observed",
                "Alejandro population serial was not observed in supplied identity evidence.",
                joined(rec["sources"]),
            ))

    all_hosts = observed_hosts | {row.get("host", "") for row in identifier_rows}
    for rec in alejandro.values():
        all_hosts |= {h for h in rec["hosts"] if h}
    categories["HostnameAnomaly"].extend(detect_hostname_anomalies(all_hosts))

    for row in TD.duplicate_exceptions(identifier_rows):
        categories["TrackerDuplicateException"].append(rec_row(
            "TrackerDuplicateException",
            row.get("HostNames", ""),
            row.get("Identifier", ""),
            row.get("HostNames", ""),
            "tracker_duplicate_exception",
            f"{row.get('IdentifierKind', '')} appears in {row.get('DeployedYesCount', '')} deployed tracker rows.",
            row.get("Sources", ""),
        ))

    return {key: rows for key, rows in categories.items() if rows}


def table_fields(rows: list[dict[str, str]]) -> list[str]:
    fields = ["Category", "Target", "ObservedHostName", "ObservedSerial", "Status", "Details", "Source"]
    extra = sorted({key for row in rows for key in row if key not in fields})
    return fields + extra


def write_json_js(path: Path, payload: dict[str, object]) -> None:
    text = json.dumps(payload, indent=2, sort_keys=True)
    text = text.replace("</", "<\\/")
    path.write_text(f"window.RECONCILE_DATA = {text};\n{CLIENT_JS}\n", encoding="utf-8")


def nav_html() -> str:
    links = [ALL_PAGE] + REPORT_PAGES
    return "\n".join(f'<a href="{file_name}">{html.escape(title)}</a>' for _, _, file_name, title in links)


def page_html(title: str, page: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body data-page="{html.escape(page)}">
  <aside class="nav">
    <div class="brand">SysAdminSuite</div>
    <div class="subbrand">Cybernet Reconcile</div>
    {nav_html()}
  </aside>
  <main>
    <section class="hero">
      <p class="eyebrow">Read-only local report</p>
      <h1>{html.escape(title)}</h1>
      <p class="lede">Alejandro serial population, deployment tracker records, identity evidence, and reachability evidence reconciled into local-only categories.</p>
    </section>
    <section id="overview"></section>
    <section class="panel">
      <div class="toolbar">
        <h2 id="table-title">Category rows</h2>
        <input id="filter" type="search" placeholder="Filter rows">
      </div>
      <div id="table"></div>
    </section>
  </main>
  <script src="data.js"></script>
</body>
</html>
"""


STYLE_CSS = """
/* Dark neon glow aesthetic for local-only operator review. */
:root {
  color-scheme: dark;
  --bg: #04110c;
  --panel: #071b14;
  --panel2: #0b261c;
  --text: #d8ffe7;
  --muted: #86b89a;
  --green: #49ff91;
  --amber: #ffd166;
  --red: #ff5d73;
  --line: rgba(73, 255, 145, 0.24);
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  background: radial-gradient(circle at top right, rgba(73,255,145,.14), transparent 28rem), var(--bg);
  color: var(--text);
  font: 15px/1.45 "Segoe UI", system-ui, sans-serif;
}
.nav {
  position: fixed;
  inset: 0 auto 0 0;
  width: 260px;
  padding: 26px 20px;
  background: rgba(3, 13, 9, .92);
  border-right: 1px solid var(--line);
}
.brand { color: var(--green); font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
.subbrand { color: var(--muted); margin: 4px 0 22px; }
.nav a {
  display: block;
  color: var(--text);
  text-decoration: none;
  padding: 9px 11px;
  margin: 4px 0;
  border: 1px solid transparent;
  border-radius: 10px;
}
.nav a:hover { border-color: var(--line); box-shadow: 0 0 18px rgba(73,255,145,.12); }
main { margin-left: 260px; padding: 32px; }
.hero, .panel, .tile {
  background: linear-gradient(180deg, rgba(11,38,28,.96), rgba(7,27,20,.94));
  border: 1px solid var(--line);
  border-radius: 18px;
  box-shadow: 0 0 30px rgba(73,255,145,.08);
}
.hero { padding: 30px; margin-bottom: 24px; }
.eyebrow { color: var(--green); letter-spacing: .12em; text-transform: uppercase; font-size: 12px; margin: 0 0 8px; }
h1 { margin: 0; font-size: clamp(30px, 5vw, 58px); }
.lede { color: var(--muted); max-width: 900px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; margin-bottom: 24px; }
.tile { padding: 18px; }
.tile strong { display: block; color: var(--green); font-size: 34px; text-shadow: 0 0 18px rgba(73,255,145,.5); }
.tile span { color: var(--muted); }
.coverage { height: 16px; background: #02100a; border: 1px solid var(--line); border-radius: 999px; overflow: hidden; margin: 12px 0 24px; }
.coverage div { height: 100%; background: linear-gradient(90deg, var(--green), #b7ff7a); box-shadow: 0 0 18px rgba(73,255,145,.7); }
.panel { padding: 22px; overflow: hidden; }
.toolbar { display: flex; gap: 16px; align-items: center; justify-content: space-between; }
input {
  width: min(360px, 100%);
  background: #020b07;
  color: var(--text);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 10px 12px;
}
table { width: 100%; border-collapse: collapse; margin-top: 16px; font-size: 13px; }
th, td { border-bottom: 1px solid rgba(134,184,154,.18); padding: 9px; text-align: left; vertical-align: top; }
th { color: var(--green); cursor: pointer; position: sticky; top: 0; background: var(--panel); }
tr.confirmed { box-shadow: inset 3px 0 0 var(--green); }
tr.alert { box-shadow: inset 3px 0 0 var(--red); }
tr.warn { box-shadow: inset 3px 0 0 var(--amber); }
.empty { color: var(--muted); padding: 20px 0; }
@media (max-width: 860px) {
  .nav { position: static; width: auto; }
  main { margin-left: 0; padding: 18px; }
  .toolbar { display: block; }
}
"""


CLIENT_JS = r"""
(function () {
  const data = window.RECONCILE_DATA || {};
  const page = document.body.dataset.page || "overview";
  const categories = data.categories || {};
  const pages = data.pages || {};
  const allRows = Object.values(categories).flat();
  const currentCategories = pages[page] || [];
  const rows = currentCategories.length ? currentCategories.flatMap(name => categories[name] || []) : allRows;

  function classify(row) {
    const cat = row.Category || "";
    if (cat === "ConfirmedInTracker") return "confirmed";
    if (/Conflict|Duplicate|Unaccounted/.test(cat)) return "alert";
    if (/Drift|Needs|Unreachable|Anomaly|Remaining|NotObserved/.test(cat)) return "warn";
    return "";
  }

  function renderOverview() {
    const el = document.getElementById("overview");
    if (!el) return;
    const total = Number(data.summary?.observed_serials || 0);
    const confirmed = Number(data.summary?.confirmed || 0);
    const pct = total ? Math.round((confirmed / total) * 100) : 0;
    const tiles = Object.entries(data.counts || {}).map(([name, count]) =>
      `<div class="tile"><strong>${count}</strong><span>${name}</span></div>`
    ).join("");
    el.innerHTML = `<div class="tiles">${tiles}</div><div class="coverage"><div style="width:${pct}%"></div></div>`;
  }

  function renderTable(inputRows) {
    const host = document.getElementById("table");
    const title = document.getElementById("table-title");
    if (!host) return;
    if (title) title.textContent = currentCategories.length ? currentCategories.join(", ") : "All categories";
    if (!inputRows.length) {
      host.innerHTML = '<div class="empty">No rows for this category.</div>';
      return;
    }
    const fields = data.fields || Object.keys(inputRows[0]);
    const head = fields.map(f => `<th data-field="${f}">${f}</th>`).join("");
    const body = inputRows.map(row => `<tr class="${classify(row)}">${
      fields.map(f => `<td>${String(row[f] || "").replace(/[&<>"']/g, ch => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
      }[ch]))}</td>`).join("")
    }</tr>`).join("");
    host.innerHTML = `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
    host.querySelectorAll("th").forEach(th => th.addEventListener("click", () => {
      const field = th.dataset.field;
      const sorted = [...inputRows].sort((a, b) => String(a[field] || "").localeCompare(String(b[field] || "")));
      renderTable(sorted);
    }));
  }

  renderOverview();
  renderTable(rows);
  const filter = document.getElementById("filter");
  if (filter) {
    filter.addEventListener("input", () => {
      const q = filter.value.toLowerCase();
      renderTable(rows.filter(row => Object.values(row).join(" ").toLowerCase().includes(q)));
    });
  }
}());
"""


def write_site(output_dir: Path, categories: dict[str, list[dict[str, str]]]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    all_rows = [row for rows in categories.values() for row in rows]
    counts = {name: len(rows) for name, rows in sorted(categories.items())}
    fields = table_fields(all_rows) if all_rows else table_fields([])
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "counts": counts,
        "categories": categories,
        "fields": fields,
        "pages": {page: categories for page, categories, _, _ in REPORT_PAGES},
        "summary": {
            "confirmed": counts.get("ConfirmedInTracker", 0),
            "observed_serials": len({row["ObservedSerial"] for row in all_rows if row.get("ObservedSerial")}),
        },
    }
    (output_dir / "style.css").write_text(STYLE_CSS, encoding="utf-8")
    write_json_js(output_dir / "data.js", payload)
    (output_dir / "index.html").write_text(page_html("Cybernet reconciliation", "overview"), encoding="utf-8")
    for page, _category, file_name, title in REPORT_PAGES:
        (output_dir / file_name).write_text(page_html(title, page), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a local Cybernet reconciliation HTML report")
    parser.add_argument("--alejandro", required=True, help="Alejandro-style Cybernet workbook")
    parser.add_argument("--tracker", required=True, help="Deployment tracker workbook")
    parser.add_argument("--tracker-sheet", default="Deployments")
    parser.add_argument("--header-scan-rows", type=int, default=40)
    parser.add_argument("--identity-csv", action="append", default=[], help="workstation_identity.csv; repeatable")
    parser.add_argument("--identity-glob", action="append", default=[], help="glob for workstation_identity*.csv; repeatable")
    parser.add_argument("--preflight-csv", action="append", default=[], help="network_preflight.csv; repeatable")
    parser.add_argument("--output-dir", default="survey/output/cybernet_reconciliation_report")
    args = parser.parse_args()

    alejandro_path = Path(args.alejandro)
    tracker_path = Path(args.tracker)
    if not alejandro_path.is_file():
        print(f"[sas-cybernet-reconcile-report] ERROR: Alejandro workbook not found: {alejandro_path}", file=sys.stderr)
        return 1
    if not tracker_path.is_file():
        print(f"[sas-cybernet-reconcile-report] ERROR: tracker workbook not found: {tracker_path}", file=sys.stderr)
        return 1
    if args.header_scan_rows < 1:
        print("[sas-cybernet-reconcile-report] ERROR: --header-scan-rows must be positive", file=sys.stderr)
        return 1

    identity_paths = expand_csv_paths(args.identity_csv, args.identity_glob)
    preflight_paths = expand_csv_paths(args.preflight_csv, [])

    try:
        alejandro = TD.parse_alejandro(alejandro_path)
        tracker, identifier_rows = TD.parse_tracker(tracker_path, args.tracker_sheet, args.header_scan_rows)
    except ValueError as exc:
        print(f"[sas-cybernet-reconcile-report] ERROR: {exc}", file=sys.stderr)
        return 1

    categories = build_reconciliation(
        alejandro,
        tracker,
        identifier_rows,
        best_identity_rows(identity_paths),
        best_preflight_rows(preflight_paths),
    )
    output_dir = Path(args.output_dir)
    write_site(output_dir, categories)

    print(f"[sas-cybernet-reconcile-report] wrote {output_dir / 'index.html'}")
    for name, rows in sorted(categories.items()):
        print(f"[sas-cybernet-reconcile-report] {name}={len(rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
