#!/usr/bin/env python3
"""Executable tests for the Windows log classifier implementation."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "harness" / "windows_log_classifier.py"
TAXONOMY_PATH = ROOT / "harness" / "taxonomy" / "windows-log-taxonomy.json"


def load_module():
    spec = importlib.util.spec_from_file_location("windows_log_classifier", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_classifier_reads_taxonomy_and_classifies_safe_read():
    module = load_module()
    taxonomy = module.load_taxonomy(TAXONOMY_PATH)

    result = module.classify_request("System", "show recent errors", taxonomy).to_dict()

    assert result["family"] == "eventlog_classic"
    assert result["operation_class"] == "read_query"
    assert result["safety_tier"] == "S0_READ_ONLY"
    assert result["host_log_mutation"] is False
    assert result["network_activity"] is False
    assert result["recommended_reader"] == "Get-WinEvent"


def test_classifier_marks_append_and_configuration_as_gated_host_mutation():
    module = load_module()
    taxonomy = module.load_taxonomy(TAXONOMY_PATH)

    append_result = module.classify_request("Application", "write event", taxonomy).to_dict()
    config_result = module.classify_request("Application", "configure retention", taxonomy).to_dict()

    assert append_result["operation_class"] == "append_event"
    assert append_result["safety_tier"] == "S2_APPEND"
    assert append_result["host_log_mutation"] is True
    assert append_result["requires_admin"] is True

    assert config_result["operation_class"] == "set_configuration"
    assert config_result["safety_tier"] == "S3_CONFIG_CHANGE"
    assert config_result["host_log_mutation"] is True
    assert config_result["backup_required"] is True


def test_renderer_outputs_read_and_export_plans_without_hidden_execution():
    module = load_module()
    taxonomy = module.load_taxonomy(TAXONOMY_PATH)

    read_plan = module.build_operation_plan(module.classify_request("System", "read recent warnings", taxonomy))
    read_render = module.render_powershell_plan(read_plan)
    assert "Get-WinEvent -FilterHashtable" in read_render
    assert "Host log mutation: false" in read_render

    export_plan = module.build_operation_plan(module.classify_request("System", "export copy", taxonomy))
    export_render = module.render_powershell_plan(export_plan)
    assert "wevtutil epl" in export_render
    assert export_plan["execution"]["harness_executes_host_action"] is False
    assert export_plan["execution"]["operator_execution_required"] is True


def test_renderer_outputs_gated_message_for_host_mutation_plan():
    module = load_module()
    taxonomy = module.load_taxonomy(TAXONOMY_PATH)

    classification = module.classify_request("Application", "write event", taxonomy)
    plan = module.build_operation_plan(classification, "survey/output/windows-log-classifier/demo")
    rendered = module.render_powershell_plan(plan)

    assert plan["execution"]["harness_executes_host_action"] is False
    assert plan["execution"]["operator_execution_required"] is True
    assert plan["execution"]["allowed_to_render_command_plan"] is True
    assert "Review required before host log action" in rendered
    assert "No host action is run by this generated plan" in rendered


def test_classifier_recognizes_provider_etw_text_and_fixture_families():
    module = load_module()
    taxonomy = module.load_taxonomy(TAXONOMY_PATH)

    cases = {
        "Microsoft-Windows-PowerShell/Operational": "eventlog_provider_channel",
        "C:/temp/demo.etl": "etw_trace",
        "C:/Windows/Logs/CBS/CBS.log": "setup_servicing_log",
        "survey/fixtures/english-log/serial_preflight_summary.sample.json": "repository_fixture_log",
        "C:/ProgramData/Vendor/app.log": "application_text_log",
    }
    for target, expected_family in cases.items():
        assert module.classify_request(target, "read", taxonomy).family == expected_family


if __name__ == "__main__":
    test_classifier_reads_taxonomy_and_classifies_safe_read()
    test_classifier_marks_append_and_configuration_as_gated_host_mutation()
    test_renderer_outputs_read_and_export_plans_without_hidden_execution()
    test_renderer_outputs_gated_message_for_host_mutation_plan()
    test_classifier_recognizes_provider_etw_text_and_fixture_families()
