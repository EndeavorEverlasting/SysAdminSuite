#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

required_tests=(
  "Tests/bash/test_english_log_artifact_contracts.sh"
  "Tests/bash/test_sysadmin_harness_validator_contracts.sh"
  "Tests/bash/test_harness_command_surface.sh"
)

[[ -f scripts/Ensure-Pr142HarnessFoundationWorktree.ps1 ]] || fail "missing PR142 worktree bootstrap"
[[ -f scripts/Invoke-SasHarnessContracts.ps1 ]] || fail "missing PowerShell harness contract runner"
pass "PowerShell worktree bootstrap and contract runner exist"

for test_file in "${required_tests[@]}"; do
  [[ -f "$test_file" ]] || fail "missing harness contract test: $test_file"
  bash -n "$test_file"
done
pass "harness contract tests exist and parse"

for test_file in "${required_tests[@]}"; do
  echo "[SAS] Running $test_file"
  bash "$test_file"
done

pass "harness contract suite passed"
