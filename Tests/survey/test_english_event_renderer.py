#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from harness.reporting.english import render_event_message, render_events


def synthetic_event() -> dict:
    return {
        "timestamp": "2026-07-11T00:00:00Z",
        "level": "info",
        "event_type": "profile_selected",
        "workflow_id": "synthetic-low-noise",
        "run_id": "synthetic-run",
        "message_template": "Selected profile {profile_id} for {target_count} approved targets",
        "variables": {"profile_id": "network_preflight", "target_count": 2},
        "artifact_refs": ["synthetic-summary.json"],
        "network_activity_performed": False,
        "target_mutation_performed": False,
    }


def test_importable_renderer_produces_linked_english() -> None:
    enriched, lines = render_events([synthetic_event()])
    assert enriched[0]["english_message"] == "Selected profile network_preflight for 2 approved targets."
    assert "No network activity occurred." in lines[0]
    assert "No target mutation occurred." in lines[0]
    assert "synthetic-summary.json" in lines[0]


def test_renderer_fails_on_missing_or_unsafe_placeholders() -> None:
    missing = synthetic_event()
    missing["variables"] = {}
    try:
        render_event_message(missing)
        raise AssertionError("missing placeholder should fail")
    except ValueError as exc:
        assert "variable is missing" in str(exc)

    unsafe = synthetic_event()
    unsafe["message_template"] = "Unsafe {profile.id}"
    try:
        render_event_message(unsafe)
        raise AssertionError("attribute traversal should fail")
    except ValueError as exc:
        assert "unsafe message_template field" in str(exc)


def test_cli_matches_importable_renderer() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        source = temp / "events.jsonl"
        jsonl_output = temp / "events.english.jsonl"
        english_output = temp / "events.english.txt"
        registry = temp / "artifact_registry.json"
        source.write_text(json.dumps(synthetic_event()) + "\n", encoding="utf-8")
        registry.write_text(json.dumps({"workflow_id": "synthetic-low-noise", "run_id": "synthetic-run", "artifacts": []}), encoding="utf-8")
        completed = subprocess.run([
            sys.executable, str(ROOT / "scripts" / "render-sas-structured-log.py"),
            "--input", str(source), "--jsonl-output", str(jsonl_output),
            "--english-output", str(english_output),
            "--artifact-registry", str(registry),
        ], check=True, capture_output=True, text=True)
        assert completed.stdout == ""
        assert "Rendered syntactic English" in completed.stderr
        rendered = json.loads(jsonl_output.read_text(encoding="utf-8"))
        assert rendered["english_message"] == render_event_message(synthetic_event())
        assert "Selected profile network_preflight" in english_output.read_text(encoding="utf-8")
        roles = {item["role"] for item in json.loads(registry.read_text(encoding="utf-8"))["artifacts"]}
        assert roles == {"events_english_jsonl", "events_english_log"}


def test_renderer_source_has_no_execution_surface() -> None:
    text = (ROOT / "harness" / "reporting" / "english.py").read_text(encoding="utf-8")
    for forbidden in ("subprocess", "socket", "Test-NetConnection", "Resolve-DnsName", "Invoke-Command", "requests."):
        assert forbidden not in text


if __name__ == "__main__":
    test_importable_renderer_produces_linked_english()
    test_renderer_fails_on_missing_or_unsafe_placeholders()
    test_cli_matches_importable_renderer()
    test_renderer_source_has_no_execution_surface()
    print("English event renderer contracts passed")
