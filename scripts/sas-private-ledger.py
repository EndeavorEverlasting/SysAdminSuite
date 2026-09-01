#!/usr/bin/env python3
"""Append private, local-only repository work events to an ignored JSONL ledger.

The ledger deliberately records metadata and operator/agent summaries, not diff bodies,
environment dumps, credentials, or network observations. It performs local Git reads only.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = "sas-private-ledger/v1"
LEDGER_RELATIVE_PATH = Path("runs") / "private-ledger" / "ledger.jsonl"
TRAILERS = {
    "sas-decision": "decision",
    "sas-plan": "plan",
}


def run_git(repo_root: Path, *args: str, check: bool = True) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    if check and completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or f"git exited {completed.returncode}"
        raise RuntimeError(detail)
    return completed.stdout.strip()


def resolve_repo_root() -> Path:
    completed = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise RuntimeError("not_inside_git_repository")
    return Path(completed.stdout.strip()).resolve()


def ledger_path(repo_root: Path) -> Path:
    return repo_root / LEDGER_RELATIVE_PATH


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def git_identity(repo_root: Path) -> tuple[str, str]:
    branch = run_git(repo_root, "branch", "--show-current", check=False).strip() or "detached"
    commit = run_git(repo_root, "rev-parse", "HEAD", check=False).strip().lower() or "unknown"
    return branch, commit


def normalize_summary(value: str) -> str:
    summary = " ".join(value.replace("\x00", "").split())
    if not summary:
        raise ValueError("summary_must_not_be_empty")
    if len(summary) > 4000:
        raise ValueError("summary_exceeds_4000_characters")
    return summary


def append_event(repo_root: Path, event: dict) -> Path:
    path = ledger_path(repo_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(payload + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    return path


def base_event(repo_root: Path, kind: str, source: str, summary: str) -> dict:
    branch, commit = git_identity(repo_root)
    return {
        "schema_version": SCHEMA_VERSION,
        "timestamp_utc": now_utc(),
        "kind": kind,
        "source": source,
        "summary": normalize_summary(summary),
        "branch": branch,
        "commit": commit,
    }


def parse_trailers(message: str) -> Iterable[tuple[str, str]]:
    for raw in message.splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        kind = TRAILERS.get(key.strip().lower())
        if kind and value.strip():
            yield kind, value.strip()


def append_commit(repo_root: Path) -> list[Path]:
    branch, commit = git_identity(repo_root)
    subject = run_git(repo_root, "show", "-s", "--format=%s", "HEAD")
    message = run_git(repo_root, "show", "-s", "--format=%B", "HEAD")
    files = [
        line.strip()
        for line in run_git(
            repo_root,
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--name-only",
            "-r",
            "HEAD",
            check=False,
        ).splitlines()
        if line.strip()
    ]
    event = {
        "schema_version": SCHEMA_VERSION,
        "timestamp_utc": now_utc(),
        "kind": "commit",
        "source": "post-commit-hook",
        "summary": normalize_summary(subject or "commit"),
        "branch": branch,
        "commit": commit,
        "files": files,
    }
    paths = [append_event(repo_root, event)]
    for kind, summary in parse_trailers(message):
        trailer_event = base_event(repo_root, kind, "commit-trailer", summary)
        trailer_event["commit"] = commit
        trailer_event["branch"] = branch
        paths.append(append_event(repo_root, trailer_event))
    return paths


def append_explicit(repo_root: Path, kind: str, summary: str, source: str) -> Path:
    return append_event(repo_root, base_event(repo_root, kind, source, summary))


def status(repo_root: Path) -> int:
    path = ledger_path(repo_root)
    if not path.exists():
        print(f"PRIVATE LEDGER: empty | {path}")
        return 0
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                count += 1
    print(f"PRIVATE LEDGER: {count} entries | {path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local-only SysAdminSuite private ledger writer")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("commit-hook", help="Append current HEAD metadata and SAS-Decision/SAS-Plan trailers")

    append = sub.add_parser("append", help="Append an explicit private decision or plan")
    append.add_argument("kind", choices=("decision", "plan"))
    append.add_argument("summary")
    append.add_argument("--source", default="operator-or-agent")

    sub.add_parser("status", help="Read ledger path/count without creating or modifying it")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        repo_root = resolve_repo_root()
        if args.command == "commit-hook":
            paths = append_commit(repo_root)
            print(f"PRIVATE LEDGER: captured commit metadata | {paths[-1]}")
            return 0
        if args.command == "append":
            path = append_explicit(repo_root, args.kind, args.summary, args.source)
            print(f"PRIVATE LEDGER: captured {args.kind} | {path}")
            return 0
        return status(repo_root)
    except Exception as exc:  # fail visibly; never pretend capture succeeded
        print(f"PRIVATE LEDGER ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
