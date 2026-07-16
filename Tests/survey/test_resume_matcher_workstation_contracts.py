#!/usr/bin/env python3
"""Dependency-free contracts for the Resume Matcher workstation deployment service."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Config/resume-matcher-workstation.sample.json"
PROFILE_SCHEMA = ROOT / "schemas/harness/resume-matcher-workstation.schema.json"
RESULT_SCHEMA = ROOT / "schemas/harness/resume-matcher-workstation-result.schema.json"
BASH_SERVICE = ROOT / "scripts/invoke-sas-resume-matcher-workstation.sh"
POWERSHELL_WRAPPER = ROOT / "scripts/Invoke-SasResumeMatcherWorkstation.ps1"
DOC = ROOT / "docs/RESUME_MATCHER_WORKSTATION.md"
WORKFLOW = ROOT / ".github/workflows/resume-matcher-workstation.yml"
CODEBASE_MAP = ROOT / "CODEBASE_MAP.md"
WORKSTATION_SKILL = ROOT / ".claude/skills/developer-workstation/SKILL.md"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check:
        assert completed.returncode == 0, completed.stderr or completed.stdout
    return completed


def load_result(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_required_surface_and_discoverability() -> None:
    for path in (
        PROFILE,
        PROFILE_SCHEMA,
        RESULT_SCHEMA,
        BASH_SERVICE,
        POWERSHELL_WRAPPER,
        DOC,
        WORKFLOW,
        CODEBASE_MAP,
        WORKSTATION_SKILL,
    ):
        read(path)
    assert "docs/RESUME_MATCHER_WORKSTATION.md" in read(CODEBASE_MAP)
    assert "RESUME_MATCHER_WORKSTATION.md" in read(WORKSTATION_SKILL)
    assert "invoke-sas-resume-matcher-workstation.sh" in read(WORKSTATION_SKILL)


def test_profile_is_pinned_closed_and_secret_free() -> None:
    profile = json.loads(read(PROFILE))
    schema = json.loads(read(PROFILE_SCHEMA))
    assert profile["schema_version"] == "sas-resume-matcher-workstation/v1"
    assert profile["schema_path"] == "schemas/harness/resume-matcher-workstation.schema.json"
    assert profile["application"]["repository_url"] == "https://github.com/srbhr/Resume-Matcher.git"
    assert profile["application"]["repository_ref"] == "main"
    assert profile["runtime"] == {
        "python_version": "3.13",
        "node_major": "22",
        "nvm_version": "v0.40.6",
        "uv_installer_url": "https://astral.sh/uv/install.sh",
        "nvm_repository_url": "https://github.com/nvm-sh/nvm.git",
    }
    assert profile["browser"]["playwright_ubuntu_2604_strategy"] == "system_chrome"
    assert profile["configuration"]["api_key_configuration"] == "settings_ui_only"
    assert profile["posture"]["automatic_authentication"] is False
    assert profile["posture"]["write_api_key_to_env"] is False
    serialized = json.dumps(profile).lower()
    assert "sk-" not in serialized
    assert "api_key_value" not in serialized
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] is False
    assert schema["properties"]["posture"]["additionalProperties"] is False


def test_result_schema_preserves_proof_boundaries() -> None:
    schema = json.loads(read(RESULT_SCHEMA))
    assert schema["additionalProperties"] is False
    assert schema["properties"]["configuration"]["properties"]["api_key_automated"]["const"] is False
    proof = schema["properties"]["proof"]["properties"]
    assert set(proof) == {
        "install_completed",
        "configuration_applied",
        "launcher_started",
        "backend_health_observed",
        "frontend_health_observed",
        "live_runtime",
    }


def test_bash_service_syntax_and_safety_contract() -> None:
    run("bash", "-n", str(BASH_SERVICE))
    source = read(BASH_SERVICE)
    assert "action=Plan" in source
    assert "Apply|Start|Stop" in source
    assert "requires --apply" in source
    assert "uv sync --python" in source
    assert "npm ci" in source
    assert "google-chrome-stable_current_amd64.deb" in source
    assert "playwright install chromium" in source
    assert "LLM_API_KEY=sk-your-api-key-here" in source
    assert '"LLM_API_KEY="' in source
    assert "automatic_authentication" in source
    assert "write_api_key_to_env" in source
    assert "curl -fsSL" in source
    assert "| sh" not in source
    assert "snap install" not in source
    assert "npm install" not in source
    assert "git status --porcelain" in source
    assert "refusing update" in source


def test_mutation_gate_rejects_apply_without_explicit_authorization() -> None:
    completed = run(
        "bash",
        str(BASH_SERVICE),
        "--action",
        "Apply",
        check=False,
    )
    assert completed.returncode == 3
    assert "requires --apply" in completed.stderr


def test_fixture_apply_is_idempotent_and_never_claims_live_install() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        fixture = Path(tmp)
        output = fixture / "apply-result.json"
        command = (
            "bash",
            str(BASH_SERVICE),
            "--action",
            "Apply",
            "--apply",
            "--fixture-root",
            str(fixture),
            "--output",
            str(output),
        )
        run(*command)
        result = load_result(output)
        assert result["outcome"] == "success"
        assert result["lifecycle_state"] == "configured"
        assert result["configuration"]["fixture_mode"] is True
        assert result["configuration"]["api_key_automated"] is False
        assert result["proof"]["configuration_applied"] is True
        assert result["proof"]["install_completed"] is False
        assert result["proof"]["launcher_started"] is False
        assert result["proof"]["live_runtime"] is False

        env_path = fixture / "home/dev/Resume-Matcher/apps/backend/.env"
        env_text = env_path.read_text(encoding="utf-8")
        assert "LLM_API_KEY=\n" in env_text
        assert "sk-your-api-key-here" not in env_text

        env_path.write_text(
            env_text.replace("LLM_API_KEY=\n", "LLM_API_KEY=existing-nonsecret-fixture\n")
            + "CUSTOM_SETTING=preserve-me\n",
            encoding="utf-8",
        )
        run(*command)
        second = env_path.read_text(encoding="utf-8")
        assert "LLM_API_KEY=existing-nonsecret-fixture" in second
        assert "CUSTOM_SETTING=preserve-me" in second


def test_fixture_validate_and_start_keep_runtime_proof_false() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        fixture = Path(tmp)
        apply_output = fixture / "apply.json"
        validate_output = fixture / "validate.json"
        start_output = fixture / "start.json"
        run(
            "bash",
            str(BASH_SERVICE),
            "--action",
            "Apply",
            "--apply",
            "--fixture-root",
            str(fixture),
            "--output",
            str(apply_output),
        )
        run(
            "bash",
            str(BASH_SERVICE),
            "--action",
            "Validate",
            "--fixture-root",
            str(fixture),
            "--output",
            str(validate_output),
        )
        run(
            "bash",
            str(BASH_SERVICE),
            "--action",
            "Start",
            "--apply",
            "--fixture-root",
            str(fixture),
            "--output",
            str(start_output),
        )
        validated = load_result(validate_output)
        started = load_result(start_output)
        assert validated["outcome"] == "success"
        assert validated["proof"]["configuration_applied"] is True
        assert validated["proof"]["live_runtime"] is False
        assert started["outcome"] == "success"
        assert started["reason_codes"] == ["fixture-no-process-launch"]
        assert started["proof"]["launcher_started"] is False
        assert started["proof"]["backend_health_observed"] is False
        assert started["proof"]["frontend_health_observed"] is False
        assert started["proof"]["live_runtime"] is False


def test_operator_docs_capture_observed_troubleshooting_contract() -> None:
    doc = read(DOC)
    for required in (
        "Python 3.13",
        "Node 22",
        "Ubuntu 26.04",
        "Playwright 1.58",
        "google-chrome-stable",
        "LLM_API_KEY=",
        "botocore",
        "foreground server",
        "DeepSeek",
        "http://localhost:3000",
        "/api/v1/health",
    ):
        assert required in doc
    assert "never writes" in doc.lower()
    assert "api key" in doc.lower()


def main() -> int:
    tests = [name for name in globals() if name.startswith("test_")]
    failures: list[str] = []
    for name in sorted(tests):
        try:
            globals()[name]()
            print(f"PASS: {name}")
        except Exception as exc:  # pragma: no cover - compact standalone runner
            failures.append(f"{name}: {exc}")
            print(f"FAIL: {name}: {exc}", file=sys.stderr)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"PASS: {len(tests)} Resume Matcher workstation contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
