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
NAABU_PIPE="survey/sas-run-naabu-pipeline.sh"
SUBNET_RUNNER="survey/sas-cybernet-subnet-survey.sh"
AD_EXPORT="survey/sas-export-ad-registered-population.sh"

for f in "$BASH_HELPER" "$PS_MODULE" "$DISPATCH" "$PREFLIGHT" "$TARGETS_README" "$NAABU_PIPE" "$SUBNET_RUNNER" "$AD_EXPORT"; do
  [[ -f "$f" ]] || fail "missing central target intake file: $f"
done

bash -n "$BASH_HELPER"
bash -n "$NAABU_PIPE"
bash -n "$SUBNET_RUNNER"
bash -n "$AD_EXPORT"

contains 'sas_target_require_input_file' "$BASH_HELPER" 'Bash helper missing input validation function'
contains 'sas_target_require_manifest_file' "$BASH_HELPER" 'Bash helper missing manifest validation function'
contains 'sas_target_require_output_path' "$BASH_HELPER" 'Bash helper missing output validation function'
contains 'targets/local' "$BASH_HELPER" 'Bash helper missing targets/local root'
contains 'logs/targets' "$BASH_HELPER" 'Bash helper missing logs/targets root'
contains 'survey/input' "$BASH_HELPER" 'Bash helper missing survey/input staging root'
contains 'survey/output' "$BASH_HELPER" 'Bash helper missing survey/output root'
contains 'logs/nmap' "$BASH_HELPER" 'Bash helper missing logs/nmap root'
contains 'survey/artifacts' "$BASH_HELPER" 'Bash helper missing survey/artifacts root'
contains 'SAS_TARGET_ALLOW_TEST_FIXTURES' "$BASH_HELPER" 'Bash helper missing fixture-only test switch'
contains 'SAS_TARGET_ALLOW_NONSTANDARD_OUTPUT' "$BASH_HELPER" 'Bash helper missing explicit nonstandard output test switch'

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

for wrapper in "$NAABU_PIPE" "$SUBNET_RUNNER" "$AD_EXPORT"; do
  contains 'TARGET_INTAKE_HELPER' "$wrapper" "$wrapper must locate shared Bash helper"
  contains 'source "$TARGET_INTAKE_HELPER"' "$wrapper" "$wrapper must source shared Bash helper"
done
contains 'sas_target_require_input_file "$file" "Naabu target list"' "$NAABU_PIPE" 'Naabu pipeline must validate target list through helper'
contains 'sas_target_require_output_path "$OUT" "Naabu output file"' "$NAABU_PIPE" 'Naabu pipeline must validate output through helper'
contains 'sas_target_require_input_file "$HOST_FILE" "confirm-windows host file"' "$SUBNET_RUNNER" 'subnet runner must validate host file through helper'
contains 'sas_target_require_input_file "$file" "subnet CIDR file"' "$SUBNET_RUNNER" 'subnet runner must validate subnet file through helper'
contains 'sas_target_require_manifest_file "$MANIFEST" "resolve-only manifest"' "$SUBNET_RUNNER" 'subnet runner must validate resolver manifest through helper'
contains 'sas_target_require_input_file "$AD_CSV" "AD registered population CSV export"' "$AD_EXPORT" 'AD export must validate AD CSV through helper'
contains 'sas_target_require_output_path "$OUTPUT_DIR/ad_registered_normalized.csv"' "$AD_EXPORT" 'AD export must validate output through helper'

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

for f in "$DISPATCH" "$PREFLIGHT" "$NAABU_PIPE" "$SUBNET_RUNNER" "$AD_EXPORT"; do
  not_contains '/tmp/sas-cybernet' "$f" "$f must not revive emergency temp path"
  not_contains 'C:\Temp' "$f" "$f must not revive emergency Windows temp path"
done

echo 'PASS: central target intake contracts'
