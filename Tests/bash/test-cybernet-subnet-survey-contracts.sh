#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RUNNER="survey/sas-cybernet-subnet-survey.sh"
CMD="survey/sas-cybernet-subnet-survey.cmd"
FIX="$ROOT/survey/fixtures/cybernet_subnet_survey"

[[ -f "$RUNNER" ]] || { echo "missing runner"; exit 1; }
bash -n "$RUNNER"

HELP="$(bash "$RUNNER" --help)"
for mode in local-context-only dns-list-only discover confirm-windows resolve-only package-only; do
  echo "$HELP" | grep -qF "$mode" || { echo "help missing mode: $mode"; exit 1; }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT_ROOT="$TMP_DIR/out"
LOG_ROOT="$TMP_DIR/logs/nmap"
mkdir -p "$OUT_ROOT" "$LOG_ROOT"

bash "$RUNNER" --site testsite --mode discover --cidr 10.10.10.0/24 \
  --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" --run-id dry001 --dry-run >/dev/null
[[ -f "$OUT_ROOT/testsite_dry001/planned_commands.txt" ]]
grep -q 'discovery_no_dns' "$OUT_ROOT/testsite_dry001/planned_commands.txt"
grep -q '\-sn' "$OUT_ROOT/testsite_dry001/planned_commands.txt"

if bash "$RUNNER" --site testsite --mode discover --cidr 10.0.0.0/16 \
  --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" --run-id badwide --dry-run 2>/dev/null; then
  echo "expected /16 to fail without --allow-wide"
  exit 1
fi

if bash "$RUNNER" --site testsite --mode discover --cidr 8.8.8.0/24 \
  --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" --run-id badpub --dry-run 2>/dev/null; then
  echo "expected public CIDR to fail without --allow-public"
  exit 1
fi

if bash "$RUNNER" --site testsite --mode confirm-windows \
  --host-file "$FIX/public_hostfile_bad.txt" \
  --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" --run-id badhost 2>/dev/null; then
  echo "expected CIDR host file rejection"
  exit 1
fi

if bash "$RUNNER" --site testsite --mode confirm-windows \
  --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT" --run-id nohost 2>/dev/null; then
  echo "expected missing --host-file failure"
  exit 1
fi

MANIFEST="$FIX/cybernet_targets_resolved.sample.csv"
RUN_ID="pack001"
RUN_DIR="$OUT_ROOT/testsite_${RUN_ID}"
mkdir -p "$RUN_DIR/resolver"
cp "$MANIFEST" "$RUN_DIR/resolver/cybernet_targets_resolved.csv"
printf '# pack test\n' > "$RUN_DIR/SUMMARY.md"
printf 'site=testsite\n' > "$RUN_DIR/RUN_MANIFEST.env"

bash "$RUNNER" --site testsite --mode package-only --run-id "$RUN_ID" \
  --manifest "$MANIFEST" --output-root "$OUT_ROOT" --logs-root "$LOG_ROOT"

ART="$ROOT/survey/artifacts/testsite_${RUN_ID}"
[[ -d "$ART" ]] || { echo "artifact dir missing: $ART"; exit 1; }
[[ -f "$ART/manifests/cybernet_targets_resolved.sample.csv" ]] || { echo "manifest not packaged"; exit 1; }
[[ -f "$ART/PACKAGE_MANIFEST.txt" ]] || { echo "PACKAGE_MANIFEST.txt missing"; exit 1; }
grep -q 'manifests/cybernet_targets_resolved.sample.csv' "$ART/PACKAGE_MANIFEST.txt"

grep -q 'sas-cybernet-subnet-survey.sh' "$CMD"

rm -rf "$ART"

printf 'Cybernet subnet survey contracts passed.\n'
