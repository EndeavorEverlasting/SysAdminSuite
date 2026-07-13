#!/usr/bin/env python3
"""Static contracts for the SysAdminSuite run context module."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "scripts" / "SasRunContext.psm1"
HARNESS_PLAN = ROOT / "docs" / "HARNESS_COMPLETION_PLAN.md"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8-sig")


def test_run_context_module_exists_and_exports_expected_api():
    text = read(MODULE)
    required_functions = [
        "New-SasRunId",
        "Test-SasWorkflowId",
        "Resolve-SasOutputRoot",
        "Assert-SasLocalOutputRoot",
        "New-SasArtifactRegistry",
        "Register-SasArtifact",
        "Get-SasRunSummaryPath",
        "New-SasRunContext",
    ]

    for function_name in required_functions:
        assert re.search(rf"function\s+{re.escape(function_name)}\b", text), f"missing function: {function_name}"
        assert function_name in text.split("Export-ModuleMember", 1)[-1], f"function is not exported: {function_name}"


def test_run_context_module_preserves_canonical_directory_shape():
    text = read(MODULE)
    required_fragments = [
        "request.json",
        "context.json",
        "plan.json",
        "plan.md",
        "actions",
        "artifacts",
        "evidence",
        "reports",
        "review",
        "summary.json",
        "operator_handoff.txt",
        "artifact_registry.json",
        "survey/output/runs",
    ]
    for fragment in required_fragments:
        assert fragment in text, f"missing canonical run fragment: {fragment}"


def test_run_context_root_includes_workflow_id_and_run_id():
    text = read(MODULE)
    assert "$workflowRoot = Join-Path $resolvedOutputRoot $WorkflowId" in text
    assert "$runRoot = Join-Path $workflowRoot $RunId" in text
    assert "$runRoot = Join-Path $resolvedOutputRoot $WorkflowId" not in text
    assert "Run context already exists" in text


def test_workflow_id_is_sanitized_before_generating_run_id_prefix():
    text = read(MODULE)
    assert "function ConvertTo-SasRunIdPrefix" in text
    assert "ConvertTo-SasRunIdPrefix -WorkflowId $WorkflowId" in text
    assert "New-SasRunId -Prefix $WorkflowId.Replace" not in text
    assert "if ($sanitized -notmatch '^[a-zA-Z]')" in text
    assert "if ($sanitized.Length -gt 32)" in text


def test_artifact_registry_entries_preserve_required_metadata():
    text = read(MODULE)
    required_fields = [
        "role",
        "path",
        "tracked",
        "live_data",
        "description",
        "source_artifact",
        "network_activity",
        "created_at",
        "created_by",
    ]
    for field in required_fields:
        assert field in text, f"missing artifact metadata field: {field}"


def test_run_context_defaults_to_no_activity_for_planner_initialization():
    text = read(MODULE)
    assert "No network activity performed." in text
    assert "initialize-run-context" in text
    assert "Register source and output artifacts before rendering reports." in text


def test_run_context_module_does_not_introduce_probe_execution_surfaces():
    text = read(MODULE)
    forbidden = [
        "Test-Connection",
        "Test-NetConnection",
        "Resolve-DnsName",
        "Invoke-WebRequest",
        "Invoke-RestMethod",
        "Start-Process",
        "nmap",
        "naabu",
        "nc.exe",
        "ncat",
        "ping.exe",
        "tracert",
    ]
    for fragment in forbidden:
        assert fragment not in text, f"run context module must not execute probes or external network tooling: {fragment}"


def test_harness_plan_names_the_same_run_context_shape():
    plan = read(HARNESS_PLAN)
    for fragment in [
        "runs/<workflow_id>/",
        "request.json",
        "context.json",
        "plan.json",
        "operator_handoff.txt",
        "survey/output/runs/<workflow_id>/",
    ]:
        assert fragment in plan, f"harness plan no longer names run context fragment: {fragment}"


if __name__ == "__main__":
    test_run_context_module_exists_and_exports_expected_api()
    test_run_context_module_preserves_canonical_directory_shape()
    test_run_context_root_includes_workflow_id_and_run_id()
    test_workflow_id_is_sanitized_before_generating_run_id_prefix()
    test_artifact_registry_entries_preserve_required_metadata()
    test_run_context_defaults_to_no_activity_for_planner_initialization()
    test_run_context_module_does_not_introduce_probe_execution_surfaces()
    test_harness_plan_names_the_same_run_context_shape()
