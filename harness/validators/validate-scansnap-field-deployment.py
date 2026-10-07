#!/usr/bin/env python3
"""Fail-closed static contract validation for deterministic ScanSnap field deployment."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        raise SystemExit(f"FAIL missing required file: {rel}")
    return path.read_text(encoding="utf-8-sig")


def load(rel: str):
    return json.loads(read(rel))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL {message}")


field_rel = "Config/SoftwareDeploy/ScanSnap/Invoke-ScanSnapFieldDeployment.ps1"
preflight_rel = "Config/SoftwareDeploy/ScanSnap/Preflight-ScanSnap-Field.cmd"
deploy_rel = "Config/SoftwareDeploy/ScanSnap/Deploy-ScanSnap-Field.cmd"
workflow_rel = "Config/SoftwareDeploy/ScanSnap/field-deployment.workflow.json"
adapter_rel = "scripts/SasSoftwareDeploymentAdapter.psm1"
validation_rel = "scripts/SasSoftwareInstallFinalization.psm1"
schema_rel = "schemas/harness/smb-scheduled-task-deployment-result.schema.json"

field = read(field_rel)
preflight = read(preflight_rel)
deploy = read(deploy_rel)
workflow = load(workflow_rel)
adapter = read(adapter_rel)
validation = read(validation_rel)
schema = load(schema_rel)

for fragment in (
    "SasNorthwellNetworkAuthority.psm1",
    "Assert-SasNorthwellNetwork",
    "Test-SasSoftwareDeploymentTransport.ps1",
    "kerberos_smb_task",
    "Resolve-SasSoftwareDeploymentTransport",
    "Invoke-SasSmbScheduledTaskDeployment",
    "DEPLOY SCANSNAP",
    "SCANSNAP_ALIAS_MISMATCH",
    "process-identity.json",
    "latest-run.json",
):
    require(fragment in field, f"field orchestrator missing contract fragment: {fragment}")

for forbidden in (
    "Get-Credential",
    "ConvertFrom-SecureString",
    "Enter-PSSession",
    "New-PSSession",
    "SendKeys",
    "AppActivate",
    "UIAutomation",
):
    require(forbidden not in field, f"field orchestrator exposes forbidden interaction: {forbidden}")

require("Invoke-ScanSnapFieldDeployment.ps1" in preflight and "-PreflightOnly" in preflight,
        "preflight CMD does not delegate exactly to the field orchestrator")
require("Invoke-ScanSnapFieldDeployment.ps1" in deploy and "-PreflightOnly" not in deploy,
        "deploy CMD does not delegate exactly to the live field orchestrator")

require(workflow["schema_version"] == "sas-scansnap-field-workflow/v1", "workflow schema version drift")
require(workflow["owners"]["network_authority"] == "scripts/SasNorthwellNetworkAuthority.psm1",
        "workflow network authority drift")
require(workflow["owners"]["transport_adapter"] == adapter_rel, "workflow adapter owner drift")
require(workflow["network_rules"]["ordinary_wifi_may_coexist_with_domain_authenticated_non_wifi"] is True,
        "VPN/LAN plus ordinary Wi-Fi coexistence contract weakened")
require(workflow["network_rules"]["transport_fallback_after_mutation"] is False,
        "transport fallback after mutation must remain forbidden")
require(workflow["operator_confirmation"]["location"] == "Admin Box only",
        "operator confirmation moved away from Admin Box")
require(workflow["operator_confirmation"]["target_side_confirmation"] is False,
        "target-side confirmation must remain forbidden")
require(workflow["process_identity"]["target_gui_automation"] is False,
        "target GUI automation must remain forbidden")

for fragment in (
    "Get-CimInstance Win32_Process",
    "process_identity_hint_json",
    "baseline_count",
    "post_launch_count",
    "delta_count",
    "cached_metadata",
    "pid_delta_child",
    "Test-SasSelectedProcessStillMatches",
):
    require(fragment in adapter, f"shared adapter lost process-identity contract: {fragment}")

require("'RegistryKeyExists'" in validation, "exact registry-key validation support missing")

execution = schema["properties"]["execution"]
require(execution["additionalProperties"] is False, "deployment execution result must remain closed")
require("process_observation" in execution["required"], "process observation is not required by closed result schema")
require("process_observation" in execution["properties"], "process observation schema missing")

commands = load("harness/api/harness-command-registry.json")["commands"]
command_ids = {item["id"] for item in commands}
require("scansnap-field-preflight" in command_ids, "ScanSnap field preflight command is not registered")
require("scansnap-field-deploy" in command_ids, "ScanSnap field deploy command is not registered")

outcomes = load("harness/api/harness-outcome-registry.json")["contracts"]
outcome_ids = {item["command_id"] for item in outcomes}
require("scansnap-field-preflight" in outcome_ids, "ScanSnap preflight outcome contract missing")
require("scansnap-field-deploy" in outcome_ids, "ScanSnap deploy outcome contract missing")

artifacts = load("harness/api/harness-artifact-registry.json")["artifacts"]
artifact_ids = {item["id"] for item in artifacts}
for artifact_id in (
    "scansnap-field-preflight-result",
    "scansnap-field-deployment-result",
    "scansnap-field-latest-pointer",
    "scansnap-process-identity-cache",
):
    require(artifact_id in artifact_ids, f"ScanSnap artifact not registered: {artifact_id}")

validators = load("harness/api/harness-validator-registry.json")["validators"]
require(any(item["id"] == "scansnap-field-deployment-contracts" for item in validators),
        "ScanSnap field validator is not registered")

manifest = load("harness/api/operational-harness-manifest.json")
component_ids = {item["id"] for item in manifest["components"]}
require("scansnap-field-workflow" in component_ids, "ScanSnap field workflow component missing")
require("scansnap-field-validator" in component_ids, "ScanSnap field validator component missing")
require("python harness/validators/validate-scansnap-field-deployment.py" in manifest["validation_commands"],
        "ScanSnap field validator missing from operational validation commands")

print("PASS scansnap-field-deployment-contracts")
