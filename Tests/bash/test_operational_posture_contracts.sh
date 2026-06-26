#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'test_operational_posture_contracts: FAIL: %s\n' "$*" >&2
  exit 1
}

POSTURE="Config/operational-posture.json"
BASH_GATE="scripts/sas-legacy-gate.sh"
PS_GATE="scripts/Invoke-SasLegacyGate.ps1"

for file in "$POSTURE" "$BASH_GATE" "$PS_GATE" docs/OPERATIONAL_POSTURE.md docs/DEPLOYMENT_TEARDOWN_DOCTRINE.md; do
  [[ -f "$file" ]] || fail "missing posture file: $file"
done

bash -n "$BASH_GATE"
bash -n bash/apps/sas-install-apps.sh
bash -n bash/apps/sas-stage-fileshare.sh

python3 - "$POSTURE" <<'PY' || exit 1
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

defaults = data.get("defaults", {})
assert defaults.get("legacyToolsEnabled") is False
assert defaults.get("legacyEnableEnv") == "SAS_ALLOW_LEGACY_TOOLS"
assert defaults.get("legacyDisabledClassification") == "LEGACY_TOOLS_DISABLED"
assert int(defaults.get("naabuMaxRate")) == 3000

lanes = {lane["id"]: lane for lane in data.get("lanes", [])}
assert lanes["survey"]["targetMutation"] == "never"
assert lanes["dashboard"]["targetMutation"] == "never"
assert lanes["deployment"]["targetMutation"] == "authorized-only"
assert lanes["deployment"]["legacyGateRequired"] is True

legacy = data.get("legacyTools", [])
assert legacy, "legacyTools must not be empty"
for tool in legacy:
    path = tool["path"]
    assert os.path.exists(path), f"legacy path missing: {path}"
    assert tool["lane"] == "deployment", f"legacy tool outside deployment lane: {path}"
PY

if bash "$BASH_GATE" --tool bash/apps/sas-install-apps.sh 2>"$ROOT/.legacy-gate.err"; then
  rm -f "$ROOT/.legacy-gate.err"
  fail "legacy gate must fail closed by default"
fi
grep -q 'LEGACY_TOOLS_DISABLED' "$ROOT/.legacy-gate.err" || fail "gate output missing disabled classification"
rm -f "$ROOT/.legacy-gate.err"

bash "$BASH_GATE" --tool bash/apps/sas-install-apps.sh --allow-legacy >/dev/null 2>&1 \
  || fail "legacy gate must allow explicit --allow-legacy"

grep -q 'bash scripts/sas-legacy-gate.sh' bash/apps/sas-install-apps.sh \
  || fail "sas-install-apps.sh must call bash legacy gate"
grep -q 'bash scripts/sas-legacy-gate.sh' bash/apps/sas-stage-fileshare.sh \
  || fail "sas-stage-fileshare.sh must call bash legacy gate"
grep -q 'Invoke-SasLegacyGate' mapping/Controllers/Map-Run-Controller.ps1 \
  || fail "Map-Run-Controller.ps1 must call PowerShell legacy gate"
grep -q 'Invoke-SasLegacyGate' EnvSetup/Deploy-Shortcuts.ps1 \
  || fail "Deploy-Shortcuts.ps1 must call PowerShell legacy gate"

grep -q 'Invoke-RemoteTransientCleanup' mapping/Controllers/Map-Run-Controller.ps1 \
  || fail "Map-Run-Controller.ps1 must include transient cleanup"
grep -q '\$adminScript' mapping/Controllers/Map-Run-Controller.ps1 \
  || fail "Map-Run-Controller.ps1 cleanup must account for copied payload script"
grep -q -- '--no-teardown' bash/apps/sas-install-apps.sh \
  || fail "sas-install-apps.sh must expose --no-teardown debug escape"
grep -q 'Worker self-teardown' bash/apps/sas-install-apps.sh \
  || fail "sas-install-apps.sh must document worker self-teardown"
grep -q -- '--teardown-after' bash/apps/sas-stage-fileshare.sh \
  || fail "sas-stage-fileshare.sh must expose transient staging teardown"

if grep -q 'sas-legacy-gate' survey/sas-run-naabu-pipeline.sh survey/sas-run-packet-probe.sh; then
  fail "survey Naabu wrappers must not be legacy-gated"
fi

grep -q 'Config/operational-posture.json' AGENTS.md || fail "AGENTS.md missing posture authority"
grep -q 'docs/OPERATIONAL_POSTURE.md' AGENTS.md || fail "AGENTS.md missing posture doc"
grep -q 'low-waste' docs/OPERATIONAL_POSTURE.md || fail "posture doc missing low-waste language"
grep -q 'LEGACY_TOOLS_DISABLED' docs/OPERATIONAL_POSTURE.md || fail "posture doc missing legacy classification"
grep -q 'not stealth' docs/OPERATIONAL_POSTURE.md || fail "posture doc must reject stealth framing"

grep -q 'dashboard/js/bundle.js' Tests/bash/test_repo_naabu_doctrine_conformance.sh \
  && fail "Naabu conformance must no longer skip dashboard/js/bundle.js"
grep -q "'\*.js'" Tests/bash/test_repo_naabu_doctrine_conformance.sh \
  || fail "Naabu conformance must inspect JavaScript command strings"
grep -q '3001' Tests/bash/test_naabu_pipeline_contracts.sh \
  || fail "Naabu pipeline contract must assert rate cap"

echo "test_operational_posture_contracts: PASS"
