#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
preflight="$repo_root/survey/sas-network-preflight.ps1"
runbook="$repo_root/docs/FIELD_NETWORK_PREFLIGHT.md"
start_here="$repo_root/START-HERE-CYBERNET-NEURON-SURVEY.md"
dashboard_patch="$repo_root/dashboard/js/cybernet-os-preflight.js"
field_files=("$runbook" "$start_here" "$dashboard_patch")

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local needle="$1" file="$2" message="$3"
  grep -Fq -- "$needle" "$file" || fail "$message"
}

assert_not_contains() {
  local needle="$1" file="$2" message="$3"
  grep -Fq -- "$needle" "$file" && fail "$message"
}

assert_file "$preflight"
assert_file "$runbook"
assert_file "$start_here"
assert_file "$dashboard_patch"

# 1-2. Field preflight must not default to emergency temp paths.
assert_not_contains 'C:\Temp' "$preflight" 'PowerShell preflight references C:\Temp'
assert_not_contains '/tmp' "$preflight" 'PowerShell preflight references /tmp'
assert_not_contains 'sas-cybernet' "$preflight" 'PowerShell preflight references emergency sas-cybernet temp folder'

# 3. No executable live sample hostnames in the product field preflight surface.
for f in "$preflight" "$runbook" "$start_here" "$dashboard_patch"; do
  if grep -Eq '(^|[^A-Z0-9])(WMH|WNH|CYB)[0-9]{3,}[A-Z0-9_-]*' "$f"; then
    fail "field preflight surface embeds executable-looking live/sample hostname: $f"
  fi
done

# 4-5. No positive Git Bash/MINGW64 or Bash-syntax field path remains.
for f in "${field_files[@]}"; do
  grep -Eiq 'Run (in|from) Git Bash|Windows Git Bash|MINGW64 prompt|bash bash/|bash survey/' "$f" \
    && fail "field doc/dashboard still routes operators to a Bash/Git Bash path: $f"
  grep -Eq 'mkdir -p|printf .+\\n' "$f" \
    && fail "field doc/dashboard still contains Bash setup syntax: $f"
done

# 6. PowerShell command surfaces must be labeled PowerShell.
for f in "${field_files[@]}"; do
  assert_contains 'Run in Windows PowerShell' "$f" "missing PowerShell label in $f"
done
assert_contains 'Get-Content' "$preflight" 'preflight must use Get-Content for TXT parsing'
assert_contains 'Resolve-DnsName' "$preflight" 'preflight must use Resolve-DnsName for DNS'
assert_contains 'Test-NetConnection' "$preflight" 'preflight must use Test-NetConnection for TCP checks'
assert_contains 'Export-Csv' "$preflight" 'preflight must export CSV output'
assert_contains '-WarningAction SilentlyContinue' "$preflight" 'Test-NetConnection warnings must be suppressed'

# 7-9. Codified source/staging/output roots.
assert_contains 'targets/local' "$preflight" 'preflight missing targets/local input root'
assert_contains 'logs/targets' "$preflight" 'preflight missing logs/targets input root'
assert_contains 'survey/input' "$preflight" 'preflight missing survey/input staging root'
assert_contains 'survey/input is normalized runtime staging only' "$runbook" 'runbook must say survey/input is staging only'
assert_contains 'survey/output' "$preflight" 'preflight missing survey/output output root'
assert_contains 'logs/nmap' "$preflight" 'preflight missing logs/nmap output root'
assert_contains 'survey/artifacts' "$preflight" 'preflight missing survey/artifacts output root'
assert_contains 'survey/output/ is generated output, not the place to invent live targets' "$start_here" 'start-here must not treat survey/output as target source'

# 10. Progress is a visible CLI contract.
assert_contains 'Write-Progress' "$preflight" 'preflight missing Write-Progress'
assert_contains 'PercentComplete' "$preflight" 'preflight missing percent progress'
assert_contains '[$Step/$Total]' "$preflight" 'preflight missing [step/total] stage output'
assert_contains '[$checkNumber/$totalChecks]' "$preflight" 'preflight missing [n/total] per-check output'

# 11. No target file means list candidates and stop.
assert_contains 'No -TargetFile was provided. Stopping without probing.' "$preflight" 'preflight must refuse to probe without target file'
assert_contains 'Get-CandidateTargetFiles' "$preflight" 'preflight must discover candidate target files'

# 12. Non-codified paths rejected unless explicit override is used.
assert_contains 'AllowNonstandardInput' "$preflight" 'preflight missing explicit nonstandard override flag'
assert_contains 'outside codified intake roots' "$preflight" 'preflight missing non-codified input rejection'
assert_contains 'NONSTANDARD INPUT OVERRIDE' "$preflight" 'preflight override mode must be clearly labeled'

# 13. TXT and CSV parsing support.
assert_contains "'.txt'" "$preflight" 'preflight missing .txt support'
assert_contains "'.csv'" "$preflight" 'preflight missing .csv support'
assert_contains 'Import-Csv' "$preflight" 'preflight missing CSV parser'
assert_contains 'HostName' "$preflight" 'preflight missing HostName column support'
assert_contains 'Hostname' "$preflight" 'preflight missing Hostname column support'
assert_contains 'Target' "$preflight" 'preflight missing Target column support'
assert_contains 'Identifier' "$preflight" 'preflight missing Identifier column support'
assert_contains 'ComputerName' "$preflight" 'preflight missing ComputerName column support'
assert_contains 'DeviceName' "$preflight" 'preflight missing DeviceName column support'
assert_contains 'Name' "$preflight" 'preflight missing Name column support'
assert_contains 'Serial-only rows must be normalized or enriched' "$preflight" 'preflight must refuse serial-only target material clearly'

# Documentation must present the simple field flow.
assert_contains 'Export or copy the approved spreadsheet' "$runbook" 'runbook missing source export/copy step'
assert_contains 'Run the PowerShell network preflight' "$runbook" 'runbook missing PowerShell preflight step'
assert_contains 'Review the generated CSV under `survey/output/network_preflight/`' "$runbook" 'runbook missing output review step'

# The field dashboard patch must point to the durable entrypoint, not emergency snippets.
assert_contains '.\\survey\\sas-network-preflight.ps1' "$dashboard_patch" 'dashboard patch missing PowerShell preflight entrypoint'
assert_contains 'survey\\output\\network_preflight' "$dashboard_patch" 'dashboard patch missing generated output folder'

echo 'PASS: PowerShell network preflight contracts'
