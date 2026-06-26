#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
preflight="$repo_root/survey/sas-network-preflight.ps1"
runbook="$repo_root/docs/FIELD_NETWORK_PREFLIGHT.md"
start_here="$repo_root/START-HERE-CYBERNET-NEURON-SURVEY.md"
dashboard_patch="$repo_root/dashboard/js/cybernet-os-preflight.js"
field_files=("$runbook" "$start_here" "$dashboard_patch")

fail(){ echo "FAIL: $*" >&2; exit 1; }
contains(){ grep -Fq -- "$1" "$2" || fail "$3"; }
not_contains(){ grep -Fq -- "$1" "$2" && fail "$3"; }
not_matches(){ grep -Eq -- "$1" "$2" && fail "$3"; }

for f in "$preflight" "$runbook" "$start_here" "$dashboard_patch"; do
  [[ -f "$f" ]] || fail "missing file: $f"
done

win_temp_re='C:[\\]Temp'
posix_tmp='/'tmp
legacy_folder='sas-'cybernet
git_shell='Git'' Bash'
ming_shell='MING''W64'

not_matches "$win_temp_re" "$preflight" 'preflight references emergency Windows temp intake'
not_contains "$posix_tmp" "$preflight" 'preflight references POSIX temp intake'
not_contains "$legacy_folder" "$preflight" 'preflight references legacy emergency target folder'

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

contains 'targets/local' "$preflight" 'missing targets/local input root'
contains 'logs/targets' "$preflight" 'missing logs/targets input root'
contains 'survey/input' "$preflight" 'missing survey/input staging root'
contains 'Normalized runtime staging only' "$runbook" 'runbook missing staging doctrine'
contains 'survey/output' "$preflight" 'missing survey/output output root'
contains 'logs/nmap' "$preflight" 'missing logs/nmap output root'
contains 'survey/artifacts' "$preflight" 'missing survey/artifacts output root'
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
for col in HostName Hostname Target Identifier ComputerName DeviceName Name; do
  contains "$col" "$preflight" "missing $col column support"
done
contains 'Serial-only rows must be normalized or enriched' "$preflight" 'must refuse serial-only material clearly'

contains 'Export or copy the approved spreadsheet' "$runbook" 'runbook missing source export/copy step'
contains 'Run the PowerShell network preflight' "$runbook" 'runbook missing PowerShell preflight step'
contains 'Review the generated CSV under `survey/output/network_preflight/`' "$runbook" 'runbook missing output review step'
contains '.\survey\sas-network-preflight.ps1' "$dashboard_patch" 'dashboard patch missing PowerShell entrypoint'
contains 'survey\output\network_preflight' "$dashboard_patch" 'dashboard patch missing generated output folder'

echo 'PASS: PowerShell network preflight contracts'
