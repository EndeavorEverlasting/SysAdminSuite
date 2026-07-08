#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

for file in \
  Run-HarnessContracts.cmd \
  Run-HarnessValidation.cmd \
  Run-EnglishReportFixture.cmd \
  Run-ExportHarnessEvidence.cmd \
  scripts/Ensure-Pr142HarnessFoundationWorktree.ps1 \
  scripts/run-harness-validation.sh \
  scripts/render-english-report-fixtures.sh \
  scripts/show-harness-evidence-paths.sh \
  Tests/bash/run_harness_contracts.sh \
  docs/launch-and-doc-index.md; do
  [[ -f "$file" ]] || fail "missing command surface file: $file"
done
pass "command surface files exist"

bash -n scripts/run-harness-validation.sh
bash -n scripts/render-english-report-fixtures.sh
bash -n scripts/show-harness-evidence-paths.sh
bash -n Tests/bash/run_harness_contracts.sh
pass "harness shell scripts parse"

grep -q "Tests/bash/run_harness_contracts.sh" Run-HarnessContracts.cmd || fail "Run-HarnessContracts.cmd does not call run_harness_contracts.sh"
grep -q "scripts/run-harness-validation.sh" Run-HarnessValidation.cmd || fail "Run-HarnessValidation.cmd does not call run-harness-validation.sh"
grep -q "scripts/render-english-report-fixtures.sh" Run-EnglishReportFixture.cmd || fail "Run-EnglishReportFixture.cmd does not call render-english-report-fixtures.sh"
grep -q "scripts/show-harness-evidence-paths.sh" Run-ExportHarnessEvidence.cmd || fail "Run-ExportHarnessEvidence.cmd does not call show-harness-evidence-paths.sh"
pass "root wrappers call implementation scripts"

grep -q "exit /b %SAS_EXIT%" Run-HarnessContracts.cmd || fail "Run-HarnessContracts.cmd does not preserve exit code"
grep -q "exit /b %SAS_EXIT%" Run-HarnessValidation.cmd || fail "Run-HarnessValidation.cmd does not preserve exit code"
grep -q "exit /b %SAS_EXIT%" Run-EnglishReportFixture.cmd || fail "Run-EnglishReportFixture.cmd does not preserve exit code"
grep -q "exit /b %SAS_EXIT%" Run-ExportHarnessEvidence.cmd || fail "Run-ExportHarnessEvidence.cmd does not preserve exit code"
pass "root wrappers preserve exit code"

grep -q "scripts/validate-sysadmin-harness.ps1" scripts/run-harness-validation.sh || fail "validation script does not call PowerShell validator"
grep -q "scripts/Render-SasEnglishReport.ps1" scripts/render-english-report-fixtures.sh || fail "report fixture script does not call renderer"
grep -q "serial_preflight_summary.sample.json" scripts/render-english-report-fixtures.sh || fail "report fixture script missing serial fixture"
grep -q "network_preflight_summary.sample.json" scripts/render-english-report-fixtures.sh || fail "report fixture script missing network fixture"
grep -q "Tests/bash/test_english_log_artifact_contracts.sh" Tests/bash/run_harness_contracts.sh || fail "contract runner missing English log test"
grep -q "Tests/bash/test_sysadmin_harness_validator_contracts.sh" Tests/bash/run_harness_contracts.sh || fail "contract runner missing validator test"
grep -q "Tests/bash/test_harness_command_surface.sh" Tests/bash/run_harness_contracts.sh || fail "contract runner missing command surface test"
pass "implementation scripts route to harness behavior"

grep -q "Ensure-Pr142HarnessFoundationWorktree.ps1" docs/launch-and-doc-index.md || fail "launch index missing PR142 worktree bootstrap"
grep -q "Bootstrap" docs/launch-and-doc-index.md || fail "launch index missing bootstrap cheat-sheet entry"
grep -q "Run-HarnessContracts.cmd" docs/launch-and-doc-index.md || fail "launch index missing harness contract wrapper"
grep -q "Run-HarnessValidation.cmd" docs/launch-and-doc-index.md || fail "launch index missing harness validation wrapper"
grep -q "Run-EnglishReportFixture.cmd" docs/launch-and-doc-index.md || fail "launch index missing report fixture wrapper"
grep -q "Run-ExportHarnessEvidence.cmd" docs/launch-and-doc-index.md || fail "launch index missing evidence wrapper"
pass "launch index names command surface"

for fragment in \
  "New-Item -ItemType Directory -Force -Path \$DevRoot" \
  "git @Arguments" \
  "worktree" \
  "origin/\$Branch" \
  "Set-Location -LiteralPath \$worktreeRoot"; do
  grep -q "$fragment" scripts/Ensure-Pr142HarnessFoundationWorktree.ps1 || fail "worktree bootstrap missing fragment: $fragment"
done
pass "worktree bootstrap creates and enters missing sibling worktree"

echo "Harness command surface contracts passed."
