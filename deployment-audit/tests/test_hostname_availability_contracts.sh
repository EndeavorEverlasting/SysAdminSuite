#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-hostname-availability"
SUMMARY_OUT="$OUT_DIR/hostname_availability_summary.csv"
DETAIL_OUT="$OUT_DIR/hostname_availability_detail.csv"
DASHBOARD_OUT="$OUT_DIR/hostname_availability.html"
WRAP_OUT_DIR="$OUT_DIR/wrapper"
FIXTURE="$ROOT/survey/fixtures/hostname_availability_sample.txt"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/survey/sas-hostname-availability.py" \
  --convention WNH270OPR \
  --convention WMH300OPR \
  --suffix-mode numeric \
  --width 3 \
  --used-names "$FIXTURE" \
  --summary-output "$SUMMARY_OUT" \
  --detail-output "$DETAIL_OUT" \
  --dashboard "$DASHBOARD_OUT" \
  --candidate-count 5

[[ -f "$SUMMARY_OUT" ]] || { echo "FAIL: missing summary output" >&2; exit 1; }
[[ -f "$DETAIL_OUT" ]] || { echo "FAIL: missing detail output" >&2; exit 1; }
[[ -f "$DASHBOARD_OUT" ]] || { echo "FAIL: missing dashboard output" >&2; exit 1; }

for col in ConventionPrefix FirstGapName NextAfterHighestName GapCandidates NextCandidates SuffixMode; do
  grep -q "$col" "$SUMMARY_OUT" || { echo "FAIL: missing summary column $col" >&2; exit 1; }
done

grep -q 'WNH270OPR003' "$SUMMARY_OUT" || { echo "FAIL: expected WNH first gap WNH270OPR003" >&2; exit 1; }
grep -q 'WNH270OPR011' "$SUMMARY_OUT" || { echo "FAIL: expected WNH next after highest WNH270OPR011" >&2; exit 1; }
grep -q 'WMH300OPR135' "$SUMMARY_OUT" || { echo "FAIL: expected WMH next after highest WMH300OPR135" >&2; exit 1; }

for detail in OCCUPIED AVAILABLE_GAP AVAILABLE_AFTER_HIGHEST; do
  grep -q "$detail" "$DETAIL_OUT" || { echo "FAIL: expected detail record $detail" >&2; exit 1; }
done

for dash_text in 'SysAdminSuite Hostname Availability' 'First gap' 'Next after highest'; do
  grep -q "$dash_text" "$DASHBOARD_OUT" || { echo "FAIL: missing dashboard text $dash_text" >&2; exit 1; }
done

bash "$ROOT/survey/sas-survey-hostname-availability.sh" \
  --convention WNH270OPR \
  --used-names "$FIXTURE" \
  --suffix-mode numeric \
  --width 3 \
  --run-id testwrapper \
  --output-dir "$WRAP_OUT_DIR" \
  --candidate-count 5

[[ -f "$WRAP_OUT_DIR/testwrapper_hostname_availability_summary.csv" ]] || { echo "FAIL: wrapper missing summary" >&2; exit 1; }
grep -q 'WNH270OPR003' "$WRAP_OUT_DIR/testwrapper_hostname_availability_summary.csv" || { echo "FAIL: wrapper expected WNH first gap" >&2; exit 1; }

echo "PASS: hostname availability contracts"
