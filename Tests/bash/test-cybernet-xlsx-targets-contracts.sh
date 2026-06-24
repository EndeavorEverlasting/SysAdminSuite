#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-xlsx-targets.sh"
PY="survey/sas-cybernet-xlsx-targets.py"

[[ -f "$RUNNER" ]] || { echo "missing runner: $RUNNER"; exit 1; }
[[ -f "$PY" ]] || { echo "missing python ingester: $PY"; exit 1; }
bash -n "$RUNNER"

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

printf 'Cybernet xlsx target ingester contracts passed (manifest=%s report=%s gaps=%s).\n' \
  "$manifest_rows" "$report_rows" "$gap_rows"
