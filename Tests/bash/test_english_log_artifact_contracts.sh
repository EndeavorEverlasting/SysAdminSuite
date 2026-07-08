#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -f scripts/Render-SasEnglishReport.ps1 ]] || fail "renderer missing"
pass "renderer exists"

grep -q "function Format-SasInlineCode" scripts/Render-SasEnglishReport.ps1 || fail "renderer missing inline-code formatter"
grep -q "\${name}:" scripts/Render-SasEnglishReport.ps1 || fail "renderer does not delimit dynamic result names before colon"
if grep -q '"`\$path`"' scripts/Render-SasEnglishReport.ps1; then
  fail "renderer contains invalid backtick-dollar-path quoting"
fi
pass "renderer PowerShell quoting guard"

for file in \
  schemas/harness/run-event.schema.json \
  schemas/harness/artifact-registry.schema.json \
  schemas/harness/operator-report.schema.json \
  survey/fixtures/english-log/serial_preflight_summary.sample.json \
  survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json \
  survey/fixtures/english-log/network_preflight_summary.sample.json \
  survey/fixtures/english-log/network_preflight_artifact_registry.sample.json; do
  [[ -f "$file" ]] || fail "missing $file"
  python3 -m json.tool "$file" >/dev/null || fail "invalid JSON: $file"
done
pass "schemas and fixtures parse"

python3 - <<'PY'
import json
from pathlib import Path
required = {
    "workflow_id", "run_id", "request_summary", "source_artifacts",
    "loaded_evidence_artifacts", "planner_name", "planner_version",
    "network_activity_performed", "low_noise_policy_version", "started_at",
    "finished_at", "operator_handoff_path", "summary_json_path",
    "report_markdown_path", "next_action"
}
for path in [
    Path("survey/fixtures/english-log/serial_preflight_summary.sample.json"),
    Path("survey/fixtures/english-log/network_preflight_summary.sample.json"),
]:
    data = json.loads(path.read_text())
    missing = sorted(required - set(data))
    if missing:
        raise SystemExit(f"{path} missing {missing}")

for path in [
    Path("survey/fixtures/english-log/serial_preflight_artifact_registry.sample.json"),
    Path("survey/fixtures/english-log/network_preflight_artifact_registry.sample.json"),
]:
    data = json.loads(path.read_text())
    roles = {a.get("role") for a in data.get("artifacts", [])}
    if not ({"source", "summary", "report", "handoff"} <= roles or {"source_serial_list", "summary_json", "report", "handoff"} <= roles):
        raise SystemExit(f"{path} missing source/summary/report/handoff roles: {roles}")
PY
pass "fixture variables and registry roles"

for wf in survey/workflows/serial-to-preflight.yaml survey/workflows/network-preflight.yaml survey/workflows/serial-iteration.yaml; do
  [[ -f "$wf" ]] || fail "missing workflow spec $wf"
  grep -q "network_activity_policy:" "$wf" || fail "workflow missing network policy: $wf"
  grep -q "target_mutation_policy:" "$wf" || fail "workflow missing target mutation policy: $wf"
done
pass "workflow specs exist"

if grep -E "Test-NetConnection|Resolve-DnsName|naabu|nmap|socket|packet|ping|nslookup|curl" scripts/Render-SasEnglishReport.ps1; then
  fail "renderer contains blocked network command text"
fi
pass "renderer contains no blocked network command text"

if grep -RE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}|\b(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)|\b(WMH|WNH|CYB)[A-Za-z0-9-]+" survey/fixtures/english-log; then
  fail "fixture contains live-looking operational identifier"
fi
pass "fixtures avoid live-looking identifiers"

echo "English log artifact contracts passed."
