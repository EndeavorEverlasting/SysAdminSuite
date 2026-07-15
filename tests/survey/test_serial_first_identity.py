#!/usr/bin/env python3
"""Offline regression tests for serial-first Cybernet identity handling.

These tests intentionally avoid network access. They use synthetic manifests and
synthetic identity evidence to prove that serial is treated as the stable
identity while hostname remains only a mutable transport hint.
"""
from __future__ import annotations

import csv
import stat
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_first_row(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return next(csv.DictReader(handle))


def to_wsl_path(path: Path) -> str:
    p = path.resolve().as_posix()
    if len(p) > 1 and p[1] == ':':
        return f"/mnt/{p[0].lower()}{p[2:]}"
    return p


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def fake_identity_adapter(path: Path) -> None:
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "targets_file=''\n"
        "output=''\n"
        "while [[ $# -gt 0 ]]; do\n"
        "  case \"$1\" in\n"
        "    --targets-file) targets_file=\"$2\"; shift 2 ;;\n"
        "    --output) output=\"$2\"; shift 2 ;;\n"
        "    --timeout) shift 2 ;;\n"
        "    *) shift ;;\n"
        "  esac\n"
        "done\n"
        "probe=$(head -n 1 \"$targets_file\" || true)\n"
        "printf '%s\\n' 'Timestamp,Target,ResolvedAddress,PingStatus,DnsName,ObservedHostName,ObservedSerial,ObservedMACs,TransportUsed,IdentityStatus,Notes' > \"$output\"\n"
        "if [[ \"$probe\" == 'OLD-CYBERNET-HOST' ]]; then\n"
        "  printf '\"2026-06-25 00:00:00\",\"%s\",\"10.10.10.10\",\"Reachable\",\"%s\",\"RENAMED-CYBERNET-HOST\",\"CYB-SERIAL-001\",\"AA:BB:CC:DD:EE:FF\",\"WMI\",\"IdentityCollected\",\"probe=%s\"\\n' \"$probe\" \"$probe\" \"$probe\" >> \"$output\"\n"
        "elif [[ \"$probe\" == 'CYB-SERIAL-003' ]]; then\n"
        "  printf '\"2026-06-25 00:00:00\",\"%s\",\"\",\"NoPing\",\"\",\"\",\"\",\"\",\"\",\"UnreachableOrBlocked\",\"probe=%s\"\\n' \"$probe\" \"$probe\" >> \"$output\"\n"
        "else\n"
        "  printf '\"2026-06-25 00:00:00\",\"%s\",\"\",\"NoPing\",\"\",\"\",\"\",\"\",\"\",\"UnreachableOrBlocked\",\"probe=%s\"\\n' \"$probe\" \"$probe\" >> \"$output\"\n"
        "fi\n",
        encoding="utf-8",
        newline="\n",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def test_manifest_builder_prefers_serial_over_hostname() -> None:
    with tempfile.TemporaryDirectory() as tmp_raw:
        tmp = Path(tmp_raw)
        requests = tmp / "survey_requests_duplicate_resolution.csv"
        output = tmp / "remote_survey_manifest.csv"

        write_csv(
            requests,
            [
                {
                    "KnownResolutionIdentifiers": "cybernet hostname=OLD-CYBERNET-HOST; cybernet serial=CYB-SERIAL-000; cybernet mac=AA-BB-CC-DD-EE-00",
                    "SurveyTargetHint": "OLD-CYBERNET-HOST",
                    "ConflictValue": "OLD-CYBERNET-HOST",
                    "MissingResolutionIdentifiers": "Neuron Serial",
                    "ExcelRow": "41",
                    "ConflictField": "Cybernet Hostname",
                    "LocationKey": "NSUH-TEST",
                }
            ],
            [
                "KnownResolutionIdentifiers",
                "SurveyTargetHint",
                "ConflictValue",
                "MissingResolutionIdentifiers",
                "ExcelRow",
                "ConflictField",
                "LocationKey",
            ],
        )

        run(
            [
                "bash",
                "deployment-audit/sas-build-survey-manifest.sh",
                "--requests",
                to_wsl_path(requests),
                "--output",
                to_wsl_path(output),
            ]
        )

        row = read_first_row(output)
        assert row["Identifier"] == "CYB-SERIAL-000"
        assert row["Target"] == "CYB-SERIAL-000"
        assert row["HostName"] == "OLD-CYBERNET-HOST"
        assert row["Serial"] == "CYB-SERIAL-000"
        assert row["MACAddress"] == "AA:BB:CC:DD:EE:00"


def test_cybernet_collector_keeps_serial_as_target_and_hostname_as_probe_hint() -> None:
    with tempfile.TemporaryDirectory() as tmp_raw:
        tmp = Path(tmp_raw)
        manifest = tmp / "manifest.csv"
        output = tmp / "cybernet_evidence.csv"
        adapter = tmp / "fake_identity_adapter.sh"

        write_csv(
            manifest,
            [
                {
                    "Identifier": "CYB-SERIAL-001",
                    "Target": "CYB-SERIAL-001",
                    "HostName": "OLD-CYBERNET-HOST",
                    "Serial": "CYB-SERIAL-001",
                    "MACAddress": "",
                    "DeviceType": "Cybernet",
                    "Source": "offline-test",
                    "ExcelRow": "42",
                    "ConflictField": "Cybernet Serial",
                    "ConflictValue": "CYB-SERIAL-001",
                }
            ],
            [
                "Identifier",
                "Target",
                "HostName",
                "Serial",
                "MACAddress",
                "DeviceType",
                "Source",
                "ExcelRow",
                "ConflictField",
                "ConflictValue",
            ],
        )
        fake_identity_adapter(adapter)

        run(
            [
                "bash",
                "survey/sas-collect-cybernet-evidence.sh",
                "--manifest",
                to_wsl_path(manifest),
                "--identity-adapter",
                to_wsl_path(adapter),
                "--output",
                to_wsl_path(output),
            ]
        )

        row = read_first_row(output)
        assert row["Target"] == "CYB-SERIAL-001"
        assert row["HostName"] == "OLD-CYBERNET-HOST"
        assert row["ExpectedSerial"] == "CYB-SERIAL-001"
        assert row["ObservedHostName"] == "RENAMED-CYBERNET-HOST"
        assert row["ObservedSerial"] == "CYB-SERIAL-001"
        assert row["EvidenceStatus"] == "Confirmed"
        assert row["Notes"] == "probe=OLD-CYBERNET-HOST"


def test_cybernet_collector_reports_serial_only_rows_without_crashing() -> None:
    with tempfile.TemporaryDirectory() as tmp_raw:
        tmp = Path(tmp_raw)
        manifest = tmp / "serial_only_manifest.csv"
        output = tmp / "cybernet_evidence.csv"
        adapter = tmp / "fake_identity_adapter.sh"

        write_csv(
            manifest,
            [
                {
                    "Identifier": "",
                    "Target": "",
                    "HostName": "",
                    "Serial": "CYB-SERIAL-003",
                    "MACAddress": "",
                    "DeviceType": "Cybernet",
                    "Source": "offline-test",
                    "ExcelRow": "44",
                    "ConflictField": "Cybernet Serial",
                    "ConflictValue": "CYB-SERIAL-003",
                }
            ],
            [
                "Identifier",
                "Target",
                "HostName",
                "Serial",
                "MACAddress",
                "DeviceType",
                "Source",
                "ExcelRow",
                "ConflictField",
                "ConflictValue",
            ],
        )
        fake_identity_adapter(adapter)

        run(
            [
                "bash",
                "survey/sas-collect-cybernet-evidence.sh",
                "--manifest",
                to_wsl_path(manifest),
                "--identity-adapter",
                to_wsl_path(adapter),
                "--output",
                to_wsl_path(output),
            ]
        )

        row = read_first_row(output)
        assert row["Target"] == "CYB-SERIAL-003"
        assert row["ExpectedSerial"] == "CYB-SERIAL-003"
        assert row["PingStatus"] == "NoPing"
        assert row["EvidenceStatus"] == "Unreachable"
        assert row["Notes"] == "probe=CYB-SERIAL-003"


def test_live_serial_probe_resolves_by_serial_before_hostname() -> None:
    with tempfile.TemporaryDirectory() as tmp_raw:
        tmp = Path(tmp_raw)
        manifest = tmp / "manifest.csv"
        identity = tmp / "identity.csv"
        output = tmp / "live_serial_probe_results.csv"

        write_csv(
            manifest,
            [
                {
                    "Identifier": "CYB-SERIAL-002",
                    "Target": "CYB-SERIAL-002",
                    "HostName": "OLD-CYBERNET-HOST",
                    "Serial": "CYB-SERIAL-002",
                    "MACAddress": "",
                    "DeviceType": "Cybernet",
                    "ExcelRow": "43",
                }
            ],
            ["Identifier", "Target", "HostName", "Serial", "MACAddress", "DeviceType", "ExcelRow"],
        )
        write_csv(
            identity,
            [
                {
                    "Timestamp": "2026-06-25 00:00:00",
                    "Target": "SOME-OTHER-HOSTNAME",
                    "ResolvedAddress": "10.10.10.20",
                    "PingStatus": "Reachable",
                    "DnsName": "SOME-OTHER-HOSTNAME",
                    "ObservedHostName": "RENAMED-CYBERNET-HOST",
                    "ObservedSerial": "CYB-SERIAL-002",
                    "ObservedMACs": "AA:BB:CC:DD:EE:11",
                    "TransportUsed": "WMI",
                    "IdentityStatus": "IdentityCollected",
                    "Notes": "offline fixture",
                }
            ],
            [
                "Timestamp",
                "Target",
                "ResolvedAddress",
                "PingStatus",
                "DnsName",
                "ObservedHostName",
                "ObservedSerial",
                "ObservedMACs",
                "TransportUsed",
                "IdentityStatus",
                "Notes",
            ],
        )

        run(
            [
                "bash",
                "survey/sas-live-serial-probe.sh",
                "--manifest",
                to_wsl_path(manifest),
                "--identity-csv",
                to_wsl_path(identity),
                "--output",
                to_wsl_path(output),
                "--no-dashboard",
            ]
        )

        row = read_first_row(output)
        assert row["target"] == "CYB-SERIAL-002"
        assert row["expected_hostname"] == "OLD-CYBERNET-HOST"
        assert row["resolved_hostname"] == "RENAMED-CYBERNET-HOST"
        assert row["resolved_serial"] == "CYB-SERIAL-002"
        assert row["classification"] == "identity_resolved"
        assert row["identity_drift_status"] == "hostname_drift"
        assert row["log_status"] == "hostname_drift"


if __name__ == "__main__":
    test_manifest_builder_prefers_serial_over_hostname()
    test_cybernet_collector_keeps_serial_as_target_and_hostname_as_probe_hint()
    test_cybernet_collector_reports_serial_only_rows_without_crashing()
    test_live_serial_probe_resolves_by_serial_before_hostname()
    print("offline serial-first identity tests passed")
