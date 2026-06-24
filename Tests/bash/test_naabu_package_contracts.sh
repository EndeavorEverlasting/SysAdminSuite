#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FIX="$ROOT/survey/fixtures/naabu_pipeline"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OUT_ROOT="$TMP/out"
LOG_ROOT="$TMP/logs"
mkdir -p "$OUT_ROOT" "$LOG_ROOT" "$LOG_ROOT/resolver"

# Fixture resolver CSV from parser
bash survey/sas-parse-naabu-evidence.sh \
  --naabu-output "$FIX/naabu.sample.jsonl" \
  --followup "$FIX/followup.sample.jsonl" \
  --output "$TMP/testsite_naabu_reachability.csv"

grep -q 'cybernet_signal' "$TMP/testsite_naabu_reachability.csv" || { echo 'missing cybernet_signal column'; exit 1; }
grep -q 'web_reachability' "$TMP/testsite_naabu_reachability.csv" || { echo 'missing web signal'; exit 1; }

# Seed run dir for package-only
RUN_DIR="$OUT_ROOT/testsite_pack001"
mkdir -p "$RUN_DIR/resolver"
cp "$TMP/testsite_naabu_reachability.csv" "$RUN_DIR/resolver/"
printf '# pack test\n' > "$RUN_DIR/SUMMARY.md"
printf 'site=testsite\n' > "$RUN_DIR/RUN_MANIFEST.env"

# Place naabu artifact in logs for package copy
cp "$FIX/naabu.sample.jsonl" "$LOG_ROOT/testsite_sample_windows_ports_naabu.json"

bash survey/sas-cybernet-subnet-survey.sh --site testsite --mode package-only \
  --run-id pack001 --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" >/dev/null

ART="$ROOT/survey/artifacts/testsite_pack001"
[[ -f "$ART/resolver/testsite_naabu_reachability.csv" ]] || { echo 'artifact missing naabu csv'; exit 1; }
grep -q 'testsite_naabu_reachability.csv' "$ART/PACKAGE_MANIFEST.txt" || { echo 'manifest missing naabu csv'; exit 1; }

rm -rf "$ART"
printf 'Naabu package contracts passed.\n'
