#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

validator="scripts/validate-sysadmin-harness.ps1"
[[ -f "$validator" ]] || fail "validator missing"

for fragment in \
  "APP HARNESS VALIDATION" \
  "scripts/SasRunContext.psm1" \
  "artifact registry" \
  "report renderer" \
  "cross-lane merge integrity" \
  "optional Python module compatibility" \
  "git_bash_not_available" \
  "optional MCP symbol smoke" \
  "lsp_project_not_loaded" \
  "hook hygiene" \
  "harness_validation_result.json" \
  "synthetic_offline" \
  "runtime_proof=\$false" \
  "network_activity_performed=\$false" \
  "launcher_execution_performed=\$false" \
  "target_mutation_performed=\$false"; do
  grep -Fq "$fragment" "$validator" || fail "validator missing contract: $fragment"
done
pass "validator declares matrix, JSON, dependency, and proof-boundary contracts"

for forbidden in Start-Process Invoke-Item explorer.exe START-HERE-SysAdminSuite Launch-SysAdminSuite Test-NetConnection Resolve-DnsName Invoke-WebRequest; do
  if grep -Fiq "$forbidden" "$validator"; then
    fail "validator contains forbidden runtime surface: $forbidden"
  fi
done
pass "validator contains no launcher or network execution surface"

[[ -f Tests/survey/test_one_command_harness_proof_contracts.py ]] || fail "executable proof contracts missing"
grep -Fq "test_one_command_harness_proof_contracts.py" tests/survey/run_offline_survey_tests.sh || fail "offline runner missing proof contracts"
pass "one-command proof is wired into offline validation"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$validator"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$validator"
else
  echo "[SKIP] PowerShell runtime unavailable; static contracts completed."
fi

echo "SysAdmin harness validator contracts passed."
