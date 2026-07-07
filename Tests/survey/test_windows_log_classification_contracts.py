#!/usr/bin/env python3
"""Static contracts for the Windows log classification system."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "WINDOWS_LOG_CLASSIFICATION_SYSTEM.md"
TAXONOMY = ROOT / "harness" / "taxonomy" / "windows-log-taxonomy.json"
SCHEMA = ROOT / "schemas" / "harness" / "windows-log-taxonomy.schema.json"
API = ROOT / "harness" / "api" / "sas-harness-api.json"
MCP = ROOT / "mcp" / "local" / "servers.json"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_windows_log_doc_names_families_operations_and_mutation_scope():
    text = read(DOC)
    required = [
        "Windows Log Classification System",
        "log family",
        "supported operations",
        "privilege needs",
        "mutation/destruction risk",
        "eventlog_classic",
        "eventlog_security",
        "eventlog_provider_channel",
        "eventlog_forwarded",
        "etw_trace",
        "setup_servicing_log",
        "application_text_log",
        "repository_fixture_log",
        "append_event",
        "set_configuration",
        "register_source",
        "install_manifest",
        "clear_with_backup",
        "clear_without_backup",
        "delete_source_registration",
        "uninstall_manifest",
        "delete_log_file",
        "tamper_history",
        "Mutating operations are in scope",
        "host_log_mutation",
        "backup_required",
        "S2+",
    ]
    for fragment in required:
        assert fragment in text, f"missing Windows log doctrine fragment: {fragment}"


def test_windows_log_taxonomy_has_required_shape_and_no_execution_default():
    taxonomy = load_json(TAXONOMY)

    assert taxonomy["schema_version"] == "sas-windows-log-taxonomy/v1"
    posture = taxonomy["default_posture"]
    assert posture["network_activity"] is False
    assert posture["host_log_mutation_default"] is False
    assert posture["tracked_live_log_outputs_allowed"] is False
    assert posture["planner_execution_allowed"] is False

    family_ids = {item["id"] for item in taxonomy["log_families"]}
    required_families = {
        "eventlog_classic",
        "eventlog_security",
        "eventlog_provider_channel",
        "eventlog_forwarded",
        "etw_trace",
        "setup_servicing_log",
        "application_text_log",
        "repository_fixture_log",
    }
    assert required_families <= family_ids, f"missing log families: {required_families - family_ids}"

    tier_ids = {item["id"] for item in taxonomy["safety_tiers"]}
    required_tiers = {
        "S0_READ_ONLY",
        "S1_EXPORT_LOCAL",
        "S2_APPEND",
        "S3_CONFIG_CHANGE",
        "S4_DESTRUCTIVE_BACKED_UP",
        "S4_DESTRUCTIVE_CONFIG",
        "S5_DESTRUCTIVE_UNBACKED",
        "S5_DISALLOWED",
    }
    assert required_tiers <= tier_ids, f"missing safety tiers: {required_tiers - tier_ids}"

    for tier in taxonomy["safety_tiers"]:
        assert tier["default_allow_execute_from_harness"] is False, tier["id"]


def test_operation_classes_cover_add_delete_clear_and_mutation():
    taxonomy = load_json(TAXONOMY)
    operations = {item["id"]: item for item in taxonomy["operation_classes"]}

    required_operations = {
        "inventory",
        "read_query",
        "export_copy",
        "archive_copy",
        "append_event",
        "register_source",
        "install_manifest",
        "set_configuration",
        "enable_high_volume_channel",
        "clear_with_backup",
        "clear_without_backup",
        "delete_source_registration",
        "uninstall_manifest",
        "delete_log_file",
        "tamper_history",
    }
    assert required_operations <= set(operations), f"missing operations: {required_operations - set(operations)}"

    for op_id in [
        "append_event",
        "register_source",
        "install_manifest",
        "set_configuration",
        "enable_high_volume_channel",
        "clear_with_backup",
        "clear_without_backup",
        "delete_source_registration",
        "uninstall_manifest",
        "delete_log_file",
        "tamper_history",
    ]:
        assert operations[op_id]["host_log_mutation"] is True, op_id

    for op_id in [
        "clear_with_backup",
        "clear_without_backup",
        "delete_source_registration",
        "uninstall_manifest",
        "delete_log_file",
    ]:
        assert operations[op_id]["backup_required"] is True, op_id

    assert operations["clear_with_backup"]["safety_tier"] == "S4_DESTRUCTIVE_BACKED_UP"
    assert operations["clear_without_backup"]["safety_tier"] == "S5_DESTRUCTIVE_UNBACKED"
    assert operations["tamper_history"]["safety_tier"] == "S5_DISALLOWED"
    assert operations["clear_without_backup"]["default_bucket"] == "deny_or_break_glass"
    assert operations["tamper_history"]["default_bucket"] == "deny_or_break_glass"


def test_classifier_output_contract_is_explicit_about_mutation_and_artifacts():
    taxonomy = load_json(TAXONOMY)
    required_fields = set(taxonomy["classifier_output_required_fields"])
    for field in [
        "target",
        "family",
        "operation_class",
        "safety_tier",
        "mutation_effect",
        "network_activity",
        "host_log_mutation",
        "requires_admin",
        "contains_sensitive_data",
        "required_gate",
        "backup_required",
        "tracked_output_allowed",
        "recommended_reader",
        "recommended_command_surface",
        "notes",
    ]:
        assert field in required_fields, f"missing classifier result field: {field}"

    for artifact in [
        "windows_log_inventory_plan.json",
        "windows_log_operation_plan.json",
        "windows_log_command_plan.ps1",
        "windows_log_classification_report.md",
    ]:
        assert artifact in taxonomy["command_render_outputs"], artifact


def test_schema_references_same_contract_names_as_taxonomy():
    schema = load_json(SCHEMA)
    assert schema["title"] == "SysAdminSuite Windows Log Taxonomy"
    assert schema["properties"]["schema_version"]["const"] == "sas-windows-log-taxonomy/v1"
    for key in [
        "default_posture",
        "safety_tiers",
        "log_families",
        "operation_classes",
        "review_buckets",
        "classifier_output_required_fields",
        "command_render_outputs",
    ]:
        assert key in schema["required"], key


def test_harness_api_and_mcp_expose_windows_log_classifier_without_execution():
    api = load_json(API)
    operations = {op["id"]: op for op in api["operations"]}

    required_api_ids = {
        "windows_log.classify",
        "windows_log.plan_operation",
        "windows_log.render_powershell",
    }
    assert required_api_ids <= set(operations), f"missing Windows log APIs: {required_api_ids - set(operations)}"

    for op_id in required_api_ids:
        op = operations[op_id]
        assert op["network_activity"] is False, op_id
        assert op["target_mutation"] is False, op_id
        assert op["mode"] in {"plan_only", "local_transform"}, op_id
        assert op["inputs"], op_id
        assert op["outputs"], op_id
        assert op["guardrails"], op_id

    assert "Classify_only" in operations["windows_log.classify"]["guardrails"]
    assert "Operator_execution_required_for_host_actions" in operations["windows_log.plan_operation"]["guardrails"]
    assert "Sensitive_operations_require_gate" in operations["windows_log.render_powershell"]["guardrails"]

    mcp = load_json(MCP)
    servers = {server["id"]: server for server in mcp["servers"]}
    assert "sas-windows-log-classifier" in servers
    server = servers["sas-windows-log-classifier"]
    assert server["network_activity"] is False
    assert server["target_mutation"] is False
    assert required_api_ids <= set(server["allowed_apis"])
    assert "Does_not_execute_host_log_mutation" in server["guardrails"]


if __name__ == "__main__":
    test_windows_log_doc_names_families_operations_and_mutation_scope()
    test_windows_log_taxonomy_has_required_shape_and_no_execution_default()
    test_operation_classes_cover_add_delete_clear_and_mutation()
    test_classifier_output_contract_is_explicit_about_mutation_and_artifacts()
    test_schema_references_same_contract_names_as_taxonomy()
    test_harness_api_and_mcp_expose_windows_log_classifier_without_execution()
