#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cmd="$repo_root/START-HERE-SysAdminSuite-Dashboard.cmd"
bat="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
friendly="$repo_root/SysAdminSuite Dashboard.cmd"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
start_md="$repo_root/START-HERE-SysAdminSuite.md"
entry_doc="$repo_root/docs/DASHBOARD_ENTRYPOINT.md"
exe_sprint="$repo_root/docs/DASHBOARD_EXE_FUTURE_SPRINT.md"
readme="$repo_root/README.md"
agents="$repo_root/AGENTS.md"
index="$repo_root/dashboard/index.html"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$cmd" ]] || fail "START-HERE-SysAdminSuite-Dashboard.cmd is missing"
[[ -f "$bat" ]] || fail "START-HERE-SysAdminSuite-Dashboard.bat is missing"
[[ -f "$friendly" ]] || fail "SysAdminSuite Dashboard.cmd is missing"
[[ -f "$start_md" ]] || fail "START-HERE-SysAdminSuite.md is missing"
[[ -f "$entry_doc" ]] || fail "docs/DASHBOARD_ENTRYPOINT.md is missing"
[[ -f "$exe_sprint" ]] || fail "docs/DASHBOARD_EXE_FUTURE_SPRINT.md is missing"

grep -Fq 'Launch-SysAdminSuiteDashboard.Host.bat' "$cmd" \
  || fail ".cmd launcher does not reference Launch-SysAdminSuiteDashboard.Host.bat"
grep -Fq 'http://127.0.0.1:5000/dashboard/' "$cmd" \
  || fail ".cmd launcher does not mention dashboard URL"
grep -Fq 'tutorial=cybernet' "$cmd" \
  || fail ".cmd launcher does not open Cybernet tutorial entry"
grep -Fq 'Press any key to close' "$cmd" \
  || fail ".cmd launcher does not pause on failure"

grep -Fq 'START-HERE-SysAdminSuite-Dashboard.cmd' "$bat" \
  || fail ".bat wrapper does not delegate to .cmd launcher"
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.cmd' "$friendly" \
  || fail "SysAdminSuite Dashboard.cmd does not delegate to .cmd launcher"

grep -Fq 'START-HERE-SysAdminSuite-Dashboard.cmd' "$readme" \
  || fail "README.md does not point to .cmd launcher"
grep -Fq '## Start here' "$readme" \
  || fail "README.md is missing Start here section"
grep -Fq 'DASHBOARD_ENTRYPOINT.md' "$agents" \
  || fail "AGENTS.md does not reference DASHBOARD_ENTRYPOINT.md"
grep -Fq 'DASHBOARD_EXE_FUTURE_SPRINT.md' "$entry_doc" \
  || fail "DASHBOARD_ENTRYPOINT.md does not reference EXE future sprint"
grep -Fq 'rel="icon"' "$index" \
  || fail "dashboard/index.html missing favicon link"
grep -Fq 'assets/harold.jpg' "$index" \
  || fail "dashboard/index.html favicon does not use Harold asset"

if git -C "$repo_root" ls-files --error-unmatch dist >/dev/null 2>&1; then
  fail "dist/ must not be committed"
fi

echo "PASS: dashboard entrypoint contracts"
