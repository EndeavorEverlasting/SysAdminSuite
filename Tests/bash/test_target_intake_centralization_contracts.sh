#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail(){ echo "FAIL: $*" >&2; exit 1; }
contains(){ grep -Fq -- "$1" "$2" || fail "$3"; }
not_contains(){ if grep -Fq -- "$1" "$2"; then fail "$3"; fi; }

BASH_HELPER="survey/lib/sas-target-intake.sh"
PS_MODULE="scripts/SasTargetIntake.psm1"
DISPATCH="survey/sas-target-intake-dispatch.ps1"
PREFLIGHT="survey/sas-network-preflight.ps1"
TARGETS_README="targets/README.md"

for f in "$BASH_HELPER" "$PS_MODULE" "$DISPATCH" "$PREFLIGHT" "$TARGETS_README"; do
  [[ -f "$f" ]] || fail "missing central target intake file: $f"
done

bash -n "$BASH_HELPER"

contains 'sas_target_require_input_file' "$BASH_HELPER" 'Bash helper missing input validation function'
contains 'sas_target_require_output_path' "$BASH_HELPER" 'Bash helper missing output validation function'
contains 'targets/local' "$BASH_HELPER" 'Bash helper missing targets/local root'
contains 'logs/targets' "$BASH_HELPER" 'Bash helper missing logs/targets root'
contains 'survey/input' "$BASH_HELPER" 'Bash helper missing survey/input staging root'
contains 'survey/output' "$BASH_HELPER" 'Bash helper missing survey/output root'
contains 'logs/nmap' "$BASH_HELPER" 'Bash helper missing logs/nmap root'
contains 'survey/artifacts' "$BASH_HELPER" 'Bash helper missing survey/artifacts root'

contains 'Get-SasTargetIntakeRoots' "$PS_MODULE" 'PowerShell module missing root set function'
contains 'Assert-SasApprovedInputPath' "$PS_MODULE" 'PowerShell module missing input assertion'
contains 'Assert-SasApprovedOutputPath' "$PS_MODULE" 'PowerShell module missing output assertion'
contains 'targets/local' "$PS_MODULE" 'PowerShell module missing targets/local root'
contains 'logs/targets' "$PS_MODULE" 'PowerShell module missing logs/targets root'
contains 'survey/input' "$PS_MODULE" 'PowerShell module missing survey/input staging root'
contains 'survey/output' "$PS_MODULE" 'PowerShell module missing survey/output root'
contains 'logs/nmap' "$PS_MODULE" 'PowerShell module missing logs/nmap root'
contains 'survey/artifacts' "$PS_MODULE" 'PowerShell module missing survey/artifacts root'

contains 'Import-Module $targetIntakeModule -Force' "$PREFLIGHT" 'PowerShell preflight must import shared target intake module'
contains 'Get-SasTargetIntakeRoots' "$PREFLIGHT" 'PowerShell preflight must consume shared root set'
contains 'Test-SasPathUnderAnyRoot' "$PREFLIGHT" 'PowerShell preflight must validate paths through shared helper'
contains 'No -TargetFile was provided. Stopping without probing.' "$PREFLIGHT" 'PowerShell preflight must still refuse empty target selection'
contains 'NONSTANDARD INPUT OVERRIDE' "$PREFLIGHT" 'PowerShell preflight must clearly label nonstandard override mode'

for mode in ListCandidates NetworkPreflight NaabuPlan ADRegisteredPlan SubnetConfirmPlan; do
  contains "$mode" "$DISPATCH" "dispatcher missing mode $mode"
done
contains 'Get-SasCandidateTargetFile' "$DISPATCH" 'dispatcher must list centralized candidates'
contains 'Assert-SasApprovedInputPath' "$DISPATCH" 'dispatcher must validate selected target files'
contains 'Run in Windows PowerShell' "$DISPATCH" 'dispatcher must label PowerShell execution path'

contains 'scripts/SasTargetIntake.psm1' "$TARGETS_README" 'targets README missing PowerShell helper reference'
contains 'survey/lib/sas-target-intake.sh' "$TARGETS_README" 'targets README missing Bash helper reference'
contains 'survey/sas-target-intake-dispatch.ps1' "$TARGETS_README" 'targets README missing dispatcher reference'
contains 'Cybernet surveys' "$TARGETS_README" 'targets README missing Cybernet use-case coverage'
contains 'subnet discovery' "$TARGETS_README" 'targets README missing subnet use-case coverage'
contains 'AD exports' "$TARGETS_README" 'targets README missing AD use-case coverage'
contains 'low-noise reachability planning' "$TARGETS_README" 'targets README missing reachability use-case coverage'

not_contains '/tmp/sas-cybernet' "$DISPATCH" 'dispatcher must not revive emergency temp path'
not_contains 'C:\Temp' "$DISPATCH" 'dispatcher must not revive emergency Windows temp path'
not_contains '/tmp/sas-cybernet' "$PREFLIGHT" 'preflight must not revive emergency temp path'
not_contains 'C:\Temp' "$PREFLIGHT" 'preflight must not revive emergency Windows temp path'

echo 'PASS: central target intake contracts'
