#!/usr/bin/env python3
"""Dependency-free validator for the canonical low-noise policy document."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "Config" / "low-noise-policy.json"
sys.path.insert(0, str(ROOT))
from harness.api.low_noise_policy import load_policy

validate_policy = load_policy

if __name__ == "__main__":
    validate_policy()
    print(f"low-noise policy valid: {POLICY_PATH.relative_to(ROOT)}")
