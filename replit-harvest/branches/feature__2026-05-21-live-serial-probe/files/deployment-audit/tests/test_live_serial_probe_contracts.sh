#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-live-serial-probe"
CSV_OUT="$OUT_DIR/live_serial_probe_results.csv"
HTML_OUT="$OUT_DIR/live_serial_probe_dashboard.html"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

bash "$ROOT/survey/sas-live-serial-probe.sh" \
  --manifest "$ROOT/survey/fixtures/live_serial_manifest.sample.csv" \
  --identity-csv "$ROOT/survey/fixtures/live_serial_identity.sample.csv" \
  --output "$CSV_OUT" \
  --dashboard "$HTML_OUT"

[[ -f "$CSV_OUT" ]] || { echo "FAIL: missing CSV output" >&2; exit 1; }
[[ -f "$HTML_OUT" ]] || { echo "FAIL: missing HTML dashboard" >&2; exit 1; }

grep -q 'can_populate_serial' "$CSV_OUT" || { echo "FAIL: missing can_populate_serial column" >&2; exit 1; }
grep -q 'can_populate_mac' "$CSV_OUT" || { echo "FAIL: missing can_populate_mac column" >&2; exit 1; }
grep -q 'live_serial_confirmed' "$CSV_OUT" || { echo "FAIL: expected live_serial_confirmed classification" >&2; exit 1; }
grep -q 'manual_review' "$CSV_OUT" || { echo "FAIL: expected manual_review classification" >&2; exit 1; }
grep -q 'unreachable_mark_off' "$CSV_OUT" || { echo "FAIL: expected unreachable_mark_off classification" >&2; exit 1; }
grep -q 'SysAdminSuite Live Serial Probe Dashboard' "$HTML_OUT" || { echo "FAIL: dashboard title missing" >&2; exit 1; }
grep -q 'Can Populate Serials' "$HTML_OUT" || { echo "FAIL: dashboard serial population card missing" >&2; exit 1; }
grep -q 'Can Populate MACs' "$HTML_OUT" || { echo "FAIL: dashboard MAC population card missing" >&2; exit 1; }
grep -q 'Follow-Up Routing' "$HTML_OUT" || { echo "FAIL: follow-up routing panel missing" >&2; exit 1; }

echo "PASS: live serial probe contracts"
