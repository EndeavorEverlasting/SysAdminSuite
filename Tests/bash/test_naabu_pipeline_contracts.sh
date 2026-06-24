#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PIPE="survey/sas-run-naabu-pipeline.sh"
FOLLOWUP="survey/sas-cybernet-packet-followup.sh"
ENSURE="survey/sas-ensure-naabu.sh"
PARSE="survey/sas-parse-naabu-evidence.sh"
FIX="$ROOT/survey/fixtures/naabu_pipeline"
CFG="$ROOT/Config/cybernet-naabu-profiles.json"

for f in "$PIPE" "$FOLLOWUP" "$ENSURE" "$PARSE" "$CFG"; do
  [[ -f "$f" ]] || { echo "missing: $f"; exit 1; }
done

bash -n "$PIPE"
bash -n "$FOLLOWUP"
bash -n "$ENSURE"
bash -n "$PARSE"

HELP="$(bash "$PIPE" --help)"
echo "$HELP" | grep -qF 'keyports_cdn' || { echo 'help missing keyports_cdn'; exit 1; }
echo "$HELP" | grep -qF '-ec' || { echo 'help missing -ec note'; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PLANNED="$TMP/planned.txt"
OUT="$TMP/out.txt"

# Default profile dry-run must include -ec -silent -p 80,443
bash "$PIPE" --site testsite --profile keyports_cdn \
  --list "$FIX/targets.sample.txt" --out "$OUT" --dry-run --planned-file "$PLANNED" >/dev/null
grep -q '\-ec' "$PLANNED" || { echo 'expected -ec in planned command'; cat "$PLANNED"; exit 1; }
grep -q '\-silent' "$PLANNED" || { echo 'expected -silent'; exit 1; }
grep -q '80,443' "$PLANNED" || { echo 'expected 80,443 ports'; exit 1; }

# Full ports rejected without --allow-full-ports
if bash "$PIPE" --site testsite --profile full_ports_cdn_guarded \
  --list "$FIX/targets.sample.txt" --out "$OUT" --dry-run 2>/dev/null; then
  echo 'expected full_ports to fail without --allow-full-ports'
  exit 1
fi

bash "$PIPE" --site testsite --profile full_ports_cdn_guarded \
  --list "$FIX/targets.sample.txt" --out "$OUT" --dry-run --allow-full-ports --planned-file "$PLANNED" >/dev/null
grep -q '\-p -' "$PLANNED" || grep -q '\-p - ' "$PLANNED" || grep -q ' -p - ' "$PLANNED" || { echo 'expected -p -'; cat "$PLANNED"; exit 1; }

# Hostname -sa profile
bash "$PIPE" --site testsite --profile hostname_all_ips \
  --host 'https://example.internal' --out "$OUT" --dry-run --planned-file "$PLANNED" >/dev/null
grep -q '\-sa' "$PLANNED" || { echo 'expected -sa'; exit 1; }
grep -q '\-host' "$PLANNED" || { echo 'expected -host'; exit 1; }

# Host discovery profile
bash "$PIPE" --site testsite --profile host_discovery_tcp80 \
  --list "$FIX/targets.sample.txt" --out "$OUT" --dry-run --planned-file "$PLANNED" >/dev/null
grep -q '\-sn' "$PLANNED" || { echo 'expected -sn'; exit 1; }
grep -q '\-ps' "$PLANNED" || { echo 'expected -ps'; exit 1; }

# UDP profile
bash "$PIPE" --site testsite --profile udp_infrastructure \
  --list "$FIX/targets.sample.txt" --out "$OUT" --dry-run --planned-file "$PLANNED" >/dev/null
grep -q 'u:53' "$PLANNED" || { echo 'expected u:53'; exit 1; }
grep -q '\-uP' "$PLANNED" || { echo 'expected -uP'; exit 1; }

# Pipe followup in planned command
bash "$PIPE" --site testsite --profile keyports_cdn \
  --list "$FIX/targets.sample.txt" --out "$OUT" --pipe-followup --dry-run --planned-file "$PLANNED" >/dev/null
grep -q 'sas-cybernet-packet-followup.sh' "$PLANNED" || { echo 'expected followup pipe'; exit 1; }

# Followup JSONL from fixture stdin
printf '10.10.10.1:443\n10.10.10.2:445\n' | bash "$FOLLOWUP" --site testsite --stdin --cybernet-detect > "$TMP/followup.jsonl"
grep -q 'windows_endpoint' "$TMP/followup.jsonl" || { echo 'expected windows signal'; exit 1; }

# Parse stub
printf '10.10.10.1:80\n' > "$TMP/naabu.txt"
bash "$PARSE" --naabu-output "$TMP/naabu.txt" --followup "$TMP/followup.jsonl" --output "$TMP/parsed.csv"
grep -q '10.10.10.1' "$TMP/parsed.csv" || { echo 'parse failed'; exit 1; }

# Ensure naabu dry-run
bash "$ENSURE" --dry-run >/dev/null || true

# Survey runner naabu dry-run uses pipeline
bash survey/sas-cybernet-subnet-survey.sh --site testsite --mode confirm-windows \
  --confirm-tool naabu --host-file "$FIX/targets.sample.txt" \
  --output-root "$TMP/out" --logs-root "$TMP/logs" --run-id naabu001 --dry-run >/dev/null
[[ -f "$TMP/out/testsite_naabu001/planned_commands.txt" ]]
grep -q 'sas-run-naabu-pipeline.sh' "$TMP/out/testsite_naabu001/planned_commands.txt" || { echo 'survey runner missing pipeline'; exit 1; }

printf 'Naabu pipeline contracts passed.\n'
