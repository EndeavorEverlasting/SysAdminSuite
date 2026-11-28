#!/usr/bin/env python3
"""Read-only, deterministic ownership classifier for fan diagnostics vs shopping.

This script NEVER controls a fan, starts Fan Control, signs in to a store,
modifies a cart, or assumes a private shopping repository can be read.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re

CONTRACT = Path(__file__).with_name("fan-cooling-task-ownership.v1.json")


def classify(description: str, contract: dict | None = None) -> dict:
    if contract is None:
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if not isinstance(description, str):
        raise TypeError("description must be text")
    hits: dict[str, list[str]] = {}
    for domain in contract["domains"]:
        detected = []
        for signal in domain["signals"]:
            pattern = r"(?<![a-z0-9])" + re.escape(signal) + r"(?![a-z0-9])"
            if re.search(pattern, description, re.IGNORECASE):
                detected.append(signal)
        if detected:
            hits[domain["id"]] = detected
    if len(hits) == 2:
        state = contract["outcomes"]["mixed"]
    elif "diagnostics" in hits:
        state = contract["outcomes"]["diagnostics"]
    elif "shopping" in hits:
        state = contract["outcomes"]["shopping"]
    else:
        state = contract["outcomes"]["none"]
    return {
        "route": state,
        "matched_domains": hits,
        "owners": {key: contract["authority"][key] for key in hits},
        "proof": "TEXT_CLASSIFICATION_ONLY",
        "diagnostics_blocks_shopping": False,
        "runtime_observed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("description", help="Task text only, never private host evidence")
    args = parser.parse_args()
    print(json.dumps(classify(args.description), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
