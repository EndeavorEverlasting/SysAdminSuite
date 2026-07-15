#!/usr/bin/env python3
"""Contracts and temporary-HOME lifecycle proof for the Windows tmux service."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/Invoke-SasWindowsTmuxWorkspace.ps1"
FIXTURES = ROOT / "Tests/Fixtures/windows-tmux-workspace"
SCHEMA = ROOT / "schemas/harness/developer-workstation-lifecycle-result.schema.json"


def read(path: Path) -> str:
    assert path.is_file(), f"missing {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def invoke(action: str, fixture: Path, home: Path, state: Path, *, allow=False, launch=False) -> dict:
    output = state.parent / f"{action.lower()}-{fixture.stem}.json"
    command = ["pwsh", "-NoProfile", "-File", str(SCRIPT), "-Action", action,
               "-FixturePath", str(fixture), "-UserConfigDir", str(home),
               "-StateRoot", str(state), "-OutputPath", str(output), "-Confirm:$false"]
    if allow:
        command.append("-AllowTargetMutation")
    if launch:
        command.append("-LaunchGui")
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30)
    assert completed.returncode == 0, completed.stderr
    assert output.is_file(), completed.stdout
    return json.loads(output.read_text(encoding="utf-8"))


def validate_result(result: dict) -> None:
    assert result["schema_version"] == "sas-developer-workstation-lifecycle-result/v1"
    assert result["proof"]["live_runtime"] is False
    assert result["proof"]["persistence_observed"] is False
    try:
        import jsonschema
    except ImportError:
        return
    jsonschema.Draft202012Validator(json.loads(read(SCHEMA))).validate(result)


def test_surface_and_parse_contract() -> None:
    text = read(SCRIPT)
    for action in ("Plan", "Apply", "Start", "Status", "Stop", "Repair", "Rollback"):
        assert f"'{action}'" in text
    for filename in ("Install-SasWindowsTmuxWorkspace.ps1", "Start-SasWindowsTmuxWorkspace.ps1",
                     "Get-SasWindowsTmuxWorkspaceStatus.ps1", "Stop-SasWindowsTmuxWorkspace.ps1",
                     "Repair-SasWindowsTmuxWorkspace.ps1", "Rollback-SasWindowsTmuxWorkspace.ps1"):
        assert (ROOT / "scripts" / filename).is_file()
    assert "SupportsShouldProcess" in text and "AllowTargetMutation" in text
    parser = "& { $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$e)|Out-Null; if($e.Count){$e|Out-String|Write-Error;exit 1} }"
    subprocess.run(["pwsh", "-NoProfile", "-Command", parser, str(SCRIPT)], check=True, cwd=ROOT)


def test_lua_and_launcher_contract() -> None:
    template = read(ROOT / "Config/wezterm-windows-tmux.lua.template")
    launcher = read(ROOT / "Launch-WorkstationWezTerm.ps1")
    assert "tmux: Development" in template and "wsl.exe" in template
    assert "new-session" in template and "-A" in template and "@SESSION@" in template
    assert "PowerShell 7 (fallback/admin)" in template
    assert "font" not in template.lower()
    assert "Start-SasWindowsTmuxWorkspace.ps1" in launcher and "LaunchGui" in launcher
    assert "wezterm-gui.exe" in read(SCRIPT)


def test_fixture_matrix_is_sanitized() -> None:
    scenarios = {json.loads(read(path))["scenario"] for path in FIXTURES.glob("*.json")}
    assert scenarios == {"healthy", "no-wsl", "docker-only", "missing-tmux", "missing-wezterm-gui", "stale-keepalive", "nested-tmux", "malformed-config", "apply-failure"}
    assert "Cheex" not in "".join(read(path) for path in FIXTURES.glob("*.json"))


def test_required_failure_reasons() -> None:
    expected = {"no-wsl": "no-wsl-distro", "docker-only": "docker-only-distro",
                "missing-tmux": "tmux-missing", "missing-wezterm-gui": "wezterm-cli-gui-confusion",
                "nested-tmux": "nested-tmux-attempt"}
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        for scenario, reason in expected.items():
            result = invoke("Plan", FIXTURES / f"{scenario}.json", root / "home", root / scenario)
            validate_result(result)
            assert result["outcome"] == "action-required" and reason in result["reason_codes"]


def test_plan_is_read_only_and_apply_requires_authorization() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); home = root / "home"; state = root / "state"
        plan = invoke("Plan", FIXTURES / "healthy.json", home, state)
        validate_result(plan)
        assert plan["outcome"] == "success" and not home.exists() and not state.exists()
        denied = invoke("Apply", FIXTURES / "healthy.json", home, state)
        assert denied["outcome"] == "action-required" and not home.exists()


def test_apply_start_status_stop_rollback_fixture_loop() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); home = root / "home"; state = root / "state"; home.mkdir()
        original = "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nconfig.color_scheme = 'Builtin Solarized Dark'\nreturn config\n"
        (home / ".wezterm.lua").write_text(original, encoding="utf-8")
        applied = invoke("Apply", FIXTURES / "healthy.json", home, state, allow=True)
        validate_result(applied)
        assert applied["outcome"] == "success" and applied["proof"]["config_applied"]
        assert "Builtin Solarized Dark" in read(home / ".wezterm.lua")
        assert "BEGIN SYSADMINSUITE" in read(home / ".wezterm.lua")
        assert "tmux: Development" in read(home / ".wezterm-sysadminsuite.lua")
        first = invoke("Start", FIXTURES / "healthy.json", home, state, launch=True)
        second = invoke("Start", FIXTURES / "healthy.json", home, state, launch=True)
        assert first["outcome"] == second["outcome"] == "success"
        status = invoke("Status", FIXTURES / "healthy.json", home, state)
        assert status["outcome"] == "success" and status["lifecycle_state"] == "session-running"
        stopped = invoke("Stop", FIXTURES / "healthy.json", home, state)
        assert stopped["outcome"] == "success"
        rolled = invoke("Rollback", FIXTURES / "healthy.json", home, state, allow=True)
        assert rolled["outcome"] == "success" and read(home / ".wezterm.lua") == original


def test_apply_failures_preserve_backup_evidence() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        for scenario, reason in (("malformed-config", "invalid-lua"), ("apply-failure", "rollback-required")):
            home = root / scenario / "home"; state = root / scenario / "state"; home.mkdir(parents=True)
            result = invoke("Apply", FIXTURES / f"{scenario}.json", home, state, allow=True)
            validate_result(result)
            assert result["outcome"] == "failure" and reason in result["reason_codes"]
            assert (state / "windows-tmux-workspace-backup.json").is_file()


def test_exact_keepalive_ownership_contract() -> None:
    text = read(SCRIPT)
    assert "Get-CimInstance Win32_Process" in text and "sas-workstation-keepalive" in text
    assert "Stop-Process -Id" in text
    assert "Stop-Process -Name" not in text and "wsl --terminate" not in text.lower()
    assert "Start-Process -FilePath 'wsl.exe'" in text and "-WindowStyle Hidden" in text


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    if not shutil.which("pwsh"):
        raise SystemExit("pwsh is required")
    for test in tests:
        test()
    print(f"PASS: {len(tests)} Windows WezTerm-tmux service contract groups")
