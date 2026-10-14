#!/usr/bin/env python3
"""Contracts for the Admin Box ADB control-plane classifier and technician CMDs."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_adb_control_plane import (  # noqa: E402
    FORBIDDEN_ADB_TOKENS,
    command_is_allowed_readonly,
    command_is_forbidden,
    evaluate_control_plane,
    main as classify_main,
)

SEAM = ROOT / "harness/api/hh_cc_reader_adb_control_plane.py"
PS1 = ROOT / "scripts/Invoke-SasHhCcReaderAdbControlPlane.ps1"
CMDS = {
    "prepare-host": ROOT / "Prepare-HHCCReaderAdbHost.cmd",
    "probe": ROOT / "Probe-HHCCReaderAdb.cmd",
    "inventory": ROOT / "Capture-HHCCReaderAdbInventory.cmd",
    "tcpip-cert": ROOT / "Certify-HHCCReaderAdbTcpip.cmd",
    "remote-view": ROOT / "Certify-HHCCReaderRemoteView.cmd",
    "orchestrate": ROOT / "Evaluate-HHCCReaderAdbControlPlane.cmd",
}
DOC = ROOT / "docs/HH_CC_READER_ADB_ADMIN_BOX_WORKFLOW.md"
CATALOG = ROOT / "Tests/survey/fixtures/hh-cc-reader-adb-control-plane/catalog.json"
LIVE_IDS = (
    "hh-cc-reader-adb-host-prepare",
    "hh-cc-reader-adb-probe",
    "hh-cc-reader-adb-inventory-capture",
    "hh-cc-reader-adb-tcpip-certify",
    "hh-cc-reader-adb-remote-view-certify",
    "hh-cc-reader-adb-control-plane-evaluate",
)
ARTIFACT_IDS = (
    "hh-cc-reader-adb-host-readiness",
    "hh-cc-reader-adb-device-probe",
    "hh-cc-reader-adb-readonly-inventory",
    "hh-cc-reader-adb-network-live-cert",
    "hh-cc-reader-adb-remote-view-live-cert",
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing: {path.relative_to(ROOT)}"
    return path.read_text(encoding="utf-8-sig")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def test_launchers_and_registries() -> None:
    for path in CMDS.values():
        text = read(path)
        assert "hh_cc_reader_adb_control_plane.py" in text or "Invoke-SasHhCcReaderAdbControlPlane.ps1" in text
        assert "exit /b %ERRORLEVEL%" in text or "exit /b !SAS_EXIT!" in text
        assert "H^&H" in text
    ps = read(PS1)
    folded = ps.casefold()
    assert "allowlisted" in folded
    assert "fastboot" not in folded
    assert "settings put" not in folded
    assert "tcpip 5555" in folded
    assert "never subnet-scan" in folded
    live = read(ROOT / "harness/api/hh_cc_reader_adb_live.py")
    assert "install_platform_tools" in live
    assert "adb install" not in live
    assert "settings put" not in live
    commands = {item["id"]: item for item in load_json(ROOT / "harness/api/harness-command-registry.json")["commands"]}
    outcomes = {item["command_id"]: item for item in load_json(ROOT / "harness/api/harness-outcome-registry.json")["contracts"]}
    artifacts = {item["id"]: item for item in load_json(ROOT / "harness/api/harness-artifact-registry.json")["artifacts"]}
    for cid in LIVE_IDS:
        assert cid in commands, cid
        assert commands[cid]["mutation"] in {"none", "local_runtime"}
        assert cid in outcomes
        assert outcomes[cid]["success_artifact_id"] in ARTIFACT_IDS
    for aid in ARTIFACT_IDS:
        assert aid in artifacts
        assert artifacts[aid]["tracked"] is False
        assert "survey/output/hh-cc-reader/" in artifacts[aid]["path"]
    doc = read(DOC)
    assert "Prepare-HHCCReaderAdbHost.cmd" in doc
    assert "Probe-HHCCReaderAdb.cmd" in doc
    assert "MUTATION_AUTHORIZED=false" in doc.casefold() or "mutation remains unauthorized" in doc.casefold()
    assert "do not scan" in doc.casefold()
    assert "USB-HOST" in doc
    assert "RS232" in doc
    assert "OPERATOR_PHYSICAL_ATTACHMENT_CONFIRMED" in doc
    assert "WINDOWS_ANDROID_ADB_INTERFACE_ENUMERATED" in doc
    assert "USB-HOST != USB-OTG/client candidate" in doc
    assert "physical attachment != enumeration" in doc
    assert "enumeration != ADB interface" in doc
    assert "ADB interface != authorization" in doc
    assert "authorization != READY" in doc
    assert "USB_OTG_ADB_CAPABILITY absent" in doc
    assert "Manage-AdminBoxAndroidToolchain.cmd Next" in doc
    assert "ADMINBOX_PROFILE_AUTHORITY_REQUIRED" in doc
    assert "QUALIFICATION_AUTHORITY_REQUIRED" in doc
    assert "Exhausted routes are never offered again" in doc
    assert "Settings > Software versions" in doc


def test_fixture_catalog_and_no_mutation_authorization() -> None:
    catalog = load_json(CATALOG)
    seen = {item["id"] for item in catalog["cases"]}
    required = {
        "01-adb-absent",
        "02-host-ready-zero-devices",
        "03-unauthorized",
        "04-offline",
        "05-ready",
        "06-multiple",
        "07-usb-no-adb-interface",
        "08-inventory-complete",
        "09-inventory-partial",
        "10-firmware-unbound",
        "11-firmware-labeled-bind",
        "12-network-connect-success",
        "13-network-refused",
        "14-network-reverted",
        "15-network-revert-failed",
        "16-remote-view-success",
        "17-remote-view-inconclusive",
        "18-mutation-refused",
        "19-usb-not-enumerated",
        "20-usb-otg-confirmed-not-enumerated",
        "21-usb-otg-confirmed-zero-windows-clients",
        "22-usb-zero-windows-clients-unconfirmed",
        "23-probe-host-tooling-not-qualified",
    }
    assert required <= seen
    for case in catalog["cases"]:
        receipt = evaluate_control_plane(case["evidence"])
        assert receipt["mutation_authorized"] is False, case["id"]
        assert receipt["mutation_performed"] is False, case["id"]
        assert receipt["campaign_target_not_used_as_current"] is True
        assert "2.0.15.260522" not in json.dumps(receipt.get("labeled_observations") or [])
        if "expected_state" in case:
            assert receipt["state"] == case["expected_state"], (
                f"{case['id']}: {receipt['state']} != {case['expected_state']}"
            )
        if "expected_firmware" in case:
            assert receipt["firmware_evidence_state"] == case["expected_firmware"], case["id"]
        if "expected_current" in case:
            assert receipt["current_firmware_classification"] == case["expected_current"], case["id"]
        if "expected_revert" in case:
            assert receipt["network_adb_revert_state"] == case["expected_revert"], case["id"]
        if "expected_next_action_contains" in case:
            assert case["expected_next_action_contains"] in (receipt.get("next_action") or ""), case["id"]
        for forbidden in case.get("expected_next_action_not_contains") or []:
            assert forbidden not in (receipt.get("next_action") or ""), (
                f"{case['id']}: forbidden next-action text {forbidden!r}"
            )
    unauth = evaluate_control_plane(next(c["evidence"] for c in catalog["cases"] if c["id"] == "03-unauthorized"))
    assert unauth["adb_transport_present"] is True
    assert unauth["attended_retry_required"] is True
    assert unauth["screen_confirmation"] == "unobserved"
    assert "approve" in unauth["next_action"].casefold()


def test_readonly_allowlist_and_forbidden_detection() -> None:
    assert command_is_forbidden("adb root")
    assert command_is_forbidden("adb install foo.apk")
    assert command_is_forbidden("fastboot flash boot x")
    assert command_is_forbidden("adb shell settings put global adb_enabled 1")
    assert command_is_allowed_readonly("adb devices -l")
    assert command_is_allowed_readonly("adb shell getprop")
    assert command_is_allowed_readonly("adb tcpip 5555")
    assert not command_is_allowed_readonly("adb reboot")


def test_cli_fixture_emits_receipt() -> None:
    catalog = load_json(CATALOG)
    case = next(item for item in catalog["cases"] if item["id"] == "03-unauthorized")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.json"
        src.write_text(json.dumps(case["evidence"]), encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(SEAM), "--input", str(src), "--output-dir", tmp],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == 0, proc.stderr
        assert "STATE=ADB_DEVICE_UNAUTHORIZED" in proc.stdout
        assert "MUTATION_AUTHORIZED=false" in proc.stdout
        assert "NEXT_ACTION=" in proc.stdout
        receipts = list(Path(tmp).glob("hh-cc-reader-*.json"))
        assert len(receipts) == 1
        payload = json.loads(receipts[0].read_text(encoding="utf-8"))
        assert payload["schema_version"] == "sas-hh-cc-reader-adb-control-plane/v1"
        assert payload["mutation_authorized"] is False


def test_p97_successor_no_longer_forbids_authorized_adb_lane() -> None:
    plan = read(ROOT / "docs/plans/hh-cc-kiosk4-p97-capability-successor-map-20261006.plan.md")
    research = read(ROOT / "docs/research/hh-cc-kiosk4-p97-android-remote-capability-frontier-20261006.md")
    boundary = load_json(ROOT / "harness/api/hh-cc-reader-live-execution-boundary.v1.json")
    assert "ADMIN_BOX" in plan or "Admin Box" in plan
    assert "51" in plan
    assert "optional/parallel" in plan.casefold() or "optional / parallel" in plan.casefold() or "optional estate" in plan.casefold()
    assert "do not redirect" in plan.casefold() or "not a prerequisite" in plan.casefold()
    assert "CONTROL_TRANSPORT_CAPABILITY" in research
    action = boundary["current_kiosk4_example"]["next_action"]
    assert "Capture-HHCCReaderAdbInventory.cmd" in action or "Probe-HHCCReaderAdb.cmd" in action
    assert boundary["current_kiosk4_example"]["mutation_authorized"] is False
    forbidden = "\n".join(boundary["current_kiosk4_example"]["explicitly_not_next"])
    assert "prerequisite for Admin Box" in forbidden or "not a prerequisite" in action.casefold()


def test_exhausted_routes_are_never_recommended() -> None:
    """W2 regression: exhausted routes must never reappear as a suggested next action.

    Exhausted for this estate after operator-corrected evidence: USB attach/reseat
    loops once micro-USB/OTG seating is confirmed, and generic PAXSTORE account /
    reseller / app-store registration. PAXSTORE may appear only as an explicit
    prohibition. Firmware mutation tokens are never offered as next actions.
    """
    catalog = load_json(CATALOG)
    for case in catalog["cases"]:
        receipt = evaluate_control_plane(case["evidence"])
        action = (receipt.get("next_action") or "").casefold()
        for token in (
            "sign up",
            "signup",
            "create an account",
            "register",
            "reseller",
            "app store",
            "marketplace account",
        ):
            assert token not in action, f"{case['id']}: exhausted-route token {token!r} in {action!r}"
        if "paxstore" in action:
            assert any(marker in action for marker in ("do not", "never", "exhausted")), (
                f"{case['id']}: PAXSTORE must be mentioned only as a prohibition: {action!r}"
            )
        usb = case["evidence"].get("usb") if isinstance(case["evidence"].get("usb"), dict) else {}
        if usb.get("operator_otg_client_path_confirmed"):
            assert "connect the authorized kiosk4 usb cable" not in action, case["id"]
            assert "not a deployment transport" in action, case["id"]
        for token in FORBIDDEN_ADB_TOKENS:
            assert token not in action, f"{case['id']}: mutation token {token!r} offered as next action"
    # Both USB_DEVICE_NOT_ENUMERATED branches share one exhausted action source.
    cases = {case["id"]: case for case in catalog["cases"]}
    seated_zero_clients = evaluate_control_plane(cases["21-usb-otg-confirmed-zero-windows-clients"]["evidence"])
    seated_unknown_device = evaluate_control_plane(cases["20-usb-otg-confirmed-not-enumerated"]["evidence"])
    assert seated_zero_clients["next_action"] == seated_unknown_device["next_action"]
    # Unconfirmed first-seat guidance is preserved as the non-exhausted control.
    unconfirmed = evaluate_control_plane(cases["22-usb-zero-windows-clients-unconfirmed"]["evidence"])
    assert "connect the authorized kiosk4 usb cable" in unconfirmed["next_action"].casefold()


def test_blocked_host_route_is_deterministic_and_read_only() -> None:
    """A blocked Admin Box names one executable gate plus the ADB-free read-only route."""
    catalog = load_json(CATALOG)
    cases = {case["id"]: case for case in catalog["cases"]}
    for case_id in ("01-adb-absent", "23-probe-host-tooling-not-qualified"):
        receipt = evaluate_control_plane(cases[case_id]["evidence"])
        action = receipt["next_action"]
        assert "Manage-AdminBoxAndroidToolchain.cmd Next" in action, case_id
        assert "Run-SasAndroidProvider.cmd prepare" in action, case_id
        assert "--archive-sha256" in action, case_id
        assert "Classify-HHCCReaderVersionDomain.cmd" in action, case_id
        assert "Evaluate-HHCCReaderFirmwareRoundtrip.cmd" in action, case_id
        assert receipt["mutation_authorized"] is False, case_id
        assert receipt["state"] == "ADB_HOST_NOT_INSTALLED", case_id


def test_labeled_baseline_route_is_preserved_and_no_entitlement_claim() -> None:
    """Protected controls: labeled-baseline continuation, no firmware mutation, no estate entitlement."""
    catalog = load_json(CATALOG)
    cases = {case["id"]: case for case in catalog["cases"]}
    labeled = evaluate_control_plane(cases["11-firmware-labeled-bind"]["evidence"])
    assert labeled["firmware_evidence_state"] == "AUTHORITATIVE_LABELED_CANDIDATE"
    assert labeled["current_firmware_classification"] == "CURRENT_FIRMWARE_BOUND"
    assert "Classify-HHCCReaderVersionDomain.cmd" in labeled["next_action"]
    assert "Evaluate-HHCCReaderFirmwareRoundtrip.cmd" in labeled["next_action"]
    assert labeled["mutation_authorized"] is False
    for case in catalog["cases"]:
        payload = json.dumps(evaluate_control_plane(case["evidence"])).casefold()
        for claim in ("entitle", "proven_access", "estate authority granted"):
            assert claim not in payload, f"{case['id']}: unsupported claim {claim!r}"


def main() -> int:
    tests = [
        test_launchers_and_registries,
        test_fixture_catalog_and_no_mutation_authorization,
        test_readonly_allowlist_and_forbidden_detection,
        test_cli_fixture_emits_receipt,
        test_p97_successor_no_longer_forbids_authorized_adb_lane,
        test_exhausted_routes_are_never_recommended,
        test_blocked_host_route_is_deterministic_and_read_only,
        test_labeled_baseline_route_is_preserved_and_no_entitlement_claim,
    ]
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL {test.__name__}: {exc}")
    if failed:
        print(f"FAILED {failed}/{len(tests)}")
        return 1
    print(f"PASSED {len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
