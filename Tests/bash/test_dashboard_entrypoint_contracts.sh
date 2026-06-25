#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
start_here_bat="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
start_here_md="$repo_root/START-HERE-SysAdminSuite.md"
entry_doc="$repo_root/docs/DASHBOARD_ENTRYPOINT.md"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
publish_script="$repo_root/tools/publish-dashboard-entrypoint.ps1"
readme="$repo_root/README.md"
survey_readme="$repo_root/survey/README.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$start_here_bat" ]] || fail "START-HERE-SysAdminSuite-Dashboard.bat is missing"
[[ -f "$start_here_md" ]] || fail "START-HERE-SysAdminSuite.md is missing"
[[ -f "$entry_doc" ]] || fail "docs/DASHBOARD_ENTRYPOINT.md is missing"
[[ -f "$host_bat" ]] || fail "Launch-SysAdminSuiteDashboard.Host.bat is missing"
[[ -f "$publish_script" ]] || fail "tools/publish-dashboard-entrypoint.ps1 is missing"

grep -Fq 'Launch-SysAdminSuiteDashboard.Host.bat' "$start_here_bat" \
  || fail "START-HERE launcher does not reference Launch-SysAdminSuiteDashboard.Host.bat"
grep -Fq 'http://127.0.0.1:5000/dashboard/' "$start_here_bat" \
  || fail "START-HERE launcher does not mention dashboard URL"
grep -Fq 'tutorial=cybernet' "$start_here_bat" \
  || fail "START-HERE launcher does not open Cybernet tutorial entry"
grep -Fq 'Press any key to close' "$start_here_bat" \
  || fail "START-HERE launcher does not pause on failure"

grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$readme" \
  || fail "README.md does not point to START-HERE-SysAdminSuite-Dashboard.bat"
grep -Fq '## Start here' "$readme" \
  || fail "README.md is missing Start here section"
grep -Fq 'http://127.0.0.1:5000/dashboard/' "$entry_doc" \
  || fail "docs/DASHBOARD_ENTRYPOINT.md does not mention dashboard URL"
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$survey_readme" \
  || fail "survey/README.md does not point to START-HERE dashboard launcher"

if git -C "$repo_root" ls-files --error-unmatch dist >/dev/null 2>&1; then
  fail "dist/ must not be committed"
fi

echo "PASS: dashboard entrypoint contracts"
