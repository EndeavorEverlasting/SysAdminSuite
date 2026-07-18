#!/usr/bin/env python3
"""Static contracts for the AI provider catalog and agent feedback system."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Config" / "ai-provider-catalog.json"
SCHEMA = ROOT / "schemas" / "harness" / "ai-provider-catalog.schema.json"
FEEDBACK_SCHEMA = ROOT / "schemas" / "harness" / "agent-feedback-event.schema.json"
FEEDBACK_SCRIPT = ROOT / "scripts" / "Invoke-SasAgentFeedback.ps1"
FEEDBACK_SUMMARY_SCRIPT = ROOT / "scripts" / "Show-SasAgentFeedbackSummary.ps1"
VISIBILITY_SCRIPT = ROOT / "scripts" / "Show-SasActiveAgent.ps1"
QUICKSTART = ROOT / "docs" / "TECHNICIAN_WORKSTATION_QUICKSTART.md"
HARNESS_API = ROOT / "harness" / "api" / "sas-harness-api.json"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT).as_posix()}"
    return path.read_text(encoding="utf-8")


def test_catalog_file_exists() -> None:
    assert CATALOG.exists()


def test_catalog_schema_exists() -> None:
    assert SCHEMA.exists()


def test_catalog_is_valid_json() -> None:
    catalog = json.loads(read(CATALOG))
    assert catalog["schema_version"] == "sas-ai-provider-catalog/v1"


def test_catalog_policy_enforces_free_tokens_before_paid() -> None:
    catalog = json.loads(read(CATALOG))
    policy = catalog["catalog_policy"]
    assert policy["free_model_priority"] is True
    assert policy["free_tokens_before_paid"] is True
    assert policy["free_to_paid_fallback"] is True
    assert policy["local_model_preference"] is True
    assert policy["agent_feedback_tracking_enabled"] is True
    assert policy["feedback_gates_orchestrator_routing"] is True


def test_tier_fallback_order_is_complete() -> None:
    catalog = json.loads(read(CATALOG))
    tiers = catalog["tier_fallback_order"]
    assert tiers == ["free_local", "free_cloud_free_tokens", "free_cloud_trial", "paid"]


def test_all_providers_have_required_fields() -> None:
    catalog = json.loads(read(CATALOG))
    for provider in catalog["providers"]:
        assert provider["id"]
        assert provider["display_name"]
        assert provider["tier"] in ("free_local", "free_cloud_free_tokens", "free_cloud_trial", "paid")
        assert isinstance(provider["free_tokens_available"], bool)
        assert provider["runtime"] in ("local", "cloud")
        assert isinstance(provider["authentication_required"], bool)
        assert len(provider["models"]) > 0
        for model in provider["models"]:
            assert model["id"]
            assert model["display_name"]
            assert model["context_window"] > 0


def test_free_tier_providers_have_free_tokens_true() -> None:
    catalog = json.loads(read(CATALOG))
    for provider in catalog["providers"]:
        if provider["tier"] in ("free_local", "free_cloud_free_tokens", "free_cloud_trial"):
            assert provider["free_tokens_available"] is True, f"{provider['id']} should have free_tokens_available=true"


def test_paid_tier_providers_have_free_tokens_false() -> None:
    catalog = json.loads(read(CATALOG))
    for provider in catalog["providers"]:
        if provider["tier"] == "paid":
            assert provider["free_tokens_available"] is False, f"{provider['id']} should have free_tokens_available=false"


def test_provider_fallback_order_matches_providers() -> None:
    catalog = json.loads(read(CATALOG))
    order = catalog["provider_fallback_order"]
    ids = {p["id"] for p in catalog["providers"]}
    for item in order:
        assert item in ids, f"fallback_order references unknown provider: {item}"
    assert len(order) == len(ids), "fallback_order must include every provider exactly once"


def test_feedback_schema_exists() -> None:
    assert FEEDBACK_SCHEMA.exists()


def test_feedback_script_exists() -> None:
    content = read(FEEDBACK_SCRIPT)
    assert "thumbs_down_requires_reason" in content.lower() or "thumbs-down" in content.lower(), \
        "feedback script must require reason for thumbs_down"


def test_visibility_script_exists() -> None:
    content = read(VISIBILITY_SCRIPT)
    assert "GNHF" in content or "gnhf" in content, \
        "visibility script must handle gnhf routing"


def test_quickstart_doc_exists() -> None:
    assert QUICKSTART.exists()


def test_harness_api_registers_feedback_operations() -> None:
    api = json.loads(read(HARNESS_API))
    ops = {op["id"] for op in api["operations"]}
    assert "agent_feedback.vote" in ops, \
        "harness API must register agent_feedback.vote operation"
    assert "agent_feedback.read_summary" in ops, \
        "harness API must register agent_feedback.read_summary operation"


def test_fallback_order_respects_tier_priority() -> None:
    """Free-local providers must appear before free-cloud, before paid in fallback order."""
    catalog = json.loads(read(CATALOG))
    tier_order = catalog["tier_fallback_order"]
    provider_order = catalog["provider_fallback_order"]
    tier_map = {p["id"]: p["tier"] for p in catalog["providers"]}
    prev_tier_rank = -1
    for provider_id in provider_order:
        tier = tier_map[provider_id]
        rank = tier_order.index(tier)
        assert rank >= prev_tier_rank, \
            f"provider {provider_id} (tier={tier}) appears before a higher-priority tier"
        prev_tier_rank = rank


def test_total_ollama_local_models_have_coding_focus() -> None:
    catalog = json.loads(read(CATALOG))
    ollama = next(p for p in catalog["providers"] if p["id"] == "ollama")
    coding_models = [m for m in ollama["models"] if m.get("coding_focus")]
    assert len(coding_models) >= 2, "Ollama should have at least 2 coding-focused models"


