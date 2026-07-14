"""Strict local renderer for SysAdminSuite structured run events."""
from __future__ import annotations

import json
import re
from pathlib import Path
from string import Formatter
from typing import Any, Iterable

FIELD_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def render_event_message(event: dict[str, Any]) -> str:
    template = event.get("message_template")
    variables = event.get("variables")
    if not isinstance(template, str) or not isinstance(variables, dict):
        raise ValueError("event requires message_template and object variables")
    for _, field_name, format_spec, conversion in Formatter().parse(template):
        if field_name is None:
            continue
        if not FIELD_NAME.fullmatch(field_name) or format_spec or conversion:
            raise ValueError(f"unsafe message_template field: {field_name}")
        if field_name not in variables:
            raise ValueError(f"message_template variable is missing: {field_name}")
    message = template.format_map(variables).strip()
    if message and message[-1] not in ".!?":
        message += "."
    return message


def render_event_line(event: dict[str, Any]) -> str:
    message = render_event_message(event)
    network = "Network activity occurred." if event.get("network_activity_performed") else "No network activity occurred."
    mutation_value = event.get("target_mutation_performed")
    if mutation_value is True:
        mutation = "Target mutation occurred."
    elif mutation_value is False:
        mutation = "No target mutation occurred."
    else:
        mutation = "Target mutation status was not declared."
    artifacts = event.get("artifact_refs", [])
    artifact_text = f" Evidence references: {', '.join(str(item) for item in artifacts)}." if artifacts else " No evidence references were declared."
    return f"[{event.get('timestamp', 'unknown time')}] {event.get('level', 'unknown level')}: {message} {network} {mutation}{artifact_text}"


def render_events(events: Iterable[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str]]:
    enriched: list[dict[str, Any]] = []
    lines: list[str] = []
    for event in events:
        item = dict(event)
        item["english_message"] = render_event_message(event)
        enriched.append(item)
        lines.append(render_event_line(event))
    return enriched, lines


def render_event_log(input_path: Path, jsonl_output: Path, english_output: Path) -> None:
    events = [json.loads(line) for line in input_path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    enriched, lines = render_events(events)
    jsonl_output.parent.mkdir(parents=True, exist_ok=True)
    english_output.parent.mkdir(parents=True, exist_ok=True)
    jsonl_output.write_text("".join(json.dumps(item, separators=(",", ":")) + "\n" for item in enriched), encoding="utf-8")
    english_output.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def register_rendered_artifacts(registry_path: Path, jsonl_output: Path, english_output: Path) -> None:
    registry = json.loads(registry_path.read_text(encoding="utf-8-sig"))
    artifacts = registry.get("artifacts")
    if not isinstance(artifacts, list):
        raise ValueError("artifact registry requires an artifacts array")
    existing = {str(item.get("path")) for item in artifacts if isinstance(item, dict)}
    for role, path, description in (
        ("events_english_jsonl", jsonl_output, "Structured events enriched with syntactic English."),
        ("events_english_log", english_output, "Agent-readable English derived from structured events."),
    ):
        if str(path) in existing:
            continue
        artifacts.append({
            "role": role,
            "path": str(path),
            "tracked": False,
            "contains_live_data": True,
            "generated": True,
            "description": description,
        })
    registry_path.write_text(json.dumps(registry, indent=2) + "\n", encoding="utf-8")
