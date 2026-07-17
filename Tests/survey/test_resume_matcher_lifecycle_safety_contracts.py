#!/usr/bin/env python3
"""Executable safety contracts for the Resume Matcher operator front door."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAFE = ROOT / "scripts/invoke-sas-resume-matcher-workstation-safe.sh"
ENGINE = ROOT / "scripts/invoke-sas-resume-matcher-workstation.sh"
PS_WRAPPER = ROOT / "scripts/Invoke-SasResumeMatcherWorkstation.ps1"
PS_ACCEPT = ROOT / "scripts/Test-SasResumeMatcherLiveAcceptance.ps1"
BASH_ACCEPT = ROOT / "scripts/test-sas-resume-matcher-live-acceptance.sh"
DOC = ROOT / "docs/RESUME_MATCHER_LIFECYCLE_SAFETY.md"
WORKFLOW = ROOT / ".github/workflows/resume-matcher-workstation.yml"


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def run(*args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )
    if check:
        assert completed.returncode == 0, completed.stderr or completed.stdout
    return completed


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def test_operator_front_door_is_discoverable_and_syntactically_valid() -> None:
    for path in (SAFE, ENGINE, PS_WRAPPER, PS_ACCEPT, BASH_ACCEPT, DOC, WORKFLOW):
        read(path)
    run("bash", "-n", str(SAFE))
    source = read(SAFE)
    assert "--allow-application-update" in source
    assert "--confirm-provider-charge" in source
    assert "git ls-remote" in source
    assert "application-update-authorization-required" in source
    assert "unmanaged-runtime-still-running" in source
    assert "did not kill arbitrary processes" in source
    for forbidden in ("pkill", "kill -9", "fuser -k", "lsof -t"):
        assert forbidden not in source


def test_provider_health_requires_separate_cost_confirmation() -> None:
    completed = run(
        "bash",
        str(SAFE),
        "--action",
        "Accept",
        "--apply",
        "--require-provider-health",
        check=False,
    )
    assert completed.returncode == 2
    assert "--confirm-provider-charge" in completed.stderr


def test_update_authorization_flag_is_apply_only() -> None:
    completed = run(
        "bash",
        str(SAFE),
        "--action",
        "Plan",
        "--allow-application-update",
        check=False,
    )
    assert completed.returncode == 2
    assert "valid only" in completed.stderr


def test_clean_clone_fast_forward_is_blocked_without_explicit_authorization() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        app = root / "Resume-Matcher"
        (app / ".git").mkdir(parents=True)
        state = root / "state"
        output = root / "blocked.json"
        fake_git = fake_bin / "git"
        write_executable(
            fake_git,
            """#!/usr/bin/env bash
set -e
args="$*"
case "$args" in
  *"rev-parse --is-inside-work-tree"*) printf 'true\\n' ;;
  *"remote get-url origin"*) printf 'https://github.com/srbhr/Resume-Matcher.git\\n' ;;
  *"status --porcelain"*) exit 0 ;;
  *"rev-parse HEAD"*) printf '1111111111111111111111111111111111111111\\n' ;;
  *"ls-remote --heads "*) printf '2222222222222222222222222222222222222222\\trefs/heads/main\\n' ;;
  *"ls-remote "*) printf '2222222222222222222222222222222222222222\\trefs/heads/main\\n' ;;
  *) exit 0 ;;
esac
""",
        )
        env = os.environ.copy()
        env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
        completed = run(
            "bash",
            str(SAFE),
            "--action",
            "Apply",
            "--apply",
            "--app-root",
            str(app),
            "--state-root",
            str(state),
            "--output",
            str(output),
            env=env,
            check=False,
        )
        assert completed.returncode == 4, completed.stderr or completed.stdout
        result = load(output)
        assert result["operation"] == "apply"
        assert result["outcome"] == "action-required"
        assert result["reason_codes"] == ["application-update-authorization-required"]
        assert result["proof"]["install_completed"] is False


def test_stop_reports_unmanaged_runtime_instead_of_claiming_full_shutdown() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        write_executable(fake_bin / "curl", "#!/usr/bin/env bash\nexit 0\n")
        output = root / "stop.json"
        env = os.environ.copy()
        env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
        completed = run(
            "bash",
            str(SAFE),
            "--action",
            "Stop",
            "--apply",
            "--state-root",
            str(root / "state"),
            "--output",
            str(output),
            env=env,
            check=False,
        )
        assert completed.returncode == 4, completed.stderr or completed.stdout
        result = load(output)
        assert result["outcome"] == "action-required"
        assert result["lifecycle_state"] == "running"
        assert result["reason_codes"] == ["unmanaged-runtime-still-running"]
        assert result["inventory"]["backend_healthy"] is True
        assert result["inventory"]["frontend_healthy"] is True
        assert result["proof"]["live_runtime"] is True


def test_windows_and_acceptance_entrypoints_route_through_safety_front_door() -> None:
    wrapper = read(PS_WRAPPER)
    accept = read(PS_ACCEPT)
    bash_accept = read(BASH_ACCEPT)
    assert "invoke-sas-resume-matcher-workstation-safe.sh" in wrapper
    assert "AllowApplicationUpdate" in wrapper
    assert "ConfirmProviderCharge" in wrapper
    assert "--allow-application-update" in wrapper
    assert "--confirm-provider-charge" in wrapper
    assert "ConfirmProviderCharge" in accept
    assert "requires -ConfirmProviderCharge" in accept
    assert "invoke-sas-resume-matcher-workstation-safe.sh" in bash_accept
    assert "--action Accept --apply" in bash_accept


def test_safety_document_names_all_three_closed_risks() -> None:
    doc = read(DOC)
    for required in (
        "--allow-application-update",
        "--confirm-provider-charge",
        "one provider request",
        "unmanaged-runtime-still-running",
        "never kills arbitrary processes",
    ):
        assert required in doc


def main() -> int:
    tests = [name for name in globals() if name.startswith("test_")]
    failures: list[str] = []
    for name in sorted(tests):
        try:
            globals()[name]()
            print(f"PASS: {name}")
        except Exception as exc:
            failures.append(f"{name}: {exc}")
            print(f"FAIL: {name}: {exc}", file=sys.stderr)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"PASS: {len(tests)} Resume Matcher lifecycle safety contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
