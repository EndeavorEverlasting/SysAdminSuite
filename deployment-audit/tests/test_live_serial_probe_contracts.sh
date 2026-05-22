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
  --ad-csv "$ROOT/survey/fixtures/live_serial_ad.sample.csv" \
  --output "$CSV_OUT" \
  --dashboard "$HTML_OUT"

[[ -f "$CSV_OUT" ]] || { echo "FAIL: missing CSV output" >&2; exit 1; }
[[ -f "$HTML_OUT" ]] || { echo "FAIL: missing HTML dashboard" >&2; exit 1; }

for col in can_populate_serial can_populate_mac probe_methods_attempted probe_method_success probe_confidence identity_drift_status resolved_hostname; do
  grep -q "$col" "$CSV_OUT" || { echo "FAIL: missing $col column" >&2; exit 1; }
done

for val in live_serial_confirmed identity_resolved manual_review unreachable_mark_off identity_csv_match ad_attribute_lookup hostname_drift resolved_from_identifier; do
  grep -q "$val" "$CSV_OUT" || { echo "FAIL: expected $val" >&2; exit 1; }
done

grep -q 'SysAdminSuite Identity Resolver Dashboard' "$HTML_OUT" || { echo "FAIL: dashboard title missing" >&2; exit 1; }
grep -q 'Glowing Identity Evidence Cards' "$HTML_OUT" || { echo "FAIL: glowing identity cards missing" >&2; exit 1; }
grep -q 'Winning Probe Methods' "$HTML_OUT" || { echo "FAIL: winning probe methods panel missing" >&2; exit 1; }
grep -q 'Hostname Drift' "$HTML_OUT" || { echo "FAIL: hostname drift card missing" >&2; exit 1; }
grep -q 'probe_method_success' "$HTML_OUT" || { echo "FAIL: probe method column missing from dashboard" >&2; exit 1; }

echo "PASS: live serial probe contracts"
