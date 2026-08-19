#!/usr/bin/env python3
"""Validate copy-safe field command capsules and durable operator-evidence contracts."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "harness" / "api" / "copy-safe-operator-command-policy.json"
DOC = ROOT / "docs" / "COPY_SAFE_OPERATOR_COMMANDS.md"
FIELD_SKILL = ROOT / ".claude" / "skills" / "field-workflow" / "SKILL.md"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_policy() -> dict:
    if not POLICY.is_file():
        fail(f"missing copy-safe policy: {POLICY}")
    data = json.loads(POLICY.read_text(encoding="utf-8"))
    if data.get("schema_version") != "sas-copy-safe-operator-command-policy/v1":
        fail("unexpected copy-safe operator command policy schema")
    return data


def require_capsule_path(capsule: dict, key: str) -> Path:
    value = capsule.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"registered capsule {capsule.get('id', '<unknown>')} is missing required path key: {key}")
    return ROOT / value


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
        "repair-evidence-without-reexecution",
        "canonical-mainline-after-merge",
        "stale-ref-mismatch-reconcile-current-floor",
        "repair-launcher-requires-repairable-artifact",
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
            key: require_capsule_path(capsule, key)
            for key in (
                "launcher",
                "engine",
                "diagnostic_engine",
                "evidence_repair_launcher",
                "evidence_repair_engine",
                "logs_launcher",
                "documentation",
            )
        }
        for label, path in paths.items():
            if not path.is_file():
                fail(f"registered capsule {label} does not exist: {path}")

        if paths["launcher"].suffix.lower() != ".cmd":
            fail(f"field capsule launcher must be CMD: {paths['launcher']}")
        if paths["logs_launcher"].suffix.lower() != ".cmd":
            fail(f"field capsule log launcher must be CMD: {paths['logs_launcher']}")
        if paths["evidence_repair_launcher"].suffix.lower() != ".cmd":
            fail(f"evidence repair launcher must be CMD: {paths['evidence_repair_launcher']}")
        if capsule.get("direct_ip_mapping") is not False:
            fail(f"printer capsule must explicitly forbid direct-IP mapping: {capsule['id']}")
        if capsule.get("default_test_page") is not False:
            fail(f"printer capsule must default to no test page: {capsule['id']}")
        if capsule.get("mutation") != "none":
            fail(f"default printer capsule must be non-mutating: {capsule['id']}")
        if not capsule.get("latest_result") or not capsule.get("latest_summary"):
            fail(f"capsule must publish stable latest evidence aliases: {capsule['id']}")

        source = capsule.get("source_resolution")
        if not isinstance(source, dict):
            fail(f"capsule must declare source_resolution: {capsule['id']}")
        if source.get("canonical_ref") != "main":
            fail(f"merged field capsule canonical ref must be main: {capsule['id']}")
        if source.get("default_branch_wins_after_merge") is not True:
            fail(f"default branch must win after merge: {capsule['id']}")
        if source.get("historical_pr_ref_allowed_for_operator_retry") is not False:
            fail(f"historical PR refs must not be operator retry sources: {capsule['id']}")
        if source.get("pinned_historical_sha_allowed_after_merge") is not False:
            fail(f"pinned historical SHAs must not survive merge as operator next-actions: {capsule['id']}")
        if source.get("ref_mismatch_action") != "RECONCILE_CURRENT_MAINLINE":
            fail(f"stale ref mismatch must reconcile current mainline: {capsule['id']}")

        repair_eligibility = capsule.get("evidence_repair_eligibility")
        if not isinstance(repair_eligibility, dict):
            fail(f"capsule must declare evidence_repair_eligibility: {capsule['id']}")
        if repair_eligibility.get("scope") != "PRESERVED_ARTIFACT_RECLASSIFICATION_ONLY":
            fail(f"evidence repair scope widened beyond artifact reclassification: {capsule['id']}")
        if repair_eligibility.get("requires_marker") != "physical_output_observed=true":
            fail(f"evidence repair must require preserved physical proof marker: {capsule['id']}")
        if repair_eligibility.get("required_after_reported_real_document_print") is not False:
            fail(f"real document print success must not force evidence repair: {capsule['id']}")
        for key in ("network_activity", "target_contact", "target_mutation"):
            if repair_eligibility.get(key) != "NONE":
                fail(f"evidence repair eligibility must remain local-only ({key}): {capsule['id']}")

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

        repair_text = paths["evidence_repair_engine"].read_text(encoding="utf-8-sig")
        for marker in (
            "sas-northwell-printer-evidence-reclassification/v1",
            "DURABLE_PHYSICAL_PRINT_EVIDENCE_PASS",
            "source_preserved_unchanged = $true",
            "test_page_requested_by_repair = $false",
            "network_activity = 'NONE'",
            "target_contact = 'NONE'",
            "target_mutation = 'NONE'",
            "latest.json",
            "latest.txt",
        ):
            if marker not in repair_text:
                fail(f"evidence repair engine lost required marker: {marker}")
        for forbidden in ("Resolve-DnsName", "Get-Printer", "Test-NetConnection", "PrintTestPage", "Add-Printer"):
            if forbidden in repair_text:
                fail(f"evidence repair engine must stay local-only; found forbidden token: {forbidden}")

        repair_launcher_text = paths["evidence_repair_launcher"].read_text(encoding="utf-8-sig")
        for marker in (
            "NO PRINT / NO NETWORK",
            "ARTIFACT RECLASSIFICATION ONLY",
            "NOT required after a successful real document print",
            "latest.json",
            "latest.txt",
            "This window will NOT close automatically",
        ):
            if marker not in repair_launcher_text:
                fail(f"evidence repair launcher lost required marker: {marker}")

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
        for text, label in ((engine_text, "operational engine"), (diagnostic_text, "diagnostic engine"), (repair_text, "repair engine")):
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
        "Repair-NorthwellPrinter-Queue-Evidence.cmd",
        "Open-NorthwellPrinter-Queue-Proof-Logs.cmd",
        "Canonical mainline wins after merge",
        "A SHA mismatch is a supersession/reconciliation signal",
        "not a reason to chase the old commit",
        "artifact reclassification only",
    ]
    for marker in required_doc_markers:
        if marker not in doc_text:
            fail(f"copy-safe documentation lost required marker: {marker}")

    if not FIELD_SKILL.is_file():
        fail(f"missing field workflow skill: {FIELD_SKILL}")
    field_skill_text = FIELD_SKILL.read_text(encoding="utf-8")
    for marker in (
        "canonical `main`",
        "historical PR branch or pinned SHA",
        "reconcile current repository truth",
        "artifact reclassification only",
    ):
        if marker not in field_skill_text:
            fail(f"field workflow skill lost supersession guardrail: {marker}")

    print(f"PASS: {len(capsules)} registered copy-safe operator command capsule(s)")
    print("PASS: default printer flow is non-printing and direct-IP mapping remains forbidden")
    print("PASS: misclassified physical evidence can be repaired without re-execution")
    print("PASS: merged capsules resolve from canonical mainline; stale historical refs are blocked")
    print("PASS: real document print success does not force artifact repair")
    print("PASS: caller-shell preservation and stable latest evidence are enforced")


if __name__ == "__main__":
    main()
