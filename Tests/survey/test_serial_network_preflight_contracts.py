#!/usr/bin/env python3
"""Offline/static contracts for serial-first network preflight.

The user-facing phrase is "ping the network for these serials", but serials are
not probe targets. This contract ensures the wrapper stages only host/IP targets
and routes serial-only or ambiguous rows to review before delegating to the
existing network preflight script. It also requires a provenance manifest so the
serial input, enrichment files, staged probe CSV, review CSV, summary, and
network-preflight output directory are tied together as one auditable artifact chain.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "survey" / "sas-network-preflight-by-serial.ps1"
RUNNER = ROOT / "tests" / "survey" / "run_offline_survey_tests.sh"


def read(path: Path) -> str:
    assert path.exists(), f"missing expected file: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8")


def test_serial_network_preflight_wrapper_exists_and_uses_target_intake():
    text = read(SCRIPT)
    required = [
        "Resolve approved serial lists to probe-ready hostnames/IPs",
        "scripts/SasTargetIntake.psm1",
        "Import-Module $targetIntakeModule -Force",
        "Assert-SasApprovedInputPath -Path $SerialFile",
        "-Role 'serial network preflight input'",
        "Assert-SasApprovedInputPath -Path $path",
        "-Role 'serial hostname enrichment input'",
        "Assert-SasApprovedOutputPath -Path $outputDirectoryFull",
        "Test-SasPathUnderRoot -Path $stagingDirectoryFull -Root $roots.StagingRoot",
        "Join-Path (Join-Path $roots.OutputRoots[0] 'serial_network_preflight')",
        "Join-Path (Join-Path $roots.StagingRoot 'serial_network_preflight')",
    ]
    for fragment in required:
        assert fragment in text, f"missing serial preflight wrapper fragment: {fragment}"


def test_serial_network_preflight_requires_resolution_before_probe():
    text = read(SCRIPT)
    required = [
        "[string]$SerialFile",
        "[string[]]$EnrichmentCsv",
        "function Read-SerialRequestRows",
        "function Read-EnrichmentMap",
        "function Select-UniqueProbeCandidateRecords",
        "function Test-ProbeReadyTargetValue",
        "REVIEW_REQUIRED_SERIAL_ONLY",
        "REVIEW_REQUIRED_MULTIPLE_HOSTNAMES",
        "REVIEW_REQUIRED_NO_PROBE_READY_HOST",
        "Serial-only rows are review-required; a serial cannot be pinged",
        "the wrapper will not arbitrarily pick one",
        "to_probe_targets.csv",
        "review_required.csv",
        "serial_network_preflight_summary.json",
        "serials_resolve_to_exactly_one_hostname_or_ip_before_network_preflight",
    ]
    for fragment in required:
        assert fragment in text, f"serial resolution contract missing: {fragment}"


def test_serial_network_preflight_preserves_candidate_source_traceability():
    text = read(SCRIPT)
    required = [
        "HostName = $host",
        "Source = ([string]$candidate.Source)",
        "$selected = $probeReadyRecords[0]",
        "Source = [string]$selected.Source",
        "RequestSource = $request.Source",
    ]
    for fragment in required:
        assert fragment in text, f"serial enrichment source traceability missing: {fragment}"


def test_serial_network_preflight_groups_duplicate_serial_candidates():
    text = read(SCRIPT)
    required = [
        "Duplicate serial direct hostnames are included in the same candidate set",
        "foreach ($peer in $requests | Where-Object",
        "$_.NormalizedSerial -eq $request.NormalizedSerial",
        "$candidates.Add([pscustomobject]@{ HostName = $peer.DirectHostName; Source = $peer.Source })",
        "$probeReady.Count -gt 1",
        "REVIEW_REQUIRED_MULTIPLE_HOSTNAMES",
    ]
    for fragment in required:
        assert fragment in text, f"duplicate serial grouping contract missing: {fragment}"


def test_serial_artifact_manifest_links_inputs_to_outputs():
    text = read(SCRIPT)
    required = [
        "artifact_manifest.json",
        "function Get-FileSha256",
        "Get-FileHash -LiteralPath $Path -Algorithm SHA256",
        "function New-FileArtifactRecord",
        "function New-DirectoryArtifactRecord",
        "protocol_version = 'serial-artifact-provenance/v1'",
        "artifact_chain_invariant",
        "serial_input_hashes_plus_enrichment_hashes_produce_staged_probe_targets_or_review_required_rows_before_any_network_preflight_artifact",
        "input_artifacts",
        "generated_artifacts",
        "serial_file_sha256",
        "hostname_enrichment_input",
        "staged_probe_targets",
        "review_required_serials",
        "run_summary",
        "network_preflight_output_directory",
        "live_evidence_commit_policy",
        "Artifact manifest:",
    ]
    for fragment in required:
        assert fragment in text, f"serial artifact provenance fragment missing: {fragment}"


def test_serial_protocol_decision_fields_are_explicit():
    text = read(SCRIPT)
    required = [
        "$protocolLayer = 'fallback_review'",
        "$protocolDecision = 'no_network_probe'",
        "$protocolReason = 'no_probe_ready_targets'",
        "$primaryProtocolApplied = $false",
        "$fallbackProtocolApplied = $true",
        "$tertiaryManifestWritten = $true",
        "$protocolLayer = 'primary_probe'",
        "$protocolDecision = 'delegated_network_preflight'",
        "$protocolReason = 'probe_ready_targets_present'",
        "$protocolLayer = 'dry_run_plan'",
        "$protocolReason = 'plan_only_requested_with_probe_ready_targets'",
        "protocol_decision_record = $protocolDecisionRecord",
        "protocol_layer = $protocolLayer",
        "protocol_decision = $protocolDecision",
        "protocol_reason = $protocolReason",
        "primary_protocol_applied = $primaryProtocolApplied",
        "fallback_protocol_applied = $fallbackProtocolApplied",
        "tertiary_manifest_written = $tertiaryManifestWritten",
        "Protocol layer:",
        "Protocol decision:",
        "Protocol reason:",
    ]
    for fragment in required:
        assert fragment in text, f"serial protocol decision fragment missing: {fragment}"


def test_serial_network_preflight_delegates_network_activity_to_existing_preflight():
    text = read(SCRIPT)
    assert "sas-network-preflight.ps1" in text
    assert "& $networkPreflightScript -TargetFile $toProbePath" in text
    assert "[switch]$PlanOnly" in text
    assert "network_activity_performed" in text

    direct_network_patterns = [
        r"\bTest-Connection\b",
        r"\bTest-NetConnection\b",
        r"\bResolve-DnsName\b",
        r"\bnmap\b",
        r"\bnaabu\b",
    ]
    for pattern in direct_network_patterns:
        assert not re.search(pattern, text, flags=re.IGNORECASE), f"wrapper performs direct network activity instead of delegating: {pattern}"


def test_serial_network_preflight_has_no_ad_or_target_mutation():
    text = read(SCRIPT)
    unsafe_patterns = [
        r"\bSet-AD\w+\b",
        r"\bNew-AD\w+\b",
        r"\bRemove-AD\w+\b",
        r"\bDisable-AD\w+\b",
        r"\bEnable-AD\w+\b",
        r"\bMove-AD\w+\b",
        r"\bInvoke-Command\b",
        r"\bEnter-PSSession\b",
        r"\bStart-Process\b",
        r"\b" + "audit" + r"pol\b",
        r"\b" + "wev" + r"tutil\s+cl\b",
        r"\b" + "Clear-" + r"Event" + r"Log\b",
    ]
    for pattern in unsafe_patterns:
        assert not re.search(pattern, text, flags=re.IGNORECASE), f"unsafe mutation or telemetry-tampering pattern present: {pattern}"


def test_offline_runner_wires_serial_network_preflight_contract():
    runner = read(RUNNER)
    assert "test_serial_network_preflight_contracts.py" in runner


if __name__ == "__main__":
    test_serial_network_preflight_wrapper_exists_and_uses_target_intake()
    test_serial_network_preflight_requires_resolution_before_probe()
    test_serial_network_preflight_preserves_candidate_source_traceability()
    test_serial_network_preflight_groups_duplicate_serial_candidates()
    test_serial_artifact_manifest_links_inputs_to_outputs()
    test_serial_protocol_decision_fields_are_explicit()
    test_serial_network_preflight_delegates_network_activity_to_existing_preflight()
    test_serial_network_preflight_has_no_ad_or_target_mutation()
    test_offline_runner_wires_serial_network_preflight_contract()
