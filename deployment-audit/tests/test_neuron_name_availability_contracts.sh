#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-neuron-name-availability"
SUMMARY_OUT="$OUT_DIR/neuron_name_availability_summary.csv"
DETAIL_OUT="$OUT_DIR/neuron_name_availability_detail.csv"
DASHBOARD_OUT="$OUT_DIR/neuron_name_availability.html"

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

echo "PASS: neuron name availability contracts"
