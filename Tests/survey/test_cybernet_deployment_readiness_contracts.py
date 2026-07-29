#!/usr/bin/env python3
"""Contracts for technician-ready Cybernet deployment and staged low-noise probes."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
READINESS = ROOT / "scripts/Invoke-SasCybernetDeploymentReadiness.ps1"
TARGET_RESOLVER = ROOT / "scripts/SasTargetNameResolution.psm1"
PROBE_CMD = ROOT / "Probe-CybernetSoftware.cmd"
DEPLOYMENT = ROOT / "scripts/Invoke-SasCybernetSoftwareDeployment.ps1"
DEPLOY_CMD = ROOT / "Deploy-CybernetSoftware.cmd"
LAUNCHER = ROOT / "scripts/SasPortableLauncher.ps1"
RECOVERY = ROOT / "scripts/Show-SasOperatorEvidence.ps1"
START_HERE = ROOT / "START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md"
LOW_NOISE_DOC = ROOT / "docs/SOFTWARE_DEPLOYMENT_LOW_NOISE.md"
TUTORIAL = ROOT / "docs/tutorials/CYBERNET_SOFTWARE_DEPLOYMENT.md"
AUTOLOGON_SKILL = ROOT / ".claude/skills/autologon-deployment/SKILL.md"
SURVEY_SKILL = ROOT / ".claude/skills/survey-low-noise/SKILL.md"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
SCHEMA = ROOT / "schemas/harness/cybernet-deployment-readiness-result.schema.json"
RUNNER = ROOT / "tests/survey/run_offline_survey_tests.sh"
PESTER = ROOT / "Tests/Pester/CybernetDeploymentReadiness.Tests.ps1"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read(path: Path) -> str:
    require(path.is_file(), f"missing readiness surface: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def by_id(items: list[dict]) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for item in items:
        identifier = item.get("id", item.get("command_id"))
        require(isinstance(identifier, str) and bool(identifier), "registry item is missing id/command_id")
        result[identifier] = item
    return result


def test_readiness_schema_is_fail_closed_and_identifier_safe() -> None:
    schema = load(SCHEMA)
    require(schema["$schema"].endswith("draft/2020-12/schema"), "readiness schema draft drifted")
    require(schema["$id"] == "schemas/harness/cybernet-deployment-readiness-result.schema.json", "readiness schema id drifted")
    require(schema["additionalProperties"] is False, "readiness schema permits unregistered fields")
    properties = schema["properties"]
    require(properties["schema_version"]["const"] == "sas-cybernet-deployment-readiness-result/v1", "readiness schema version drifted")
    require(properties["target_scope"]["properties"]["identifier_emitted"]["const"] is False, "readiness schema permits target identifier emission")
    require(properties["target_mutation_performed"]["const"] is False, "readiness schema permits target mutation")
    require(properties["transport_intent"]["const"] == "kerberos_smb_task", "readiness schema permits broad transport intent")
    require(set(properties["tested_ports"]["items"]["enum"]) == {445, 135}, "readiness schema permits ports outside SMB/Task Scheduler dependencies")
    require("CYBERNET_DEPLOYMENT_READINESS_READY" in properties["status"]["enum"], "live readiness status missing from schema")
    require("CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY" in properties["status"]["enum"], "fixture readiness status missing from schema")


def test_readiness_surface_is_one_target_read_only_and_artifact_backed() -> None:
    readiness = read(READINESS)
    probe = read(PROBE_CMD)
    for marker in (
        "Invoke-SasCybernetDeploymentReadiness",
        "Confirm-SasNorthwellNetwork.ps1",
        "Test-SasSoftwareDeploymentTransport.ps1",
        "SasTargetNameResolution.psm1",
        "Resolve-SasCanonicalTargetFqdn -TargetName $targetInput",
        "TransportIntent = 'kerberos_smb_task'",
        "CYBERNET_DEPLOYMENT_READINESS_READY",
        "CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY",
        "cybernet_deployment_readiness_result.json",
        "target_fingerprint",
        "identifier_emitted = $false",
        "target_mutation_performed = $false",
        "transport_authorization_proven",
        "tested_ports",
        "sas evidence",
    ):
        require(marker in readiness, f"readiness orchestrator missing {marker}")
    require("-AllowNetworkActivity" in probe, "probe launcher does not acknowledge live read-only observation")
    require("No task creation, software installation, target mutation, or restart" in probe, "probe launcher proof ceiling drifted")
    require("never probes WinRM" in probe, "probe launcher no longer states the transport boundary")
    for forbidden in (
        "TransportIntent = 'auto'",
        "Invoke-SasSoftwareDeploymentTransportObservation",
        "nmap",
        "naabu",
        "shutdown.exe",
        "/Create",
        "Invoke-SasCybernetClinicalCoreDeployment.ps1",
        "Invoke-SasAutoLogonS4URestartDeployment.ps1",
    ):
        require(forbidden.lower() not in readiness.lower(), f"readiness surface gained forbidden behavior: {forbidden}")


def test_readiness_uses_canonical_identity_and_keeps_fixtures_offline() -> None:
    readiness = read(READINESS)
    resolver = read(TARGET_RESOLVER)
    require("Resolve-SasCanonicalTargetFqdn" in resolver, "canonical target resolver is missing")
    require("different canonical host identity" in resolver, "canonical resolver no longer rejects identity mismatch")
    require("multiple canonical FQDNs" in resolver, "canonical resolver no longer rejects multiple identities")
    require("Unable to resolve one canonical FQDN" in resolver, "canonical resolver no longer rejects zero identities")
    require("if ($FixtureMode)" in readiness, "fixture/live target resolution split missing")
    fixture_check = readiness.index("Fixture mode requires one syntactically valid FQDN")
    canonical_call = readiness.index("Resolve-SasCanonicalTargetFqdn -TargetName $targetInput")
    require(fixture_check < canonical_call, "fixture validation is not separated from live canonical DNS resolution")
    require("Test-SasCanonicalFqdn -Value $targetInput" in readiness, "fixture mode does not validate its offline FQDN")
    require("$targetResolution.disposition" in readiness and "UNIQUE_CANONICAL_FQDN" in readiness, "live readiness does not require unique canonical identity")


def test_readiness_stages_stop_before_broadening_or_mutation() -> None:
    readiness = read(READINESS)
    transport_call = readiness.index("$transport = & $transportPath")
    ready_check = readiness.index("$transportReady = (")
    success = readiness.index("CYBERNET_DEPLOYMENT_READINESS_READY")
    require(transport_call < ready_check, "readiness classification occurs before the registered transport result")
    require(ready_check < success, "readiness success is not gated by transport classification")
    require("Where-Object { $_ -in @(5985, 5986) }" in readiness, "WinRM broadening guard missing")
    require("The Cybernet readiness probe broadened into WinRM ports" in readiness, "WinRM broadening does not fail closed")
    require("Do not broaden ports or retry" in readiness, "iterative probe failure guidance missing")


def test_full_deployment_owns_readiness_before_any_mutation() -> None:
    deployment = read(DEPLOYMENT)
    readiness_call = deployment.index("$readiness = & $readinessScript")
    core_call = deployment.index("$coreResult = & $coreScript")
    autologon_call = deployment.index("$autoResult = & $autoScript")
    require(readiness_call < core_call < autologon_call, "full deployment order is not readiness -> clinical core -> AutoLogon")
    for marker in (
        "low_noise_transport_preflight_required = $true",
        "readiness_result_path",
        "readiness_status",
        "readiness_transport_classification",
        "readiness_selected_transport",
        "readiness_tested_ports",
        "CYBERNET_DEPLOYMENT_READINESS_READY",
        "kerberos_smb_task_ready",
        "kerberos_smb_task",
        "CYBERNET_SOFTWARE_DEPLOYMENT_COMPLETED_RESTARTED",
        "Run sas evidence before any retry",
    ):
        require(marker in deployment, f"full deployment missing readiness contract marker: {marker}")
    require("Where-Object { $_ -in @(5985,5986) }" in deployment, "full deployment does not reject broadened WinRM observations")
    require("Live deployment was not started" in deployment, "failed readiness does not stop before mutation")
    deploy_cmd = read(DEPLOY_CMD)
    require("bounded low-noise Kerberos SMB plus Task Scheduler readiness" in deploy_cmd, "technician deployment help omits integrated readiness")
    require("sas cybernet Probe" in deploy_cmd, "deployment help omits optional readiness diagnosis")
    require("does not require a separate fixture, live-cert, runtime-proof" in deploy_cmd, "deployment help reintroduced a prerequisite loop")


def test_portable_operator_routes_probe_alias_and_deploy_separately() -> None:
    launcher = read(LAUNCHER)
    for marker in (
        "Probe-CybernetSoftware.cmd",
        "sas cybernet Probe HOST",
        "sas network HOST",
        "sas cybernet Deploy HOST",
        "readiness included",
        "The standalone Probe is optional diagnosis; it is NOT a prerequisite loop before Deploy",
        "'network'",
        "if ($mode -eq 'probe')",
        "if ($mode -eq 'deploy')",
    ):
        require(marker in launcher, f"portable launcher missing {marker}")
    probe_route = launcher.index("if ($mode -eq 'probe')")
    deploy_route = launcher.index("if ($mode -eq 'deploy')")
    hardware_route = launcher.index("Run-CybernetBatchConfiguration.cmd", deploy_route)
    require(probe_route < deploy_route < hardware_route, "portable Cybernet route ordering drifted")


def test_agent_and_technician_guidance_answer_the_actual_request() -> None:
    texts = {
        "start-here": read(START_HERE),
        "low-noise-doc": read(LOW_NOISE_DOC),
        "tutorial": read(TUTORIAL),
        "autologon-skill": read(AUTOLOGON_SKILL),
        "survey-skill": read(SURVEY_SKILL),
    }
    for name, text in texts.items():
        require("sas cybernet Deploy" in text, f"{name} omits canonical deployment")
        require("sas cybernet Probe" in text, f"{name} omits canonical readiness probe")
        lowered = text.lower()
        require("readiness" in lowered, f"{name} omits readiness semantics")
        require("not" in lowered and "deployment" in lowered, f"{name} does not separate readiness from deployment")
    for name in ("start-here", "low-noise-doc", "autologon-skill", "survey-skill"):
        lowered = texts[name].lower()
        require("winrm" in lowered, f"{name} omits WinRM exclusion")
        require("nmap" in lowered and "naabu" in lowered, f"{name} omits broad-scan exclusions")
    require("separate probe is **not required** before deployment" in texts["start-here"], "start-here reintroduced a manual probe prerequisite")
    require("same-transaction low-noise readiness gate" in texts["autologon-skill"], "agent deployment routing does not own readiness")
    require("must not become a repeated prerequisite loop" in texts["survey-skill"], "low-noise skill can trap technicians in probe loops")


def test_harness_registers_probe_artifact_and_same_turn_deployment_continuation() -> None:
    commands = by_id(load(COMMANDS)["commands"])
    artifacts = by_id(load(ARTIFACTS)["artifacts"])
    outcomes = by_id(load(OUTCOMES)["contracts"])

    command = commands["cybernet-deployment-probe"]
    require(command["kind"] == "run", "readiness command uses an unsupported harness kind")
    require(command["command"] == "sas cybernet Probe HOST", "readiness command drifted")
    require(command["source_of_truth"] == "Probe-CybernetSoftware.cmd", "readiness source of truth drifted")
    require(command["mutation"] == "none", "readiness command gained mutation authority")
    require(command["network"] is True, "live readiness no longer declares bounded network activity")

    artifact = artifacts["cybernet-deployment-readiness-result"]
    require(artifact["tracked"] is False, "readiness evidence became tracked")
    require(artifact["contains_live_data"] is True, "readiness live-data classification drifted")
    require(artifact["path"].endswith("artifacts/cybernet_deployment_readiness_result.json"), "readiness artifact path drifted")

    contract = outcomes["cybernet-deployment-probe"]
    require(contract["success_outcome"] == "artifact_created", "readiness incorrectly claims product deployment")
    require(contract["success_artifact_id"] == "cybernet-deployment-readiness-result", "readiness outcome artifact drifted")
    continuation = next(item for item in contract["continuations"] if item["when_goal"] == "software-deploy")
    require(continuation["command_id"] == "cybernet-software-deploy", "readiness does not continue to the product command")
    require(continuation["same_turn"] is True, "authorized deployment continuation is not same-turn")
    require(continuation["requires_authorization"] is True, "readiness incorrectly grants deployment authority")


def test_crash_recovery_and_validation_wiring_cover_readiness() -> None:
    recovery = read(RECOVERY)
    for marker in (
        "cybernet_deployment_readiness_result.json",
        "CYBERNET_DEPLOYMENT_READINESS_READY",
        "CYBERNET_DEPLOYMENT_READINESS_FIXTURE_READY",
        "This is not deployment completion",
        "sas cybernet Deploy HOST",
    ):
        require(marker in recovery, f"evidence recovery missing readiness marker: {marker}")
    require("python3 Tests/survey/test_cybernet_deployment_readiness_contracts.py" in read(RUNNER), "offline floor does not run readiness contracts")
    require(PESTER.is_file(), "Pester fixture proof is not wired by file presence")


def test_no_user_specific_or_live_target_literals() -> None:
    combined = "\n".join(read(path) for path in (
        READINESS, PROBE_CMD, DEPLOYMENT, DEPLOY_CMD, LAUNCHER, RECOVERY,
        START_HERE, LOW_NOISE_DOC, TUTORIAL, AUTOLOGON_SKILL, SURVEY_SKILL,
    ))
    for forbidden in ("pa_rperez26", "Cheex", "rperez26@", "rperez@", "NWMCB"):
        require(forbidden.lower() not in combined.lower(), f"user/live-target literal found: {forbidden}")


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Cybernet deployment readiness contracts ({len(tests)} groups)")
