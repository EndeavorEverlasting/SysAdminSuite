#!/usr/bin/env python3
"""Validate copy-safe field command capsules and durable operator-evidence contracts."""

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
        "no-parent-shell-exit",
        "durable-latest-evidence",
        "no-repeat-physical-proof-by-default",
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
        paths = {
            "launcher": ROOT / capsule["launcher"],
            "engine": ROOT / capsule["engine"],
            "diagnostic_engine": ROOT / capsule["diagnostic_engine"],
            "logs_launcher": ROOT / capsule["logs_launcher"],
            "documentation": ROOT / capsule["documentation"],
        }
        for label, path in paths.items():
            if not path.is_file():
                fail(f"registered capsule {label} does not exist: {path}")

        if paths["launcher"].suffix.lower() != ".cmd":
            fail(f"field capsule launcher must be CMD: {paths['launcher']}")
        if paths["logs_launcher"].suffix.lower() != ".cmd":
            fail(f"field capsule log launcher must be CMD: {paths['logs_launcher']}")
        if capsule.get("direct_ip_mapping") is not False:
            fail(f"printer capsule must explicitly forbid direct-IP mapping: {capsule['id']}")
        if capsule.get("default_test_page") is not False:
            fail(f"printer capsule must default to no test page: {capsule['id']}")
        if capsule.get("mutation") != "none":
            fail(f"default printer capsule must be non-mutating: {capsule['id']}")
        if not capsule.get("latest_result") or not capsule.get("latest_summary"):
            fail(f"capsule must publish stable latest evidence aliases: {capsule['id']}")

        launcher_text = paths["launcher"].read_text(encoding="utf-8-sig")
        for line in launcher_text.splitlines():
            if prompt_re.match(line) or continuation_re.match(line):
                fail(f"terminal transcript marker embedded in launcher {paths['launcher']}: {line!r}")
        if "PrintTestPage" in launcher_text or "Issue one bounded Windows test page" in launcher_text:
            fail("operator launcher regressed to requesting a physical test page")
        for marker in ("latest.txt", "latest.json", "This window will NOT close automatically"):
            if marker not in launcher_text:
                fail(f"operator launcher lost durable/persistent marker: {marker}")

        engine_text = paths["engine"].read_text(encoding="utf-8-sig")
        if "PrintTestPage" in engine_text or "-PrintTestPage" in engine_text:
            fail("default operational engine must never request a test page")
        for marker in (
            "sas-northwell-printer-queue-operational/v1",
            "QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED",
            "QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED",
            "latest.json",
            "latest.txt",
            "Evidence is durable. Closing this terminal does not lose the result.",
        ):
            if marker not in engine_text:
                fail(f"operational engine lost required marker: {marker}")

        diagnostic_text = paths["diagnostic_engine"].read_text(encoding="utf-8-sig")
        for marker in (
            "sas-northwell-printer-queue-proof/v1",
            "direct_ip_mapping_performed = $false",
            "Get-Printer -ComputerName",
            "Get-NetTCPConnection -RemoteAddress",
        ):
            if marker not in diagnostic_text:
                fail(f"bounded diagnostic engine lost required marker: {marker}")

        forbidden_mapping = [
            r"Add-Printer\s+-PortName",
            r"Add-PrinterPort",
            r"PrintUIEntry[^\r\n]*/if",
        ]
        for text, label in ((engine_text, "operational engine"), (diagnostic_text, "diagnostic engine")):
            for pattern in forbidden_mapping:
                if re.search(pattern, text, flags=re.IGNORECASE):
                    fail(f"{label} contains direct-IP/local-port mapping behavior: {pattern}")

    doc_text = DOC.read_text(encoding="utf-8")
    required_doc_markers = [
        "Do not reconstruct a terminal session from chat output.",
        "one physical line",
        "The normal launcher never prints a test page.",
        "latest.txt",
        "latest.json",
        "Do not append `exit $LASTEXITCODE`",
        "Open-NorthwellPrinter-Queue-Proof-Logs.cmd",
    ]
    for marker in required_doc_markers:
        if marker not in doc_text:
            fail(f"copy-safe documentation lost required marker: {marker}")

    print(f"PASS: {len(capsules)} registered copy-safe operator command capsule(s)")
    print("PASS: default printer flow is non-printing and direct-IP mapping remains forbidden")
    print("PASS: caller-shell preservation and stable latest evidence are enforced")


if __name__ == "__main__":
    main()
