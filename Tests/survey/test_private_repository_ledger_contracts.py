#!/usr/bin/env python3
"""Executable contracts for the local-only repository ledger and commit hook."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "scripts" / "sas-private-ledger.py"
HOOK = ROOT / ".githooks" / "post-commit"
DOC = ROOT / "docs" / "PRIVATE_REPOSITORY_LEDGER.md"
VALIDATOR = ROOT / "scripts" / "validate-sysadmin-harness.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "one-command-harness-proof.yml"


def run(*args: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=False)
    if check and completed.returncode != 0:
        raise AssertionError(completed.stdout + completed.stderr)
    return completed


def test_tracked_contract_surfaces_and_privacy_boundary() -> None:
    for path in (WRITER, HOOK, DOC, VALIDATOR, WORKFLOW):
        assert path.is_file(), f"missing private-ledger contract surface: {path.relative_to(ROOT)}"

    writer = WRITER.read_text(encoding="utf-8")
    hook = HOOK.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")

    assert "runs/private-ledger/ledger.jsonl" in doc
    assert "scripts/sas-private-ledger.py commit-hook" in hook
    assert "SAS-Decision" in doc and "SAS-Plan" in doc
    assert "append decision" in doc and "append plan" in doc
    assert "diff bodies" in doc
    assert "status does not create or mutate" in doc

    for forbidden in (
        r"requests\.", r"urllib\.", r"http://", r"https://", r"Invoke-WebRequest",
        r"Test-NetConnection", r"Start-Process", r"subprocess\.(?:Popen|call).*?(?:explorer|browser|game)",
    ):
        assert not re.search(forbidden, writer + "\n" + hook, re.IGNORECASE), forbidden

    ignored = run("git", "check-ignore", "runs/private-ledger/ledger.jsonl", cwd=ROOT, check=False)
    assert ignored.returncode == 0, "private ledger path must remain gitignored"


def test_status_is_read_only_when_ledger_is_absent() -> None:
    with tempfile.TemporaryDirectory(prefix="sas-ledger-status-") as tmp:
        repo = Path(tmp)
        run("git", "init", "-q", cwd=repo)
        scripts = repo / "scripts"
        scripts.mkdir()
        shutil.copy2(WRITER, scripts / WRITER.name)

        completed = run(sys.executable, str(scripts / WRITER.name), "status", cwd=repo)
        assert "PRIVATE LEDGER: empty" in completed.stdout
        assert not (repo / "runs").exists(), "read-only status must not create ledger directories"


def test_post_commit_hook_and_explicit_decision_plan_capture() -> None:
    with tempfile.TemporaryDirectory(prefix="sas-ledger-hook-") as tmp:
        repo = Path(tmp)
        run("git", "init", "-q", cwd=repo)
        run("git", "config", "user.name", "SysAdminSuite Harness", cwd=repo)
        run("git", "config", "user.email", "harness@example.invalid", cwd=repo)
        run("git", "config", "core.hooksPath", ".githooks", cwd=repo)

        (repo / "scripts").mkdir()
        (repo / ".githooks").mkdir()
        shutil.copy2(WRITER, repo / "scripts" / WRITER.name)
        shutil.copy2(HOOK, repo / ".githooks" / "post-commit")
        (repo / ".githooks" / "post-commit").chmod(0o755)
        (repo / ".gitignore").write_text("runs/\n", encoding="utf-8")
        (repo / "tracked.txt").write_text("synthetic fixture\n", encoding="utf-8")

        run("git", "add", ".", cwd=repo)
        commit = run(
            "git", "commit", "-m", "synthetic ledger commit",
            "-m", "SAS-Decision: keep private continuity out of source control\nSAS-Plan: validate hook hygiene through P11",
            cwd=repo,
        )
        assert "PRIVATE LEDGER: captured commit metadata" in commit.stdout

        ledger = repo / "runs" / "private-ledger" / "ledger.jsonl"
        rows = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines() if line.strip()]
        assert [row["kind"] for row in rows] == ["commit", "decision", "plan"]
        assert re.fullmatch(r"[0-9a-f]{40}", rows[0]["commit"])
        assert rows[0]["summary"] == "synthetic ledger commit"
        assert rows[0]["files"]
        assert all("content" not in row and "diff" not in row for row in rows)

        explicit = run(
            sys.executable, str(repo / "scripts" / WRITER.name),
            "append", "decision", "reuse the canonical one-command harness owner",
            "--source", "synthetic-contract",
            cwd=repo,
        )
        assert "captured decision" in explicit.stdout
        rows = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines() if line.strip()]
        assert rows[-1]["kind"] == "decision"
        assert rows[-1]["source"] == "synthetic-contract"

        status = run("git", "status", "--porcelain", cwd=repo)
        assert status.stdout.strip() == "", "ignored ledger writes must not dirty the repository"


def test_one_command_proof_owns_ledger_hygiene_gate() -> None:
    validator = VALIDATOR.read_text(encoding="utf-8-sig")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    for marker in (
        "private repository ledger",
        "scripts/sas-private-ledger.py",
        ".githooks/post-commit",
        "runs/private-ledger/ledger.jsonl",
    ):
        assert marker in validator, f"one-command validator missing ledger contract: {marker}"
    assert "test_private_repository_ledger_contracts.py" in workflow
    assert "scripts/sas-private-ledger.py" in workflow


def main() -> int:
    tests = [
        test_tracked_contract_surfaces_and_privacy_boundary,
        test_status_is_read_only_when_ledger_is_absent,
        test_post_commit_hook_and_explicit_decision_plan_capture,
        test_one_command_proof_owns_ledger_hygiene_gate,
    ]
    for test in tests:
        test()
    print(f"PASS: private repository ledger contracts ({len(tests)} groups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
