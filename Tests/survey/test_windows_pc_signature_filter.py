#!/usr/bin/env python3
"""Contracts for the local Windows-PC signature filter."""
from __future__ import annotations

import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILTER = ROOT / "survey" / "sas-filter-windows-pc-signature.py"


def run_filter(input_path: Path, candidates: Path, report: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(FILTER),
            "--input",
            str(input_path),
            "--candidates-out",
            str(candidates),
            "--report-out",
            str(report),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def load_report(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["Host"]: row for row in csv.DictReader(handle)}


def test_jsonl_filters_non_pc_devices_and_requires_both_ports() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        evidence = root / "evidence.jsonl"
        candidates = root / "candidates.txt"
        report = root / "report.csv"
        items = [
            {"host": "ap01.example.invalid", "port": 80},
            {"host": "ap01.example.invalid", "port": 443},
            {"host": "printer01.example.invalid", "port": 80},
            {"host": "printer01.example.invalid", "port": 9100},
            {"host": "rpc-only.example.invalid", "port": 135},
            {"host": "smb-only.example.invalid", "port": 445},
            {"host": "pc01.example.invalid", "port": 135},
            {"host": "pc01.example.invalid", "port": 445},
            {"host": "pc01.example.invalid", "port": 3389},
        ]
        evidence.write_text("\n".join(json.dumps(item) for item in items) + "\n", encoding="utf-8")

        result = run_filter(evidence, candidates, report)
        assert result.returncode == 0, result.stderr
        assert candidates.read_text(encoding="utf-8").splitlines() == ["pc01.example.invalid"]

        rows = load_report(report)
        assert rows["pc01.example.invalid"]["SignatureStatus"] == "WINDOWS_PC_SIGNATURE_MATCH"
        assert rows["rpc-only.example.invalid"]["SignatureStatus"] == "RPC_ONLY"
        assert rows["smb-only.example.invalid"]["SignatureStatus"] == "SMB_ONLY"
        assert rows["ap01.example.invalid"]["SignatureStatus"] == "NO_WINDOWS_PC_SIGNATURE"
        assert rows["printer01.example.invalid"]["SignatureStatus"] == "NO_WINDOWS_PC_SIGNATURE"
        assert "9100" in rows["printer01.example.invalid"]["ObservedPorts"]


def test_text_input_is_aggregated_by_host_without_packets() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        evidence = root / "evidence.txt"
        candidates = root / "candidates.txt"
        report = root / "report.csv"
        evidence.write_text(
            "# synthetic host:port evidence\n"
            "pc02.example.invalid:445\n"
            "printer02.example.invalid:9100\n"
            "pc02.example.invalid:135\n",
            encoding="utf-8",
        )

        result = run_filter(evidence, candidates, report)
        assert result.returncode == 0, result.stderr
        assert candidates.read_text(encoding="utf-8").splitlines() == ["pc02.example.invalid"]
        assert "PC signature filter: 1 matched / 2 observed hosts" in result.stdout


def test_source_contract_is_local_only_and_dual_port() -> None:
    text = FILTER.read_text(encoding="utf-8")
    assert "REQUIRED_PORTS = {135, 445}" in text
    assert "performs no network activity" in text
    assert "not proof of Cybernet identity" in text
    for forbidden in ("nmap", "naabu -", "socket.connect", "requests.", "urllib.request"):
        assert forbidden not in text.lower(), forbidden


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: Windows-PC signature filter contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
