#!/usr/bin/env bash
# Contract tests for survey/sas-cybernet-detect.sh (canonical enrichment CLI).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DETECT="survey/sas-cybernet-detect.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$DETECT" --help >/dev/null

printf '10.10.10.1:443\n10.10.10.2:445\n' | bash "$DETECT" --site testsite --stdin --jsonl > "$TMP/out.jsonl"
grep -q 'web_reachability' "$TMP/out.jsonl" || { echo 'expected web_reachability signal'; exit 1; }
grep -q 'windows_endpoint' "$TMP/out.jsonl" || { echo 'expected windows_endpoint signal'; exit 1; }
grep -q '"source":"naabu_silent_pipe"' "$TMP/out.jsonl" || { echo 'expected naabu_silent_pipe source'; exit 1; }

printf '10.10.10.3:5985\n' > "$TMP/in.txt"
bash "$DETECT" --site testsite --input "$TMP/in.txt" --jsonl | grep -q 'winrm' || { echo 'expected winrm signal'; exit 1; }

if printf '1.1.1.1:80\n' | bash "$DETECT" --stdin --jsonl 2>/dev/null; then
  echo 'expected failure without --site'
  exit 1
fi

echo "Cybernet detect contracts passed."
