#!/usr/bin/env python3
"""Contracts for SystemRescue NVMe forensics and portable field-kit tooling."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "recovery" / "systemrescue" / "sas-recovery.sh"
FORENSICS = ROOT / "recovery" / "systemrescue" / "lib" / "forensics.sh"
QR = ROOT / "recovery" / "systemrescue" / "lib" / "qr.sh"
EXPORT = ROOT / "recovery" / "systemrescue" / "export-field-kit.sh"
VERIFY = ROOT / "recovery" / "systemrescue" / "verify-field-kit.sh"
DOC = ROOT / "recovery" / "systemrescue" / "NVME_FORENSICS.md"
START = ROOT / "START-HERE-SYSTEMRESCUE-RECOVERY.md"

FILES = (RUNNER, FORENSICS, QR, EXPORT, VERIFY, DOC, START)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*args],
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
    )


def test_shell_files_parse_and_runner_exposes_forensics() -> None:
    for path in (RUNNER, FORENSICS, QR, EXPORT, VERIFY):
        result = run("bash", "-n", str(path))
        assert result.returncode == 0, f"{path}: {result.stderr}"

    help_result = run("bash", str(RUNNER), "--help")
    assert help_result.returncode == 0, help_result.stderr
    for command in ("nvme-baseline", "nvme-read-repro", "forensics-qr-catalog"):
        assert command in help_result.stdout, command


def test_read_reproduction_is_source_read_only_and_self_postmorteming() -> None:
    text = read(FORENSICS)
    for marker in (
        'require_source_not_mounted "$source"',
        'blockdev --setro "$source"',
        'require_ro_block "$source"',
        'ddrescue -f -n "$source" /dev/null "$workdir/read-repro.map"',
        'printf \'%s\\n\' "$rc" > "$workdir/ddrescue.exit"',
        '"$workdir/kernel-delta.txt"',
        'DEVICE_NODE_PRESENT_AFTER=',
        'DEVICE_SIZE_QUERY_AFTER=',
        'RESULT_CAPTURED=YES',
    ):
        assert marker in text, marker

    for forbidden in (
        "blockdev --setrw",
        "mount -o rw",
        "ntfsfix",
        "chkdsk",
        "bootrec",
        "repair-bde",
        "manage-bde -off",
    ):
        assert forbidden not in text.lower(), forbidden


def test_reproduction_classifies_controller_loss_without_automatic_retry() -> None:
    text = read(FORENSICS)
    for marker in (
        "NVME_RESET_FAILURE_REPRODUCED",
        "NVME_RESET_NOT_READY",
        "NVME_TIMEOUT_OR_RESET",
        "BLOCK_IO_FAILURE_WITHOUT_RESET",
        "SEQUENTIAL_READ_COMPLETED",
        "DDRESCUE_EXIT_UNCLASSIFIED",
        "Device not ready; aborting reset",
        "Disabling device after reset failure",
        "reset controller",
        "Buffer I/O error on dev .*nvme",
    ):
        assert marker in text, marker
    assert text.count("ddrescue -f -n") == 1
    assert "while true" not in text
    assert "reboot" not in text.lower()
    assert "poweroff" not in text.lower()


def test_forensic_terminal_output_has_an_executable_viewport_gate() -> None:
    text = read(FORENSICS)
    assert "FORENSIC_VIEWPORT_LINES=20" in text
    assert 'lines=$(wc -l < "$file")' in text
    assert 'forensic summary has $lines lines; viewport limit is $FORENSIC_VIEWPORT_LINES' in text
    assert text.count('forensic_print_summary "$workdir/') >= 2
    assert 'cat "$workdir/dmesg' not in text
    assert 'cat "$workdir/kernel-delta' not in text

    doc = read(DOC).lower()
    for marker in (
        "transport budget",
        "observable viewport budget",
        "verbose output is written to files",
        "one diagnostic",
    ):
        assert marker in doc, marker


def test_forensics_qr_catalog_is_short_pointer_only_and_loop_free() -> None:
    result = run(
        "bash",
        str(RUNNER),
        "forensics-qr-catalog",
        "--repo-mount",
        "/mnt/sas",
        "--source",
        "/dev/nvme0n1",
        "--expect-model",
        "Example NVMe 2TB",
        "--expect-serial",
        "SERIAL123",
        "--workdir",
        "/tmp/sas-case",
        "--max-chars",
        "240",
    )
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    counts = [int(line.split("=", 1)[1]) for line in lines if line.startswith("QR_F") and "_CHARS=" in line]
    assert len(counts) == 3, result.stdout
    assert max(counts) <= 240

    commands = []
    for index, line in enumerate(lines):
        if line.startswith("QR_F") and "_CHARS=" in line:
            commands.append(lines[index + 1])
    assert len(commands) == 3
    for command in commands:
        assert len(command) <= 240
        lowered = command.lower()
        for forbidden in ("while ", "for ", " do ", " done", "base64", "h4si"):
            assert forbidden not in lowered, (forbidden, command)
    assert any("nvme-baseline" in command for command in commands)
    assert any("nvme-read-repro" in command for command in commands)


def test_field_kit_export_is_verified_and_never_silently_overwrites() -> None:
    with tempfile.TemporaryDirectory() as temp:
        target = Path(temp)
        first = run("bash", str(EXPORT), "--target-root", str(target))
        assert first.returncode == 0, first.stderr
        kit = target / "sas-systemrescue-field-kit"
        assert (kit / "MANIFEST.sha256").is_file()
        assert (kit / "recovery" / "systemrescue" / "sas-recovery.sh").is_file()
        assert (kit / "recovery" / "systemrescue" / "lib" / "forensics.sh").is_file()

        verified = run("bash", str(kit / "recovery" / "systemrescue" / "verify-field-kit.sh"))
        assert verified.returncode == 0, verified.stderr
        assert "FIELD_KIT_VERIFY=PASS" in verified.stdout

        second = run("bash", str(EXPORT), "--target-root", str(target))
        assert second.returncode != 0
        assert "refusing overwrite" in second.stderr


def test_public_forensics_lane_contains_no_private_case_identity() -> None:
    combined = "\n".join(read(path) for path in FILES)
    lowered = combined.lower()
    for forbidden in (
        "pmr367w100205p2702",
        "00000000nt176xle",
        "drive.google.com",
        "docs.google.com",
        "14134176",
        "st-b42970y1418",
    ):
        assert forbidden not in lowered, forbidden

    for marker in (
        "CONFIRMED MODEL",
        "CONFIRMED SERIAL",
        "privacy",
        "private",
    ):
        assert marker.lower() in lowered, marker


def test_start_here_routes_to_forensics_and_portable_kit() -> None:
    start = read(START)
    assert "NVME_FORENSICS.md" in start
    assert "export-field-kit.sh" in start
    assert "read-only" in start.lower()


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: SystemRescue NVMe forensics contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
