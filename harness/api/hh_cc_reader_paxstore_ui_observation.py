"""Thin PAXSTORE Terminal Management UI observation ingest seam (read-only).

Call stack (success):
  CLI / CMD
    -> ingest_ui_observation(...)
    -> identity bind (serial, optional MAC)
    -> map Installed Firmware display value -> observation packet
    -> optional freeze_baseline via round-trip seam

Never invents firmware. Never pushes firmware. Operator captures UI fields into
a private JSON file; this seam only validates, maps, and optionally freezes.

Version-domain note: PAXSTORE UI Installed Firmware is a display-name domain and
MUST NOT be silently rewritten to the campaign target string 2.0.15.260522.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_roundtrip import freeze_baseline, resolve_target_identity
from harness.api.hh_cc_reader_paxstore_terminal_observe import (
    VERSION_DOMAIN,
    to_baseline_observation,
)

SCHEMA = "sas-hh-cc-reader-paxstore-ui-observation/v1"
SURFACE = "paxstore_terminal_ui_app_firmware"
MECHANISM_ID = "paxstore-terminal-management-ui"
YES_NO_UNKNOWN = frozenset({"YES", "NO", "UNKNOWN"})
CAMPAIGN_TARGET = "2.0.15.260522"


def _norm_mac(value: Any) -> str | None:
    if value is None:
        return None
    text = "".join(ch for ch in str(value).upper() if ch.isalnum())
    return text or None


def _norm_text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    return text or None


def _tri_state(value: Any, *, default: str = "UNKNOWN") -> str:
    text = _norm_text(value)
    if text is None:
        return default
    upper = text.upper()
    if upper in YES_NO_UNKNOWN:
        return upper
    return default


def map_ui_capture(
    capture: dict[str, Any],
    *,
    expected_serial: str | None = None,
    expected_mac: str | None = None,
) -> dict[str, Any]:
    """Map operator-captured Terminal Management fields to an observation receipt."""
    # Serial/MAC must come from the UI capture; expected_* are bind checks only.
    serial = _norm_text(capture.get("serial") or capture.get("source_serial"))
    expected_serial_n = _norm_text(expected_serial)
    expected_mac_n = _norm_mac(
        expected_mac if expected_mac is not None else capture.get("expected_mac")
    )
    returned_mac = _norm_mac(capture.get("mac") or capture.get("returned_mac") or capture.get("live_mac"))
    firmware_name = _norm_text(
        capture.get("installed_firmware")
        or capture.get("current_firmware_value")
        or capture.get("installedFirmware")
    )

    reasons: list[str] = []
    if not serial:
        reasons.append("capture_missing_serial")
    elif expected_serial_n and serial != expected_serial_n:
        reasons.append("serial_mismatch")
    if expected_mac_n and not returned_mac:
        reasons.append("capture_missing_mac")
    elif expected_mac_n and returned_mac and returned_mac != expected_mac_n:
        reasons.append("mac_mismatch")

    identity_bound = not reasons and bool(serial)
    access_state = (
        "OBSERVED"
        if identity_bound and firmware_name
        else ("IDENTITY_MISMATCH" if reasons else "FIRMWARE_FIELD_ABSENT")
    )

    target_visible = _tri_state(capture.get("target_package_visible"))
    restorable = _tri_state(capture.get("current_package_restorable"))
    package_id = _norm_text(capture.get("target_package_id"))
    package_version = _norm_text(capture.get("target_package_version"))
    if (
        target_visible == "YES"
        and package_id
        and package_version == CAMPAIGN_TARGET
    ):
        package_mapping = "PROVEN"
    elif target_visible == "YES":
        package_mapping = "PARTIAL"
    else:
        package_mapping = "UNPROVEN"

    return {
        "schema": SCHEMA,
        "artifact": "paxstore-ui-terminal-observation",
        "access_state": access_state,
        "identity_bound": identity_bound,
        "identity_rejection_reasons": reasons,
        "source_serial": serial,
        "expected_serial": expected_serial_n or serial,
        "returned_mac": returned_mac,
        "expected_mac": expected_mac_n,
        "model_name": _norm_text(capture.get("model_name") or capture.get("model")),
        "terminal_name": _norm_text(capture.get("terminal_name") or capture.get("name")),
        "tid": _norm_text(capture.get("tid")),
        "terminal_status": _norm_text(capture.get("terminal_status") or capture.get("status")),
        "last_access_time": capture.get("last_access_time"),
        "current_firmware_value": firmware_name,
        "firmware_install_time": capture.get("firmware_install_time")
        or capture.get("install_time"),
        "version_domain": VERSION_DOMAIN,
        "version_domain_note": (
            "PAXSTORE UI Installed Firmware is not automatically equal to "
            f"campaign target {CAMPAIGN_TARGET}; map domains explicitly before eligibility."
        ),
        "mutation_performed": False,
        "network_contacted": False,
        "credential_state": "UI_OPERATOR_CAPTURE",
        "mechanism_id": MECHANISM_ID,
        "surface": SURFACE,
        "package_mapping": {
            "state": package_mapping,
            "target_package_visible": target_visible,
            "target_package_id": package_id,
            "target_package_version": package_version,
            "campaign_target": CAMPAIGN_TARGET,
        },
        "restore_disposition": {
            "current_package_restorable": restorable,
            "restorable_package_id": _norm_text(capture.get("restorable_package_id")),
        },
        "freshness_notes": _norm_text(capture.get("freshness_notes")),
    }


def compare_ui_api_parity(
    ui_receipt: dict[str, Any],
    api_receipt: dict[str, Any],
) -> dict[str, Any]:
    """Compare UI and API observation receipts without choosing a winner on divergence."""
    ui_serial = _norm_text(ui_receipt.get("source_serial"))
    api_serial = _norm_text(api_receipt.get("source_serial"))
    ui_mac = _norm_mac(ui_receipt.get("returned_mac"))
    api_mac = _norm_mac(api_receipt.get("returned_mac"))
    ui_fw = _norm_text(ui_receipt.get("current_firmware_value"))
    api_fw = _norm_text(api_receipt.get("current_firmware_value"))
    ui_status = _norm_text(ui_receipt.get("terminal_status"))
    api_status = _norm_text(api_receipt.get("terminal_status") or api_receipt.get("status"))
    ui_last = ui_receipt.get("last_access_time")
    api_last = api_receipt.get("last_access_time") or api_receipt.get("lastAccessTime")
    ui_bound = ui_receipt.get("identity_bound") is True
    api_bound = api_receipt.get("identity_bound") is True

    identity_parity = "FAIL"
    if ui_bound and api_bound and ui_serial and api_serial and ui_serial == api_serial:
        if ui_mac and api_mac and ui_mac != api_mac:
            identity_parity = "FAIL"
        elif ui_mac and api_mac and ui_mac == api_mac:
            identity_parity = "PASS"
        elif not ui_mac or not api_mac:
            identity_parity = "INCOMPLETE"
        else:
            identity_parity = "PASS"

    if ui_fw and api_fw:
        firmware_parity = "PASS" if ui_fw == api_fw else "FAIL"
    else:
        firmware_parity = "INCOMPLETE"

    status_parity = "UNKNOWN"
    if ui_status and api_status:
        status_parity = "PASS" if ui_status == api_status else "FAIL"

    checkin_parity = "UNKNOWN"
    if ui_last is not None and api_last is not None:
        checkin_parity = "PASS" if str(ui_last) == str(api_last) else "FAIL"

    divergences: list[str] = []
    if identity_parity == "FAIL":
        divergences.append("identity")
    if firmware_parity == "FAIL":
        divergences.append("installed_firmware")
    if status_parity == "FAIL":
        divergences.append("terminal_status")
    if checkin_parity == "FAIL":
        divergences.append("last_access_time")

    if divergences:
        overall = "DIVERGENCE"
    elif identity_parity == "PASS" and firmware_parity == "PASS":
        # STATUS/CHECKIN may remain UNKNOWN until API maps those fields.
        overall = "PASS"
    else:
        overall = "INCOMPLETE"

    return {
        "schema": "sas-hh-cc-reader-paxstore-ui-api-parity/v1",
        "artifact": "paxstore-ui-api-parity",
        "IDENTITY_PARITY": identity_parity,
        "FIRMWARE_PARITY": firmware_parity,
        "STATUS_PARITY": status_parity,
        "CHECKIN_PARITY": checkin_parity,
        "overall": overall,
        "divergences": divergences,
        "ui_serial": ui_serial,
        "api_serial": api_serial,
        "ui_mac": ui_mac,
        "api_mac": api_mac,
        "ui_firmware": ui_fw,
        "api_firmware": api_fw,
        "resolution_rule": (
            "On DIVERGENCE do not guess which surface wins; "
            "inspect timestamps and refresh/sync state before mutation. "
            "STATUS/CHECKIN UNKNOWN does not grant PASS by itself."
        ),
        "mutation_performed": False,
    }


def ingest_ui_observation(
    capture: dict[str, Any],
    *,
    expected_serial: str | None = None,
    expected_mac: str | None = None,
    live_ipv4: str | None = None,
    probe_mac_match: bool = True,
    freeze: bool = False,
    source_name: str | None = "Kiosk4",
) -> dict[str, Any]:
    """Ingest a Terminal Management UI capture and optionally freeze baseline."""
    mapped = map_ui_capture(
        capture,
        expected_serial=expected_serial,
        expected_mac=expected_mac,
    )
    ipv4 = _norm_text(live_ipv4) or _norm_text(capture.get("live_ipv4") or capture.get("ip"))

    if freeze and mapped.get("identity_bound") and mapped.get("current_firmware_value"):
        observation = to_baseline_observation(
            mapped,
            live_ipv4=ipv4,
            probe_mac_match=probe_mac_match,
            source_name=source_name or _norm_text(capture.get("source_name")) or "Kiosk4",
        )
        identity = resolve_target_identity(observation)
        baseline = freeze_baseline(observation, identity)
        mapped["baseline"] = {
            "state": baseline.get("state"),
            "baseline_locked": baseline.get("baseline_locked"),
            "missing_fields": baseline.get("missing_fields"),
            "current_firmware_value": baseline.get("current_firmware_value"),
            "version_domain": VERSION_DOMAIN,
        }
        mapped["identity_resolution"] = {
            "state": identity.get("state"),
            "unique_target": identity.get("unique_target"),
        }
    return mapped


def _write_receipt(payload: dict[str, Any], output: Path | None) -> Path:
    out_dir = ROOT / "survey" / "output" / "hh-cc-reader"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = output or (
        out_dir / f"hh-cc-reader-paxstore-ui-observe-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Ingest read-only PAXSTORE Terminal Management UI observation."
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Private UI capture JSON (Installed Firmware + identity fields)",
    )
    parser.add_argument("--expected-serial", default=None, help="Optional serial bind override")
    parser.add_argument("--expected-mac", default=None, help="Optional MAC bind override")
    parser.add_argument("--live-ipv4", default=None, help="Optional live IPv4 for baseline freeze")
    parser.add_argument(
        "--freeze",
        action="store_true",
        help="If observation is identity-bound with firmware, run freeze_baseline",
    )
    parser.add_argument("--output", default=None, help="Receipt path (ignored survey/output by default)")
    parser.add_argument(
        "--compare-api",
        default=None,
        help="Optional API observe receipt JSON for UI/API parity comparison",
    )
    args = parser.parse_args(argv)

    capture = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
    result = ingest_ui_observation(
        capture,
        expected_serial=args.expected_serial,
        expected_mac=args.expected_mac,
        live_ipv4=args.live_ipv4,
        freeze=args.freeze,
    )

    if args.compare_api:
        api_receipt = json.loads(Path(args.compare_api).read_text(encoding="utf-8-sig"))
        result["parity"] = compare_ui_api_parity(result, api_receipt)

    path = _write_receipt(result, Path(args.output) if args.output else None)
    print(json.dumps(result, indent=2))
    print(f"RECEIPT={path}", file=sys.stderr)

    if result.get("access_state") == "OBSERVED" and result.get("current_firmware_value"):
        if args.freeze and not (result.get("baseline") or {}).get("baseline_locked"):
            return 4
        if args.compare_api:
            overall = (result.get("parity") or {}).get("overall")
            if overall == "DIVERGENCE":
                return 5
            if overall != "PASS":
                return 6
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
