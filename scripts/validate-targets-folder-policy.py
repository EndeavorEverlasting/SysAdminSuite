#!/usr/bin/env python3
"""Validate tracked files under targets/ against SysAdminSuite intake policy.

Uses `git ls-files targets/` only. Live/local evidence must stay gitignored.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import PurePosixPath

LIVE_NAME_PATTERNS: list[tuple[str, str]] = [
    (r"active\s*deployment\s*tracker", "active deployment tracker"),
    (r"alejandro", "Alejandro"),
    (r"cybernet\s*sources", "Cybernet sources"),
    (r"\bwave\b", "wave"),
    (r"\bssuh\b", "SSUH"),
    (r"\bnsuh\b", "NSUH"),
    (r"serial", "serial"),
    (r"\bmac\b", "mac"),
    (r"\bnmap\b", "nmap"),
    (r"\bnaabu\b", "naabu"),
    (r"workstation\s*identity", "workstation identity"),
    (r"\bpreflight\b", "preflight"),
]

FORBIDDEN_EXTENSIONS = {".xlsx", ".xlsm", ".xls", ".zip"}
FORBIDDEN_ZONE_PREFIXES = (
    "targets/live/",
    "targets/local/",
    "targets/incoming/",
    "targets/raw/",
)
SANITIZED_SUFFIXES = (
    ".sample.csv",
    ".example.csv",
    ".fixture.csv",
    ".sample.json",
    ".example.json",
    ".fixture.json",
)

ALLOWED_HINT = """\
ALLOWED tracked files under targets/:
  - targets/README.md
  - targets/**/*.md
  - targets/**/*.schema.json
  - targets/sanitized/**/*.{sample,example,fixture}.{csv,json}
  - targets/**/.gitkeep

REMINDER: Place live workbooks, CSVs, and evidence locally under gitignored
paths (for example targets/local/ or logs/targets/). Do not git add them."""


def normalize_path(path: str) -> str:
    return path.replace("\\", "/").lstrip("./")


def live_name_violation(path: str) -> str | None:
    lower = path.lower()
    for pattern, label in LIVE_NAME_PATTERNS:
        if re.search(pattern, lower, flags=re.IGNORECASE):
            return f"path or filename suggests live evidence ({label})"
    return None


def check_path(path: str) -> tuple[bool, str]:
    rel = normalize_path(path)
    if not rel.startswith("targets/"):
        return True, ""

    parts = PurePosixPath(rel)

    if parts.name == ".gitkeep":
        return True, ""

    if rel == "targets/README.md":
        return True, ""

    if rel.endswith(".md"):
        return True, ""

    if rel.endswith(".schema.json"):
        return True, ""

    for prefix in FORBIDDEN_ZONE_PREFIXES:
        if rel.startswith(prefix):
            if parts.name == ".gitkeep":
                return True, ""
            return False, f"tracked file under forbidden intake zone '{prefix.rstrip('/')}'"

    if "/sanitized/" in rel:
        if rel.endswith(SANITIZED_SUFFIXES):
            violation = live_name_violation(parts.name)
            if violation:
                return False, violation
            return True, ""
        return False, "files under targets/sanitized/ must end with .sample|.example|.fixture and .csv|.json"

    ext = parts.suffix.lower()
    if ext in FORBIDDEN_EXTENSIONS:
        return False, f"extension '{ext}' is not allowed in tracked targets/"

    if ext in {".csv", ".tsv"}:
        return False, "csv/tsv only allowed under targets/sanitized/ with approved fixture suffix"

    if ext == ".txt":
        return False, "txt not allowed in tracked targets/ unless under approved sanitized fixture naming"

    violation = live_name_violation(rel)
    if violation:
        return False, violation

    return False, "unclassified tracked file under targets/ (not doc, schema, or sanitized fixture)"


def list_tracked_targets_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "targets/"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(result.stderr or "git ls-files failed", file=sys.stderr)
        raise SystemExit(2)
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def main() -> int:
    tracked = list_tracked_targets_files()
    failures: list[tuple[str, str]] = []
    for path in tracked:
        ok, reason = check_path(path)
        if not ok:
            failures.append((path, reason))

    if failures:
        print("TARGETS FOLDER POLICY: FAIL", file=sys.stderr)
        for path, reason in failures:
            print(f"  OFFENDING: {path}", file=sys.stderr)
            print(f"  REASON: {reason}", file=sys.stderr)
        print(file=sys.stderr)
        print(ALLOWED_HINT, file=sys.stderr)
        return 1

    print(f"TARGETS FOLDER POLICY: PASS ({len(tracked)} tracked file(s) under targets/)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
