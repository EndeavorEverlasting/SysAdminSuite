#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

ledger="docs/handoff/pr142-scope-ledger.md"
boundary="Tests/bash/RUN_CONTEXT_LANE_BOUNDARY.md"
[[ -f "$ledger" ]] || fail "missing PR #142 scope ledger"
[[ -f "$boundary" ]] || fail "missing run context lane boundary"
pass "scope ledger and run context boundary exist"

for phrase in \
  "PR #142 is intentionally a broad harness-foundation PR" \
  "## Owned lanes" \
  "## Explicit non-owned lanes" \
  "## Merge-risk controls" \
  "## Merge-readiness rule" \
  "Harness Contracts succeeds" \
  "Pester succeeds" \
  "Survey doctrine succeeds" \
  "scripts/SasRunContext.psm1 remains outside PR #142-owned changes"; do
  grep -Fq "$phrase" "$ledger" || fail "scope ledger missing phrase: $phrase"
done
pass "scope ledger records broad PR controls"

for owned in \
  "Harness doctrine" \
  "Fixture-backed English reports" \
  "Harness command surface" \
  "Harness validation helpers" \
  "CI/static parity" \
  "Run-context boundary documentation" \
  "Merge-readiness reporting" \
  "Workflow specs and schemas" \
  "Local staging and output discovery"; do
  grep -Fq "$owned" "$ledger" || fail "scope ledger missing owned lane: $owned"
done
pass "scope ledger enumerates owned lanes"

for surfaced in \
  "scripts/validate-sysadmin-harness.ps1" \
  "scripts/Ensure-Pr142HarnessFoundationWorktree.ps1" \
  "scripts/run-harness-validation.sh" \
  "scripts/render-english-report-fixtures.sh" \
  "scripts/show-harness-evidence-paths.sh" \
  "Tests/bash/RUN_CONTEXT_LANE_BOUNDARY.md" \
  "docs/handoff/pr142-merge-readiness.md" \
  "survey/input/README.md" \
  "survey/output/README.md" \
  "survey/artifacts/README.md"; do
  grep -Fq "$surfaced" "$ledger" || fail "scope ledger missing changed surface: $surfaced"
done
pass "scope ledger names scope-control surfaces changed by PR #142"

for non_owned in \
  "Canonical run context module" \
  "Target reduction planner" \
  "Low-noise port policy" \
  "Windows log classifier" \
  "Manifest-driven deployment"; do
  grep -Fq "$non_owned" "$ledger" || fail "scope ledger missing non-owned lane: $non_owned"
done
pass "scope ledger enumerates non-owned lanes"

grep -Fq "Windows .cmd launchers must be PowerShell-native" "$ledger" || fail "scope ledger missing Windows launcher rule"
grep -Fq "must not depend on Git Bash or WSL" "$ledger" || fail "scope ledger missing no-Bash Windows rule"
grep -Fq "Bash contract scripts may stay tracked for CI/static parity" "$ledger" || fail "scope ledger missing CI/static Bash parity rule"
pass "scope ledger distinguishes Windows and CI execution paths"

grep -Fq "PR #146" "$boundary" || fail "run context boundary does not name PR #146"
grep -Fq "must consume that module after rebasing" "$boundary" || fail "run context boundary does not require consuming merged run context module"
grep -Fq "Do not add new foundation-contract assertions here that make this PR the behavioral owner" "$boundary" || fail "run context boundary does not forbid behavioral ownership"
pass "run context module is consumed from PR #146, not owned by PR #142"

if grep -RE "Test-NetConnection|Resolve-DnsName|naabu|nmap|socket|packet|ping|nslookup|curl" "$ledger" scripts/Render-SasEnglishReport.ps1; then
  fail "scope-controlled behavior surfaces contain blocked live-network command text"
fi
pass "scope-controlled behavior surfaces avoid blocked live-network command text"

echo "PR #142 scope boundary contracts passed."
