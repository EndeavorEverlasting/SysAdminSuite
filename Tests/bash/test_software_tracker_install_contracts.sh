#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

python_tool="$repo_root/scripts/software_tracker_installs.py"
bash_wrapper="$repo_root/scripts/sas-software-tracker-install.sh"
cmd_launcher="$repo_root/Start-SoftwareTrackerInstall.cmd"
pytest_file="$repo_root/Tests/test_software_tracker_installs.py"
docs_file="$repo_root/docs/SOFTWARE_TRACKER_INSTALLS.md"
config_file="$repo_root/Config/software-tracker.example.json"

[[ -f "$python_tool" ]] || fail "missing Python Software Tracker install tool"
[[ -f "$bash_wrapper" ]] || fail "missing Bash Software Tracker install wrapper"
[[ -f "$cmd_launcher" ]] || fail "missing CMD Software Tracker install front door"
[[ -f "$pytest_file" ]] || fail "missing pytest coverage"
[[ -f "$docs_file" ]] || fail "missing Software Tracker install docs"
[[ -f "$config_file" ]] || fail "missing example config"

grep -q 'software_tracker_installs.py' "$bash_wrapper" || fail "Bash wrapper does not call Python core"
grep -q 'Git\\bin\\bash.exe' "$cmd_launcher" || fail "CMD front door does not use Git Bash"
grep -q 'PowerShell remains legacy/reference' "$docs_file" || fail "docs do not label PowerShell as legacy/reference"
grep -q 'Python + Bash/CMD' "$docs_file" || fail "docs do not name Python + Bash/CMD as primary"
grep -q 'software_tracker_directories_schema.xlsx' "$pytest_file" || fail "pytest does not consume directories schema fixture"
grep -q 'software_tracker_bad_rows.xlsx' "$pytest_file" || fail "pytest does not consume bad rows fixture"
grep -q 'Tests/fixtures/installers' "$pytest_file" || fail "pytest does not consume installer fixtures via config"
grep -q 'Software Tracker.xlsx' "$repo_root/.gitignore" || fail "real Software Tracker.xlsx is not ignored"
grep -q '\*.real.xlsx' "$repo_root/.gitignore" || fail "real xlsx pattern is not ignored"
grep -q 'data/private/' "$repo_root/.gitignore" || fail "private data directory is not ignored"

if git -C "$repo_root" ls-files 'tools/software/Invoke-SoftwareTrackerInstall.ps1' | grep -q .; then
  fail "new PowerShell-first Software Tracker automation was added"
fi

if grep -Eq 'shell *= *True|webbrowser\.open|curl .*http|Start-Process .*http' "$python_tool"; then
  fail "Python tool contains unsafe shell or URL execution pattern"
fi

paths_config="$repo_root/Config/software-tracker.paths.json"
panel_js="$repo_root/dashboard/js/panel-software.js"
tutorial_js="$repo_root/dashboard/js/software-tracker-tutorial.js"
index_html="$repo_root/dashboard/index.html"
smoke_test="$repo_root/dashboard/smoke-test.js"

[[ -f "$paths_config" ]] || fail "missing Config/software-tracker.paths.json"
[[ -f "$panel_js" ]] || fail "missing Software panel JS"
[[ -f "$tutorial_js" ]] || fail "missing Software Tracker tutorial JS"
[[ -f "$index_html" ]] || fail "missing dashboard index.html"

grep -q 'logs/targets/software/Software Tracker 6-26-2026.xlsx' "$paths_config" || fail "paths config missing offline workbook path"
grep -q 'Preview Install Plan' "$panel_js" || fail "panel missing Preview Install Plan label"
grep -q 'Review Plan' "$panel_js" || fail "panel missing Review Plan label"
grep -q 'Approve Live Run' "$panel_js" || fail "panel missing Approve Live Run label"
grep -q 'Run Approved Installs' "$panel_js" || fail "panel missing Run Approved Installs label"
grep -q 'Export Report' "$panel_js" || fail "panel missing Export Report label"
grep -q 'software-tracker-install-plan' "$repo_root/dashboard/js/parsers.js" || fail "parser missing install-plan type"
grep -q 'software-tracker-hero' "$index_html" || fail "dashboard missing Software Tracker hero"
grep -q 'software-tracker-tutorial' "$index_html" || fail "dashboard missing Software Tracker tutorial"
grep -q 'workflow-tutorial' "$index_html" || fail "dashboard missing shared workflow-tutorial class"
grep -q 'SOFTWARE_TRACKER_TUTORIAL_STEPS' "$tutorial_js" || fail "tutorial missing 7-step workflow"
grep -q 'Dry-run preview' "$tutorial_js" || fail "tutorial missing dry-run step"
grep -q '\--execute' "$tutorial_js" || fail "tutorial missing guarded execute path"

echo "PASS: Software Tracker install contracts"
