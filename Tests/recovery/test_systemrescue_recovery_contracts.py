#!/usr/bin/env python3
"""Contracts for the guarded SystemRescue disk-recovery harness."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "recovery" / "systemrescue" / "sas-recovery.sh"
README = ROOT / "recovery" / "systemrescue" / "README.md"
START = ROOT / "START-HERE-SYSTEMRESCUE-RECOVERY.md"
LIB_DIR = ROOT / "recovery" / "systemrescue" / "lib"
IMPLEMENTATION_FILES = (
    RUNNER,
    LIB_DIR / "common.sh",
    LIB_DIR / "imaging.sh",
    LIB_DIR / "extraction.sh",
    LIB_DIR / "qr.sh",
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing required file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def read_implementation() -> str:
    return "\n".join(read(path) for path in IMPLEMENTATION_FILES)


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(RUNNER), *args],
        cwd=ROOT,
        check=False,
        text=True,
        capture_output=True,
    )


def test_shell_parses_and_help_surface_is_executable() -> None:
    for path in IMPLEMENTATION_FILES:
        parsed = subprocess.run(["bash", "-n", str(path)], check=False, capture_output=True, text=True)
        assert parsed.returncode == 0, f"{path}: {parsed.stderr}"
    help_result = run("--help")
    assert help_result.returncode == 0, help_result.stderr
    for command in (
        "inventory",
        "protect-source",
        "mount-destination",
        "start-image",
        "resume-image",
        "capture-checkpoint",
        "attach-image",
        "open-bitlocker",
        "mount-ntfs",
        "audit-user-data",
        "copy-user-data",
        "cleanup",
        "qr-catalog",
    ):
        assert command in help_result.stdout, command


def test_source_and_image_layers_fail_closed_read_only() -> None:
    text = read_implementation()
    for marker in (
        "blockdev --setro",
        "require_ro_block",
        "require_source_not_mounted",
        "losetup --find --show --read-only --partscan",
        "cryptsetup open --type bitlk --readonly",
        "mount -t ntfs-3g -o ro",
        "require_mount_option \"$mountpoint\" ro",
    ):
        assert marker in text, marker


def test_new_and_resumed_imaging_have_separate_contracts() -> None:
    text = read_implementation()
    assert "new imaging requires --confirm-new-image" in text
    assert "image already exists; use resume-image" in text
    assert "mapfile already exists; use resume-image" in text
    assert "insufficient destination space" in text
    assert "require_file \"$workdir/$image\"" in text
    assert "require_file \"$workdir/$map\"" in text
    assert 'ddrescue --no-scrape --verbose "$source" "$workdir/$image" "$workdir/$map"' in text


def test_all_destination_writes_are_bound_to_the_selected_partition_and_mount() -> None:
    text = read_implementation()
    for marker in (
        "--destination-partition",
        "--destination-mount",
        'require_destination_binding "$destination_partition" "$destination_mount" "$workdir"',
        'require_destination_binding "$destination_partition" "$destination_mount" "$state_parent"',
        'require_destination_binding "$destination_partition" "$destination_mount" "$(dirname "$report")"',
        'require_destination_binding "$destination_partition" "$destination_mount" "$destination_root"',
    ):
        assert marker in text, marker
    assert 'findmnt -rn --target "$mountpoint"' not in text


def test_checkpoint_preserves_kernel_map_and_artifact_evidence() -> None:
    text = read_implementation()
    for marker in (
        'dmesg > "$workdir/dmesg-$tag.txt"',
        'ddrescuelog -t "$workdir/$map" > "$workdir/ddrescuelog-$tag.txt"',
        'ls -lah "$workdir" > "$workdir/artifacts-$tag.txt"',
        "sync",
    ):
        assert marker in text, marker


def test_user_copy_scope_is_explicit_and_verifiable() -> None:
    text = read_implementation()
    for marker in (
        "is_system_profile",
        "--exclude=/AppData/***",
        "--exclude=/NTUSER.DAT*",
        "--safe-links",
        "--ignore-errors",
        "mktemp",
        "PENDING_ITEMS=",
        "RECOVERED USER DATA COPY VERIFIED BY RSYNC DRY RUN",
        "COPY COMPLETED WITH LOGGED ITEMS REQUIRING REVIEW",
        "2>/dev/null | sort || true",
        '"${profile_bytes:-UNKNOWN}"',
    ):
        assert marker in text, marker
    assert "--delete" not in text
    assert "|'Public'|" not in text


def test_loop_state_is_atomic_and_cleanup_binds_it_to_the_expected_image() -> None:
    text = read_implementation()
    for marker in (
        r"printf 'LOOP=%s\nIMAGE=%s\n'",
        "set -o noclobber",
        "state file validation failed",
        '[[ "$loopdev" =~ ^/dev/loop[0-9]+$ ]]',
        "state image mismatch",
        "losetup --noheadings --raw --output BACK-FILE",
        "loop backing-file mismatch",
        "--loop-state-file, and --image are required",
    ):
        assert marker in text, marker


def test_forbidden_source_repair_and_secret_collection_are_absent() -> None:
    combined = "\n".join(read(path) for path in (*IMPLEMENTATION_FILES, README, START)).lower()
    for forbidden in (
        "chkdsk /f",
        "chkdsk /r",
        "ntfsfix ",
        "bootrec ",
        "manage-bde -off",
        "repair-bde",
        "diskpart clean",
        "get-credential",
    ):
        assert forbidden not in combined, forbidden


def test_qr_catalog_enforces_practical_limit_and_emits_short_pointer_commands() -> None:
    result = run(
        "qr-catalog",
        "--repo-mount", "/mnt/sas",
        "--source", "/dev/nvme0n1",
        "--expect-model", "Lexar SSD NQ700 2TB",
        "--expect-serial", "SERIAL123",
        "--destination", "/dev/sda2",
        "--destination-label", "Expansion",
        "--workdir", "/mnt/expansion/CASE",
        "--image", "disk.img",
        "--map", "disk.map",
        "--bitlocker-partition-number", "3",
        "--mode", "resume",
        "--max-chars", "240",
    )
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    counts = [int(line.split("=", 1)[1]) for line in lines if line.startswith("QR_") and "_CHARS=" in line]
    assert len(counts) == 10, counts
    assert max(counts) <= 240, counts
    assert "H4sI" not in result.stdout
    assert "base64" not in result.stdout
    assert "CONFIRM_" not in result.stdout
    assert "bash \"$R\"" in result.stdout


def test_qr_catalog_rejects_a_limit_below_generated_command_size() -> None:
    result = run(
        "qr-catalog",
        "--repo-mount", "/mnt/sas",
        "--source", "/dev/nvme0n1",
        "--expect-model", "Lexar SSD NQ700 2TB",
        "--expect-serial", "SERIAL123",
        "--destination", "/dev/sda2",
        "--destination-label", "Expansion",
        "--workdir", "/mnt/expansion/CASE",
        "--image", "disk.img",
        "--map", "disk.map",
        "--bitlocker-partition-number", "3",
        "--max-chars", "20",
    )
    assert result.returncode != 0
    assert "limit is 20" in result.stderr


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"PASS: SystemRescue recovery contracts ({len(tests)} groups)")


if __name__ == "__main__":
    main()
