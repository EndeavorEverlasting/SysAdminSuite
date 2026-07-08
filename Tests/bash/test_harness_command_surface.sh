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
  scripts/Invoke-SasHarnessContracts.ps1 \
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

grep -Fq 'scripts\Invoke-SasHarnessContracts.ps1' Run-HarnessContracts.cmd || fail "Run-HarnessContracts.cmd does not call PowerShell contract runner"
grep -Fq 'scripts\validate-sysadmin-harness.ps1' Run-HarnessValidation.cmd || fail "Run-HarnessValidation.cmd does not call PowerShell validator"
grep -Fq 'scripts\Render-SasEnglishReport.ps1' Run-EnglishReportFixture.cmd || fail "Run-EnglishReportFixture.cmd does not call PowerShell renderer"
grep -Fq 'Harness output locations' Run-ExportHarnessEvidence.cmd || fail "Run-ExportHarnessEvidence.cmd does not print evidence locations"
pass "root wrappers call PowerShell-native implementation surfaces"

for wrapper in Run-HarnessContracts.cmd Run-HarnessValidation.cmd Run-EnglishReportFixture.cmd Run-ExportHarnessEvidence.cmd; do
  grep -Fq 'exit /b %SAS_EXIT%' "$wrapper" || fail "$wrapper does not preserve exit code"
  if grep -Fq 'bash ' "$wrapper"; then
    fail "$wrapper still depends on Bash"
  fi
done
pass "root wrappers preserve exit code and avoid Bash dependency"

grep -Fq 'scripts/validate-sysadmin-harness.ps1' scripts/Invoke-SasHarnessContracts.ps1 || fail "PowerShell contract runner does not call validator"
grep -Fq 'scripts/validate-sysadmin-harness.ps1' scripts/run-harness-validation.sh || fail "validation script does not call PowerShell validator"
grep -Fq 'scripts/Render-SasEnglishReport.ps1' scripts/render-english-report-fixtures.sh || fail "report fixture script does not call renderer"
grep -Fq 'serial_preflight_summary.sample.json' scripts/render-english-report-fixtures.sh || fail "report fixture script missing serial fixture"
grep -Fq 'network_preflight_summary.sample.json' scripts/render-english-report-fixtures.sh || fail "report fixture script missing network fixture"
grep -Fq 'Tests/bash/test_english_log_artifact_contracts.sh' Tests/bash/run_harness_contracts.sh || fail "contract runner missing English log test"
grep -Fq 'Tests/bash/test_sysadmin_harness_validator_contracts.sh' Tests/bash/run_harness_contracts.sh || fail "contract runner missing validator test"
grep -Fq 'Tests/bash/test_harness_command_surface.sh' Tests/bash/run_harness_contracts.sh || fail "contract runner missing command surface test"
pass "implementation scripts route to harness behavior"

grep -Fq 'Invoke-SasHarnessContracts.ps1' docs/launch-and-doc-index.md || fail "launch index missing PowerShell contract runner"
grep -Fq 'Ensure-Pr142HarnessFoundationWorktree.ps1' docs/launch-and-doc-index.md || fail "launch index missing PR142 worktree bootstrap"
grep -Fq 'Bootstrap' docs/launch-and-doc-index.md || fail "launch index missing bootstrap cheat-sheet entry"
grep -Fq 'Run-HarnessContracts.cmd' docs/launch-and-doc-index.md || fail "launch index missing harness contract wrapper"
grep -Fq 'Run-HarnessValidation.cmd' docs/launch-and-doc-index.md || fail "launch index missing harness validation wrapper"
grep -Fq 'Run-EnglishReportFixture.cmd' docs/launch-and-doc-index.md || fail "launch index missing report fixture wrapper"
grep -Fq 'Run-ExportHarnessEvidence.cmd' docs/launch-and-doc-index.md || fail "launch index missing evidence wrapper"
pass "launch index names command surface"

for fragment in \
  "New-Item -ItemType Directory -Force -Path \$DevRoot" \
  "git @Arguments" \
  "worktree" \
  "origin/\$Branch" \
  "Set-Location -LiteralPath \$worktreeRoot"; do
  grep -Fq "$fragment" scripts/Ensure-Pr142HarnessFoundationWorktree.ps1 || fail "worktree bootstrap missing fragment: $fragment"
done
pass "worktree bootstrap creates and enters missing sibling worktree"

echo "Harness command surface contracts passed."
