#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
checker="$repo_root/tools/sas-check-repo-freshness.sh"
gitignore="$repo_root/.gitignore"
workflow="$repo_root/.github/workflows/dashboard-smoke.yml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$checker" ]] || fail "repo freshness checker is missing"

grep -Fq 'fetch --quiet origin' "$checker" \
  || fail "checker does not fetch origin read-only"
grep -Fq 'rev-list --left-right --count main...origin/main' "$checker" \
  || fail "checker does not compare local main to origin/main"
grep -Fq 'git pull --ff-only origin main' "$checker" \
  || fail "checker does not document approved fast-forward update command"
grep -Fq 'updateAvailable' "$checker" \
  || fail "checker JSON does not expose updateAvailable"
grep -Fq 'canAutoUpdate' "$checker" \
  || fail "checker JSON does not expose canAutoUpdate"
grep -Fq 'manualReviewReason' "$checker" \
  || fail "checker JSON does not expose manualReviewReason"
grep -Fq 'reset --hard' "$checker" \
  && fail "checker must not use git reset --hard"

grep -Fq 'dashboard/repo-freshness.json' "$gitignore" \
  || fail "runtime repo freshness JSON must be ignored"
grep -Fq 'test_repo_freshness_contracts.sh' "$workflow" \
  || fail "dashboard smoke workflow does not run repo freshness contracts"

echo "PASS: repo freshness contracts"
