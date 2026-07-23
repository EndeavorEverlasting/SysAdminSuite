#!/usr/bin/env python3
"""Validate line endings and trailing whitespace in changed Git text blobs.

The check reads bytes from the Git index or commit object, not from the working
copy. Windows files may therefore check out as CRLF while the repository stores
canonical LF bytes and `git diff --check` remains stable on Linux runners.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

TEXT_SUFFIXES = {
    ".bash",
    ".bat",
    ".c",
    ".cfg",
    ".cmd",
    ".cpp",
    ".cs",
    ".fixture",
    ".h",
    ".hpp",
    ".ini",
    ".json",
    ".jsonl",
    ".lua",
    ".md",
    ".ps1",
    ".psm1",
    ".py",
    ".sh",
    ".toml",
    ".yaml",
    ".yml",
}
TEXT_NAMES = {
    ".gitattributes",
    ".gitignore",
    ".claudeignore",
    "Dockerfile",
    "Makefile",
}


def git(repo: Path, *args: str, check: bool = True) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and completed.returncode != 0:
        message = completed.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {message}")
    return completed.stdout


def split_z(data: bytes) -> list[str]:
    return [item.decode("utf-8", errors="surrogateescape") for item in data.split(b"\0") if item]


def is_text_path(path: str) -> bool:
    candidate = Path(path)
    return candidate.name in TEXT_NAMES or candidate.suffix.lower() in TEXT_SUFFIXES


def changed_paths(repo: Path, args: argparse.Namespace) -> tuple[list[str], str]:
    if args.cached:
        data = git(repo, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
        return split_z(data), "index"
    if args.commit:
        data = git(repo, "diff-tree", "--no-commit-id", "--name-only", "--diff-filter=ACMR", "-r", "-z", args.commit)
        return split_z(data), args.commit
    if args.range:
        base, head = args.range
        data = git(repo, "diff", "--name-only", "--diff-filter=ACMR", "-z", base, head)
        return split_z(data), head
    if args.paths:
        return list(dict.fromkeys(args.paths)), args.ref
    data = git(repo, "diff-tree", "--no-commit-id", "--name-only", "--diff-filter=ACMR", "-r", "-z", "HEAD")
    return split_z(data), "HEAD"


def read_blob(repo: Path, source: str, path: str) -> bytes | None:
    spec = f":{path}" if source == "index" else f"{source}:{path}"
    completed = subprocess.run(
        ["git", "-C", str(repo), "show", spec],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout


def validate_blob(path: str, data: bytes) -> list[str]:
    if b"\0" in data:
        return []
    failures: list[str] = []
    if b"\r" in data:
        failures.append("contains CR/CRLF bytes in the Git blob; canonical repository text must be LF")
    for number, line in enumerate(data.split(b"\n"), start=1):
        if line.endswith((b" ", b"\t")):
            failures.append(f"line {number} has trailing space or tab")
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--cached", action="store_true", help="validate staged blobs from the Git index")
    modes.add_argument("--commit", metavar="REF", help="validate text files changed by one commit")
    modes.add_argument("--range", nargs=2, metavar=("BASE", "HEAD"), help="validate text files changed between two refs")
    modes.add_argument("--paths", nargs="+", help="validate explicit paths from --ref, default HEAD")
    parser.add_argument("--ref", default="HEAD", help="blob ref used with --paths")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip())
    paths, source = changed_paths(repo, args)
    checked = 0
    failures: list[str] = []
    for path in paths:
        if not is_text_path(path):
            continue
        data = read_blob(repo, source, path)
        if data is None:
            continue
        checked += 1
        for detail in validate_blob(path, data):
            failures.append(f"{path}: {detail}")

    if failures:
        print("FAIL: repository text policy", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print("Run git add --renormalize <path> after confirming the change is representation-only.", file=sys.stderr)
        return 1

    print(f"PASS: repository text policy ({checked} changed text blobs checked from {source})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
