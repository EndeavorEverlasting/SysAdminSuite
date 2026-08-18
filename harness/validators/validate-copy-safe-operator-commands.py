#!/usr/bin/env python3
"""Validate copy-safe field command capsules and transcript-separation contracts."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "harness" / "api" / "copy-safe-operator-command-policy.json"
DOC = ROOT / "docs" / "COPY_SAFE_OPERATOR_COMMANDS.md"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_policy() -> dict:
    if not POLICY.is_file():
        fail(f"missing copy-safe policy: {POLICY}")
    data = json.loads(POLICY.read_text(encoding="utf-8"))
    if data.get("schema_version") != "sas-copy-safe-operator-command-policy/v1":
        fail("unexpected copy-safe operator command policy schema")
    return data


def main() -> None:
    data = load_policy()
    rules = {rule.get("id"): rule for rule in data.get("rules", [])}
    required = {
        "no-powershell-prompts",
        "no-continuation-prompts",
        "launcher-first",
        "single-command-copy",
    }
    missing = required.difference(rules)
    if missing:
        fail(f"missing copy-safe rules: {sorted(missing)}")

    prompt_re = re.compile(rules["no-powershell-prompts"]["pattern"], re.IGNORECASE)
    continuation_re = re.compile(rules["no-continuation-prompts"]["pattern"])

    capsules = data.get("registered_capsules", [])
    if not capsules:
        fail("copy-safe policy has no registered capsules")

    for capsule in capsules:
        launcher = ROOT / capsule["launcher"]
        engine = ROOT / capsule["engine"]
        documentation = ROOT / capsule["documentation"]
        for path in (launcher, engine, documentation):
            if not path.is_file():
                fail(f"registered capsule path does not exist: {path}")
        if launcher.suffix.lower() != ".cmd":
            fail(f"field capsule launcher must be CMD: {launcher}")
        if capsule.get("direct_ip_mapping") is not False:
            fail(f"printer capsule must explicitly forbid direct-IP mapping: {capsule['id']}")

        launcher_text = launcher.read_text(encoding="utf-8-sig")
        for line in launcher_text.splitlines():
            if prompt_re.match(line) or continuation_re.match(line):
                fail(f"terminal transcript marker embedded in launcher {launcher}: {line!r}")

    doc_text = DOC.read_text(encoding="utf-8")
    required_doc_markers = [
        "Do not reconstruct a terminal session from chat output.",
        "one physical line",
        "Prove-NorthwellPrinter-Queue.cmd",
        "LIVE_PHYSICAL_PRINT_PROOF_PASS",
    ]
    for marker in required_doc_markers:
        if marker not in doc_text:
            fail(f"copy-safe documentation lost required marker: {marker}")

    engine_text = (ROOT / "scripts" / "Invoke-SasNorthwellPrinterQueueProof.ps1").read_text(encoding="utf-8-sig")
    engine_markers = [
        "sas-northwell-printer-queue-proof/v1",
        "direct_ip_mapping_performed = $false",
        "Get-Printer -ComputerName",
        "Get-NetTCPConnection -RemoteAddress",
        "PrintTestPage",
        "LIVE_PHYSICAL_PRINT_PROOF_PASS",
        "field-runs\\printer-queue-proof",
    ]
    for marker in engine_markers:
        if marker not in engine_text:
            fail(f"printer queue proof engine lost required marker: {marker}")

    forbidden_mapping = [
        r"Add-Printer\s+-PortName",
        r"Add-PrinterPort",
        r"PrintUIEntry[^\r\n]*/if",
    ]
    for pattern in forbidden_mapping:
        if re.search(pattern, engine_text, flags=re.IGNORECASE):
            fail(f"proof engine contains direct-IP/local-port mapping behavior: {pattern}")

    print(f"PASS: {len(capsules)} registered copy-safe operator command capsule(s)")
    print("PASS: transcript prompt markers are forbidden from launcher payloads")
    print("PASS: Northwell printer queue proof remains shared-queue-first and bounded")


if __name__ == "__main__":
    main()
