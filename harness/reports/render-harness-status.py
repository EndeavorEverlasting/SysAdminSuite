#!/usr/bin/env python3
"""Render a human-readable operational harness status report from tracked registries."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8-sig"))


def render() -> str:
    manifest = load("harness/api/operational-harness-manifest.json")
    validators = load("harness/api/harness-validator-registry.json")
    commands = load("harness/api/harness-command-registry.json")
    artifacts = load("harness/api/harness-artifact-registry.json")
    outcomes = load("harness/api/harness-outcome-registry.json")
    deployment_states = load("harness/api/deployment-state-registry.json")
    required = [item for item in manifest["components"] if item.get("required")]
    missing = [item["path"] for item in required if not (ROOT / item["path"]).is_file()]
    blocking = [item for item in validators["validators"] if item.get("blocking")]
    deploy = [item for item in commands["commands"] if item.get("kind") in {"deploy", "deploy-plan"}]
    local_artifacts = [item for item in artifacts["artifacts"] if not item.get("tracked")]
    continuations = [
        (contract["command_id"], continuation)
        for contract in outcomes["contracts"]
        for continuation in contract.get("continuations", [])
    ]
    cybernet = next(item for item in deployment_states["contexts"] if item["id"] == "cybernet-autologon")
    truth = cybernet["current_product_truth"]
    states = {item["id"]: item for item in cybernet["states"]}
    pre_reboot = states["autologon_pre_reboot_configured"]
    runtime = states["autologon_runtime_proven"]

    lines = [
        "# SysAdminSuite Operational Harness Generated Status", "", "Schema: `sas-harness-status-report/v1`", "",
        "## Summary", "", f"- Required harness components: **{len(required)}**", f"- Missing required components: **{len(missing)}**",
        f"- Registered validators: **{len(validators['validators'])}** ({len(blocking)} blocking)",
        f"- Registered canonical commands: **{len(commands['commands'])}**",
        f"- Registered outcome contracts: **{len(outcomes['contracts'])}** ({len(continuations)} same-turn continuations)",
        f"- Registered deployment-state contexts: **{len(deployment_states['contexts'])}**",
        f"- Registered artifact roles: **{len(artifacts['artifacts'])}** ({len(local_artifacts)} generated/local)", "", "## Working", "",
        "Required-component inventory is **not complete**; see Missing below." if missing else "All required component paths declared by the operational harness manifest are present in this checkout.",
        "", "## Outcome-driven execution", "",
        "Validation is an admission gate, not completion, when the requested goal remains unproven.",
        "Successful dry/test/build/plan commands must resolve a registered artifact; registered safe continuations remain same-turn.",
        "", "## AutoLogon / Cybernet desired state", "",
        f"- Current field AutoLogon apply command: `{truth['current_live_apply_command_id']}`.",
        f"- Required pre-reboot classification: `{pre_reboot['positive_classification']}`.",
        f"- Required pre-reboot artifact: `{pre_reboot['artifact_id']}`.",
        f"- Canonical LocalSystem AutoLogon enabled: `{str(truth['canonical_system_install_enabled']).lower()}`; qualification: `{truth['canonical_system_qualification_status']}`.",
        "- Transport live certification and fixture proof are admission only; they are not AutoLogon application.",
        "- When the Cybernet clinical core is already proven installed/accepted, preserve it instead of reinstalling it merely to reach AutoLogon.",
        f"- Actual-session runtime command: `{runtime['command_id']}`; required runtime classification: `{runtime['positive_classification']}`; artifact: `{runtime['artifact_id']}`.",
        "- Deployment plus runtime proof requires real apply first, then a separately authorized attended reboot/direct automatic-sign-in observation, then actual-session runtime proof.",
        "", "## Blocking validator floor", "",
    ]
    lines.extend(f"- `{item['id']}` — `{item['command']}`" for item in blocking)
    lines += ["", "## Same-turn continuations", ""]
    lines.extend(
        f"- `{source}` -> `{item['command_id']}` when goal is `{item['when_goal']}`; authorization required: `{item['requires_authorization']}`"
        for source, item in continuations
    )
    if not continuations:
        lines.append("- None registered.")
    lines += ["", "## Canonical deployment-facing commands", ""]
    lines.extend(f"- `{item['id']}` — `{item['command']}` — mutation: `{item['mutation']}`" for item in deploy)
    lines += ["", "## Missing", ""]
    lines.extend((f"- `{path}`" for path in missing) if missing else ["- None in the required component inventory."])
    lines += ["", "## Proof ceiling", "", manifest["proof_ceiling"], "", "This generated report is a registry/path view. It does not claim that validators, target deployment, reboot, or runtime proof were executed in the current checkout unless their command/artifact output is separately recorded.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", help="Optional output path. Without it, print to stdout.")
    args = parser.parse_args()
    text = render()
    if args.output:
        path = Path(args.output)
        if not path.is_absolute():
            path = ROOT / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print(path)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
