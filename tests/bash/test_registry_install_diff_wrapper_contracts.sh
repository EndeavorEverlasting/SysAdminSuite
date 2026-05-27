#!/usr/bin/env bash
set -euo pipefail

WRAPPER="scripts/sas_registry_install_diff.sh"
[[ -f "$WRAPPER" ]] || { echo "missing wrapper"; exit 1; }
[[ -x "$WRAPPER" ]] || { echo "wrapper not executable"; exit 1; }

bash -n "$WRAPPER"

grep -q "Invoke-RegistryInstallDiff.ps1" "$WRAPPER"

grep -Eq "pwsh|powershell" "$WRAPPER"

grep -q "POWERSHELL_UNAVAILABLE_IN_ENVIRONMENT" "$WRAPPER"

! grep -Eqi "reg (add|delete|import|restore)" "$WRAPPER"
! grep -Eqi "Set-ItemProperty|New-ItemProperty|Remove-ItemProperty" "$WRAPPER"

"$WRAPPER" --help >/dev/null

echo "PASS: wrapper contracts"
