#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cmd="$repo_root/START-HERE-SysAdminSuite-Dashboard.cmd"
bat="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
friendly="$repo_root/SysAdminSuite Dashboard.cmd"
host_bat="$repo_root/Launch-SysAdminSuiteDashboard.Host.bat"
start_md="$repo_root/START-HERE-SysAdminSuite.md"
entry_doc="$repo_root/docs/DASHBOARD_ENTRYPOINT.md"
field_release_doc="$repo_root/docs/DASHBOARD_FIELD_RELEASE.md"
field_release_script="$repo_root/tools/build/New-DashboardFieldRelease.ps1"
field_release_workflow="$repo_root/.github/workflows/dashboard-field-release.yml"
exe_sprint="$repo_root/docs/DASHBOARD_EXE_FUTURE_SPRINT.md"
readme="$repo_root/README.md"
survey_readme="$repo_root/survey/README.md"
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
# Pause-on-failure: the host-missing branch must both emit its error and pause.
# "Press any key to close" also appears on the success path, so assert the
# failure message exists alongside a pause rather than the pause text alone.
grep -Fq 'Could not find Launch-SysAdminSuiteDashboard.Host.bat' "$bat" \
  || fail ".bat launcher does not report the missing host launcher on failure"
grep -Fq 'Press any key to close' "$bat" \
  || fail ".bat launcher does not pause before closing"

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

# Clone/download wording: field users must be told where to clone from and warned
# against the nested SysAdminSuite\SysAdminSuite mistake. Assert in the lay-user
# front doors (README + START-HERE) and the agent canonical reference.
for clone_doc in "$readme" "$start_md" "$entry_doc"; do
  grep -Fq 'git clone https://github.com/EndeavorEverlasting/SysAdminSuite.git' "$clone_doc" \
    || fail "$(basename "$clone_doc") is missing the git clone instruction"
  grep -Fq 'SysAdminSuite\SysAdminSuite' "$clone_doc" \
    || fail "$(basename "$clone_doc") is missing the nested-folder (SysAdminSuite\\SysAdminSuite) warning"
done

# Canonical docs must not present a .cmd as the primary field instruction.
# grep is line-based, so .* matches "same line"; alternation covers both .cmd
# aliases. A nearby alias mention on its own line (e.g. "...are compatibility
# aliases") is intentionally allowed; only a same-line "Double-click <x>.cmd"
# primary instruction is forbidden.
grep -Eq 'Double-click.*(START-HERE-SysAdminSuite-Dashboard|SysAdminSuite Dashboard)\.cmd' "$start_md" \
  && fail "START-HERE-SysAdminSuite.md must not present a .cmd as the primary double-click"
# Auto-publish on first run: the host launcher must build the dashboard host
# automatically (via the publish script) when it is missing, and must check for
# the .NET SDK first so a clean failure path exists.
[[ -f "$host_bat" ]] || fail "Launch-SysAdminSuiteDashboard.Host.bat is missing"
grep -Fq 'publish-dashboard-entrypoint.ps1' "$host_bat" \
  || fail "host launcher does not auto-invoke publish-dashboard-entrypoint.ps1"
grep -Fq 'powershell.exe' "$host_bat" \
  || fail "host launcher does not run the publish script via powershell.exe"
grep -Fq 'dotnet' "$host_bat" \
  || fail "host launcher does not check for dotnet before building"

# The root .bat must NOT instruct field users to run the publish command by hand
# as the normal path, and must not tell them to double-click again as a routine.
grep -Fq -- '-File tools\publish-dashboard-entrypoint.ps1' "$bat" \
  && fail "root .bat must not instruct field users to run publish manually"
grep -Fiq 'double-click this file again' "$bat" \
  && fail "root .bat must not tell users to double-click again as the normal path"

# The root .bat must health-check before opening the browser (no dead tab).
grep -Fq 'curl' "$bat" \
  || fail "root .bat has no health check (curl) before opening the browser"
health_line=$(grep -n 'HOST_UP=1' "$bat" | head -1 | cut -d: -f1)
browser_line=$(grep -n 'start "" "http' "$bat" | head -1 | cut -d: -f1)
[[ -n "$health_line" && -n "$browser_line" && "$health_line" -lt "$browser_line" ]] \
  || fail "root .bat opens the browser before the host health check"

# Field-safe build-failure messaging in the root .bat.
grep -Fq 'The dashboard app could not be built on this machine' "$bat" \
  || fail "root .bat missing field-safe build-failure message"
grep -Fq 'packaged SysAdminSuite Dashboard field release' "$bat" \
  || fail "root .bat missing field-release / IT-admin guidance"

# Launcher must distinguish packaged field release vs source checkout paths.
grep -Fq 'Packaged field release detected' "$bat" \
  || fail "root .bat does not detect packaged field release layout"
grep -Fq 'Source checkout detected' "$bat" \
  || fail "root .bat does not label source-checkout path"

# Field release package tooling and docs (no SDK on target).
[[ -f "$field_release_doc" ]] || fail "docs/DASHBOARD_FIELD_RELEASE.md is missing"
[[ -f "$field_release_script" ]] || fail "tools/build/New-DashboardFieldRelease.ps1 is missing"
[[ -f "$field_release_workflow" ]] || fail ".github/workflows/dashboard-field-release.yml is missing"
grep -Fq 'DASHBOARD_FIELD_RELEASE.md' "$entry_doc" \
  || fail "DASHBOARD_ENTRYPOINT.md does not reference field release doc"
grep -Fq 'field release package' "$start_md" \
  || fail "START-HERE-SysAdminSuite.md does not explain field release package"
grep -Fq 'app/bin/SysAdminSuite.DashboardHost.exe' "$field_release_doc" \
  || fail "DASHBOARD_FIELD_RELEASE.md does not document app/bin host layout"

# Docs must mention automatic first-run preparation and keep CLI non-default.
for prep_doc in "$readme" "$start_md" "$entry_doc" "$survey_readme"; do
  grep -Fq 'automatically prepare' "$prep_doc" \
    || fail "$(basename "$prep_doc") does not mention automatic first-run preparation"
done
grep -Fq 'Use CLI tools only' "$start_md" \
  || fail "START-HERE-SysAdminSuite.md must keep CLI as non-default"

grep -Fq 'rel="icon"' "$index" \
  || fail "dashboard/index.html missing favicon link"
grep -Fq 'assets/harold.jpg' "$index" \
  || fail "dashboard/index.html favicon does not use Harold asset"

if git -C "$repo_root" ls-files --error-unmatch dist >/dev/null 2>&1; then
  fail "dist/ must not be committed"
fi

echo "PASS: dashboard entrypoint contracts"
