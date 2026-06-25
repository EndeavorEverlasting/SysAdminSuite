#!/usr/bin/env bash
# Contract tests for the Cybernet reconciliation HTML report generator.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-reconcile-report.sh"
PY="survey/sas-cybernet-reconcile-report.py"

fail() { printf '[cybernet-reconcile-report-contracts] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[cybernet-reconcile-report-contracts] PASS: %s\n' "$*"; }

[[ -f "$RUNNER" ]] || fail "missing runner: $RUNNER"
[[ -f "$PY" ]] || fail "missing python generator: $PY"
bash -n "$RUNNER"

# Reuse the wrapper's interpreter-selection contract (python3 -> python -> py -3)
# so this test does not fail in Git Bash/MSYS2 where only `py -3` is present.
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1 || {
  fail "python required for contract test"
}
PYTHON_CMD=(python3)
command -v python3 >/dev/null 2>&1 || PYTHON_CMD=(python)
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || PYTHON_CMD=(py -3)
"${PYTHON_CMD[@]}" -m py_compile "$PY"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ALEJANDRO="$TMP_DIR/alejandro-fixture.xlsx"
TRACKER="$TMP_DIR/tracker-fixture.xlsx"
IDENTITY="$TMP_DIR/workstation_identity.csv"
PREFLIGHT="$TMP_DIR/network_preflight.csv"
REPORT_DIR="$TMP_DIR/report"

"${PYTHON_CMD[@]}" - "$ALEJANDRO" "$TRACKER" "$IDENTITY" "$PREFLIGHT" <<'PY'
import csv
import sys
from openpyxl import Workbook

alejandro_path, tracker_path, identity_path, preflight_path = sys.argv[1:5]

wb = Workbook()
ws = wb.active
ws.title = "AKBAR WAVE 1"
ws["A1"] = "MEDTEST24-ALEJONLY"
po = wb.create_sheet("PO 1")
po.append(["Host", "Serial"])
po.append(["WTS001OPR001", "MEDTEST24-CONFIRM"])
po.append(["WTS001OPR002", "MEDTEST24-DRIFT"])
po.append(["WTS001OPR004", "MEDTEST24-MAC01"])
po.append(["WNH2650PR001", "MEDTEST24-ANOMALY"])
wb.save(alejandro_path)

twb = Workbook()
dep = twb.active
dep.title = "Deployments"
dep.append(["Device Type", "Cybernet Hostname", "Cybernet Serial", "Cybernet MAC", "Neuron S/N", "Deployed"])
dep.append(["Cybernet-Neuron", "WTS001OPR001", "MEDTEST24-CONFIRM", "000D050AA101", "NEU-001", "Yes"])
dep.append(["Cybernet-Neuron", "WTS001OPR999", "MEDTEST24-DRIFT", "000D050AA102", "NEU-002", "Yes"])
dep.append(["Cybernet-Neuron", "WTS001OPR003", "MEDTEST24-EXPECTED", "000D050AA103", "NEU-003", "Yes"])
dep.append(["Cybernet-Neuron", "WTS001OPR004", "MEDTEST24-MAC01", "000D050AA104", "NEU-004", "Yes"])
dep.append(["Cybernet-Neuron", "WTS001OPR010", "MEDTEST24-DUPTRACK", "000D050AA110", "NEU-DUP", "Yes"])
dep.append(["Cybernet-Neuron", "WTS001OPR011", "MEDTEST24-DUPTRACK", "000D050AA111", "NEU-DUP", "Yes"])
twb.save(tracker_path)

with open(identity_path, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=[
        "Timestamp", "Target", "ResolvedAddress", "PingStatus", "DnsName", "ObservedHostName",
        "ObservedSerial", "ObservedMACs", "TransportUsed", "IdentityStatus", "Notes",
    ])
    writer.writeheader()
    writer.writerow({
        "Timestamp": "2026-06-25T12:00:00Z", "Target": "WTS001OPR001", "ResolvedAddress": "10.0.0.1",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR001", "ObservedHostName": "WTS001OPR001",
        "ObservedSerial": "MEDTEST24-CONFIRM", "ObservedMACs": "000D050AA101", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:01:00Z", "Target": "WTS001OPR002", "ResolvedAddress": "10.0.0.2",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR002", "ObservedHostName": "WTS001OPR002",
        "ObservedSerial": "MEDTEST24-DRIFT", "ObservedMACs": "000D050AA102", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:02:00Z", "Target": "WTS001OPR003", "ResolvedAddress": "10.0.0.3",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR003", "ObservedHostName": "WTS001OPR003",
        "ObservedSerial": "MEDTEST24-CONFLICT", "ObservedMACs": "000D050AA103", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:03:00Z", "Target": "WTS001OPR004", "ResolvedAddress": "10.0.0.4",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR004", "ObservedHostName": "WTS001OPR004",
        "ObservedSerial": "MEDTEST24-MAC01", "ObservedMACs": "000D050AA999", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:04:00Z", "Target": "WTS001OPR005", "ResolvedAddress": "10.0.0.5",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR005", "ObservedHostName": "WTS001OPR005",
        "ObservedSerial": "MEDTEST24-DUPOBS", "ObservedMACs": "000D050AA105", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:05:00Z", "Target": "WTS001OPR006", "ResolvedAddress": "10.0.0.6",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR006", "ObservedHostName": "WTS001OPR006",
        "ObservedSerial": "MEDTEST24-DUPOBS", "ObservedMACs": "000D050AA106", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })
    writer.writerow({
        "Timestamp": "2026-06-25T12:06:00Z", "Target": "WTS001OPR007", "ResolvedAddress": "10.0.0.7",
        "PingStatus": "Reachable", "DnsName": "WTS001OPR007", "ObservedHostName": "WTS001OPR007",
        "ObservedSerial": "MEDTEST24-NEW", "ObservedMACs": "000D050AA107", "TransportUsed": "WMI",
        "IdentityStatus": "IdentityCollected", "Notes": "synthetic",
    })

with open(preflight_path, "w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=["Timestamp", "Target", "PingStatus", "Port", "PortStatus"])
    writer.writeheader()
    writer.writerow({"Timestamp": "2026-06-25T12:07:00Z", "Target": "WTS001OPR008", "PingStatus": "Reachable", "Port": "135", "PortStatus": "Open"})
    writer.writerow({"Timestamp": "2026-06-25T12:08:00Z", "Target": "WTS001OPR009", "PingStatus": "NoPing", "Port": "135", "PortStatus": "ClosedOrFiltered"})
    writer.writerow({"Timestamp": "2026-06-25T12:09:00Z", "Target": "WTS001OPR012", "PingStatus": "NoPing", "Port": "445", "PortStatus": "Open"})
PY

bash "$RUNNER" \
  --alejandro "$ALEJANDRO" \
  --tracker "$TRACKER" \
  --identity-csv "$IDENTITY" \
  --preflight-csv "$PREFLIGHT" \
  --output-dir "$REPORT_DIR" >/dev/null

for path in \
  "$REPORT_DIR/index.html" \
  "$REPORT_DIR/confirmations.html" \
  "$REPORT_DIR/duplicates.html" \
  "$REPORT_DIR/conflicts.html" \
  "$REPORT_DIR/drift.html" \
  "$REPORT_DIR/unaccounted.html" \
  "$REPORT_DIR/coverage.html" \
  "$REPORT_DIR/remaining.html" \
  "$REPORT_DIR/anomalies.html" \
  "$REPORT_DIR/style.css" \
  "$REPORT_DIR/data.js"; do
  [[ -f "$path" ]] || fail "missing report output: $path"
done

for token in \
  ConfirmedInTracker \
  SerialMatchHostDrift \
  SerialConflict \
  MACConflict \
  DuplicateObservedSerial \
  UnaccountedSerial \
  ReachableNeedsIdentity \
  Unreachable \
  InAlejandroNotDeployed \
  TrackerSerialNotObserved \
  AlejandroSerialNotObserved \
  TrackerDuplicateException \
  HostnameAnomaly; do
  grep -q "$token" "$REPORT_DIR/data.js" || fail "missing category token in data.js: $token"
done

grep -q "Cybernet reconciliation" "$REPORT_DIR/index.html" || fail "index page missing title"
grep -q "neon" "$REPORT_DIR/style.css" || grep -q "glow" "$REPORT_DIR/style.css" || fail "style should preserve glow aesthetic"
# Open-port-but-NoPing host must be classified ReachableNeedsIdentity, not Unreachable.
"${PYTHON_CMD[@]}" - "$REPORT_DIR/data.js" <<'PY' || fail "open preflight port must classify as ReachableNeedsIdentity (not Unreachable)"
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
marker = "window.RECONCILE_DATA = "
data, _ = json.JSONDecoder().raw_decode(text, text.index(marker) + len(marker))
cats = data["categories"]
def hosts(cat):
    return {r.get("Target", "") for r in cats.get(cat, [])}
assert "WTS001OPR012" in hosts("ReachableNeedsIdentity"), "open-port host missing from ReachableNeedsIdentity"
assert "WTS001OPR012" not in hosts("Unreachable"), "open-port host wrongly marked Unreachable"
PY

MISSING_ERR="$TMP_DIR/missing.err"
if bash "$RUNNER" \
  --alejandro "$ALEJANDRO" \
  --tracker "$TRACKER" \
  --identity-csv "$TMP_DIR/missing_identity.csv" \
  --output-dir "$TMP_DIR/missing_report" 2>"$MISSING_ERR"; then
  fail "missing explicit evidence CSV path should fail"
fi
grep -q "evidence CSV not found" "$MISSING_ERR" || fail "missing explicit evidence CSV should produce actionable error"

git check-ignore -q survey/output/cybernet_reconciliation_report/index.html || {
  fail "survey/output report path must remain gitignored"
}

pass "synthetic reconciliation categories, HTML output, and ignore policy"
