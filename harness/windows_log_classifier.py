#!/usr/bin/env python3
"""Windows log operation classifier for SysAdminSuite.

This module is intentionally inert against the host. It loads the tracked
taxonomy, classifies a requested Windows log target/action, and renders an
operator-visible plan. It never calls Get-WinEvent, wevtutil, PowerShell, or
filesystem mutation APIs against the host.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TAXONOMY = ROOT / "harness" / "taxonomy" / "windows-log-taxonomy.json"


@dataclass(frozen=True)
class Classification:
    target: str
    family: str
    operation_class: str
    safety_tier: str
    review_bucket: str
    mutation_effect: str
    network_activity: bool
    host_log_mutation: bool
    requires_admin: bool
    contains_sensitive_data: bool
    required_gate: str
    backup_required: bool
    tracked_output_allowed: bool
    recommended_reader: str
    recommended_command_surface: str
    notes: list[str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "target": self.target,
            "family": self.family,
            "operation_class": self.operation_class,
            "safety_tier": self.safety_tier,
            "review_bucket": self.review_bucket,
            "mutation_effect": self.mutation_effect,
            "network_activity": self.network_activity,
            "host_log_mutation": self.host_log_mutation,
            "requires_admin": self.requires_admin,
            "contains_sensitive_data": self.contains_sensitive_data,
            "required_gate": self.required_gate,
            "backup_required": self.backup_required,
            "tracked_output_allowed": self.tracked_output_allowed,
            "recommended_reader": self.recommended_reader,
            "recommended_command_surface": self.recommended_command_surface,
            "notes": self.notes,
        }


def load_taxonomy(path: Path = DEFAULT_TAXONOMY) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        taxonomy = json.load(handle)
    if taxonomy.get("schema_version") != "sas-windows-log-taxonomy/v1":
        raise ValueError(f"unsupported taxonomy schema_version in {path}")
    return taxonomy


def _index_by_id(items: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {item["id"]: item for item in items}


def _clean(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def infer_family(target: str, taxonomy: dict[str, Any]) -> str:
    target_text = target.strip()
    lowered = _clean(target_text)
    families = _index_by_id(taxonomy["log_families"])

    classic = {"application", "system", "setup"}
    if lowered in classic:
        return "eventlog_classic"
    if lowered == "security":
        return "eventlog_security"
    if lowered == "forwardedevents":
        return "eventlog_forwarded"
    if lowered.startswith("microsoft-windows-") and "/" in lowered:
        return "eventlog_provider_channel"
    if lowered.endswith(".etl") or " etw " in f" {lowered} " or "wpr trace" in lowered:
        return "etw_trace"
    if any(token in lowered for token in ("cbs.log", "dism.log", "panther", "windowsupdate")):
        return "setup_servicing_log"
    if "fixtures" in lowered or lowered.endswith((".sample.json", ".sample.csv", ".sample.md")):
        return "repository_fixture_log"

    for family_id, family in families.items():
        for example in family.get("examples", []):
            if lowered == _clean(example):
                return family_id

    return "application_text_log"


def infer_operation(requested_operation: str) -> str:
    text = _clean(requested_operation)

    tamper_tokens = ("tamper", "falsify", "rewrite history", "suppress evidence", "hide evidence")
    if any(token in text for token in tamper_tokens):
        return "tamper_history"

    if "clear" in text and ("backup" in text or "/bu" in text or "export first" in text):
        return "clear_with_backup"
    if "clear" in text:
        return "clear_without_backup"

    if any(token in text for token in ("remove-eventlog", "delete source", "remove source", "delete registration", "remove registration")):
        return "delete_source_registration"
    if any(token in text for token in ("uninstall manifest", "wevtutil um", "remove manifest")):
        return "uninstall_manifest"
    if any(token in text for token in ("delete file", "remove-item", "delete evtx", "delete etl", "delete log file")):
        return "delete_log_file"

    if any(token in text for token in ("high volume", "high-volume", "analytic", "debug channel", "verbose channel")):
        return "enable_high_volume_channel"
    if any(token in text for token in ("configure", "set retention", "retention", "max size", "resize", "enable", "disable", "acl", "path", "wevtutil sl")):
        return "set_configuration"
    if any(token in text for token in ("install manifest", "wevtutil im", "register manifest")):
        return "install_manifest"
    if any(token in text for token in ("register source", "new-eventlog", "create source", "create classic log")):
        return "register_source"
    if any(token in text for token in ("append", "write-eventlog", "write event", "eventcreate", "create event")):
        return "append_event"
    if any(token in text for token in ("archive", "wevtutil al")):
        return "archive_copy"
    if any(token in text for token in ("export", "copy out", "save evtx", "wevtutil epl")):
        return "export_copy"
    if any(token in text for token in ("inventory", "list logs", "list providers", "list channels", "enumerate")):
        return "inventory"
    if any(token in text for token in ("read", "query", "show", "search", "filter", "recent", "errors", "warnings")):
        return "read_query"

    return "read_query"


def classify_request(target: str, requested_operation: str, taxonomy: dict[str, Any]) -> Classification:
    family_id = infer_family(target, taxonomy)
    operation_id = infer_operation(requested_operation)

    families = _index_by_id(taxonomy["log_families"])
    operations = _index_by_id(taxonomy["operation_classes"])
    tiers = _index_by_id(taxonomy["safety_tiers"])

    family = families[family_id]
    operation = operations[operation_id]
    tier = tiers[operation["safety_tier"]]

    rank = int(tier["rank"])
    requires_admin = rank >= 2 or family_id == "eventlog_security"
    command_surface = "powershell" if family_id.startswith("eventlog_") or family_id == "etw_trace" else "file_parser"

    notes = [
        "Classifier only; no host log action was executed.",
        "Use provider and event id together when interpreting Windows Event Log records.",
    ]
    if family.get("special_handling"):
        notes.append("Special handling: " + ", ".join(family["special_handling"]))
    if operation["backup_required"]:
        notes.append("Backup or preservation artifact is required before operator execution.")
    if operation["default_bucket"] == "deny_or_break_glass":
        notes.append("Default route is review/denial unless a documented break-glass process applies.")

    return Classification(
        target=target,
        family=family_id,
        operation_class=operation_id,
        safety_tier=operation["safety_tier"],
        review_bucket=operation["default_bucket"],
        mutation_effect=operation["mutation_effect"],
        network_activity=False,
        host_log_mutation=bool(operation["host_log_mutation"]),
        requires_admin=requires_admin,
        contains_sensitive_data=bool(family["contains_sensitive_data"]),
        required_gate=tier["minimum_gate"],
        backup_required=bool(operation["backup_required"]),
        tracked_output_allowed=bool(family["tracked_output_allowed"]),
        recommended_reader=family["default_reader"],
        recommended_command_surface=command_surface,
        notes=notes,
    )


def build_operation_plan(classification: Classification, output_root: str | None = None) -> dict[str, Any]:
    output_root = output_root or "survey/output/windows-log-classifier/<run_id>"
    allowed_to_render = not classification.safety_tier.startswith("S5_")

    return {
        "schema_version": "sas-windows-log-operation-plan/v1",
        "classification": classification.to_dict(),
        "execution": {
            "harness_executes_host_action": False,
            "operator_execution_required": classification.host_log_mutation or classification.safety_tier != "S0_READ_ONLY",
            "allowed_to_render_command_plan": allowed_to_render,
            "required_gate": classification.required_gate,
        },
        "artifacts": {
            "output_root": output_root,
            "classification_json": f"{output_root}/windows_log_classification.json",
            "operation_plan_json": f"{output_root}/windows_log_operation_plan.json",
            "command_plan": f"{output_root}/windows_log_command_plan.ps1",
            "operator_report": f"{output_root}/windows_log_classification_report.md",
        },
        "next_action": _next_action(classification, allowed_to_render),
    }


def _next_action(classification: Classification, allowed_to_render: bool) -> str:
    if not allowed_to_render:
        return "Route to human review; do not render or execute an unpreserved high-risk host-log action."
    if classification.host_log_mutation:
        return "Review the gate, backup requirement, and command plan before explicit operator execution."
    if classification.safety_tier == "S1_EXPORT_LOCAL":
        return "Confirm the export path is local/gitignored before operator execution."
    return "Review the rendered read plan and run it only in the approved operator context."


def _ps_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def render_powershell_plan(plan: dict[str, Any]) -> str:
    classification = plan["classification"]
    target = classification["target"]
    operation = classification["operation_class"]
    tier = classification["safety_tier"]
    output_root = plan["artifacts"]["output_root"]

    header = [
        "# SysAdminSuite Windows log command plan",
        "# Rendered only. This file does not execute unless an operator runs selected commands.",
        f"# Target: {target}",
        f"# Operation: {operation}",
        f"# Safety tier: {tier}",
        f"# Required gate: {classification['required_gate']}",
        f"# Host log mutation: {str(classification['host_log_mutation']).lower()}",
        "",
        "$ErrorActionPreference = 'Stop'",
        f"$LogTarget = {_ps_quote(target)}",
        f"$OutputRoot = {_ps_quote(output_root)}",
        "New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null",
        "",
    ]

    if operation == "inventory":
        body = [
            "Get-WinEvent -ListLog * |",
            "  Select-Object LogName, RecordCount, IsEnabled, LogMode, MaximumSizeInBytes |",
            "  Sort-Object LogName",
        ]
    elif operation == "read_query":
        body = [
            "$StartTime = (Get-Date).AddHours(-24)",
            "Get-WinEvent -FilterHashtable @{ LogName = $LogTarget; StartTime = $StartTime } -MaxEvents 200 |",
            "  Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, Message",
        ]
    elif operation in {"export_copy", "archive_copy"}:
        body = [
            "$ExportPath = Join-Path $OutputRoot (($LogTarget -replace '[^A-Za-z0-9._-]', '_') + '.evtx')",
            "wevtutil epl $LogTarget $ExportPath",
            "Write-Host \"Exported log to $ExportPath\"",
        ]
        if operation == "archive_copy":
            body.extend([
                "$ArchivePath = Join-Path $OutputRoot (($LogTarget -replace '[^A-Za-z0-9._-]', '_') + '.archive.evtx')",
                "wevtutil al $ExportPath /l:en-US",
                "Write-Host \"Archive metadata attached to exported log.\"",
            ])
    elif operation in {"append_event", "register_source", "install_manifest", "set_configuration", "enable_high_volume_channel", "clear_with_backup", "delete_source_registration", "uninstall_manifest"}:
        body = [
            "# This operation changes host logging state.",
            "# The classifier renders a handoff only; fill placeholders after approval.",
            "# Required gate must be satisfied before an operator runs any host-action command.",
            "Write-Host 'Review required before host log action. No host action is run by this generated plan.'",
        ]
        if operation == "clear_with_backup":
            body.extend([
                "$BackupPath = Join-Path $OutputRoot (($LogTarget -replace '[^A-Za-z0-9._-]', '_') + '.before-clear.evtx')",
                "# After explicit authorization, an operator may use the approved backup path with the platform clear command.",
                "Write-Host \"Backup path reserved: $BackupPath\"",
            ])
    else:
        body = [
            "Write-Host 'No command rendered for this high-risk or unsupported operation class.'",
        ]

    return "\n".join(header + body) + "\n"


def write_outputs(plan: dict[str, Any], command_plan: str, output_root: Path) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "windows_log_classification.json").write_text(
        json.dumps(plan["classification"], indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_root / "windows_log_operation_plan.json").write_text(
        json.dumps(plan, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (output_root / "windows_log_command_plan.ps1").write_text(command_plan, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Classify Windows log operation requests without executing host actions.")
    parser.add_argument("--target", required=True, help="Log target, channel, provider log, trace path, or fixture path.")
    parser.add_argument("--operation", required=True, help="Requested operation in natural language or operation-like terms.")
    parser.add_argument("--taxonomy", default=str(DEFAULT_TAXONOMY), help="Path to windows-log-taxonomy.json.")
    parser.add_argument("--output-root", help="Optional output root for generated plan artifacts.")
    parser.add_argument(
        "--emit",
        choices=["classification", "plan", "powershell", "all"],
        default="classification",
        help="Select stdout payload.",
    )
    parser.add_argument("--write", action="store_true", help="Write local classification/plan/command artifacts.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    taxonomy = load_taxonomy(Path(args.taxonomy))
    classification = classify_request(args.target, args.operation, taxonomy)
    plan = build_operation_plan(classification, args.output_root)
    command_plan = render_powershell_plan(plan)

    if args.write:
        write_outputs(plan, command_plan, Path(plan["artifacts"]["output_root"]))

    if args.emit == "classification":
        print(json.dumps(classification.to_dict(), indent=2, sort_keys=True))
    elif args.emit == "plan":
        print(json.dumps(plan, indent=2, sort_keys=True))
    elif args.emit == "powershell":
        print(command_plan, end="")
    else:
        print(json.dumps({"classification": classification.to_dict(), "plan": plan, "powershell": command_plan}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
