#!/usr/bin/env bash
set -euo pipefail

# Smoke test for AD registered population reconcile.
# Uses synthetic fixtures only. No live AD, DNS, Naabu, or Nmap.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/survey/output/test-ad-reconcile"
ROSTER_OUT_DIR="$ROOT/survey/output/test-ad-registered-population"
FIXTURE_AD="$ROOT/survey/fixtures/ad_registered_cybernet.sample.csv"
FIXTURE_EVIDENCE="$ROOT/survey/fixtures/ad_evidence_manifest.sample.csv"
FIXTURE_NETWORK="$ROOT/survey/fixtures/ad_network_evidence.sample.csv"
FIXTURE_SERIAL="$ROOT/survey/fixtures/ad_live_serial.sample.csv"

rm -rf "$OUT_DIR"
rm -rf "$ROSTER_OUT_DIR"
mkdir -p "$OUT_DIR"

bash "$ROOT/survey/sas-ad-reconcile.sh" \
  --ad-csv "$FIXTURE_AD" \
  --evidence-csv "$FIXTURE_EVIDENCE" \
  --network-csv "$FIXTURE_NETWORK" \
  --serial-csv "$FIXTURE_SERIAL" \
  --output-dir "$OUT_DIR" \
  --prefix CYB \
  --stale-days 90

required_files=(
  ad_registered_normalized.csv
  ad_targets_hostnames.txt
  ad_targets_dns.txt
  ad_evidence_matches.csv
  ad_only.csv
  evidence_only.csv
  ad_disabled.csv
  ad_stale.csv
  ad_missing_dns.csv
  ad_duplicates.csv
  network_reachable.csv
  network_silent.csv
  live_serial_matched.csv
  live_serial_unavailable.csv
  ad_summary.json
  README.txt
)

for f in "${required_files[@]}"; do
  [[ -f "$OUT_DIR/$f" ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done

grep -q 'CYBTEST001' "$OUT_DIR/ad_targets_hostnames.txt" || { echo "FAIL: expected CYBTEST001 in hostnames" >&2; exit 1; }
grep -q 'CYBTEST999' "$OUT_DIR/evidence_only.csv" || { echo "FAIL: expected CYBTEST999 in evidence_only" >&2; exit 1; }
grep -q 'CYBTEST003' "$OUT_DIR/ad_disabled.csv" || { echo "FAIL: expected CYBTEST003 in ad_disabled" >&2; exit 1; }
grep -q 'CYBTEST005' "$OUT_DIR/ad_stale.csv" || { echo "FAIL: expected CYBTEST005 in ad_stale" >&2; exit 1; }
grep -q 'CYBTEST002' "$OUT_DIR/ad_missing_dns.csv" || { echo "FAIL: expected CYBTEST002 in ad_missing_dns" >&2; exit 1; }
grep -q 'CYBTEST004' "$OUT_DIR/ad_duplicates.csv" || { echo "FAIL: expected CYBTEST004 in ad_duplicates" >&2; exit 1; }
grep -q 'ad_registered' "$OUT_DIR/ad_summary.json" || { echo "FAIL: summary missing population authority" >&2; exit 1; }
grep -q 'reachable' "$OUT_DIR/network_reachable.csv" || { echo "FAIL: expected reachable network evidence" >&2; exit 1; }
grep -q 'matched' "$OUT_DIR/live_serial_matched.csv" || { echo "FAIL: expected matched serial evidence" >&2; exit 1; }

bash "$ROOT/survey/sas-export-ad-registered-population.sh" \
  --ad-csv "$FIXTURE_AD" \
  --evidence-csv "$FIXTURE_EVIDENCE" \
  --network-csv "$FIXTURE_NETWORK" \
  --serial-csv "$FIXTURE_SERIAL" \
  --output-dir "$ROSTER_OUT_DIR" \
  --prefix CYB \
  --stale-days 90 > "$ROSTER_OUT_DIR.stdout"

[[ -f "$ROSTER_OUT_DIR/ad_registered_normalized.csv" ]] || { echo "FAIL: roster wrapper missing normalized output" >&2; exit 1; }
grep -q 'AD REGISTERED POPULATION ROSTER SUMMARY' "$ROSTER_OUT_DIR.stdout" || { echo "FAIL: roster wrapper summary missing" >&2; exit 1; }
grep -q 'offline/static evidence' "$ROSTER_OUT_DIR.stdout" || { echo "FAIL: roster wrapper should label fallback as offline/static evidence" >&2; exit 1; }
grep -q 'CYBTEST005' "$ROSTER_OUT_DIR/ad_stale.csv" || { echo "FAIL: roster wrapper expected stale fixture" >&2; exit 1; }

python3 "$ROOT/survey/sas-import-ad-computers.py" \
  --input "$FIXTURE_AD" \
  --output "$ROSTER_OUT_DIR/imported_ad_computers.csv" >/dev/null
grep -q 'PopulationAuthority' "$ROSTER_OUT_DIR/imported_ad_computers.csv" || { echo "FAIL: importer missing PopulationAuthority column" >&2; exit 1; }
grep -q 'AD_REGISTERED' "$ROSTER_OUT_DIR/imported_ad_computers.csv" || { echo "FAIL: importer should emit AD_REGISTERED" >&2; exit 1; }

echo "PASS: AD registered population reconcile smoke test"
