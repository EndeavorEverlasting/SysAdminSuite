#!/usr/bin/env bash
# Contract test for targets/ intake policy guard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/scripts/validate-targets-folder-policy.py"

if [[ ! -f "$GUARD" ]]; then
  echo "FAIL: guard script not found: $GUARD"
  exit 1
fi

run_case() {
  local label="$1"
  local expect="$2"
  local tmp
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    git init -q
    git config user.email "contract@test.local"
    git config user.name "Contract Test"
    mkdir -p scripts
    cp "$GUARD" scripts/validate-targets-folder-policy.py
    eval "$3"
    git add -A
    if python scripts/validate-targets-folder-policy.py >/dev/null 2>&1; then
      rc=0
    else
      rc=1
    fi
    if [[ "$expect" == "pass" && $rc -eq 0 ]]; then
      echo "PASS: $label"
    elif [[ "$expect" == "fail" && $rc -ne 0 ]]; then
      echo "PASS: $label (correctly rejected)"
    else
      echo "FAIL: $label (expected $expect, got rc=$rc)"
      exit 1
    fi
  )
  rm -rf "$tmp"
}

run_case "allowed sanitized fixture tree" pass '
  mkdir -p targets/schema targets/sanitized/examples
  echo "# hub" > targets/README.md
  cp "$ROOT/targets/schema/cybernet-targets.schema.json" targets/schema/cybernet-targets.schema.json
  cp "$ROOT/targets/sanitized/examples/cybernet_targets.sample.csv" targets/sanitized/examples/cybernet_targets.sample.csv
'

run_case "Alejandro workbook at targets root" fail '
  mkdir -p targets
  echo xlsx > "targets/Alejandro'"'"'s list of Cybernets.xlsx"
'

run_case "live zone csv" fail '
  mkdir -p targets/live
  echo csv > targets/live/cybernet_targets.csv
'

run_case "active deployment tracker name" fail '
  mkdir -p "targets/Cybernet sources"
  echo xlsx > "targets/Cybernet sources/Active Deployment Tracker 2026-05-17.xlsx"
'

run_case "nsuh serials txt" fail '
  mkdir -p targets
  echo txt > targets/nsuh_serials.txt
'

run_case "sanitized name implying live data" fail '
  mkdir -p targets/sanitized/examples
  echo csv > targets/sanitized/examples/active_deployment_tracker.csv
'

echo "Targets folder policy contract tests passed."
