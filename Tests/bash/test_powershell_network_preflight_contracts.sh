#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
preflight="$repo_root/survey/sas-network-preflight.ps1"
serial_plan="$repo_root/survey/sas-serial-preflight-plan.ps1"
runbook="$repo_root/docs/FIELD_NETWORK_PREFLIGHT.md"
low_noise_doc="$repo_root/docs/LOW_NOISE_PROBE_PRINCIPLES.md"
start_here="$repo_root/START-HERE-CYBERNET-NEURON-SURVEY.md"
dashboard_patch="$repo_root/dashboard/js/cybernet-os-preflight.js"
ps_module="$repo_root/scripts/SasTargetIntake.psm1"
dispatch="$repo_root/survey/sas-target-intake-dispatch.ps1"
bash_helper="$repo_root/survey/lib/sas-target-intake.sh"
field_files=("$runbook" "$start_here" "$dashboard_patch")

fail(){ echo "FAIL: $*" >&2; exit 1; }
contains(){ grep -Fq -- "$1" "$2" || fail "$3"; }
not_contains(){ if grep -Fq -- "$1" "$2"; then fail "$3"; fi; }
not_matches(){ if grep -Eq -- "$1" "$2"; then fail "$3"; fi; }

for f in "$preflight" "$serial_plan" "$runbook" "$low_noise_doc" "$start_here" "$dashboard_patch" "$ps_module" "$dispatch" "$bash_helper"; do
  [[ -f "$f" ]] || fail "missing file: $f"
done

bash -n "$bash_helper"

win_temp_re='C:[\\]Temp'
posix_tmp='/'tmp
legacy_folder='sas-'cybernet
git_shell='Git'' Bash'
ming_shell='MING''W64'

not_matches "$win_temp_re" "$preflight" 'preflight references emergency Windows temp intake'
not_contains "$posix_tmp" "$preflight" 'preflight references POSIX temp intake'
not_contains "$legacy_folder" "$preflight" 'preflight references legacy emergency target folder'
not_matches "$win_temp_re" "$serial_plan" 'serial preflight references emergency Windows temp intake'
not_contains "$posix_tmp" "$serial_plan" 'serial preflight references POSIX temp intake'
not_contains "$legacy_folder" "$serial_plan" 'serial preflight references legacy emergency target folder'

for f in "$preflight" "$runbook" "$start_here" "$dashboard_patch"; do
  grep -Eq '(^|[^A-Z0-9])(WMH|WNH|CYB)[0-9]{3,}[A-Z0-9_-]*' "$f" \
    && fail "field preflight surface embeds executable-looking hostname: $f"
done

for f in "${field_files[@]}"; do
  grep -Eiq "Run (in|from) $git_shell|Windows $git_shell|$ming_shell prompt|bash bash/|bash survey/" "$f" \
    && fail "field surface routes operators to a non-PowerShell shell: $f"
  grep -Eq 'mkdir -p|printf .+\\n' "$f" \
    && fail "field surface contains Bash setup syntax: $f"
  contains 'Run in Windows PowerShell' "$f" "missing PowerShell label in $f"
done

contains 'Get-Content' "$preflight" 'missing TXT parser hook'
contains 'Resolve-DnsName' "$preflight" 'missing DNS hook'
contains 'Test-NetConnection' "$preflight" 'missing TCP hook'
contains '-WarningAction SilentlyContinue' "$preflight" 'missing quiet warning handling'
contains 'Export-Csv' "$preflight" 'missing CSV export'

contains 'Import-Module $targetIntakeModule -Force' "$preflight" 'preflight must import shared target intake module'
contains 'Get-SasTargetIntakeRoots' "$preflight" 'preflight must consume shared root set'
contains 'Test-SasPathUnderAnyRoot' "$preflight" 'preflight must validate through shared path helper'

for f in "$preflight" "$serial_plan" "$ps_module" "$bash_helper" "$dispatch"; do
  contains 'targets/local' "$f" "$f missing targets/local input root"
  contains 'logs/targets' "$f" "$f missing logs/targets input root"
  contains 'survey/input' "$f" "$f missing survey/input staging root"
  contains 'survey/output' "$f" "$f missing survey/output output root"
  contains 'logs/nmap' "$f" "$f missing logs/nmap output root"
  contains 'survey/artifacts' "$f" "$f missing survey/artifacts output root"
done
contains 'Normalized runtime staging only' "$runbook" 'runbook missing staging doctrine'
contains '`survey/output/` is generated output' "$start_here" 'start-here must classify survey/output as generated output'

contains 'Write-Progress' "$preflight" 'missing Write-Progress'
contains 'PercentComplete' "$preflight" 'missing percent progress'
contains '[$Step/$Total]' "$preflight" 'missing stage [step/total] output'
contains '[$checkNumber/$totalChecks]' "$preflight" 'missing per-check [n/total] output'

contains 'No -TargetFile was provided. Stopping without probing.' "$preflight" 'must refuse no target file'
contains 'Get-CandidateTargetFiles' "$preflight" 'must discover candidate target files'
contains 'AllowNonstandardInput' "$preflight" 'missing explicit nonstandard override flag'
contains 'outside codified intake roots' "$preflight" 'missing non-codified input rejection'
contains 'NONSTANDARD INPUT OVERRIDE' "$preflight" 'missing clear override label'

contains "'.txt'" "$preflight" 'missing .txt support'
contains "'.csv'" "$preflight" 'missing .csv support'
contains 'Import-Csv' "$preflight" 'missing CSV parser'
for col in HostName Hostname Target Identifier ComputerName DeviceName Name DnsName DNSName FQDN IPAddress IP IPv4; do
  contains "$col" "$preflight" "missing $col column support"
done
contains 'function Get-ExplicitTargetType' "$preflight" 'missing explicit target type helper'
contains 'function Test-ExplicitNonHostType' "$preflight" 'missing explicit non-host type guard'
contains "\$targetColumns = @('Target')" "$preflight" 'Target column must be separate from ambiguous Identifier'
contains "\$identifierColumns = @('Identifier')" "$preflight" 'Identifier column must be handled as ambiguous unless explicitly typed'
contains 'Skipping ambiguous Identifier value without explicit host/IP type' "$preflight" 'ambiguous Identifier rows must not silently probe'
contains 'Serial-only rows must be normalized or enriched' "$preflight" 'must refuse serial-only material clearly'

contains 'Alejandro serial list' "$serial_plan" 'serial planner must name Alejandro serial input'
contains 'serial-to-target evidence file' "$serial_plan" 'serial planner must validate evidence bridge files'
contains 'STAGE_FOR_NETWORK_PREFLIGHT' "$serial_plan" 'serial planner missing staged decision'
contains 'REVIEW_REQUIRED_NO_PROBE_READY_EVIDENCE' "$serial_plan" 'serial planner missing review decision'
contains 'do not ping the serial string' "$serial_plan" 'serial planner must not ping serial strings'
contains 'network_activity_performed = $false' "$serial_plan" 'serial planner must report no network activity'
contains 'to_probe_targets.txt' "$serial_plan" 'serial planner must stage target file'
contains 'low_noise_principle' "$serial_plan" 'serial planner summary missing low-noise principle'
contains 'network_visibility_note' "$serial_plan" 'serial planner summary missing network visibility note'
contains 'probe_selection_questions' "$serial_plan" 'serial planner summary missing probe selection questions'
contains 'probe_again_guidance' "$serial_plan" 'serial planner summary missing probe-again guidance'
contains 'LowNoiseDisposition' "$serial_plan" 'serial planner plan rows missing low-noise disposition'
contains 'The network sees packets, not the shell' "$serial_plan" 'serial planner must explain shell choice is not network visibility control'
contains 'If a device was recently reachable' "$serial_plan" 'serial planner must discourage habitual repeat probes'
contains 'SerialPreflightPlan' "$dispatch" 'dispatcher missing SerialPreflightPlan mode'
contains 'sas-serial-preflight-plan.ps1' "$dispatch" 'dispatcher missing serial planner entrypoint'

for mode in ListCandidates SerialPreflightPlan NetworkPreflight NaabuPlan ADRegisteredPlan SubnetConfirmPlan; do
  contains "$mode" "$dispatch" "dispatcher missing mode $mode"
done
contains 'Assert-SasApprovedInputPath' "$dispatch" 'dispatcher must validate selected target files'
contains 'sas_target_require_input_file' "$bash_helper" 'Bash helper missing reusable input validator'
contains 'sas_target_require_output_path' "$bash_helper" 'Bash helper missing reusable output validator'

contains 'Export or copy the approved spreadsheet' "$runbook" 'runbook missing source export/copy step'
contains 'Alejandro serial list flow' "$runbook" 'runbook missing Alejandro serial flow'
contains 'approved serial-to-host/IP evidence' "$runbook" 'runbook missing serial evidence bridge rule'
contains 'Serial-only rows go to review, not packets' "$runbook" 'runbook must route serial-only rows to review'
contains 'Low-noise probe posture' "$runbook" 'runbook missing low-noise probe posture section'
contains 'The network sees packets, not the shell' "$runbook" 'runbook missing network visibility principle'
contains 'Which exact ports answer the survey question?' "$runbook" 'runbook missing low-noise probe selection questions'
contains 'Five probes are unnecessary' "$runbook" 'runbook missing pragmatic repeat-probe guidance'
contains 'Run the PowerShell network preflight' "$runbook" 'runbook missing PowerShell preflight step'
contains 'Review the generated CSV under `survey/output/network_preflight/`' "$runbook" 'runbook missing output review step'
contains '.\survey\sas-network-preflight.ps1' "$dashboard_patch" 'dashboard patch missing PowerShell preflight entrypoint'
contains 'survey\output\network_preflight' "$dashboard_patch" 'dashboard patch missing generated output folder'

contains '# Low-Noise Probe Principles' "$low_noise_doc" 'low-noise doctrine missing title'
contains 'The network sees packets, not the operator' "$low_noise_doc" 'low-noise doctrine missing shell distinction'
contains 'smaller scope' "$low_noise_doc" 'low-noise doctrine missing scope principle'
contains 'fewer ports' "$low_noise_doc" 'low-noise doctrine missing port principle'
contains 'lower rate' "$low_noise_doc" 'low-noise doctrine missing rate principle'
contains 'fewer retries' "$low_noise_doc" 'low-noise doctrine missing retry principle'
contains 'Is this a CDN/WAF/load-balanced/front-door target?' "$low_noise_doc" 'low-noise doctrine missing front-door question'
contains 'five probes are unnecessary' "$low_noise_doc" 'low-noise doctrine missing pragmatic retry guidance'
contains 'low_noise_principle' "$low_noise_doc" 'low-noise doctrine missing artifact context fields'
contains 'Do not use stealth, bypass, or no-trace language.' "$low_noise_doc" 'low-noise doctrine must reject evasion language'

echo 'PASS: PowerShell network preflight contracts'
