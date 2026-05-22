#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-neuron-nmap-matcher"
TARGET_OUT="$OUT_DIR/neuron_resolved_targets.csv"
REVIEW_OUT="$OUT_DIR/neuron_probe_review.csv"
DASHBOARD_OUT="$OUT_DIR/neuron_probe_review.html"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

python3 "$ROOT/survey/sas-match-neurons-from-nmap.py" \
  --manifest "$ROOT/survey/fixtures/neuron_nmap_match_manifest.sample.csv" \
  --nmap-xml "$ROOT/survey/fixtures/neuron_nmap_match_sample.xml" \
  --output "$TARGET_OUT" \
  --review-output "$REVIEW_OUT" \
  --dashboard "$DASHBOARD_OUT"

[[ -f "$TARGET_OUT" ]] || { echo "FAIL: missing resolved target output" >&2; exit 1; }
[[ -f "$REVIEW_OUT" ]] || { echo "FAIL: missing review output" >&2; exit 1; }
[[ -f "$DASHBOARD_OUT" ]] || { echo "FAIL: missing dashboard output" >&2; exit 1; }

for col in NeuronHost ExpectedMAC ExpectedSerial Site Room Notes; do
  grep -q "$col" "$TARGET_OUT" || { echo "FAIL: missing target column $col" >&2; exit 1; }
done

for val in '192.0.2.10' 'AA:BB:CC:DD:EE:10' 'SAMPLE-SERIAL-001' 'ResolvedBy=nmap_mac_match'; do
  grep -q "$val" "$TARGET_OUT" || { echo "FAIL: expected target value $val" >&2; exit 1; }
done

for status in MAC_MATCH_RESOLVED MAC_NOT_FOUND_IN_NMAP SERIAL_ONLY_NO_MAC NO_USABLE_IDENTIFIER; do
  grep -q "$status" "$REVIEW_OUT" || { echo "FAIL: expected review status $status" >&2; exit 1; }
done

for dash_text in 'SysAdminSuite Neuron MAC/Subnet Dashboard' 'Neuron Identity Evidence Cards' 'Resolved by MAC' 'MAC Match Resolved' 'Local operational artifact'; do
  grep -q "$dash_text" "$DASHBOARD_OUT" || { echo "FAIL: missing dashboard text $dash_text" >&2; exit 1; }
done

echo "PASS: neuron nmap matcher contracts"
