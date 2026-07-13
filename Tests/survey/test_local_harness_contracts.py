#!/usr/bin/env python3
"""Static contracts for the SysAdminSuite local development harness."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "LOCAL_DEVELOPMENT_HARNESS.md"
API = ROOT / "harness" / "api" / "sas-harness-api.json"
MCP = ROOT / "mcp" / "local" / "servers.json"
POLICY_API = ROOT / "harness" / "api" / "low_noise_policy.py"
EVENT_RENDERER = ROOT / "harness" / "reporting" / "english.py"
PRE_COMMIT = ROOT / ".githooks" / "pre-commit"
PRE_PUSH = ROOT / ".githooks" / "pre-push"
INSTALLER = ROOT / "scripts" / "install-local-harness-hooks.sh"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "survey-doctrine.yml"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_harness_documentation_names_the_spine():
    text = read(DOC)
    required = [
        "Install repo hooks",
        "Define stable local APIs",
        "Catalog local MCP servers",
        "Make reports emerge from local artifacts",
        ".githooks/",
        "scripts/install-local-harness-hooks.sh",
        "harness/api/sas-harness-api.json",
        "mcp/local/servers.json",
        "Tests/survey/test_local_harness_contracts.py",
        "harness/api/low_noise_policy.py",
        "harness/reporting/english.py",
        "scripts/render-sas-structured-log.py",
        "must not introduce hidden network activity",
        "target-side artifacts",
        "credential collection",
        "monitoring bypass behavior",
    ]
    for fragment in required:
        assert fragment in text, f"missing harness spine fragment: {fragment}"
    assert POLICY_API.exists()
    assert EVENT_RENDERER.exists()


def test_local_hooks_run_expected_contracts_and_block_generated_evidence():
    pre_commit = read(PRE_COMMIT)
    pre_push = read(PRE_PUSH)
    installer = read(INSTALLER)

    for fragment in [
        "python3 Tests/survey/test_local_harness_contracts.py",
        "python3 Tests/survey/test_probe_socket_access_contracts.py",
        "python3 Tests/survey/test_standard_corporate_tooling_contracts.py",
        "python3 Tests/survey/test_software_install_harness_contracts.py",
        "git diff --cached --name-only",
        "survey/output/*",
        "logs/*",
        "*.pcap",
        "*.pcapng",
        "*.evtx",
        "generated evidence must stay local/gitignored",
    ]:
        assert fragment in pre_commit, f"pre-commit hook missing: {fragment}"

    for fragment in [
        "bash tests/survey/run_offline_survey_tests.sh",
        "python3 Tests/survey/test_local_harness_contracts.py",
    ]:
        assert fragment in pre_push, f"pre-push hook missing: {fragment}"

    assert "git config core.hooksPath .githooks" in installer
    assert "chmod +x .githooks/pre-commit .githooks/pre-push" in installer


def test_harness_api_manifest_is_local_first_and_has_required_operations():
    api = load_json(API)
    assert api["schema_version"] == "sas-harness-api/v1"
    posture = api["posture"]
    assert posture["default_network_activity"] is False
    assert posture["default_target_mutation"] is False
    assert posture["evidence_scope"] == "local_gitignored_artifacts"
    assert "\\\\nt2kwb972sms01\\" in posture["approved_software_sources"]

    allowed_modes = {"plan_only", "local_read", "local_transform", "operator_execute"}
    assert set(api["modes"]) == allowed_modes

    operations = {op["id"]: op for op in api["operations"]}
    required_ids = {
        "target_reduction.plan",
        "standard_probe.render_cmd",
        "standard_probe.render_powershell",
        "report.generate_from_artifacts",
        "mcp.catalog.list",
        "software_install.operator_execute",
    }
    assert required_ids <= set(operations), f"missing harness API operations: {required_ids - set(operations)}"

    for op_id, op in operations.items():
        assert op["mode"] in allowed_modes, f"invalid mode for {op_id}"
        assert op["inputs"], f"operation must name inputs: {op_id}"
        assert op["outputs"], f"operation must name outputs: {op_id}"
        assert op["guardrails"], f"operation must name guardrails: {op_id}"

        if op_id == "software_install.operator_execute":
            assert op["mode"] == "operator_execute"
            assert op["network_activity"] is True
            assert op["target_mutation"] is True
            for guardrail in [
                "Approved_read_only_software_share_only",
                "No_credential_collection",
                "No_monitoring_bypass_or_log_suppression",
                "No_repo_owned_target_logs_reports_manifests_or_transcripts",
                "Run_specific_staging_cleanup_attempted_on_all_failure_paths",
                "Prune_empty_SysAdminSuite_target_directories",
            ]:
                assert guardrail in op["guardrails"]
        else:
            assert op["network_activity"] is False, f"planner/local API must be non-network: {op_id}"
            assert op["target_mutation"] is False, f"planner/local API must not mutate targets: {op_id}"

    target_reduction = operations["target_reduction.plan"]
    for output in [
        "reduced_targets.csv",
        "retry_candidates.csv",
        "review_required.csv",
        "location_subnet_candidates.csv",
        "target_reduction_summary.json",
    ]:
        assert output in target_reduction["outputs"]

    reporter = operations["report.generate_from_artifacts"]
    assert "optional_run_events_jsonl" in reporter["inputs"]
    assert "low_noise_policy_json" in reporter["inputs"]
    assert "events_english.jsonl" in reporter["outputs"]
    assert "events_english.txt" in reporter["outputs"]


def test_local_mcp_catalog_only_exposes_allowed_apis():
    api = load_json(API)
    catalog = load_json(MCP)
    allowed_api_ids = {op["id"] for op in api["operations"]}

    assert catalog["schema_version"] == "sas-local-mcp-catalog/v1"
    posture = catalog["posture"]
    assert posture["network_probe_execution_default"] is False
    assert posture["target_mutation_default"] is False
    assert posture["credential_collection_allowed"] is False
    assert posture["unapproved_background_services_allowed"] is False

    servers = catalog["servers"]
    assert {server["id"] for server in servers} == {
        "sas-target-reduction",
        "sas-standard-tools",
        "sas-evidence-reporter",
    }

    for server in servers:
        assert server["status"] == "planned"
        assert server["command"].startswith("python -m harness.mcp."), server["id"]
        assert server["network_activity"] is False, server["id"]
        assert server["target_mutation"] is False, server["id"]
        assert server["allowed_apis"], server["id"]
        assert set(server["allowed_apis"]) <= allowed_api_ids, server["id"]
        assert "software_install.operator_execute" not in set(server["allowed_apis"]), server["id"]
        assert server["guardrails"], server["id"]

    reporter = next(server for server in servers if server["id"] == "sas-evidence-reporter")
    assert "report.generate_from_artifacts" in reporter["allowed_apis"]
    assert "Renders_syntactic_English_from_structured_events" in reporter["guardrails"]


def test_reporting_rule_and_next_sprint_outputs_are_preserved():
    text = read(DOC)
    required = [
        "input artifact(s) -> classifier/transform -> report output -> summary metadata",
        "what it consumed",
        "what it excluded",
        "what it classified",
        "what remains unresolved",
        "Reached is not identity proof.",
        "Non-reached is not dead.",
        "target_reduction.plan",
        "reduced_targets.csv",
        "retry_candidates.csv",
        "review_required.csv",
        "location_subnet_candidates.csv",
        "target_reduction_summary.json",
    ]
    for fragment in required:
        assert fragment in text, f"missing reporting/sprint contract: {fragment}"


def test_harness_contract_is_wired_into_local_runner_and_ci():
    runner = read(RUNNER)
    workflow = read(WORKFLOW)
    assert "python3 Tests/survey/test_local_harness_contracts.py" in runner
    assert "python3 Tests/survey/test_software_install_harness_contracts.py" in runner
    assert "Tests/survey/test_local_harness_contracts.py" in workflow
    assert "Local harness contracts" in workflow


if __name__ == "__main__":
    test_harness_documentation_names_the_spine()
    test_local_hooks_run_expected_contracts_and_block_generated_evidence()
    test_harness_api_manifest_is_local_first_and_has_required_operations()
    test_local_mcp_catalog_only_exposes_allowed_apis()
    test_reporting_rule_and_next_sprint_outputs_are_preserved()
    test_harness_contract_is_wired_into_local_runner_and_ci()
