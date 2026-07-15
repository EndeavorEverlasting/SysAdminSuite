#!/usr/bin/env python3
"""Fixture contracts for the native-Linux WezTerm to tmux workspace host."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/invoke-sas-linux-tmux-workspace.sh"
FIXTURES = ROOT / "Tests/Fixtures/linux-tmux-workspace"
SCHEMA = ROOT / "schemas/harness/developer-workstation-lifecycle-result.schema.json"


def shell_path(path: Path) -> str:
    resolved = path.resolve()
    if os.name != "nt":
        return str(resolved)
    drive = resolved.drive.rstrip(":").lower()
    return f"/mnt/{drive}/{resolved.as_posix().split(':', 1)[1].lstrip('/')}"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def invoke(action: str, fixture: str, home: Path, state: Path, *, apply=False, launch=False) -> dict:
    output = state.parent / f"{action.lower()}-{fixture}.json"
    command = ["bash", shell_path(SCRIPT), "--action", action, "--fixture", shell_path(FIXTURES / f"{fixture}.fixture"),
               "--user-root", shell_path(home), "--state-root", shell_path(state), "--output", shell_path(output)]
    if apply:
        command.append("--apply")
    if launch:
        command.append("--launch-gui")
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert completed.returncode == 0, completed.stderr
    result = json.loads(read(output))
    assert json.loads(completed.stdout) == result
    return result


def validate(result: dict) -> None:
    assert result["schema_version"] == "sas-developer-workstation-lifecycle-result/v1"
    assert result["proof"]["live_runtime"] is False
    assert result["proof"]["persistence_observed"] is False
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.Draft202012Validator(json.loads(read(SCHEMA))).validate(result)


def test_shell_surfaces_and_syntax() -> None:
    expected = ["invoke", "install", "start", "get", "stop", "repair", "rollback"]
    files = sorted((ROOT / "scripts").glob("*sas-linux-tmux-workspace*.sh"))
    assert len(files) == len(expected)
    for path in files:
        subprocess.run(["bash", "-n", shell_path(path)], check=True, cwd=ROOT)


def test_native_templates_and_agent_posture() -> None:
    wezterm = read(ROOT / "Config/wezterm-linux-tmux.lua.template")
    tmux = read(ROOT / "Config/tmux-sysadminsuite.conf")
    shell = read(ROOT / "Config/bashrc-sysadminsuite.sh")
    assert "tmux: Development" in wezterm and "new-session" in wezterm and "-A" in wezterm
    assert "wsl" not in wezterm.lower() and "pwsh" not in wezterm.lower()
    assert "history-limit" in tmux and "mouse on" in tmux
    assert "AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=0" in shell
    assert "${TMUX:-}" in shell and ".local/agent-switchboard/bin" in shell


def test_fixture_matrix() -> None:
    assert {path.stem for path in FIXTURES.glob("*.fixture")} == {
        "supported", "unsupported", "missing-tmux", "missing-wezterm", "existing-session",
        "custom-dotfiles", "malformed-config", "apply-failure", "rollback"
    }
    assert "Cheex" not in "".join(read(path) for path in FIXTURES.glob("*.fixture"))


def test_plan_is_read_only_and_failures_are_typed() -> None:
    expected = {"unsupported": "unsupported-platform", "missing-tmux": "tmux-missing",
                "missing-wezterm": "wezterm-cli-gui-confusion"}
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        healthy = invoke("Plan", "supported", root / "home", root / "state")
        validate(healthy)
        assert healthy["outcome"] == "success" and not (root / "home").exists() and not (root / "state").exists()
        for scenario, reason in expected.items():
            result = invoke("Plan", scenario, root / "home", root / scenario)
            validate(result)
            assert result["outcome"] == "action-required" and reason in result["reason_codes"]


def test_apply_requires_explicit_authorization() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        result = invoke("Apply", "supported", root / "home", root / "state")
        assert result["outcome"] == "action-required" and not (root / "home").exists()


def test_temporary_home_lifecycle_and_preservation() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); home = root / "home"; state = root / "state"; home.mkdir()
        lua = "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nconfig.color_scheme = 'Builtin Solarized Dark'\nreturn config\n"
        bashrc = "export USER_SETTING=preserved\n"
        tmuxrc = "set -g status-position top\n"
        (home / ".wezterm.lua").write_text(lua, encoding="utf-8")
        (home / ".bashrc").write_text(bashrc, encoding="utf-8")
        (home / ".tmux.conf").write_text(tmuxrc, encoding="utf-8")
        applied = invoke("Apply", "custom-dotfiles", home, state, apply=True)
        validate(applied)
        assert applied["outcome"] == "success" and applied["proof"]["config_applied"]
        assert "Builtin Solarized Dark" in read(home / ".wezterm.lua")
        assert "USER_SETTING=preserved" in read(home / ".bashrc")
        assert "status-position top" in read(home / ".tmux.conf")
        assert (state / "linux-tmux-workspace-backup.json").is_file()
        assert invoke("Start", "custom-dotfiles", home, state, launch=True)["outcome"] == "success"
        assert invoke("Start", "custom-dotfiles", home, state, launch=True)["outcome"] == "success"
        assert invoke("Status", "custom-dotfiles", home, state)["outcome"] == "success"
        assert invoke("Stop", "custom-dotfiles", home, state)["outcome"] == "success"
        rolled = invoke("Rollback", "custom-dotfiles", home, state, apply=True)
        assert rolled["outcome"] == "success"
        assert read(home / ".wezterm.lua") == lua and read(home / ".bashrc") == bashrc and read(home / ".tmux.conf") == tmuxrc


def test_malformed_and_apply_failure_keep_rollback_evidence() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        for scenario, reason in (("malformed-config", "invalid-lua"), ("apply-failure", "rollback-required")):
            home = root / scenario / "home"; state = root / scenario / "state"; home.mkdir(parents=True)
            (home / ".wezterm.lua").write_text("return {\n", encoding="utf-8")
            result = invoke("Apply", scenario, home, state, apply=True)
            validate(result)
            assert result["outcome"] == "failure" and reason in result["reason_codes"]
            assert (state / "linux-tmux-workspace-backup.json").is_file()


def test_safety_and_native_only_contract() -> None:
    text = read(SCRIPT)
    assert "curl |" not in text and "curl -" not in text and "wsl" not in text.lower()
    assert "sudo" in text and "install_missing" in text and "--install-missing" in text
    assert "${TMUX:-}" in text and "tmux kill-session -t" in text
    assert "nohup wezterm start --always-new-process" in text
    assert "AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=0" in text


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: {len(tests)} native-Linux WezTerm-tmux contract groups")
