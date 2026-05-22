#!/usr/bin/env bash
set -euo pipefail

# SysAdminSuite Bash-on-Windows smoke test.
# Verifies the commands expected by survey scripts exist in the active Bash environment.

missing=0

check_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "PASS: $command_name"
  else
    echo "FAIL: $command_name not found"
    missing=$((missing + 1))
  fi
}

echo "======================================"
echo " SysAdminSuite Bash-on-Windows Smoke Test"
echo "======================================"
echo

check_command bash
check_command cmd.exe
check_command hostname.exe
check_command ping.exe
check_command nslookup.exe

# These are reached through cmd.exe /c, but checking common availability helps catch broken PATHs.
check_command tee
check_command date
check_command tr

if [[ "$missing" -gt 0 ]]; then
  echo
  echo "Smoke test failed. Missing command count: $missing"
  echo "Expected runtime: Bash on Windows, usually Git Bash or MSYS2 Bash."
  exit 1
fi

echo
echo "Smoke test passed. Bash-on-Windows runtime looks usable."
