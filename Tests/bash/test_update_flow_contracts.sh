#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
helper="$repo_root/tools/update/Invoke-SysAdminSuiteUpdate.ps1"
policy="$repo_root/docs/APPROVED_UPDATE_FLOW.md"
manifest="$repo_root/Config/update-manifest.sample.json"
launcher="$repo_root/START-HERE-SysAdminSuite-Dashboard.bat"
deployment_doc="$repo_root/docs/DEPLOYMENT_ARTIFACTS.md"
field_doc="$repo_root/docs/DASHBOARD_FIELD_RELEASE.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$helper" ]] || fail "update helper is missing"
[[ -f "$policy" ]] || fail "approved update policy doc is missing"
[[ -f "$manifest" ]] || fail "update manifest sample is missing"

# Updates must require explicit approval before mutation.
grep -Fq -- '-CheckOnly' "$helper" \
  || fail "helper is missing CheckOnly mode"
grep -Fq -- '-Apply' "$helper" \
  || fail "helper is missing Apply mode"
grep -Fq -- '-Approved' "$helper" \
  || fail "helper is missing Approved guard"
grep -Fq -- '-Json' "$helper" \
  || fail "helper is missing Json output mode"
grep -Fq 'StateJsonPath' "$helper" \
  || fail "helper is missing StateJsonPath runtime state output"
grep -Fq 'Refusing to apply update without -Approved' "$helper" \
  || fail "helper does not refuse apply without approval"

# Source clone path must be fast-forward only and must never hard reset.
grep -Fq "'pull', '--ff-only', 'origin', 'main'" "$helper" \
  || fail "git clone update path does not use git pull --ff-only origin main"
grep -Fq "'fetch', 'origin'" "$helper" \
  || fail "git clone update path does not fetch origin"
grep -Fq "'status', '--short'" "$helper" \
  || fail "git clone update path does not check for a clean working tree"
grep -Fq "'branch', '--show-current'" "$helper" \
  || fail "git clone update path does not verify current branch"
grep -Fq "'log', '--branches', '--not', '--remotes', '--oneline'" "$helper" \
  || fail "git clone update path does not check for local-only commits"
grep -Fq "'rev-list', '--left-right', '--count', 'main...origin/main'" "$helper" \
  || fail "git clone update path does not compare local main with origin/main"
grep -Fq 'Behind' "$helper" \
  || fail "git clone update path does not expose behind count"
grep -Fq 'CanAutoUpdate' "$helper" \
  || fail "git clone update path does not expose auto-update safety"
grep -Fq 'reset --hard' "$helper" \
  && fail "helper must not use git reset --hard"

# Package path must be manifest and checksum based.
grep -Fq 'checksumSha256' "$helper" \
  || fail "package update path does not verify checksumSha256"
grep -Fq 'Expand-Archive' "$helper" \
  || fail "package update path does not extract package"
grep -Fq 'app.previous' "$helper" \
  || fail "package update path does not create an app backup"
grep -Fq '"packageUrl"' "$manifest" \
  || fail "manifest sample must include packageUrl"
grep -Fq '"checksumSha256"' "$manifest" \
  || fail "manifest sample must include checksumSha256"

# Launcher must check and prompt; it must not apply silently.
grep -Fq 'Invoke-SysAdminSuiteUpdate.ps1' "$launcher" \
  || fail "launcher does not call update helper"
grep -Fq 'repo-freshness.json' "$launcher" \
  || fail "launcher does not write dashboard freshness state"
grep -Fq 'Your local SysAdminSuite copy is behind the latest main' "$launcher" \
  || fail "launcher does not explain behind-main update state"
grep -Fq 'Apply the update before opening the dashboard' "$launcher" \
  || fail "launcher does not prompt for update approval"
grep -Fq -- '-Apply -Approved' "$launcher" \
  || fail "launcher does not pass Approved when applying update"

# Docs must distinguish git clone vs package updates and forbid silent updates.
grep -Fq 'must never update silently' "$policy" \
  || fail "policy doc does not forbid silent updates"
grep -Fq 'git pull --ff-only' "$policy" \
  || fail "policy doc does not document git fast-forward path"
grep -Fq 'checksum-verified' "$field_doc" \
  || fail "field release doc does not mention checksum-verified package updates"
grep -Fq 'Invoke-SysAdminSuiteUpdate.ps1' "$deployment_doc" \
  || fail "deployment artifacts doc does not reference update helper"

echo "PASS: approved update flow contracts"
