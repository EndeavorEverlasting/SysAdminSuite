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
canonical_profile="harness/api/canonical-path-registry.json"
canonical_validator="harness/validators/validate-canonical-path-contracts.py"
prompt_registry="docs/prompts.json"
schema="schemas/harness/harness-proof-result.schema.json"
composed_schema="schemas/harness/one-command-harness-proof-result.schema.json"
vm_schema="schemas/harness/vm-dry-run-readiness.schema.json"
workflow=".github/workflows/one-command-harness-proof.yml"
for required in "$validator" "$base_validator" "$vm_validator" "$profile" "$canonical_profile" "$canonical_validator" "$prompt_registry" "$schema" "$composed_schema" "$vm_schema" "$workflow"; do
  [[ -f "$required" ]] || fail "required one-command proof file missing: $required"
done

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  fail "Python 3 interpreter unavailable (tried python3, then python)"
fi

for fragment in \
  "APP HARNESS VALIDATION" \
  "scripts/SasRunContext.psm1" \
  "artifact registry" \
  "report renderer" \
  "cross-lane merge integrity" \
  "canonical path profile" \
  "harness/api/canonical-path-registry.json" \
  "onedrive_enabled" \
  "desktop_dev_root" \
  "docs/prompts.json" \
  "P11" \
  "optional Python module compatibility" \
  "git_bash_not_available" \
  "optional MCP symbol smoke" \
  "lsp_project_not_loaded" \
  "hook hygiene" \
  "harness_validation_result.json" \
  "synthetic_offline" \
  "final_status" \
  "validator_set" \
  "prompt_owner" \
  "runtime_proof=\$false" \
  "network_activity_performed=\$false" \
  "launcher_execution_performed=\$false" \
  "target_mutation_performed=\$false"; do
  grep -Fq "$fragment" "$base_validator" || fail "base validator missing contract: $fragment"
done
pass "base validator declares profile, Prompt Kit, matrix, JSON, dependency, and proof-boundary contracts"

for fragment in \
  "APP HARNESS VALIDATION" \
  "Test-SasVmDryRunReadiness.ps1" \
  "VM dry run:" \
  "required proof unavailable" \
  "environment_blocked" \
  "final_status" \
  "validator_set" \
  "prompt_owner" \
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
pass "one command composes base harness, canonical user profile, and VM readiness matrices"

"$PYTHON_BIN" - "$schema" "$composed_schema" "$vm_schema" "$profile" "$canonical_profile" "$prompt_registry" <<'PY'
import json
import pathlib
import sys

result_schema = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
composed_schema = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
vm_schema = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
profile = json.loads(pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"))
canonical = json.loads(pathlib.Path(sys.argv[5]).read_text(encoding="utf-8"))
prompts = json.loads(pathlib.Path(sys.argv[6]).read_text(encoding="utf-8-sig"))

assert result_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert composed_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert composed_schema["additionalProperties"] is False
for field in ("final_status", "validator_set", "profile", "prompt_owner"):
    assert field in composed_schema["required"]
assert "disposition" in composed_schema["properties"]["checks"]["items"]["required"]
assert result_schema["properties"]["schema_version"]["const"] == "sas-harness-proof/v1"
assert composed_schema["properties"]["proof_level"]["const"] == "synthetic_offline"
for field in (
    "runtime_proof",
    "network_activity_performed",
    "launcher_execution_performed",
    "target_mutation_performed",
    "data_mutation_performed",
):
    assert composed_schema["properties"][field]["const"] is False

assert canonical["profile_parameters"]["required"] == ["os", "user", "onedrive_enabled", "desktop_dev_root"]
assert canonical["policy"]["onedrive_toggle_does_not_choose_desktop_location"] is True
assert canonical["policy"]["desktop_dev_root_is_authoritative"] is True
assert {p["platform"] for p in canonical["profiles"]} >= {"windows", "linux", "macos"}
assert len([item for item in prompts if item.get("id") == "P11"]) == 1

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
for fragment in \
  "Invoke-SasVmDryRunHarnessProof.ps1" \
  "harness/api/canonical-path-registry.json" \
  "harness/validators/validate-canonical-path-contracts.py" \
  "docs/prompts.json" \
  "test_vm_dry_run_readiness_contracts.py" \
  "one-command-harness-proof-result.schema.json" \
  "vm-dry-run-readiness.schema.json" \
  "Test-Json"; do
  grep -Fq "$fragment" "$workflow" || fail "workflow missing proof dependency: $fragment"
done
[[ "$(grep -Fc 'Invoke-SasVmDryRunHarnessProof.ps1 -OutputRoot' "$workflow")" -eq 1 ]] || fail "CI must invoke the canonical composed validator exactly once"
pass "machine-readable result and profile-aware CI composition are explicit"

for surface in "$validator" "$base_validator" "$vm_validator"; do
  for forbidden in Start-VM New-VM Checkpoint-VM Restore-VMSnapshot Start-Process Invoke-Item explorer.exe START-HERE-SysAdminSuite Launch-SysAdminSuite Test-NetConnection Resolve-DnsName Invoke-WebRequest; do
    if grep -Fiq "$forbidden" "$surface"; then
      fail "$surface contains forbidden VM, launcher, or network execution surface: $forbidden"
    fi
  done
done
pass "one-command proof surfaces contain no VM start, launcher, package, or network execution"

[[ -f Tests/survey/test_one_command_harness_proof_contracts.py ]] || fail "one-command executable proof contracts missing"
[[ -f Tests/survey/test_vm_dry_run_readiness_contracts.py ]] || fail "VM readiness executable proof contracts missing"
grep -Fq "test_one_command_harness_proof_contracts.py" tests/survey/run_offline_survey_tests.sh || fail "offline runner missing base proof contracts"
pass "base offline runner and dedicated Windows proof CI are both present"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$validator"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$validator"
else
  echo "[SKIP] PowerShell runtime unavailable; static contracts completed."
fi

echo "SysAdmin one-command profile-aware harness contracts passed."
