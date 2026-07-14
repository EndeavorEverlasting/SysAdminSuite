#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash_helper="$repo_root/survey/lib/sas-progress.sh"
ps_helper="$repo_root/scripts/SasProgress.psm1"
docs="$repo_root/docs/PROGRESS_REPORTING.md"

for path in "$bash_helper" "$ps_helper" "$docs"; do
  [[ -f "$path" ]] || fail "missing progress contract file: $path"
done

for state in running waiting complete failed skipped; do
  grep -Fq "$state" "$bash_helper" || fail "Bash helper missing $state"
  grep -Fq "$state" "$ps_helper" || fail "PowerShell helper missing $state"
  grep -Fqi "$state" "$docs" || fail "documentation missing $state"
done

grep -Fq '>&2' "$bash_helper" || fail 'Bash progress must use stderr'
grep -Fq 'Write-Host' "$ps_helper" || fail 'PowerShell progress must avoid success output'
grep -Fq 'NoProgress' "$ps_helper" || fail 'PowerShell helper missing -NoProgress'
grep -Fq 'sas_progress_disable' "$bash_helper" || fail 'Bash helper missing suppression'

for script in \
  bash/transport/sas-network-preflight.sh \
  bash/transport/sas-printer-probe.sh \
  bash/transport/sas-smb-readonly-recon.sh \
  bash/transport/sas-wmi-identity.sh \
  bash/transport/sas-workstation-identity.sh; do
  grep -Fq -- '--no-progress' "$repo_root/$script" || fail "$script missing --no-progress"
  grep -Fq 'sas_progress_complete' "$repo_root/$script" || fail "$script missing complete state"
  grep -Fq 'sas_progress_fail' "$repo_root/$script" || fail "$script missing failed state"
done

grep -Fq '[SAS][running]' "$repo_root/Launch-SysAdminSuiteDashboard.Host.bat" || fail 'dashboard launcher missing running state'
grep -Fq '[SAS][complete]' "$repo_root/Launch-SysAdminSuiteDashboard.Host.bat" || fail 'dashboard launcher missing complete state'
grep -Fq '[SAS][failed]' "$repo_root/Launch-SysAdminSuiteDashboard.Host.bat" || fail 'dashboard launcher missing failed state'
grep -Fq '[SAS][skipped]' "$repo_root/Launch-SysAdminSuiteDashboard.Host.bat" || fail 'dashboard launcher missing skipped state'

grep -Fq "case 'RunWaiting'" "$repo_root/dashboard/js/run-control.js" || fail 'dashboard lifecycle missing waiting state'
grep -Fq "case 'RunSkipped'" "$repo_root/dashboard/js/run-control.js" || fail 'dashboard lifecycle missing skipped state'
grep -Fq 'Probe failed before completion' "$repo_root/dashboard/relay.py" || fail 'relay child failure is not surfaced'

grep -Fq '[SAS][running]' "$repo_root/Run-HarnessValidation.cmd" || fail 'validator wrapper missing running state'
grep -Fq '[SAS][complete]' "$repo_root/Run-HarnessValidation.cmd" || fail 'validator wrapper missing complete state'
grep -Fq '[SAS][failed]' "$repo_root/Run-HarnessValidation.cmd" || fail 'validator wrapper missing failed state'

printf 'PASS: progress reporting contracts\n'
