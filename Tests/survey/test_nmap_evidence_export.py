#!/usr/bin/env python3
"""Offline contract tests for Nmap evidence export classification columns."""
from __future__ import annotations

import csv
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXPORTER = REPO_ROOT / "survey" / "sas-nmap-evidence-export.py"
CLASSIFIER = REPO_ROOT / "survey" / "sas-survey-device-classify.py"
FIXTURE = REPO_ROOT / "survey" / "fixtures" / "nmap_sample_output.txt"


def load_classifier():
    spec = importlib.util.spec_from_file_location("sas_survey_device_classify", CLASSIFIER)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load {CLASSIFIER}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


CLASSIFICATION_FIELDS = load_classifier().CLASSIFICATION_FIELDS


def run_export(output_path: Path) -> None:
    proc = subprocess.run(
        [sys.executable, str(EXPORTER), "--input", str(FIXTURE), "--output", str(output_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"exporter failed: {proc.stderr or proc.stdout}")


def test_nmap_export_includes_classification_columns() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "nmap_evidence.csv"
        run_export(out)
        with out.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames or []
            assert "SourceFile" not in CLASSIFICATION_FIELDS
            for column in CLASSIFICATION_FIELDS:
                assert column in header, f"missing column {column} in export header"
            rows = list(reader)
        assert len(rows) >= 2, "fixture should produce hostname and IP-only rows"

        hostname_row = next(r for r in rows if r.get("observed_hostname"))
        assert hostname_row.get("DeviceRole") == "target_workstation"
        assert hostname_row.get("NextAction")
        assert hostname_row.get("RoleConfidence")
        assert hostname_row.get("SourceFile") == FIXTURE.name

        ip_only_row = next(r for r in rows if not r.get("observed_hostname"))
        assert ip_only_row.get("RoleConfidence") == "needs_review"
        assert "nmap:no-hostname" in (ip_only_row.get("RoleSignals") or "")
        assert ip_only_row.get("NextAction")
        assert ip_only_row.get("SourceFile") == FIXTURE.name


def main() -> int:
    tests = [test_nmap_export_includes_classification_columns]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {test.__name__}: {exc}", file=sys.stderr)
    if failed:
        print(f"{failed} test(s) failed", file=sys.stderr)
        return 1
    print(f"All {len(tests)} Nmap export test(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
