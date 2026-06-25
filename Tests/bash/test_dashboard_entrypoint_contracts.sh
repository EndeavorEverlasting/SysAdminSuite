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

# Canonical launcher is the .bat: it must contain the full launcher logic.
grep -Fq 'Launch-SysAdminSuiteDashboard.Host.bat' "$bat" \
  || fail ".bat launcher does not reference Launch-SysAdminSuiteDashboard.Host.bat"
grep -Fq 'http://127.0.0.1:5000/dashboard/' "$bat" \
  || fail ".bat launcher does not mention dashboard URL"
grep -Fq 'tutorial=cybernet' "$bat" \
  || fail ".bat launcher does not open Cybernet tutorial entry"
grep -Fq 'Press any key to close' "$bat" \
  || fail ".bat launcher does not pause on failure"

# .cmd files are compatibility aliases that delegate to the canonical .bat.
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$cmd" \
  || fail ".cmd wrapper does not delegate to .bat launcher"
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$friendly" \
  || fail "SysAdminSuite Dashboard.cmd does not delegate to .bat launcher"

grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$readme" \
  || fail "README.md does not point to .bat launcher"
grep -Fq '## Start here' "$readme" \
  || fail "README.md is missing Start here section"
grep -Fq 'DASHBOARD_ENTRYPOINT.md' "$agents" \
  || fail "AGENTS.md does not reference DASHBOARD_ENTRYPOINT.md"
grep -Fq 'DASHBOARD_EXE_FUTURE_SPRINT.md' "$entry_doc" \
  || fail "DASHBOARD_ENTRYPOINT.md does not reference EXE future sprint"

# START-HERE doc must name the .bat as the canonical front door, include the
# dashboard URL, and carry the lay-user Mermaid flow.
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$start_md" \
  || fail "START-HERE-SysAdminSuite.md does not point to .bat launcher"
grep -Fq 'http://127.0.0.1:5000/dashboard/' "$start_md" \
  || fail "START-HERE-SysAdminSuite.md does not include the dashboard URL"
grep -Fq 'flowchart TD' "$start_md" \
  || fail "START-HERE-SysAdminSuite.md is missing the Mermaid workflow diagram"

# Canonical docs must not present a .cmd as the primary field instruction.
grep -Eq 'Double-click[^\n]*START-HERE-SysAdminSuite-Dashboard\.cmd' "$start_md" \
  && fail "START-HERE-SysAdminSuite.md must not present .cmd as the primary double-click"
grep -Fq 'rel="icon"' "$index" \
  || fail "dashboard/index.html missing favicon link"
grep -Fq 'assets/harold.jpg' "$index" \
  || fail "dashboard/index.html favicon does not use Harold asset"

if git -C "$repo_root" ls-files --error-unmatch dist >/dev/null 2>&1; then
  fail "dist/ must not be committed"
fi

echo "PASS: dashboard entrypoint contracts"
