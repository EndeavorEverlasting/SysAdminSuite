#!/usr/bin/env bash
# Contract tests for Cybernet XLSX target ingester and Alejandro-vs-tracker serial rules.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-xlsx-targets.sh"
PY="survey/sas-cybernet-xlsx-targets.py"
DIFF_RUNNER="survey/sas-cybernet-tracker-diff.sh"
DIFF_PY="survey/sas-cybernet-tracker-diff.py"
CONTRACT_PY="$ROOT/Tests/bash/cybernet_serial_contract_fixtures.py"

[[ -f "$RUNNER" ]] || { echo "missing runner: $RUNNER"; exit 1; }
[[ -f "$PY" ]] || { echo "missing python ingester: $PY"; exit 1; }
[[ -f "$DIFF_RUNNER" ]] || { echo "missing tracker diff runner: $DIFF_RUNNER"; exit 1; }
[[ -f "$DIFF_PY" ]] || { echo "missing tracker diff python: $DIFF_PY"; exit 1; }
[[ -f "$CONTRACT_PY" ]] || { echo "missing contract fixture helper: $CONTRACT_PY"; exit 1; }
bash -n "$RUNNER"
bash -n "$DIFF_RUNNER"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "python required for contract test"
  exit 1
}

PYTHON_CMD=(python3)
command -v python3 >/dev/null 2>&1 || PYTHON_CMD=(python)

fail() { printf '[cybernet-xlsx-contracts] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[cybernet-xlsx-contracts] PASS: %s\n' "$*"; }

run_ingester() {
  local workbook="$1" enrichment="$2" manifest="$3" report="$4" gaps="$5"
  local -a args=(--workbook "$workbook" --output "$manifest" --report "$report" --gaps "$gaps" --device-type Cybernet)
  if [[ -n "$enrichment" ]]; then
    args+=(--enrichment "$enrichment")
  fi
  bash "$RUNNER" "${args[@]}" >/dev/null
}

count_data_rows() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing output: $path"
  local lines
  lines="$(wc -l < "$path" | tr -d ' ')"
  [[ "$lines" -ge 1 ]] || fail "empty csv: $path"
  echo "$((lines - 1))"
}

assert_manifest_serial_count() {
  local manifest="$1" serial="$2" expected="$3"
  local count
  count="$("${PYTHON_CMD[@]}" - "$manifest" "$serial" <<'PY'
import csv, sys
path, serial = sys.argv[1:3]
count = 0
with open(path, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        if row.get("Serial", "").upper() == serial.upper():
            count += 1
print(count)
PY
)"
  [[ "$count" -eq "$expected" ]] || fail "expected $expected manifest row(s) for serial $serial, got $count"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# --- baseline smoke (existing contract) ---
PRIMARY="$TMP_DIR/alejandro-fixture.xlsx"
ENRICH="$TMP_DIR/enrichment-fixture.xlsx"
OUT_MANIFEST="$TMP_DIR/cybernet_targets.csv"
OUT_REPORT="$TMP_DIR/enrichment_report.csv"
OUT_GAPS="$TMP_DIR/gaps.csv"

"${PYTHON_CMD[@]}" - "$PRIMARY" "$ENRICH" <<'PY'
import sys
from openpyxl import Workbook

primary_path, enrich_path = sys.argv[1:3]

wb = Workbook()
ws = wb.active
ws.title = "AKBAR WAVE 1 AND 2"
ws["A1"] = "MEDTEST24-00001"
ws["A2"] = "MEDTEST24-00002"
po = wb.create_sheet("PO 1")
po["A1"] = "wts001opr001"
po["B1"] = "MEDTEST24-00003"
po["A2"] = "wts001opr002"
po["B2"] = "MEDTEST24-00004"
wb.save(primary_path)

ewb = Workbook()
dep = ewb.active
dep.title = "Deployments"
dep.append(["Device Type", "Cybernet Hostname", "Cybernet Serial", "Cybernet MAC"])
dep.append(["Cybernet-Neuron", "WTS001OPR001", "MEDTEST24-00001", "000D050AA58D"])
dep.append(["Cybernet-Neuron", "WTS001OPR002", "MEDTEST24-00002", "000D050AA58E"])
host = ewb.create_sheet("SSUH Host")
host["A1"] = "WTS001OPR099"
ewb.save(enrich_path)
PY

run_ingester "$PRIMARY" "$ENRICH" "$OUT_MANIFEST" "$OUT_REPORT" "$OUT_GAPS"
[[ "$(count_data_rows "$OUT_MANIFEST")" -gt 0 ]] || fail "expected manifest rows > 0"
[[ "$(count_data_rows "$OUT_REPORT")" -gt 0 ]] || fail "expected report rows > 0"
head -n 1 "$OUT_MANIFEST" | grep -q 'IdentifierType'
head -n 1 "$OUT_REPORT" | grep -q 'ResolutionStatus'
grep -qE 'FULL|PARTIAL|MINIMAL' "$OUT_REPORT"
pass "baseline smoke ingester outputs"

# --- scenario fixtures (generated, sanitized) ---
FIXTURE_JSON="$("${PYTHON_CMD[@]}" "$CONTRACT_PY" --emit-fixtures "$TMP_DIR")"
PRIMARY_DUP="$(printf '%s' "$FIXTURE_JSON" | "${PYTHON_CMD[@]}" -c 'import json,sys; print(json.load(sys.stdin)["primary_dup"])')"
PRIMARY_DIFF="$(printf '%s' "$FIXTURE_JSON" | "${PYTHON_CMD[@]}" -c 'import json,sys; print(json.load(sys.stdin)["primary_diff"])')"
TRACKER_DIFF="$(printf '%s' "$FIXTURE_JSON" | "${PYTHON_CMD[@]}" -c 'import json,sys; print(json.load(sys.stdin)["tracker_diff"])')"
PRIMARY_SERIAL_ONLY="$(printf '%s' "$FIXTURE_JSON" | "${PYTHON_CMD[@]}" -c 'import json,sys; print(json.load(sys.stdin)["primary_serial_only"])')"

# --- Alejandro duplicate serial collapse ---
MANIFEST_DUP="$TMP_DIR/manifest_dup.csv"
REPORT_DUP="$TMP_DIR/report_dup.csv"
GAPS_DUP="$TMP_DIR/gaps_dup.csv"
run_ingester "$PRIMARY_DUP" "" "$MANIFEST_DUP" "$REPORT_DUP" "$GAPS_DUP"
assert_manifest_serial_count "$MANIFEST_DUP" "MEDTEST24-DUP01" 1
assert_manifest_serial_count "$MANIFEST_DUP" "MEDTEST24-UNIQ01" 1
[[ "$(count_data_rows "$MANIFEST_DUP")" -eq 2 ]] || fail "duplicate collapse should leave two unique serial targets"
grep -q 'WTS001OPR001' "$MANIFEST_DUP" || fail "collapsed duplicate serial should retain PO hostname enrichment"
pass "Alejandro duplicate serial collapse"

# --- serial-only untracked row retained but not live-probe-ready ---
MANIFEST_SO="$TMP_DIR/manifest_serial_only.csv"
REPORT_SO="$TMP_DIR/report_serial_only.csv"
GAPS_SO="$TMP_DIR/gaps_serial_only.csv"
run_ingester "$PRIMARY_SERIAL_ONLY" "" "$MANIFEST_SO" "$REPORT_SO" "$GAPS_SO"
grep -q 'MEDTEST24-SERIALONLY01' "$MANIFEST_SO" || fail "serial-only untracked row must remain in manifest"
"${PYTHON_CMD[@]}" - "$MANIFEST_SO" "$REPORT_SO" "$GAPS_SO" <<'PY'
import csv, sys

manifest, report, gaps = sys.argv[1:4]
rows = list(csv.DictReader(open(manifest, newline="", encoding="utf-8")))
match = [r for r in rows if r.get("Serial") == "MEDTEST24-SERIALONLY01"]
if len(match) != 1:
    raise SystemExit(f"expected one serial-only manifest row, got {len(match)}")
row = match[0]
if not row.get("Serial"):
    raise SystemExit("serial-only row missing Serial column")
if row.get("MACAddress", "").strip():
    raise SystemExit("serial-only row should not be live-probe-ready (MAC still empty)")
report_rows = {r["ResolvedSerial"]: r for r in csv.DictReader(open(report, newline="", encoding="utf-8"))}
status = report_rows.get("MEDTEST24-SERIALONLY01", {}).get("ResolutionStatus", "")
if status == "FULL":
    raise SystemExit("serial-only row must not reach FULL resolution")
gap_serials = {r.get("Serial") for r in csv.DictReader(open(gaps, newline="", encoding="utf-8"))}
if "MEDTEST24-SERIALONLY01" not in gap_serials:
    raise SystemExit("serial-only row should appear in gap report until enriched")
PY
pass "serial-only untracked row retained but not live-probe-ready"

# --- tracker serial inventory contract (inline until ingester emits diff CSVs) ---
CONTRACT_RESULT="$("${PYTHON_CMD[@]}" "$CONTRACT_PY" --validate-diff "$PRIMARY_DIFF" "$TRACKER_DIFF")"
printf '%s' "$CONTRACT_RESULT" | "${PYTHON_CMD[@]}" -c '
import json, sys
data = json.load(sys.stdin)
alejandro_unique = set(data["alejandro_unique_serials"])
tracker_unique = set(data["tracker_unique_serials"])
already = set(data["already_tracked"])
untracked = set(data["untracked"])
if alejandro_unique & tracker_unique != already:
    raise SystemExit("already_tracked must equal alejandro ∩ tracker unique serials")
if untracked != (alejandro_unique - tracker_unique):
    raise SystemExit("untracked must equal alejandro unique serials minus tracker inventory")
if "MEDTEST24-TRACKED01" not in already:
    raise SystemExit("tracked serial missing from already_tracked set")
if "MEDTEST24-NEW01" not in untracked:
    raise SystemExit("new alejandro serial missing from untracked set")
if "MEDTEST24-TRACKED01" in untracked:
    raise SystemExit("tracked serial must be excluded from untracked candidates")
'
pass "tracker serial exclusion contract"

# --- deployed-yes duplicate exception contract ---
DUP_CONTRACT="$("${PYTHON_CMD[@]}" "$CONTRACT_PY" --validate-duplicates "$TRACKER_DIFF")"
printf '%s' "$DUP_CONTRACT" | "${PYTHON_CMD[@]}" -c '
import json, sys
data = json.load(sys.stdin)
exceptions = data["duplicate_exceptions"]
non_deployed = data["non_deployed_repeats"]
if any(item["identifier"] == "MEDTEST24-HIST01" for item in exceptions):
    raise SystemExit("repeated non-deployed identifier must not emit duplicate exception")
if not any(item["identifier"] == "MEDTEST24-DUPYES01" and item["deployed_yes_count"] > 1 for item in exceptions):
    raise SystemExit("repeated Deployed=Yes identifier must emit duplicate exception")
if non_deployed.get("MEDTEST24-HIST01", 0) < 2:
    raise SystemExit("fixture must include repeated non-deployed tracker identifier")
'
pass "deployed-yes duplicate exception contract"

# --- tracker diff runner outputs ---
DIFF_PREFIX="$TMP_DIR/diff/cybernet"
bash "$DIFF_RUNNER" \
  --alejandro "$PRIMARY_DIFF" \
  --tracker "$TRACKER_DIFF" \
  --output-prefix "$DIFF_PREFIX" \
  --device-type Cybernet >/dev/null

UNTRACKED_CSV="${DIFF_PREFIX}_alejandro_untracked.csv"
DUP_EXCEPTIONS_CSV="${DIFF_PREFIX}_tracker_duplicate_exceptions.csv"
for suffix in \
  alejandro_unique_serials \
  tracker_unique_serials \
  alejandro_already_tracked \
  alejandro_untracked \
  tracker_duplicate_exceptions; do
  [[ -f "${DIFF_PREFIX}_${suffix}.csv" ]] || fail "missing diff output: ${DIFF_PREFIX}_${suffix}.csv"
done
grep -q 'MEDTEST24-NEW01' "$UNTRACKED_CSV" || fail "diff untracked csv missing new serial"
grep -q 'MEDTEST24-TRACKED01' "$UNTRACKED_CSV" && fail "diff untracked csv must exclude tracked serial"
grep -q 'MEDTEST24-DUPYES01' "$DUP_EXCEPTIONS_CSV" || fail "duplicate exceptions csv missing deployed-yes duplicate"
grep -q 'MEDTEST24-HIST01' "$DUP_EXCEPTIONS_CSV" && fail "duplicate exceptions csv must ignore non-deployed repeats"
pass "tracker diff runner csv contract"

printf 'Cybernet xlsx target ingester contracts passed (baseline + serial comparison rules).\n'
