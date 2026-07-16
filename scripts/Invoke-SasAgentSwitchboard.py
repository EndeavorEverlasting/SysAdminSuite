#!/usr/bin/env python3
"""Version-pinned, timeout-bounded SysAdminSuite adapter for AgentSwitchboard v2."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/Fixtures/agent-switchboard-v2"
REQUEST_VERSION = "agentswitchboard-invocation/v2"
RESULT_VERSION = "agentswitchboard-result/v2"
ALLOWED_REQUEST = {"schema_version", "platform", "execution_domain", "distro", "requested_agents", "operation", "install_missing_only", "native_preference", "bridge_permission", "posture", "fixture_scenario", "evidence_output_dir"}


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError("JSON root must be an object")
    return value


def validate_request(request: dict) -> None:
    if set(request) - ALLOWED_REQUEST:
        raise ValueError("request has unsupported fields")
    if request.get("schema_version") != REQUEST_VERSION:
        raise ValueError(f"request schema must be {REQUEST_VERSION}")
    if request.get("platform") not in {"windows", "linux", "macos"}:
        raise ValueError("unsupported platform")
    if request.get("execution_domain") not in {"windows-native", "windows-wsl", "linux-native", "unsupported"}:
        raise ValueError("unsupported execution domain")
    agents = request.get("requested_agents")
    if not isinstance(agents, list) or not agents or len(agents) != len(set(agents)) or not set(agents) <= {"opencode", "agy", "goose"}:
        raise ValueError("requested_agents is invalid")
    if request.get("install_missing_only") is not True:
        raise ValueError("install_missing_only must be true")
    if request.get("execution_domain") == "windows-wsl" and not request.get("distro"):
        raise ValueError("windows-wsl requires a distro")


def validate_result(result: dict, request: dict) -> None:
    if result.get("schema_version") != RESULT_VERSION:
        raise ValueError(f"result schema must be {RESULT_VERSION}")
    if result.get("overall_status") not in {"pass", "partial", "action-required", "unsupported", "failure"}:
        raise ValueError("invalid overall_status")
    agents = result.get("agents")
    requested_agents = request["requested_agents"]
    if not isinstance(agents, dict) or not set(requested_agents) <= set(agents):
        raise ValueError("result omits requested agents")
    for agent in requested_agents:
        row = agents[agent]
        if row.get("installation_domain") != request["execution_domain"]:
            raise ValueError(f"execution-domain mismatch for {agent}")
        if row.get("selected_backend") not in {"native", "bridge", "missing", "unknown"}:
            raise ValueError(f"invalid backend for {agent}")
        if row.get("authentication_readiness") not in {"unknown", "required", "ready"}:
            raise ValueError(f"invalid authentication readiness for {agent}")
        if row.get("selected_backend") == "bridge" and request.get("bridge_permission") is not True:
            raise ValueError(f"bridge selected without permission for {agent}")
    proof = result.get("proof", {})
    installation = proof.get("installation_observed")
    if not isinstance(installation, bool):
        raise ValueError("AgentSwitchboard installation proof must be boolean")
    if installation and not (request.get("posture") == "live" and request.get("operation") == "install-missing"):
        raise ValueError("installation proof is valid only for live install-missing")
    for field in ("authentication_observed", "provider_response_observed", "interactive_behavior_observed"):
        if proof.get(field) is not False:
            raise ValueError(f"AgentSwitchboard proof field must remain false: {field}")


def sanitize(text: str) -> str:
    text = re.sub(r"[A-Za-z]:[\\/][^\r\n]+", "<path>", text)
    text = re.sub(r"/home/[^/\s]+", "/home/<user>", text)
    return text.strip()[:1000]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--agentswitchboard-root", type=Path)
    parser.add_argument("--fixture-result", choices=["native", "native-linux", "native-windows", "bridge", "missing", "authentication-required", "malformed", "live-install"])
    parser.add_argument("--simulate-timeout", action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=15)
    args = parser.parse_args()
    try:
        request = load(args.request)
        validate_request(request)
        if args.simulate_timeout:
            print("AgentSwitchboard timed out after the bounded fixture interval", file=sys.stderr)
            return 124
        if args.fixture_result:
            result = load(FIXTURES / f"{args.fixture_result}.json")
        else:
            if not args.agentswitchboard_root or not (args.agentswitchboard_root / "agentswitchboard").is_dir():
                raise ValueError("a valid --agentswitchboard-root is required for live invocation")
            completed = subprocess.run(
                [sys.executable, "-m", "agentswitchboard", str(args.request.resolve())],
                cwd=args.agentswitchboard_root,
                capture_output=True,
                text=True,
                timeout=args.timeout_seconds,
            )
            if not completed.stdout.strip():
                raise ValueError(f"AgentSwitchboard returned no result: {sanitize(completed.stderr)}")
            result = json.loads(completed.stdout)
        validate_result(result, request)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        return 0
    except subprocess.TimeoutExpired:
        print("AgentSwitchboard timed out", file=sys.stderr)
        return 124
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"AgentSwitchboard adapter rejected the boundary: {sanitize(str(exc))}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
