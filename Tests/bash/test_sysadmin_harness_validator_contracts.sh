#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

validator="scripts/validate-sysadmin-harness.ps1"
schema="schemas/harness/harness-proof-result.schema.json"
workflow=".github/workflows/one-command-harness-proof.yml"
[[ -f "$validator" ]] || fail "validator missing"
[[ -f "$schema" ]] || fail "harness proof result schema missing"
[[ -f "$workflow" ]] || fail "one-command proof workflow missing"

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
  grep -Fq "$fragment" "$validator" || fail "validator missing contract: $fragment"
done
pass "validator declares matrix, JSON, dependency, and proof-boundary contracts"

python - "$schema" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
schema = json.loads(path.read_text(encoding="utf-8"))
assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
assert schema["additionalProperties"] is False
assert schema["properties"]["schema_version"]["const"] == "sas-harness-proof/v1"
assert schema["properties"]["proof_level"]["const"] == "synthetic_offline"
for field in (
    "runtime_proof",
    "network_activity_performed",
    "launcher_execution_performed",
    "target_mutation_performed",
    "data_mutation_performed",
):
    assert schema["properties"][field]["const"] is False
PY
grep -Fq "harness-proof-result.schema.json" "$workflow" || fail "workflow missing result schema gate"
grep -Fq "Test-Json" "$workflow" || fail "workflow does not validate emitted JSON"
pass "machine-readable proof schema is closed and enforced in CI"

for forbidden in Start-Process Invoke-Item explorer.exe START-HERE-SysAdminSuite Launch-SysAdminSuite Test-NetConnection Resolve-DnsName Invoke-WebRequest; do
  if grep -Fiq "$forbidden" "$validator"; then
    fail "validator contains forbidden runtime surface: $forbidden"
  fi
done
pass "validator contains no launcher or network execution surface"

[[ -f Tests/survey/test_one_command_harness_proof_contracts.py ]] || fail "executable proof contracts missing"
grep -Fq "test_one_command_harness_proof_contracts.py" tests/survey/run_offline_survey_tests.sh || fail "offline runner missing proof contracts"
pass "one-command proof is wired into offline validation"

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$validator"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$validator"
else
  echo "[SKIP] PowerShell runtime unavailable; static contracts completed."
fi

echo "SysAdmin harness validator contracts passed."
