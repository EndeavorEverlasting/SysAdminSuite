#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-neuron-name-availability"
SUMMARY_OUT="$OUT_DIR/neuron_name_availability_summary.csv"
DETAIL_OUT="$OUT_DIR/neuron_name_availability_detail.csv"
DASHBOARD_OUT="$OUT_DIR/neuron_name_availability.html"
WRAP_OUT_DIR="$OUT_DIR/wrapper"
GUARD_ERR="$OUT_DIR/authorization_guard.err"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/survey/sas-neuron-name-availability.py" \
  --convention LIJ-MACH- \
  --convention CCMC-MACH- \
  --nmap-xml "$ROOT/survey/fixtures/neuron_name_availability_sample.xml" \
  --summary-output "$SUMMARY_OUT" \
  --detail-output "$DETAIL_OUT" \
  --dashboard "$DASHBOARD_OUT" \
  --candidate-count 5

[[ -f "$SUMMARY_OUT" ]] || { echo "FAIL: missing summary output" >&2; exit 1; }
[[ -f "$DETAIL_OUT" ]] || { echo "FAIL: missing detail output" >&2; exit 1; }
[[ -f "$DASHBOARD_OUT" ]] || { echo "FAIL: missing dashboard output" >&2; exit 1; }

for col in ConventionPrefix FirstGapName NextAfterHighestName GapCandidates NextCandidates; do
  grep -q "$col" "$SUMMARY_OUT" || { echo "FAIL: missing summary column $col" >&2; exit 1; }
done

grep -q 'LIJ-MACH-C' "$SUMMARY_OUT" || { echo "FAIL: expected LIJ first gap LIJ-MACH-C" >&2; exit 1; }
grep -q 'LIJ-MACH-AB' "$SUMMARY_OUT" || { echo "FAIL: expected LIJ next after highest LIJ-MACH-AB" >&2; exit 1; }
grep -q 'CCMC-MACH-B' "$SUMMARY_OUT" || { echo "FAIL: expected CCMC first gap CCMC-MACH-B" >&2; exit 1; }
grep -q 'CCMC-MACH-D' "$SUMMARY_OUT" || { echo "FAIL: expected CCMC next after highest CCMC-MACH-D" >&2; exit 1; }

for detail in OCCUPIED AVAILABLE_GAP AVAILABLE_AFTER_HIGHEST; do
  grep -q "$detail" "$DETAIL_OUT" || { echo "FAIL: expected detail record $detail" >&2; exit 1; }
done

for dash_text in 'SysAdminSuite Neuron Name Availability' 'First gap' 'Next after highest' 'Local operational artifact'; do
  grep -q "$dash_text" "$DASHBOARD_OUT" || { echo "FAIL: missing dashboard text $dash_text" >&2; exit 1; }
done

bash "$ROOT/survey/sas-survey-neuron-name-availability.sh" \
  --convention LIJ-MACH- \
  --convention CCMC-MACH- \
  --used-names "$ROOT/survey/fixtures/neuron_name_availability_sample.xml" \
  --skip-nmap \
  --run-id testwrapper \
  --output-dir "$WRAP_OUT_DIR" \
  --candidate-count 5

[[ -f "$WRAP_OUT_DIR/testwrapper_neuron_name_availability_summary.csv" ]] || { echo "FAIL: wrapper missing summary" >&2; exit 1; }
[[ -f "$WRAP_OUT_DIR/testwrapper_neuron_name_availability_detail.csv" ]] || { echo "FAIL: wrapper missing detail" >&2; exit 1; }
[[ -f "$WRAP_OUT_DIR/testwrapper_neuron_name_availability.html" ]] || { echo "FAIL: wrapper missing dashboard" >&2; exit 1; }

grep -q 'LIJ-MACH-C' "$WRAP_OUT_DIR/testwrapper_neuron_name_availability_summary.csv" || { echo "FAIL: wrapper expected LIJ first gap" >&2; exit 1; }

if bash "$ROOT/survey/sas-survey-neuron-name-availability.sh" \
  --convention LIJ-MACH- \
  --target 192.0.2.1 \
  --output-dir "$OUT_DIR/guard" \
  2>"$GUARD_ERR"; then
  echo "FAIL: live discovery should require --authorized-discovery" >&2
  exit 1
fi

grep -q -- '--authorized-discovery' "$GUARD_ERR" || { echo "FAIL: authorization guard message missing" >&2; exit 1; }

echo "PASS: neuron name availability contracts"
