#!/usr/bin/env python3
"""Dependency-free integrity validator for the operational harness registries."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
COMMANDS = ROOT / "harness/api/harness-command-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
OUTCOMES = ROOT / "harness/api/harness-outcome-registry.json"
DEPLOYMENT_STATES = ROOT / "harness/api/deployment-state-registry.json"
MANIFEST_SCHEMA = ROOT / "schemas/harness/operational-harness-manifest.schema.json"
VALIDATOR_SCHEMA = ROOT / "schemas/harness/harness-validator-registry.schema.json"
COMMAND_SCHEMA = ROOT / "schemas/harness/harness-command-registry.schema.json"
ARTIFACT_SCHEMA = ROOT / "schemas/harness/harness-artifact-registry.schema.json"
OUTCOME_SCHEMA = ROOT / "schemas/harness/harness-outcome-registry.schema.json"
DEPLOYMENT_STATE_SCHEMA = ROOT / "schemas/harness/deployment-state-registry.schema.json"
FRESH_AGENT = ROOT / "harness/workflows/fresh-agent-intake.yaml"
OUTCOME_WORKFLOW = ROOT / "harness/workflows/outcome-driven-execution.yaml"
DEPLOYMENT_WORKFLOW = ROOT / "harness/workflows/cybernet-autologon-deployment-state.yaml"
SKILL = ROOT / "harness/skills/harness-maintenance/SKILL.md"
OUTCOME_SKILL = ROOT / "harness/skills/outcome-driven-execution/SKILL.md"
DEPLOYMENT_SKILL = ROOT / "harness/skills/cybernet-autologon-deployment-state/SKILL.md"
DEPLOYMENT_VALIDATOR = ROOT / "harness/validators/validate-deployment-state-contracts.py"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
REGISTRY_CI = ROOT / ".github/workflows/harness-registry-integrity.yml"
STATUS = ROOT / "docs/HARNESS_STATUS.md"
RENDERER = ROOT / "harness/reports/render-harness-status.py"


def load(path: Path) -> dict:
    assert path.is_file(), f"missing harness registry: {path.relative_to(ROOT)}"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read(path: Path) -> str:
    assert path.is_file(), f"missing harness component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def tracked(relative: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", relative],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def require_unique(items: list[dict], label: str) -> None:
    ids = [str(item.get("id", item.get("command_id", ""))).strip() for item in items]
    assert all(ids), f"{label} contains an empty id"
    assert len(ids) == len(set(ids)), f"{label} contains duplicate ids"


def test_manifest_components() -> None:
    manifest = load(MANIFEST)
    assert manifest["schema_version"] == "sas-operational-harness-manifest/v1"
    require_unique(manifest["components"], "operational harness components")
    kinds = {item["kind"] for item in manifest["components"]}
    assert "deployment_state_registry" in kinds
    for component in manifest["components"]:
        path = str(component["path"])
        assert (ROOT / path).is_file(), f"manifest component missing: {path}"
        if component.get("tracked", False):
            assert tracked(path), f"manifest component is not tracked: {path}"
        assert str(component.get("validation", "")).strip(), f"component missing validation: {component['id']}"


def test_registry_schema_authorities() -> None:
    expected = {
        MANIFEST_SCHEMA: "sas-operational-harness-manifest/v1",
        COMMAND_SCHEMA: "sas-harness-command-registry/v1",
        VALIDATOR_SCHEMA: "sas-harness-validator-registry/v1",
        ARTIFACT_SCHEMA: "sas-harness-artifact-registry/v1",
        OUTCOME_SCHEMA: "sas-harness-outcome-registry/v1",
        DEPLOYMENT_STATE_SCHEMA: "sas-deployment-state-registry/v1",
    }
    for path, version in expected.items():
        schema = load(path)
        assert schema["$schema"].endswith("draft/2020-12/schema"), f"schema draft mismatch: {path.name}"
        assert schema["properties"]["schema_version"]["const"] == version, f"schema version mismatch: {path.name}"
        relative = path.relative_to(ROOT).as_posix()
        assert tracked(relative), f"registry schema is not tracked: {relative}"


def test_validator_registry() -> None:
    registry = load(VALIDATORS)
    assert registry["schema_version"] == "sas-harness-validator-registry/v1"
    validators = registry["validators"]
    require_unique(validators, "validator registry")
    required = {
        "harness-registry-integrity", "harness-outcome-contracts", "deployment-state-contracts",
        "operational-harness-completeness", "local-harness-contracts", "repository-text-policy-staged",
        "repository-text-policy-commit", "patch-whitespace", "offline-survey-floor", "pester-full",
        "managed-tests-release", "dashboard-publish",
    }
    assert required <= {item["id"] for item in validators}
    for item in validators:
        assert str(item.get("command", "")).strip(), f"validator command missing: {item['id']}"
        assert str(item.get("proof", "")).strip(), f"validator proof missing: {item['id']}"
        assert isinstance(item.get("scope"), list) and item["scope"], f"validator scope missing: {item['id']}"
        assert isinstance(item.get("blocking"), bool), f"validator blocking flag invalid: {item['id']}"


def test_command_registry() -> None:
    registry = load(COMMANDS)
    assert registry["schema_version"] == "sas-harness-command-registry/v1"
    commands = registry["commands"]
    require_unique(commands, "command registry")
    required = {
        "harness-validate", "harness-outcome-validate", "deployment-state-validate", "harness-completeness",
        "offline-floor", "powershell-tests", "managed-tests", "dashboard-build", "dashboard-launch",
        "cybernet-plan", "cybernet-apply", "autologon-remote", "autologon-runtime-proof",
    }
    assert required <= {item["id"] for item in commands}
    for item in commands:
        assert str(item.get("command", "")).strip(), f"command text missing: {item['id']}"
        source = str(item.get("source_of_truth", "")).strip()
        assert source and (ROOT / source).is_file(), f"command source missing: {item['id']} -> {source}"
        assert item.get("mutation") in {
            "none", "repository_read_only", "repository_build_output_only", "local_runtime", "authorized_target_mutation"
        }, f"command mutation class invalid: {item['id']}"
        if item["mutation"] == "authorized_target_mutation":
            assert item.get("network") is True, f"target mutation must declare network activity: {item['id']}"

    by_id = {item["id"]: item for item in commands}
    assert by_id["cybernet-plan"]["command"] == "Run-CybernetClientConfiguration.cmd Plan HOST"
    assert by_id["cybernet-apply"]["command"] == "Run-CybernetClientConfiguration.cmd Apply HOST"
    assert by_id["cybernet-plan"]["source_of_truth"] == "Run-CybernetClientConfiguration.cmd"
    assert by_id["cybernet-apply"]["source_of_truth"] == "Run-CybernetClientConfiguration.cmd"
    assert "sas cybernet" not in by_id["cybernet-plan"]["command"].lower()
    assert "sas cybernet" not in by_id["cybernet-apply"]["command"].lower()


def test_outcome_registry_wiring() -> None:
    outcomes = load(OUTCOMES)
    commands = load(COMMANDS)["commands"]
    artifacts = load(ARTIFACTS)["artifacts"]
    assert outcomes["schema_version"] == "sas-harness-outcome-registry/v1"
    assert outcomes["policy"]["validation_is_admission_not_completion"] is True
    assert outcomes["policy"]["dry_run_must_emit_artifact"] is True
    assert "runtime_proven" in outcomes["policy"]["allowed_terminal_outcomes"]
    require_unique(outcomes["contracts"], "outcome registry")
    command_ids = {item["id"] for item in commands}
    artifact_ids = {item["id"] for item in artifacts}
    contracts = {item["command_id"]: item for item in outcomes["contracts"]}
    assert set(contracts) == command_ids, "outcome registry must cover every canonical command"
    for command_id, contract in contracts.items():
        artifact_id = contract.get("success_artifact_id")
        if artifact_id is not None:
            assert artifact_id in artifact_ids, f"outcome references unknown artifact: {command_id} -> {artifact_id}"
        for continuation in contract.get("continuations", []):
            assert continuation["command_id"] in command_ids, f"outcome references unknown continuation: {command_id}"
            assert continuation["same_turn"] is True, f"continuation must stay in the same turn: {command_id}"
    assert contracts["autologon-runtime-proof"]["success_outcome"] == "runtime_proven"
    assert tracked(OUTCOMES.relative_to(ROOT).as_posix())
    assert tracked(OUTCOME_WORKFLOW.relative_to(ROOT).as_posix())
    assert tracked(OUTCOME_SKILL.relative_to(ROOT).as_posix())


def test_deployment_state_wiring() -> None:
    registry = load(DEPLOYMENT_STATES)
    assert registry["schema_version"] == "sas-deployment-state-registry/v1"
    assert registry["policy"]["test_autologon_with_authorized_target_means_apply_pilot"] is True
    assert registry["policy"]["transport_live_cert_is_admission_only"] is True
    assert registry["policy"]["do_not_reinstall_verified_core_apps"] is True
    context_ids = {item["id"] for item in registry["contexts"]}
    assert "cybernet-autologon" in context_ids
    for path in (DEPLOYMENT_STATES, DEPLOYMENT_STATE_SCHEMA, DEPLOYMENT_WORKFLOW, DEPLOYMENT_SKILL, DEPLOYMENT_VALIDATOR):
        assert tracked(path.relative_to(ROOT).as_posix()), f"deployment-state component is not tracked: {path.relative_to(ROOT)}"


def test_guardrail_wiring() -> None:
    pre_commit = read(PRE_COMMIT)
    for marker in (
        "git checkout-index --all --force --prefix=\"$snapshot/\"",
        "GIT_DIR=\"$git_dir\"",
        "GIT_WORK_TREE=\"$snapshot\"",
        "pre-commit: validating the exact staged snapshot",
        "validate-harness-registries.py",
        "validate-outcome-contracts.py",
        "validate-deployment-state-contracts.py",
    ):
        assert marker in pre_commit, f"pre-commit staged-snapshot guard missing: {marker}"

    registry_ci = read(REGISTRY_CI)
    assert "if: github.event_name == 'push'" in registry_ci
    assert "if: github.event_name == 'workflow_dispatch'" in registry_ci
    assert "if: github.event_name != 'pull_request'" not in registry_ci
    assert "Check manual-dispatch whitespace" in registry_ci


def test_fresh_agent_wiring() -> None:
    workflow = read(FRESH_AGENT)
    skill = read(SKILL)
    for marker in (
        "workflow_id: fresh-agent-intake", "read AGENTS.md without modifying it",
        "harness/api/harness-command-registry.json", "harness/api/harness-validator-registry.json",
        "harness/api/harness-artifact-registry.json", "harness/api/harness-outcome-registry.json",
        "harness/api/deployment-state-registry.json", "harness/skills/harness-maintenance/SKILL.md",
        "harness/skills/outcome-driven-execution/SKILL.md", "harness/skills/cybernet-autologon-deployment-state/SKILL.md",
        "python harness/validators/validate-harness-registries.py", "python harness/validators/validate-outcome-contracts.py",
        "python harness/validators/validate-deployment-state-contracts.py", "git diff --check", "tools/New-SasSprintCapsule.ps1",
        "follow registered same-turn continuations instead of handing safe executable work back to the operator",
    ):
        assert marker in workflow, f"fresh-agent workflow missing: {marker}"
    for marker in (
        "## Trigger", "## Required inputs", "## Procedure", "## Expected outputs", "## Proof ceiling",
        "harness/workflows/fresh-agent-intake.yaml", "harness/api/harness-command-registry.json",
        "harness/api/harness-validator-registry.json", "harness/api/harness-outcome-registry.json",
        "harness/api/deployment-state-registry.json",
    ):
        assert marker in skill, f"harness-maintenance skill missing: {marker}"


def test_artifact_and_report_wiring() -> None:
    registry = load(ARTIFACTS)
    require_unique(registry["artifacts"], "artifact registry")
    ids = {item["id"] for item in registry["artifacts"]}
    for required in (
        "harness-registry-validation-result", "harness-outcome-validation-result",
        "deployment-state-validation-result", "deployment-state-registry", "generated-harness-status-report",
        "cybernet-client-configuration-summary", "autologon-s4u-pilot-result", "autologon-technician-runtime-proof",
    ):
        assert required in ids, f"artifact registry missing: {required}"
    cybernet_artifact = next(item for item in registry["artifacts"] if item["id"] == "cybernet-client-configuration-summary")
    assert "Run-CybernetClientConfiguration.cmd Plan HOST" in cybernet_artifact["generator"]
    assert "Run-CybernetClientConfiguration.cmd Apply HOST" in cybernet_artifact["generator"]
    renderer = read(RENDERER)
    assert "sas-harness-status-report/v1" in renderer
    assert "harness-validator-registry.json" in renderer
    assert "harness-command-registry.json" in renderer
    assert "harness-outcome-registry.json" in renderer
    assert "deployment-state-registry.json" in renderer
    assert "Same-turn continuations" in renderer
    assert "AutoLogon / Cybernet desired state" in renderer
    status = read(STATUS)
    assert "Harness registry integrity" in status
    assert "Fresh-agent intake" in status
    assert "Outcome-driven execution" in status
    assert "AutoLogon / Cybernet desired-state execution" in status


def main() -> int:
    test_manifest_components()
    test_registry_schema_authorities()
    test_validator_registry()
    test_command_registry()
    test_outcome_registry_wiring()
    test_deployment_state_wiring()
    test_guardrail_wiring()
    test_fresh_agent_wiring()
    test_artifact_and_report_wiring()
    print("PASS: harness registry integrity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
