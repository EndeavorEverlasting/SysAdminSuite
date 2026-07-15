#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

validator="scripts/Invoke-SasVmDryRunHarnessProof.ps1"
base_validator="scripts/validate-sysadmin-harness.ps1"
vm_validator="scripts/Test-SasVmDryRunReadiness.ps1"
profile="harness/e2e/vm-dry-run-readiness.json"
schema="schemas/harness/harness-proof-result.schema.json"
vm_schema="schemas/harness/vm-dry-run-readiness.schema.json"
workflow=".github/workflows/one-command-harness-proof.yml"
for required in "$validator" "$base_validator" "$vm_validator" "$profile" "$schema" "$vm_schema" "$workflow"; do
  [[ -f "$required" ]] || fail "required one-command VM proof file missing: $required"
done

for fragment in \
  "APP HARNESS VALIDATION" \
  "scripts/SasRunContext.psm1" \
  "artifact registry" \
  "report renderer" \
  "cross-lane merge integrity" \
  "optional Python module compatibility" \
  "git_bash_not_available" \
  "optional MCP symbol smoke" \
  "lsp_project_not_loaded" \
  "hook hygiene" \
  "harness_validation_result.json" \
  "synthetic_offline" \
  "runtime_proof=\$false" \
  "network_activity_performed=\$false" \
  "launcher_execution_performed=\$false" \
  "target_mutation_performed=\$false"; do
  grep -Fq "$fragment" "$base_validator" || fail "base validator missing contract: $fragment"
done
pass "base validator declares matrix, JSON, dependency, and proof-boundary contracts"

for fragment in \
  "APP HARNESS VALIDATION" \
  "Test-SasVmDryRunReadiness.ps1" \
  "VM dry run:" \
  "synthetic_offline" \
  "runtime_proof = \$false" \
  "network_activity_performed = \$false" \
  "launcher_execution_performed = \$false" \
  "target_mutation_performed = \$false" \
  "data_mutation_performed = \$false"; do
  grep -Fq "$fragment" "$validator" || fail "composed validator missing contract: $fragment"
done
for fragment in \
  "VM DRY-RUN READINESS" \
  "request-only dry run" \
  "runtime entry gate" \
  "vm_provider_not_available" \
  "no VM started" \
  "no real package executed"; do
  grep -Fq "$fragment" "$vm_validator" || fail "VM readiness validator missing contract: $fragment"
done
pass "one command composes the base harness and VM readiness matrices"

python - "$schema" "$vm_schema" "$profile" <<'PY'
import json
import pathlib
import sys

result_schema = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
vm_schema = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
profile = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))

assert result_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert result_schema["additionalProperties"] is False
assert result_schema["properties"]["schema_version"]["const"] == "sas-harness-proof/v1"
assert result_schema["properties"]["proof_level"]["const"] == "synthetic_offline"
for field in (
    "runtime_proof",
    "network_activity_performed",
    "launcher_execution_performed",
    "target_mutation_performed",
    "data_mutation_performed",
):
    assert result_schema["properties"][field]["const"] is False

assert vm_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert vm_schema["additionalProperties"] is False
assert profile["schema_version"] == "sas-vm-dry-run-readiness/v1"
assert profile["proof_class"] == "synthetic_offline_vm_readiness"
assert profile["proof_ceiling"] == "readiness_only_no_vm_started"
for field in (
    "readiness_validator_starts_vm",
    "readiness_validator_executes_real_package",
    "readiness_validator_mutates_host",
    "readiness_validator_contacts_target",
    "readiness_validator_uses_external_network",
    "autologon_allowed",
):
    assert profile["safety"][field] is False
PY
grep -Fq "Invoke-SasVmDryRunHarnessProof.ps1" "$workflow" || fail "workflow missing composed VM dry-run command"
grep -Fq "test_vm_dry_run_readiness_contracts.py" "$workflow" || fail "workflow missing executable VM readiness contracts"
grep -Fq "vm-dry-run-readiness.schema.json" "$workflow" || fail "workflow missing VM profile schema gate"
grep -Fq "harness-proof-result.schema.json" "$workflow" || fail "workflow missing result schema gate"
grep -Fq "Test-Json" "$workflow" || fail "workflow does not validate emitted JSON"
pass "machine-readable result and VM readiness schemas are closed and enforced in CI"

for surface in "$validator" "$vm_validator"; do
  for forbidden in Start-VM New-VM Checkpoint-VM Restore-VMSnapshot Start-Process Invoke-Item explorer.exe START-HERE-SysAdminSuite Launch-SysAdminSuite Test-NetConnection Resolve-DnsName Invoke-WebRequest; do
    if grep -Fiq "$forbidden" "$surface"; then
      fail "$surface contains forbidden VM, launcher, or network execution surface: $forbidden"
    fi
  done
done
pass "one-command VM readiness surfaces contain no VM start, launcher, package, or network execution"

[[ -f Tests/survey/test_one_command_harness_proof_contracts.py ]] || fail "one-command executable proof contracts missing"
[[ -f Tests/survey/test_vm_dry_run_readiness_contracts.py ]] || fail "VM readiness executable proof contracts missing"
grep -Fq "test_one_command_harness_proof_contracts.py" tests/survey/run_offline_survey_tests.sh || fail "offline runner missing base proof contracts"
pass "base offline runner and dedicated Windows VM-readiness CI are both present"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$validator"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$validator"
else
  echo "[SKIP] PowerShell runtime unavailable; static contracts completed."
fi

echo "SysAdmin one-command VM dry-run harness contracts passed."
