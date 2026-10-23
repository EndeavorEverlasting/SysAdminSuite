#!/usr/bin/env python3
"""Validate the repository-owned operator recipe catalog."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "Config" / "operator-recipes.json"

REQUIRED_FIELDS = {
    "id",
    "title",
    "platform",
    "category",
    "status",
    "entrypoint",
    "documentation",
    "validation",
    "privilege",
    "proofCeiling",
}
ALLOWED_STATUS = {"active", "archived"}


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    if data.get("schema") != 1:
        fail("operator recipe registry schema must be 1")

    recipes = data.get("recipes")
    if not isinstance(recipes, list) or not recipes:
        fail("operator recipe registry must contain at least one recipe")

    ids: set[str] = set()
    for recipe in recipes:
        missing = REQUIRED_FIELDS - set(recipe)
        if missing:
            fail(f"{recipe.get('id', '<unknown>')} missing fields: {sorted(missing)}")

        recipe_id = recipe["id"]
        if recipe_id in ids:
            fail(f"duplicate operator recipe id: {recipe_id}")
        ids.add(recipe_id)

        if recipe["status"] not in ALLOWED_STATUS:
            fail(f"{recipe_id} has unsupported status {recipe['status']!r}")

        if "command" in recipe or "scriptBody" in recipe or "snippet" in recipe:
            fail(f"{recipe_id} must reference tracked executable files instead of embedding command text")

        for key in ("entrypoint", "documentation"):
            target = ROOT / recipe[key]
            if not target.is_file():
                fail(f"{recipe_id} {key} does not exist: {recipe[key]}")

        engine = recipe.get("engine")
        if engine and not (ROOT / engine).is_file():
            fail(f"{recipe_id} engine does not exist: {engine}")

        validation = recipe["validation"]
        if not isinstance(validation, list) or not validation:
            fail(f"{recipe_id} must name at least one validation surface")
        for validation_path in validation:
            if not (ROOT / validation_path).is_file():
                fail(f"{recipe_id} validation path does not exist: {validation_path}")

    clipboard = next((item for item in recipes if item["id"] == "windows.clipboard.repair"), None)
    if clipboard is None:
        fail("windows.clipboard.repair recipe is missing")
    if clipboard["entrypoint"] != "Repair-Clipboard.cmd":
        fail("windows.clipboard.repair must point to Repair-Clipboard.cmd")
    if clipboard.get("engine") != "scripts/Repair-SasClipboard.ps1":
        fail("windows.clipboard.repair must point to scripts/Repair-SasClipboard.ps1")

    print(f"PASS: operator recipe registry validated ({len(recipes)} recipe(s)).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
