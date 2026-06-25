#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-xlsx-targets.sh"
PY="survey/sas-cybernet-xlsx-targets.py"
DIFF_RUNNER="survey/sas-cybernet-tracker-diff.sh"
DIFF_PY="survey/sas-cybernet-tracker-diff.py"

[[ -f "$RUNNER" ]] || { echo "missing runner: $RUNNER"; exit 1; }
[[ -f "$PY" ]] || { echo "missing python ingester: $PY"; exit 1; }
[[ -f "$DIFF_RUNNER" ]] || { echo "missing tracker diff runner: $DIFF_RUNNER"; exit 1; }
[[ -f "$DIFF_PY" ]] || { echo "missing tracker diff python: $DIFF_PY"; exit 1; }
bash -n "$RUNNER"
bash -n "$DIFF_RUNNER"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
  echo "python required for contract test"
  exit 1
}

PYTHON_CMD=(python3)
command -v python3 >/dev/null 2>&1 || PYTHON_CMD=(python)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PRIMARY="$TMP_DIR/alejandro-fixture.xlsx"
ENRICH="$TMP_DIR/enrichment-fixture.xlsx"
TRACKER="$TMP_DIR/tracker-fixture.xlsx"
OUT_MANIFEST="$TMP_DIR/cybernet_targets.csv"
OUT_REPORT="$TMP_DIR/enrichment_report.csv"
OUT_GAPS="$TMP_DIR/gaps.csv"
DIFF_PREFIX="$TMP_DIR/diff/cybernet"

"${PYTHON_CMD[@]}" - "$PRIMARY" "$ENRICH" "$TRACKER" <<'PY'
import sys
from openpyxl import Workbook

primary_path, enrich_path, tracker_path = sys.argv[1:4]

wb = Workbook()
ws = wb.active
ws.title = "AKBAR WAVE 1 AND 2"
ws["A1"] = "MEDTEST24-00001"
ws["A2"] = "MEDTEST24-00001"
ws["A3"] = "MEDTEST24-00002"
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

twb = Workbook()
dep = twb.active
dep.title = "Deployments"
dep.append(["Device Type", "Deployed", "Cybernet Hostname", "Cybernet Serial", "Cybernet MAC"])
dep.append(["Cybernet-Neuron", "No", "WTS001OPR001", "MEDTEST24-00003", "000D050AA58F"])
dep.append(["Cybernet-Neuron", "No", "WTS001OPR010", "MEDTEST24-00006", "000D050AA590"])
dep.append(["Cybernet-Neuron", "No", "WTS001OPR011", "MEDTEST24-00006", "000D050AA591"])
dep.append(["Cybernet-Neuron", "Yes", "WTS001OPR020", "MEDTEST24-00005", "000D050AA592"])
dep.append(["Cybernet-Neuron", "Yes", "WTS001OPR021", "MEDTEST24-00005", "000D050AA593"])
twb.save(tracker_path)
PY

bash "$RUNNER" \
  --workbook "$PRIMARY" \
  --enrichment "$ENRICH" \
  --output "$OUT_MANIFEST" \
  --report "$OUT_REPORT" \
  --gaps "$OUT_GAPS" \
  --device-type Cybernet >/dev/null

for path in "$OUT_MANIFEST" "$OUT_REPORT" "$OUT_GAPS"; do
  [[ -f "$path" ]] || { echo "missing output: $path"; exit 1; }
done

manifest_rows="$(($(wc -l < "$OUT_MANIFEST") - 1))"
report_rows="$(($(wc -l < "$OUT_REPORT") - 1))"
gap_rows="$(($(wc -l < "$OUT_GAPS") - 1))"

[[ "$manifest_rows" -gt 0 ]] || { echo "expected manifest rows > 0"; exit 1; }
[[ "$report_rows" -gt 0 ]] || { echo "expected report rows > 0"; exit 1; }

head -n 1 "$OUT_MANIFEST" | grep -q 'IdentifierType'
head -n 1 "$OUT_REPORT" | grep -q 'ResolutionStatus'
grep -qE 'FULL|PARTIAL|MINIMAL' "$OUT_REPORT"

bash "$DIFF_RUNNER" \
  --alejandro "$PRIMARY" \
  --tracker "$TRACKER" \
  --output-prefix "$DIFF_PREFIX" \
  --device-type Cybernet >/dev/null

for suffix in \
  alejandro_unique_serials \
  tracker_unique_serials \
  alejandro_already_tracked \
  alejandro_untracked \
  tracker_duplicate_exceptions; do
  [[ -f "${DIFF_PREFIX}_${suffix}.csv" ]] || { echo "missing diff output: ${DIFF_PREFIX}_${suffix}.csv"; exit 1; }
done

"${PYTHON_CMD[@]}" - "$DIFF_PREFIX" <<'PY'
import csv
import sys

prefix = sys.argv[1]

def rows(name):
    with open(f"{prefix}_{name}.csv", newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))

unique = {row["Serial"]: row for row in rows("alejandro_unique_serials")}
assert len(unique) == 4, unique
assert unique["MEDTEST24-00001"]["RowCount"] == "2", unique["MEDTEST24-00001"]
assert unique["MEDTEST24-00001"]["ProbeReady"] == "No", unique["MEDTEST24-00001"]
assert unique["MEDTEST24-00003"]["ProbeReady"] == "Yes", unique["MEDTEST24-00003"]

already = rows("alejandro_already_tracked")
assert [row["Serial"] for row in already] == ["MEDTEST24-00003"], already

untracked = {row["Serial"]: row for row in rows("alejandro_untracked")}
assert set(untracked) == {"MEDTEST24-00001", "MEDTEST24-00002", "MEDTEST24-00004"}, untracked
assert untracked["MEDTEST24-00001"]["IdentifierType"] == "Serial", untracked["MEDTEST24-00001"]
assert untracked["MEDTEST24-00004"]["IdentifierType"] == "HostName", untracked["MEDTEST24-00004"]

dups = rows("tracker_duplicate_exceptions")
assert any(row["IdentifierKind"] == "serial" and row["Identifier"] == "MEDTEST24-00005" for row in dups), dups
assert not any(row["Identifier"] == "MEDTEST24-00006" for row in dups), dups
PY

printf 'Cybernet xlsx target ingester contracts passed (manifest=%s report=%s gaps=%s).\n' \
  "$manifest_rows" "$report_rows" "$gap_rows"
