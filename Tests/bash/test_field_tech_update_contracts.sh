#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
updater="$repo_root/Update-SysAdminSuite.ps1"
bat="$repo_root/Update-SysAdminSuite.bat"
progress="$repo_root/tools/update/Show-SysAdminSuiteProgress.ps1"
approved="$repo_root/tools/update/Invoke-SysAdminSuiteUpdate.ps1"
doc="$repo_root/docs/FIELD_TECH_UPDATE.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$updater" ]] || fail "field tech updater is missing"
[[ -f "$bat" ]] || fail "field tech BAT wrapper is missing"
[[ -f "$progress" ]] || fail "shared progress helper is missing"

# The field updater must make progress a product-visible contract.
grep -Fq 'Show-SysAdminSuiteStep' "$updater" \
  || fail "updater does not use shared stage progress"
grep -Fq 'Write-Progress' "$progress" \
  || fail "progress helper does not call Write-Progress"
grep -Fq '[$Step/$Total]' "$progress" \
  || fail "progress helper does not print [step/total] text"
grep -Fq 'Git network operations stream their own output' "$updater" \
  || fail "updater does not document stage-based git progress"

# This is the explicit repair lane, so hard reset/clean are allowed only here.
grep -Fq "'reset', '--hard', 'origin/main'" "$updater" \
  || fail "field repair updater must reset to origin/main"
grep -Fq "'clean', '-fd'" "$updater" \
  || fail "field repair updater must clean stale files"
grep -Fq '& git -C $Root @Arguments' "$updater" \
  || fail "git operations must be scoped with git -C"
grep -Fq 'Assert-SafeInstallRoot' "$updater" \
  || fail "updater must validate safe install roots"
grep -Fq 'Refusing to update a drive root' "$updater" \
  || fail "updater must refuse drive roots"
grep -Fq 'Refusing to update protected folder' "$updater" \
  || fail "updater must refuse protected folders"
grep -Fq 'Default install path must end in SysAdminSuite' "$updater" \
  || fail "updater must guard the default SysAdminSuite leaf"
grep -Fq 'Get-Command git' "$updater" \
  || fail "updater must check git availability"
grep -Fq 'Missing progress helper' "$updater" \
  || fail "updater must fail clearly when the progress helper is missing"
grep -Fq 'reset --hard' "$approved" \
  && fail "approved launcher update helper must remain fast-forward only"

# Existing non-git folders must be backed up, not overwritten.
grep -Fq 'Invoke-BackupNonGitFolder' "$updater" \
  || fail "updater is missing non-git backup function"
grep -Fq 'Rename-Item' "$updater" \
  || fail "updater does not rename non-git folders to backups"
grep -Fq '.old.$timestamp' "$updater" \
  || fail "updater backup naming must include .old timestamp suffix"

# The updater must launch the canonical dashboard path and must not apply silently.
grep -Fq 'START-HERE-SysAdminSuite-Dashboard.bat' "$updater" \
  || fail "updater does not launch canonical dashboard BAT"
grep -Fq 'Read-Host' "$updater" \
  || fail "updater must ask for explicit confirmation"
grep -Fq 'Type YES to update' "$updater" \
  || fail "updater confirmation must require YES"
grep -Fq 'Update-SysAdminSuite.ps1' "$bat" \
  || fail "BAT wrapper does not call the PowerShell updater"

[[ -f "$doc" ]] || fail "field tech update doc is missing"
grep -Fq 'Do not run git clone over an existing copy' "$doc" \
  || fail "field tech doc must warn against cloning over existing copy"
grep -Fq 'reset --hard' "$doc" \
  || fail "field tech doc must explain reset-hard behavior"

echo "PASS: field tech update contracts"
