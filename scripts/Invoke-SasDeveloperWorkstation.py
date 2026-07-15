#!/usr/bin/env python3
"""One-command developer workstation orchestrator for Windows and native Linux."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ROOT / "Tests/Fixtures/developer-workstation-orchestrator/scenarios.json"
MODES = ("Inventory", "Plan", "Apply", "Start", "Status", "Stop", "Repair", "Validate", "Rollback")


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def shell_path(path: Path) -> str:
    resolved = path.resolve()
    if os.name != "nt":
        return str(resolved)
    drive = resolved.drive.rstrip(":").lower()
    return f"/mnt/{drive}/{resolved.as_posix().split(':', 1)[1].lstrip('/')}"


def sanitize(text: str) -> str:
    text = re.sub(r"[A-Za-z]:[\\/][^\r\n]+", "<path>", text)
    text = re.sub(r"/home/[^/\s]+", "/home/<user>", text)
    return text.strip()[:1000]


def execute(command: list[str], timeout: int, cwd: Path = ROOT) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def lifecycle_status(result: dict) -> str:
    return {"success": "PASS", "partial": "ACTION_REQUIRED", "action-required": "ACTION_REQUIRED", "failure": "FAIL", "unsupported": "SKIP"}.get(result.get("outcome"), "FAIL")


def step(name: str, status: str, message: str, artifact_role: str | None = None) -> dict:
    value = {"name": name, "status": status, "message": sanitize(message)}
    if artifact_role:
        value["artifact_role"] = artifact_role
    return value


def run_inventory(platform: str, fixture: dict | None, run_root: Path, timeout: int) -> tuple[dict | None, dict]:
    output = run_root / "inventory.json"
    lifecycle = run_root / "inventory-lifecycle.json"
    if platform == "windows":
        command = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts/Get-SasDeveloperWorkstationInventory.ps1"), "-OutputPath", str(output), "-LifecycleOutputPath", str(lifecycle)]
        if fixture:
            command += ["-Fixture", fixture["inventory_fixture"]]
    else:
        command = ["bash", shell_path(ROOT / "scripts/get-sas-developer-workstation-inventory.sh"), "--output", shell_path(output), "--lifecycle-output", shell_path(lifecycle)]
        if fixture:
            command += ["--fixture", fixture["inventory_fixture"]]
    completed = execute(command, timeout)
    if completed.returncode or not output.is_file():
        return None, step("inventory", "FAIL", completed.stderr or "inventory did not produce an artifact", "inventory")
    return load(output), step("inventory", "PASS", f"Inventory selected {fixture['execution_domain'] if fixture else platform}.", "inventory")


def run_workspace(platform: str, domain: str, action: str, fixture: dict | None, run_root: Path, timeout: int, allow: bool, launch_gui: bool) -> tuple[dict | None, dict]:
    output = run_root / f"workspace-{action.lower()}.json"
    if domain == "windows-native":
        operation = "configure" if action in {"Apply", "Repair"} else "rollback" if action == "Rollback" else action.lower()
        supported = action in {"Plan", "Status", "Start", "Stop"}
        result = {"schema_version":"sas-developer-workstation-lifecycle-result/v1","workflow_id":"developer-workstation","run_id":f"developer-workstation-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}-{uuid4().hex[:8]}","operation":operation,"outcome":"success" if supported else "action-required","lifecycle_state":"stopped" if action=="Stop" else "configured" if supported else "action-required","reason_codes":["none"] if supported else ["unsupported-platform"],"message":"Windows PowerShell fallback selected; no WSL or persistent tmux lifecycle was invoked.","artifacts":[],"proof":{"install_completed":False,"config_applied":False,"launcher_started":False,"tmux_attached":False,"command_acknowledged":False,"behavior_observed":False,"persistence_observed":False,"live_runtime":False,"operator_accepted":False}}
        write(output, result)
        return result, step(action.lower(), lifecycle_status(result), result["message"], "backend-status")
    user_root = run_root / "fixture-home" if fixture else Path.home()
    state_root = run_root / "fixture-state" if fixture else (Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local/state"))) / "SysAdminSuite/workstation")
    if platform == "windows":
        command = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts/Invoke-SasWindowsTmuxWorkspace.ps1"), "-Action", action,
                   "-UserConfigDir", str(user_root), "-StateRoot", str(state_root), "-OutputPath", str(output), "-Confirm:$false"]
        if fixture:
            command += ["-FixturePath", str(ROOT / f"Tests/Fixtures/windows-tmux-workspace/{fixture['workspace_fixture']}.json")]
        if allow:
            command.append("-AllowTargetMutation")
        if launch_gui:
            command.append("-LaunchGui")
    else:
        command = ["bash", shell_path(ROOT / "scripts/invoke-sas-linux-tmux-workspace.sh"), "--action", action,
                   "--user-root", shell_path(user_root), "--state-root", shell_path(state_root), "--output", shell_path(output)]
        if fixture:
            command += ["--fixture", shell_path(ROOT / f"Tests/Fixtures/linux-tmux-workspace/{fixture['workspace_fixture']}.fixture")]
        if allow:
            command.append("--apply")
        if launch_gui:
            command.append("--launch-gui")
    try:
        completed = execute(command, timeout)
    except subprocess.TimeoutExpired:
        return None, step(action.lower(), "FAIL", "workspace operation timed out", "backend-status")
    if completed.returncode or not output.is_file():
        return None, step(action.lower(), "FAIL", completed.stderr or "workspace operation produced no artifact", "backend-status")
    result = load(output)
    return result, step(action.lower(), lifecycle_status(result), result.get("message", "workspace result"), "backend-status")


def make_agent_request(fixture: dict | None, platform: str, domain: str, mode: str, bridge: bool, distro: str | None) -> dict:
    requested = fixture.get("requested_agents", ["opencode", "agy", "goose"]) if fixture else ["opencode", "agy", "goose"]
    operation = "smoke" if mode == "Validate" else "repair-check" if mode == "Repair" else "install-missing" if mode == "Apply" else "inventory"
    request = {
        "schema_version": "agentswitchboard-invocation/v2",
        "platform": platform,
        "execution_domain": domain,
        "requested_agents": requested,
        "operation": operation,
        "install_missing_only": True,
        "native_preference": True,
        "bridge_permission": bridge,
        "posture": "fixture" if fixture else "live",
    }
    if domain == "windows-wsl":
        if not distro:
            raise ValueError("selected Windows WSL domain has no non-Docker distro")
        request["distro"] = distro
    if fixture:
        source = fixture.get("agent_fixture") or "native"
        request["fixture_scenario"] = "authentication-required" if source == "authentication-required" else "bridge" if source == "bridge" else "missing" if source == "missing" else "native"
    return request


def run_agent_adapter(args, fixture: dict | None, platform: str, domain: str, distro: str | None, run_root: Path) -> tuple[dict | None, dict]:
    request_path = run_root / "agentswitchboard-request.json"
    result_path = run_root / "agentswitchboard-result.json"
    request = make_agent_request(fixture, platform, domain, args.mode, bool(args.bridge_permission or (fixture and fixture.get("bridge_permission"))), distro)
    write(request_path, request)
    command = [sys.executable, str(ROOT / "scripts/Invoke-SasAgentSwitchboard.py"), "--request", str(request_path), "--output", str(result_path), "--timeout-seconds", str(args.timeout_seconds)]
    if fixture:
        if fixture.get("simulate_timeout"):
            command.append("--simulate-timeout")
        else:
            command += ["--fixture-result", fixture["agent_fixture"]]
    elif args.agentswitchboard_root:
        command += ["--agentswitchboard-root", str(args.agentswitchboard_root)]
    completed = execute(command, args.timeout_seconds + 2)
    if completed.returncode == 124:
        return None, step("agent-readiness", "FAIL", "AgentSwitchboard exceeded the bounded timeout", "agentswitchboard-result")
    if completed.returncode or not result_path.is_file():
        return None, step("agent-readiness", "FAIL", completed.stderr or "AgentSwitchboard result was malformed", "agentswitchboard-result")
    result = load(result_path)
    status = "PASS" if result["overall_status"] == "pass" else "ACTION_REQUIRED" if result["overall_status"] in {"partial", "action-required"} else "SKIP" if result["overall_status"] == "unsupported" else "FAIL"
    backends = sorted({row["selected_backend"] for row in result["agents"].values()})
    auth = sorted({row["authentication_readiness"] for row in result["agents"].values()})
    return result, step("agent-readiness", status, f"Agent backends={','.join(backends)}; authentication={','.join(auth)}.", "agentswitchboard-result")


def classify(steps: list[dict], agent_result: dict | None, unsupported: bool) -> str:
    statuses = {item["status"] for item in steps}
    if "FAIL" in statuses:
        return "FAIL"
    if unsupported:
        return "UNSUPPORTED"
    if "ACTION_REQUIRED" in statuses:
        return "ACTION_REQUIRED"
    if agent_result and any(row["selected_backend"] == "bridge" for row in agent_result["agents"].values()):
        return "PARTIAL"
    return "PASS"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=MODES, default="Inventory")
    parser.add_argument("--platform", choices=["auto", "windows", "linux", "macos"], default="auto")
    parser.add_argument("--execution-domain", choices=["auto", "windows-native", "windows-wsl", "linux-native", "unsupported"], default="auto")
    parser.add_argument("--fixture-scenario")
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--allow-target-mutation", action="store_true")
    parser.add_argument("--bridge-permission", action="store_true")
    parser.add_argument("--launch-gui", action="store_true")
    parser.add_argument("--agentswitchboard-root", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=15)
    args = parser.parse_args()
    fixture = None
    if args.fixture_scenario:
        fixture = next((item for item in load(SCENARIOS)["scenarios"] if item["id"] == args.fixture_scenario), None)
        if fixture is None:
            parser.error("unknown fixture scenario")
    platform = fixture["platform"] if fixture else ("windows" if os.name == "nt" else "linux") if args.platform == "auto" else args.platform
    domain = fixture["execution_domain"] if fixture else ("windows-wsl" if platform == "windows" else "linux-native") if args.execution_domain == "auto" else args.execution_domain
    run_id = f"developer-workstation-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}-{uuid4().hex[:8]}"
    run_root = args.output_root or ROOT / "runs/developer-workstation" / run_id
    run_root.mkdir(parents=True, exist_ok=True)
    if args.mode in {"Apply", "Repair", "Rollback"} and not args.allow_target_mutation:
        result = {"schema_version": "sas-developer-workstation-orchestrator-result/v2", "run_id": run_id, "mode": args.mode, "platform": platform, "execution_domain": domain, "outcome": "ACTION_REQUIRED", "steps": [step("mutation-gate", "ACTION_REQUIRED", f"{args.mode} requires --allow-target-mutation")], "artifacts": [], "proof": {"fixture": bool(fixture), "live_runtime": False, "behavior_observed": False, "persistence_observed": False, "operator_accepted": False}}
        result_path = run_root / "orchestrator-result.json"
        write(result_path, result)
        write(run_root / "artifact-registry.json", {"schema_version":"sas-developer-workstation-artifact-chain/v2","run_id":run_id,"path_class":"temporary-fixture" if fixture else "repo-ignored-run","artifacts":[]})
        execute([sys.executable, str(ROOT / "scripts/Render-SasDeveloperWorkstationEnglish.py"), "--input", str(result_path), "--output", str(run_root / "english-summary.txt")], args.timeout_seconds)
        print((run_root / "english-summary.txt").read_text(encoding="utf-8"), end="")
        return 0
    steps: list[dict] = []
    artifacts: list[dict] = []
    if platform == "macos" or domain == "unsupported":
        steps.append(step("platform", "SKIP", "macOS is unsupported by the workstation v3 contract"))
        unsupported = True
        agent_result = None
    else:
        unsupported = False
        inventory, inventory_step = run_inventory(platform, fixture, run_root, args.timeout_seconds)
        steps.append(inventory_step); artifacts.append({"role": "inventory", "path": "inventory.json"})
        selected_distro = "Ubuntu" if fixture and domain == "windows-wsl" else None
        if inventory and domain == "windows-wsl" and not selected_distro:
            selected = next((item for item in inventory.get("domains", []) if item.get("id") == "windows-wsl" and item.get("available") and not item.get("backend", {}).get("docker_only")), None)
            selected_distro = selected.get("backend", {}).get("distribution") if selected else None
        workspace_results = []
        if args.mode != "Inventory":
            plan_result, plan_step = run_workspace(platform, domain, "Plan", fixture, run_root, args.timeout_seconds, False, False)
            steps.append(plan_step); artifacts.append({"role": "plan", "path": "workspace-plan.json"})
            workspace_results.append(plan_result)
        if args.mode in {"Apply", "Start", "Status", "Stop", "Repair", "Validate", "Rollback"}:
            if args.mode == "Apply":
                actions = [("Apply", True, False), ("Start", False, args.launch_gui), ("Status", False, False)]
            elif args.mode == "Validate":
                actions = [("Status", False, False)]
            elif args.mode == "Rollback" and fixture:
                actions = [("Apply", True, False), ("Rollback", True, False)]
            else:
                actions = [(args.mode, args.mode in {"Repair", "Rollback"}, args.launch_gui)]
            for action, allow, launch in actions:
                workspace_result, workspace_step = run_workspace(platform, domain, action, fixture, run_root, args.timeout_seconds, allow, launch)
                steps.append(workspace_step); workspace_results.append(workspace_result)
                artifacts.append({"role": "rollback-result" if action == "Rollback" else "backend-status", "path": f"workspace-{action.lower()}.json"})
                if workspace_step["status"] == "FAIL":
                    break
        agent_result, agent_step = run_agent_adapter(args, fixture, platform, domain, selected_distro, run_root)
        steps.append(agent_step)
        artifacts.extend([{"role": "agentswitchboard-result", "path": "agentswitchboard-result.json"}, {"role": "english-summary", "path": "english-summary.txt"}])
    outcome = classify(steps, agent_result, unsupported)
    result = {"schema_version": "sas-developer-workstation-orchestrator-result/v2", "run_id": run_id, "mode": args.mode, "platform": platform, "execution_domain": domain, "outcome": outcome, "steps": steps, "artifacts": artifacts, "proof": {"fixture": bool(fixture), "live_runtime": False, "behavior_observed": False, "persistence_observed": False, "operator_accepted": False}}
    result_path = run_root / "orchestrator-result.json"
    write(result_path, result)
    registry = {"schema_version": "sas-developer-workstation-artifact-chain/v2", "run_id": run_id, "path_class": "temporary-fixture" if fixture else "repo-ignored-run", "artifacts": artifacts}
    write(run_root / "artifact-registry.json", registry)
    execute([sys.executable, str(ROOT / "scripts/Render-SasDeveloperWorkstationEnglish.py"), "--input", str(result_path), "--output", str(run_root / "english-summary.txt")], args.timeout_seconds)
    print((run_root / "english-summary.txt").read_text(encoding="utf-8"), end="")
    return 0 if outcome in {"PASS", "PARTIAL", "ACTION_REQUIRED", "UNSUPPORTED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
