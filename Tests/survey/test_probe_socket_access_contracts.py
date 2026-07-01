#!/usr/bin/env python3
"""Static contracts for probe/socket access boundaries.

This test turns the low-noise operational posture into an enforceable code gate:
raw socket/probe-library access must stay behind approved SysAdminSuite wrapper
surfaces. New network probe code should fail here until it is intentionally
scoped, reviewed, and wired through the same low-noise controls.
"""
from __future__ import annotations

from pathlib import Path
import re
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]

CODE_SUFFIXES = {".go", ".py", ".sh", ".ps1", ".psm1", ".cmd", ".bat"}
SCAN_ROOTS = (
    ROOT / "survey",
    ROOT / "probe" / "packet-expenditure",
)

# These files are the only approved places where packet/probe execution or probe
# binary availability may be assembled in the active survey lane. They are not
# blanket approval for broad scanning; each surface still has to preserve
# low-noise profile controls and local-only evidence behavior.
APPROVED_PROBE_SURFACES = {
    "survey/sas-ensure-naabu.sh",
    "survey/sas-naabu-profile-command.sh",
    "survey/sas-run-naabu-pipeline.sh",
    "survey/sas-run-packet-probe.sh",
    "survey/sas-network-preflight.ps1",
    "survey/sas-cybernet-subnet-survey.sh",
    "survey/sas-run-naabu-scan.sh",
    "probe/packet-expenditure/cmd/sas-packet-probe/main.go",
    "probe/packet-expenditure/internal/runner/cli.go",
    "probe/packet-expenditure/internal/runner/library_naabu.go",
}

RAW_SOCKET_ACCESS_PATTERNS = [
    # Go direct socket primitives or raw packet libraries.
    re.compile(r"\bnet\.(?:Dial|DialContext|DialTimeout|Listen|ListenPacket|ListenTCP|ListenUDP)\s*\("),
    re.compile(r"\b(?:syscall|unix)\.Socket\s*\("),
    re.compile(r"golang\.org/x/net/(?:icmp|ipv4|ipv6)"),
    re.compile(r"github\.com/(?:google/gopacket|mdlayher/raw|mdlayher/packet|projectdiscovery/naabu)"),
    # Python direct socket or packet/probe libraries. DNS resolution helpers are
    # intentionally not treated as raw socket ownership in this first gate.
    re.compile(r"\bsocket\.(?:socket|create_connection)\s*\("),
    re.compile(r"\b(?:import|from)\s+scapy\b"),
    re.compile(r"\bnmap\.PortScanner\s*\("),
]

REQUIRED_SURFACE_FRAGMENTS = {
    "survey/sas-ensure-naabu.sh": [
        "Config/cybernet-naabu-profiles.json",
        "--dry-run",
        "NAABU_VERSION",
        "BIN_DIR",
        "download_naabu_windows",
    ],
    "survey/sas-naabu-profile-command.sh": [
        "Render-only. This script never executes naabu and never touches target hosts.",
        "survey/naabu_profiles.json",
        "--profile",
        "--list must be under logs/targets/",
        "print(\" \".join(argv))",
    ],
    "survey/sas-run-packet-probe.sh": [
        "Enforced low-noise Naabu packet probe wrapper",
        "--site",
        "--list",
        "--out",
        "--profile",
        "--dry-run",
        "building sas-packet-probe",
    ],
    "probe/packet-expenditure/cmd/sas-packet-probe/main.go": [
        "profile.Validate()",
        "targets.Load",
        "AuditCLI",
        "writeDrySummary",
        "runner.Run",
        "OK_NAABU_PACKET_PROBE_PLANNED",
    ],
    "probe/packet-expenditure/internal/runner/cli.go": [
        "BuildArgv",
        '"-ec"',
        '"-json"',
        '"-silent"',
        '"-duc"',
        "exec.CommandContext",
        "ingestNaabuJSONL",
    ],
    "probe/packet-expenditure/internal/runner/library_naabu.go": [
        "//go:build naabu_lib",
        "HostsFile",
        "Silent:",
        "ExcludeCDN:",
        "DisableUpdateCheck:",
        "OnResult",
    ],
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def iter_code_files() -> Iterable[Path]:
    for root in SCAN_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in CODE_SUFFIXES:
                continue
            yield path


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {rel(path)}"
    return path.read_text(encoding="utf-8")


def strip_comment_only_lines(text: str) -> str:
    kept: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        kept.append(line)
    return "\n".join(kept)


def raw_socket_matches(text: str) -> list[str]:
    searchable = strip_comment_only_lines(text)
    return [pattern.pattern for pattern in RAW_SOCKET_ACCESS_PATTERNS if pattern.search(searchable)]


def test_raw_socket_access_is_restricted_to_approved_surfaces():
    violations: list[str] = []
    for path in iter_code_files():
        text = read(path)
        matches = raw_socket_matches(text)
        if not matches:
            continue
        relative = rel(path)
        if relative not in APPROVED_PROBE_SURFACES:
            violations.append(f"{relative}: {', '.join(matches)}")

    assert not violations, (
        "raw socket/probe-library access must stay behind approved low-noise wrappers; "
        "new probe surfaces require explicit review and allowlisting:\n" + "\n".join(violations)
    )


def test_approved_probe_surfaces_keep_low_noise_controls_visible():
    missing: list[str] = []
    for relative, fragments in REQUIRED_SURFACE_FRAGMENTS.items():
        text = read(ROOT / relative)
        for fragment in fragments:
            if fragment not in text:
                missing.append(f"{relative}: {fragment}")

    assert not missing, (
        "approved probe/socket surfaces must preserve visible low-noise controls:\n"
        + "\n".join(missing)
    )


def test_socket_access_contract_names_the_operator_boundary():
    posture = read(ROOT / "docs" / "OPERATIONAL_POSTURE.md")
    low_noise = read(ROOT / "docs" / "LOW_NOISE_SURVEY_DOCTRINE.md")
    agents = read(ROOT / "AGENTS.md")

    required = [
        "It is not stealth, evasion, log suppression, or hiding activity.",
        "This project uses \"low-noise survey discipline,\" not \"stealth.\"",
        "Do not attempt to bypass monitoring, evade security tools, hide activity, or defeat logging.",
        "Use \"low-noise survey discipline\" language.",
    ]
    combined = "\n".join([posture, low_noise, agents])
    for fragment in required:
        assert fragment in combined, f"operator boundary wording missing: {fragment}"


if __name__ == "__main__":
    test_raw_socket_access_is_restricted_to_approved_surfaces()
    test_approved_probe_surfaces_keep_low_noise_controls_visible()
    test_socket_access_contract_names_the_operator_boundary()
