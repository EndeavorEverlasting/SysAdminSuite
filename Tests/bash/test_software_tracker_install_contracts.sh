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

echo "PASS: Software Tracker install contracts"
