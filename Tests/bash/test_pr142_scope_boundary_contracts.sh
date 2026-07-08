#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

ledger="docs/handoff/pr142-scope-ledger.md"
[[ -f "$ledger" ]] || fail "missing PR #142 scope ledger"
pass "scope ledger exists"

for phrase in \
  "PR #142 is intentionally a broad harness-foundation PR" \
  "## Owned lanes" \
  "## Explicit non-owned lanes" \
  "## Merge-risk controls" \
  "## Merge-readiness rule" \
  "Harness Contracts succeeds" \
  "Pester succeeds" \
  "Survey doctrine succeeds" \
  "scripts/SasRunContext.psm1 remains absent"; do
  grep -Fq "$phrase" "$ledger" || fail "scope ledger missing phrase: $phrase"
done
pass "scope ledger records broad PR controls"

for owned in \
  "Harness doctrine" \
  "Fixture-backed English reports" \
  "Harness command surface" \
  "CI/static parity" \
  "Workflow specs and schemas" \
  "Local output discovery"; do
  grep -Fq "$owned" "$ledger" || fail "scope ledger missing owned lane: $owned"
done
pass "scope ledger enumerates owned lanes"

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

if [[ -f scripts/SasRunContext.psm1 ]]; then
  fail "PR #142 branch contains scripts/SasRunContext.psm1; run context belongs to PR #146"
fi
pass "run context module remains outside PR #142 branch"

if grep -RE "Test-NetConnection|Resolve-DnsName|naabu|nmap|socket|packet|ping|nslookup|curl" "$ledger" scripts/Invoke-SasHarnessContracts.ps1 scripts/validate-sysadmin-harness.ps1 scripts/Render-SasEnglishReport.ps1; then
  fail "scope-controlled harness surfaces contain blocked live-network command text"
fi
pass "scope-controlled harness surfaces avoid blocked live-network command text"

echo "PR #142 scope boundary contracts passed."
