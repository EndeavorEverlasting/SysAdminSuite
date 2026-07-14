#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ui="$repo_root/dashboard/js/software-deployment-tutorial.js"
loader="$repo_root/dashboard/js/launch-repo-setup-tutorial.js"
runtime="$repo_root/dashboard/test_software_deployment_tutorial.js"
start_doc="$repo_root/START-HERE-SysAdminSuite.md"
written="$repo_root/docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for path in "$ui" "$loader" "$runtime" "$start_doc" "$written"; do
  [[ -f "$path" ]] || fail "missing required software deployment surface: ${path#$repo_root/}"
done

grep -Fq 'software-deployment-tutorial.js' "$loader" \
  || fail "front-door loader does not load the software deployment tutorial"
grep -Fq 'Primary deployment interface' "$ui" \
  || fail "dashboard does not mark Software Deployment as the primary interface"
grep -Fq 'Start Software Deployment' "$ui" \
  || fail "dashboard is missing the software deployment start action"
grep -Fq 'Jump to Safe Dry Run' "$ui" \
  || fail "dashboard is missing the direct safe-dry-run action"
grep -Fq "'software-deployment'" "$ui" \
  || fail "dashboard is missing the ?tutorial=software-deployment route"
grep -Fq 'Invoke-SasSoftwareInstallE2E.ps1' "$ui" \
  || fail "dashboard tutorial does not run the executable fixture proof first"
grep -Fq 'Invoke-SasSoftwareInstall.ps1' "$ui" \
  || fail "dashboard tutorial does not compose the canonical software installer"
grep -Fq 'real_operator_wrapper_executed' "$ui" \
  || fail "dashboard tutorial does not require real-wrapper fixture evidence"
grep -Fq 'delta is 3 / 0 / 0' "$ui" \
  || fail "dashboard tutorial does not require the exact fixture delta"
grep -Fq 'Use one hostname or FQDN only' "$ui" \
  || fail "dashboard tutorial does not reject multi-target pilot input"
grep -Fq -- '-WhatIf' "$ui" \
  || fail "dashboard tutorial is missing request-only planning"
grep -Fq -- '-AllowTargetMutation' "$ui" \
  || fail "dashboard tutorial is missing the explicit live mutation gate"
grep -Fq 'Confirmation remains enabled' "$ui" \
  || fail "dashboard tutorial does not preserve confirmation on the first pilot"
grep -Fq 'completed_count = 1' "$ui" \
  || fail "dashboard tutorial does not require completed-count evidence"
grep -Fq 'cleanup_failure_count = 0' "$ui" \
  || fail "dashboard tutorial does not require cleanup proof"
grep -Fq 'repo_artifact_remaining_count = 0' "$ui" \
  || fail "dashboard tutorial does not require remnant proof"
grep -Fq 'Expand only when' "$ui" \
  || fail "dashboard tutorial is missing expansion gates"
grep -Fq 'Stop when' "$ui" \
  || fail "dashboard tutorial is missing stop gates"

grep -Fq 'web interface is the canonical technician tutorial' "$start_doc" \
  || fail "START-HERE does not identify the web interface as canonical"
grep -Fq 'Supporting written runbook' "$start_doc" \
  || fail "START-HERE does not demote Markdown to a supporting runbook"

node --check "$ui"
node --check "$loader"
node --check "$runtime"
node "$runtime"

echo "PASS: dashboard software deployment tutorial contracts"
