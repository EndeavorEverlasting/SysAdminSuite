#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

WRAP="survey/sas-run-packet-probe.sh"
FIX="$ROOT/survey/fixtures/naabu_pipeline"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in "$WRAP" "Config/cybernet-packet-profile.json" "$FIX/targets.sample.txt"; do
  [[ -f "$f" ]] || { echo "missing: $f"; exit 1; }
done

bash -n "$WRAP"

PLAN="$TMP/planned.txt"
OUT="$TMP/results.json"
SUMMARY="$TMP/summary.json"

bash "$WRAP" --site testsite \
  --list "$FIX/targets.sample.txt" \
  --out "$OUT" \
  --summary "$SUMMARY" \
  --planned-file "$PLAN" \
  --dry-run >/dev/null

grep -q -- '-tp 1000' "$PLAN" || { echo 'missing -tp 1000'; cat "$PLAN"; exit 1; }
grep -q -- '-c 50' "$PLAN" || { echo 'missing -c 50'; cat "$PLAN"; exit 1; }
grep -q -- '-rate 3000' "$PLAN" || { echo 'missing -rate 3000'; cat "$PLAN"; exit 1; }
grep -q -- '-ss' "$PLAN" || { echo 'missing -ss'; cat "$PLAN"; exit 1; }
grep -q -- '-pt 20' "$PLAN" || { echo 'missing -pt 20'; cat "$PLAN"; exit 1; }
grep -q -- '-ec' "$PLAN" || { echo 'missing -ec'; cat "$PLAN"; exit 1; }
grep -q -- '-silent' "$PLAN" || { echo 'missing -silent'; cat "$PLAN"; exit 1; }
grep -q -- '-json' "$PLAN" || { echo 'missing -json'; cat "$PLAN"; exit 1; }
grep -q -- '-duc' "$PLAN" || { echo 'missing -duc'; cat "$PLAN"; exit 1; }
grep -q '"classification": "OK_NAABU_PACKET_PROBE_PLANNED"' "$SUMMARY" || { echo 'summary missing planned classification'; cat "$SUMMARY"; exit 1; }

LIB_PLAN="$TMP/planned-library.txt"
LIB_SUMMARY="$TMP/summary-library.json"
bash "$WRAP" --site testsite \
  --list "$FIX/targets.sample.txt" \
  --out "$OUT" \
  --summary "$LIB_SUMMARY" \
  --planned-file "$LIB_PLAN" \
  --engine library \
  --dry-run >/dev/null
grep -q -- '-ec' "$LIB_PLAN" || { echo 'library dry-run missing -ec'; cat "$LIB_PLAN"; exit 1; }
grep -q '"engine": "library"' "$LIB_SUMMARY" || { echo 'summary missing library engine'; cat "$LIB_SUMMARY"; exit 1; }

if bash "$WRAP" --site testsite --list "$FIX/targets.sample.txt" --out "$OUT" --engine typo --dry-run 2>/dev/null; then
  echo 'expected invalid engine to fail'
  exit 1
fi

BAD="$TMP/bad-profile.json"
python - "$BAD" <<'PY'
import json, sys
p = json.load(open("Config/cybernet-packet-profile.json", encoding="utf-8"))
p["stream"] = True
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"))
PY
if bash "$WRAP" --site testsite --list "$FIX/targets.sample.txt" --out "$OUT" --profile "$BAD" --dry-run 2>/dev/null; then
  echo 'expected stream + smart scan profile to fail'
  exit 1
fi

CIDR="$TMP/cidr.txt"
printf '10.10.10.0/24\n' > "$CIDR"
if bash "$WRAP" --site testsite --list "$CIDR" --out "$OUT" --dry-run 2>/dev/null; then
  echo 'expected CIDR target list to fail'
  exit 1
fi

PUBLIC="$TMP/public.txt"
printf '8.8.8.8\n' > "$PUBLIC"
if bash "$WRAP" --site testsite --list "$PUBLIC" --out "$OUT" --dry-run 2>/dev/null; then
  echo 'expected public target list to fail'
  exit 1
fi

printf 'Packet probe contracts passed.\n'
