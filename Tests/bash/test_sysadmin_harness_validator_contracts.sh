#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -f scripts/validate-sysadmin-harness.ps1 ]] || fail "validator missing"
pass "validator exists"

grep -q "SYSADMIN HARNESS VALIDATION" scripts/validate-sysadmin-harness.ps1 || fail "validator missing title"
grep -q "PASS" scripts/validate-sysadmin-harness.ps1 || fail "validator missing PASS matrix output"
grep -q "FAIL" scripts/validate-sysadmin-harness.ps1 || fail "validator missing FAIL matrix output"
pass "validator matrix contract"

for file in \
  Run-HarnessContracts.cmd \
  Run-HarnessValidation.cmd \
  Run-EnglishReportFixture.cmd \
  Run-ExportHarnessEvidence.cmd \
  scripts/run-harness-validation.sh \
  scripts/render-english-report-fixtures.sh \
  scripts/show-harness-evidence-paths.sh \
  scripts/Render-SasEnglishReport.ps1 \
  Tests/bash/run_harness_contracts.sh \
  Tests/bash/test_harness_command_surface.sh \
  schemas/harness/run-event.schema.json \
  schemas/harness/artifact-registry.schema.json \
  schemas/harness/operator-report.schema.json \
  survey/workflows/serial-to-preflight.yaml \
  survey/workflows/network-preflight.yaml \
  survey/workflows/serial-iteration.yaml; do
  grep -q "$file" scripts/validate-sysadmin-harness.ps1 || fail "validator does not name required file: $file"
done
pass "validator names required files"

if grep -q "scripts/SasRunContext.psm1" scripts/validate-sysadmin-harness.ps1; then
  fail "validator still claims run context ownership"
fi
pass "validator does not claim run context ownership"

grep -q "command surface wrappers" scripts/validate-sysadmin-harness.ps1 || fail "validator missing command surface wrapper check"
grep -q "command surface scripts" scripts/validate-sysadmin-harness.ps1 || fail "validator missing command surface script check"
grep -q "Run-HarnessContracts.cmd" scripts/validate-sysadmin-harness.ps1 || fail "validator missing contract launcher check"
grep -q "Tests/bash/run_harness_contracts.sh" scripts/validate-sysadmin-harness.ps1 || fail "validator missing contract runner route"
grep -q "exit /b %SAS_EXIT%" scripts/validate-sysadmin-harness.ps1 || fail "validator missing wrapper exit-code check"
pass "validator covers command surface wiring"

blocked='(Test-''NetConnection|Resolve-''DnsName|naa''bu|n''map|soc''ket|pack''et|pi''ng|nslook''up|cu''rl)'
if grep -E "$blocked" scripts/validate-sysadmin-harness.ps1; then
  fail "validator contains blocked command text"
fi
pass "validator contains no blocked command text"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File scripts/validate-sysadmin-harness.ps1
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-sysadmin-harness.ps1
else
  echo "[SKIP] PowerShell runtime unavailable; static validator contract checks completed."
fi

echo "SysAdmin harness validator contracts passed."
