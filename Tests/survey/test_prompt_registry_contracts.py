#!/usr/bin/env python3
"""Contracts for the human-facing prompt registry and embedded prompt kit."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "docs" / "prompts.json"
PROMPT_KIT = ROOT / "docs" / "prompt-kit.html"
REQUIRED_FIELDS = {
    "id", "seq", "name", "type", "class", "sprintRole", "progress",
    "useWhen", "inspectFirst", "expectedOutput", "nextStep", "proofGate",
    "color", "copySheet", "category", "copyContent", "keywords",
}


def load_registry() -> list[dict]:
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    assert isinstance(data, list) and data, "prompt registry must be a non-empty array"
    return data


def load_embedded_prompts() -> list[dict]:
    html = PROMPT_KIT.read_text(encoding="utf-8")
    marker = "var PROMPTS="
    start = html.index(marker) + len(marker)
    data, _ = json.JSONDecoder().raw_decode(html[start:])
    assert isinstance(data, list), "embedded PROMPTS payload must be an array"
    return data


def test_registry_shape_and_identity() -> None:
    prompts = load_registry()
    ids = [item["id"] for item in prompts]
    seqs = [item["seq"] for item in prompts]
    assert len(ids) == len(set(ids)), "prompt IDs must be unique"
    assert len(seqs) == len(set(seqs)), "prompt sequences must be unique"
    for item in prompts:
        missing = REQUIRED_FIELDS - set(item)
        assert not missing, f"{item.get('id', '<unknown>')} missing fields: {sorted(missing)}"
        assert item["id"] == f"P{item['seq']}"
        assert item["copySheet"] == f"{item['id']}_COPY_SAFE"
        assert isinstance(item["keywords"], list) and item["keywords"]


def test_p64_instruction_to_skill_extractor_contract() -> None:
    prompts = {item["id"]: item for item in load_registry()}
    prompt = prompts["P64"]
    assert prompt["name"] == "Agent Instruction-to-Skill Extractor"
    assert "end-to-end testing procedures" in prompt["useWhen"]
    content = prompt["copyContent"]
    for marker in (
        "EXTRACT THE END-TO-END TESTING INSTRUCTIONS FROM AGENTS.MD",
        "reuse the existing canonical project-level skill",
        "Keep universal invariants, instruction precedence, compact routing",
        "Require every extracted procedural marker in the project skill",
        "Reject those detailed markers if they return to AGENTS.md",
        "Run the applicable fixture-safe/default E2E gate",
        "Exactly one canonical project-level skill owns the procedure",
        "commit SHA",
        "push/PR state",
        "one exact next command",
    ):
        assert marker in content, f"P64 missing contract marker: {marker}"


def test_prompt_kit_embeds_exact_registry() -> None:
    assert load_embedded_prompts() == load_registry()


def main() -> None:
    tests = [
        test_registry_shape_and_identity,
        test_p64_instruction_to_skill_extractor_contract,
        test_prompt_kit_embeds_exact_registry,
    ]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} prompt registry contracts")


if __name__ == "__main__":
    main()
