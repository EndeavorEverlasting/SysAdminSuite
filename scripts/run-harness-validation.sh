#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v pwsh >/dev/null 2>&1; then
  PS_BIN="pwsh"
elif command -v powershell.exe >/dev/null 2>&1; then
  PS_BIN="powershell.exe"
elif command -v powershell >/dev/null 2>&1; then
  PS_BIN="powershell"
else
  echo "[SAS][FAIL] PowerShell runtime not found. Install pwsh or run on Windows PowerShell." >&2
  exit 127
fi

echo "[SAS] Running synthetic harness validation"
echo "[SAS] Implementation: scripts/validate-sysadmin-harness.ps1"
"$PS_BIN" -NoProfile -File "$ROOT/scripts/validate-sysadmin-harness.ps1"
