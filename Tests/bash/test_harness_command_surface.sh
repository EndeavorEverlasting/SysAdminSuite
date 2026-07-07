#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

for file in \
  Run-HarnessValidation.cmd \
  Run-EnglishReportFixture.cmd \
  Run-ExportHarnessEvidence.cmd \
  scripts/run-harness-validation.sh \
  scripts/render-english-report-fixtures.sh \
  scripts/show-harness-evidence-paths.sh \
  docs/launch-and-doc-index.md; do
  [[ -f "$file" ]] || fail "missing command surface file: $file"
done
pass "command surface files exist"

bash -n scripts/run-harness-validation.sh
bash -n scripts/render-english-report-fixtures.sh
bash -n scripts/show-harness-evidence-paths.sh
pass "harness shell scripts parse"

grep -q "scripts/run-harness-validation.sh" Run-HarnessValidation.cmd || fail "Run-HarnessValidation.cmd does not call run-harness-validation.sh"
grep -q "scripts/render-english-report-fixtures.sh" Run-EnglishReportFixture.cmd || fail "Run-EnglishReportFixture.cmd does not call render-english-report-fixtures.sh"
grep -q "scripts/show-harness-evidence-paths.sh" Run-ExportHarnessEvidence.cmd || fail "Run-ExportHarnessEvidence.cmd does not call show-harness-evidence-paths.sh"
pass "root wrappers call implementation scripts"

grep -q "exit /b %SAS_EXIT%" Run-HarnessValidation.cmd || fail "Run-HarnessValidation.cmd does not preserve exit code"
grep -q "exit /b %SAS_EXIT%" Run-EnglishReportFixture.cmd || fail "Run-EnglishReportFixture.cmd does not preserve exit code"
grep -q "exit /b %SAS_EXIT%" Run-ExportHarnessEvidence.cmd || fail "Run-ExportHarnessEvidence.cmd does not preserve exit code"
pass "root wrappers preserve exit code"

grep -q "scripts/validate-sysadmin-harness.ps1" scripts/run-harness-validation.sh || fail "validation script does not call PowerShell validator"
grep -q "scripts/Render-SasEnglishReport.ps1" scripts/render-english-report-fixtures.sh || fail "report fixture script does not call renderer"
grep -q "serial_preflight_summary.sample.json" scripts/render-english-report-fixtures.sh || fail "report fixture script missing serial fixture"
grep -q "network_preflight_summary.sample.json" scripts/render-english-report-fixtures.sh || fail "report fixture script missing network fixture"
pass "implementation scripts route to harness behavior"

grep -q "Run-HarnessValidation.cmd" docs/launch-and-doc-index.md || fail "launch index missing harness validation wrapper"
grep -q "Run-EnglishReportFixture.cmd" docs/launch-and-doc-index.md || fail "launch index missing report fixture wrapper"
grep -q "Run-ExportHarnessEvidence.cmd" docs/launch-and-doc-index.md || fail "launch index missing evidence wrapper"
pass "launch index names command surface"

echo "Harness command surface contracts passed."
