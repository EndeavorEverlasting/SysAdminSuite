#!/usr/bin/env python3
"""Dependency-free cross-contract validator for rework-prevention harness state."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "harness/api/rework-prevention-registry.json"
SCHEMA = ROOT / "schemas/harness/rework-prevention-registry.schema.json"
WORKFLOW = ROOT / "harness/workflows/rework-prevention-recovery.yaml"
SKILL = ROOT / "harness/skills/rework-prevention/SKILL.md"
REPORT = ROOT / "docs/HARNESS_REWORK_PREVENTION.md"
RENDERER = ROOT / "harness/reports/render-rework-prevention-report.py"
FRESH = ROOT / "harness/workflows/fresh-agent-intake.yaml"
MAINTENANCE = ROOT / "harness/workflows/operational-harness-maintenance.yaml"
MANIFEST = ROOT / "harness/api/operational-harness-manifest.json"
VALIDATORS = ROOT / "harness/api/harness-validator-registry.json"
ARTIFACTS = ROOT / "harness/api/harness-artifact-registry.json"
PRE_COMMIT = ROOT / ".githooks/pre-commit"
PRE_PUSH = ROOT / ".githooks/pre-push"
REWORK_CI = ROOT / ".github/workflows/rework-prevention-harness.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing rework-prevention harness component: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load(path: Path) -> dict:
    return json.loads(read(path))


def main() -> int:
    registry = load(REGISTRY)
    schema = load(SCHEMA)
    assert schema["$schema"].endswith("draft/2020-12/schema")
    assert schema["properties"]["schema_version"]["const"] == "sas-rework-prevention-registry/v1"
    assert registry["schema_version"] == "sas-rework-prevention-registry/v1"

    policy = registry["policy"]
    for key in (
        "evidence_before_retry",
        "shell_is_metadata_only",
        "network_context_must_be_explicit",
        "source_validation_before_target_mutation",
        "unresolved_previous_run_blocks_retry",
        "cleanup_requires_positive_evidence",
        "narrow_validation_before_broad_suites",
    ):
        assert policy[key] is True, f"rework policy must fail closed: {key}"

    forbidden = set(policy["forbidden_retry_patterns"])
    required_forbidden = {
        "interactive_try_catch_finally_fragments",
        "implicit_or_assumed_network_context",
        "implicit_or_assumed_terminal_state",
        "partial_target_staging_before_complete_source_preflight",
        "retry_without_previous_run_recovery_or_absence_proof",
        "swallowed_nonzero_exit_code",
        "invented_package_filename_to_mask_catalog_drift",
        "unrelated_diagnostic_expansion_while_changed_surface_is_unproven",
    }
    assert required_forbidden <= forbidden

    controls = registry["controls"]
    control_ids = [item["id"] for item in controls]
    assert len(control_ids) == len(set(control_ids)), "duplicate rework-prevention control id"
    required_controls = {
        "persistent-operator-context",
        "explicit-network-routing",
        "terminal-agnostic-entrypoints",
        "complete-source-preflight-before-target",
        "transactional-run-ownership",
        "prior-run-recovery-gate",
        "checkpoint-and-exit-code-integrity",
        "catalog-drift-is-data",
        "focused-validation-ladder",
    }
    assert required_controls <= set(control_ids)
    for item in controls:
        assert item["validation"] == "rework-prevention-contracts"
        for field in ("trigger", "required_behavior", "forbidden_behavior", "proof_artifact"):
            assert item[field].strip(), f"control {item['id']} missing {field}"

    patterns = registry["known_failure_patterns"]
    pattern_ids = [item["id"] for item in patterns]
    assert len(pattern_ids) == len(set(pattern_ids)), "duplicate failure pattern id"
    required_patterns = {
        "stale-installed-launcher",
        "windows-drive-path-assumption",
        "empty-evidence-list-binder-failure",
        "dispatcher-hides-failure",
        "unexpected-shell-runtime-dependency",
        "package-catalog-drift",
        "target-mutation-before-source-readiness",
        "cleanup-escapes-transaction",
        "operator-context-reacclimation",
        "diagnostic-side-quest-expansion",
    }
    assert required_patterns <= set(pattern_ids)
    known_controls = set(control_ids)
    for item in patterns:
        missing = set(item["prevention_controls"]) - known_controls
        assert not missing, f"failure pattern {item['id']} references unknown controls: {sorted(missing)}"

    workflow = read(WORKFLOW)
    for marker in (
        "workflow_id: rework-prevention-recovery",
        "inspect_previous_run",
        "classify_environment",
        "prove_sources_before_mutation",
        "bounded_recovery",
        "focused_validation",
        "exact_next_action",
        "do not ask the operator to re-explain state already present in tracked or local evidence",
    ):
        assert marker in workflow, f"recovery workflow missing: {marker}"

    skill = read(SKILL)
    for marker in (
        "## Trigger",
        "## Required inputs",
        "## Procedure",
        "Evidence before retry",
        "Terminal is metadata",
        "Network is execution state",
        "Source readiness precedes mutation",
        "Recovery is run-scoped",
        "Focused validators before broad suites",
    ):
        assert marker in skill, f"rework skill missing: {marker}"

    report = read(REPORT)
    for marker in (
        "# Harness Rework Prevention",
        "What is enforced",
        "Known failure classes",
        "What remains outside this harness proof",
        "Exact validator",
    ):
        assert marker in report, f"rework report missing: {marker}"

    renderer = read(RENDERER)
    assert "rework-prevention-registry.json" in renderer
    assert "known_failure_patterns" in renderer
    assert "forbidden_retry_patterns" in renderer

    fresh = read(FRESH)
    maintenance = read(MAINTENANCE)
    for text, name in ((fresh, "fresh-agent"), (maintenance, "maintenance")):
        assert "rework-prevention-registry.json" in text, f"{name} workflow does not load rework registry"
        assert "validate-rework-prevention-contracts.py" in text, f"{name} workflow does not validate rework contracts"

    manifest = load(MANIFEST)
    component_ids = {item["id"] for item in manifest["components"]}
    assert {
        "rework-prevention-registry",
        "rework-prevention-schema",
        "rework-prevention-workflow",
        "rework-prevention-skill",
        "rework-prevention-validator",
        "rework-prevention-report",
        "rework-prevention-renderer",
        "rework-prevention-ci",
    } <= component_ids
    assert "python harness/validators/validate-rework-prevention-contracts.py" in manifest["validation_commands"]

    validator_registry = load(VALIDATORS)
    validator = next(item for item in validator_registry["validators"] if item["id"] == "rework-prevention-contracts")
    assert validator["blocking"] is True
    assert validator["command"] == "python harness/validators/validate-rework-prevention-contracts.py"

    artifact_registry = load(ARTIFACTS)
    artifact_ids = {item["id"] for item in artifact_registry["artifacts"]}
    assert {"rework-prevention-registry", "rework-prevention-validation-result", "rework-prevention-report"} <= artifact_ids

    for path in (PRE_COMMIT, PRE_PUSH, REWORK_CI):
        text = read(path)
        assert "validate-rework-prevention-contracts.py" in text, f"validator not wired into {path.relative_to(ROOT)}"

    rework_ci = read(REWORK_CI)
    assert "Validate rework-prevention schema" in rework_ci
    assert "Run harness completeness contracts" in rework_ci
    assert "git diff --check" in rework_ci

    combined = "\n".join(read(path) for path in (REGISTRY, WORKFLOW, SKILL, REPORT))
    for forbidden_literal in ("pa_rperez26", "WPJ075OPR046", "nslijhs.net\\C$", "password", "credential="):
        assert forbidden_literal.lower() not in combined.lower(), f"private/live literal leaked into rework harness: {forbidden_literal}"

    print(f"PASS: rework-prevention harness contracts ({len(controls)} controls, {len(patterns)} failure patterns)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
