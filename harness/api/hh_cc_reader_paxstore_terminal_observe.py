"""Thin PAXSTORE serial-bound terminal observation seam (read-only).

Call stack (success):
  CLI / CMD
    -> observe_terminal_by_sn(...)
    -> credential gate / injectable transport
    -> GET {base}/v1/3rdsys/terminal?serialNo&includeInstalledFirmware=true
    -> identity bind (serial, optional MAC)
    -> map installedFirmware.firmwareName -> observation packet
    -> optional freeze_baseline via round-trip seam

Never invents firmware. Never pushes firmware. Credentials come only from the
operator environment (SAS_PAXSTORE_API_KEY / SAS_PAXSTORE_API_SECRET).

Version-domain note: PAXSTORE installedFirmware.firmwareName is a PayDroid /
package-name domain and MUST NOT be silently rewritten to the campaign target
string 2.0.15.260522.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from harness.api.hh_cc_reader_firmware_roundtrip import freeze_baseline, resolve_target_identity

SCHEMA = "sas-hh-cc-reader-paxstore-terminal-observe/v1"
DEFAULT_BASE_URL = "https://api.whatspos.com/p-market-api"
TERMINAL_BY_SN_PATH = "/v1/3rdsys/terminal"
ENV_API_KEY = "SAS_PAXSTORE_API_KEY"
ENV_API_SECRET = "SAS_PAXSTORE_API_SECRET"
ENV_BASE_URL = "SAS_PAXSTORE_BASE_URL"
ENV_ESTATE_AUTHORITY = "SAS_PAXSTORE_ESTATE_AUTHORITY"
ESTATE_AUTHORITY_OWNED = "OWNED_ADMINISTERING"
VERSION_DOMAIN = "paxstore_installed_firmware_name"

Transport = Callable[[str, dict[str, str]], dict[str, Any]]


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


def credentials_from_env(environ: dict[str, str] | None = None) -> dict[str, str | None]:
    env = environ if environ is not None else os.environ
    return {
        "api_key": _norm_text(env.get(ENV_API_KEY)),
        "api_secret": _norm_text(env.get(ENV_API_SECRET)),
        "base_url": _norm_text(env.get(ENV_BASE_URL)) or DEFAULT_BASE_URL,
        "estate_authority": _norm_text(env.get(ENV_ESTATE_AUTHORITY)),
    }


def missing_credential_access_state(environ: dict[str, str] | None = None) -> str:
    """Classify missing ESI credentials by estate ownership.

    AUTHORIZED_ACCESS_SETUP_REQUIRED — operator owns/administers the marketplace
    and must enable External System Integration / bind local keys.

    CREDENTIAL_GATE — rights belong to an external owner the operator does not possess.
    """
    creds = credentials_from_env(environ)
    if creds.get("estate_authority") == ESTATE_AUTHORITY_OWNED:
        return "AUTHORIZED_ACCESS_SETUP_REQUIRED"
    return "CREDENTIAL_GATE"


def build_signed_get(
    *,
    base_url: str,
    api_key: str,
    api_secret: str,
    serial_no: str,
    timestamp_ms: int | None = None,
    include_installed_firmware: bool = True,
) -> tuple[str, dict[str, str], str]:
    """Return (url, headers, query) matching PAXSTORE ThirdPartySysApiClient signing."""
    ts = str(timestamp_ms if timestamp_ms is not None else int(time.time() * 1000))
    # Fixed order so the signed query equals the URL query (unlike JVM HashMap).
    params = [
        ("includeDetailInfoList", "false"),
        ("includeInstalledApks", "false"),
        ("includeInstalledFirmware", "true" if include_installed_firmware else "false"),
        ("includeMasterTerminal", "false"),
        ("serialNo", serial_no.strip()),
        ("sysKey", api_key),
        ("timestamp", ts),
    ]
    query = urllib.parse.urlencode(params, encoding="utf-8")
    signature = (
        hmac.new(api_secret.encode("utf-8"), query.encode("utf-8"), hashlib.sha256)
        .hexdigest()
        .upper()
    )
    base = base_url.rstrip("/")
    url = f"{base}{TERMINAL_BY_SN_PATH}?{query}"
    headers = {
        "signature": signature,
        "SDK-Language": "Python",
        "SDK-Version": "sas-hh-cc-observe/0.1",
        "Time-Zone": "UTC",
        "Accept-Language": "en-US",
    }
    return url, headers, query


def default_http_transport(url: str, headers: dict[str, str]) -> dict[str, Any]:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(detail) if detail else {}
        except json.JSONDecodeError:
            payload = {"raw": detail}
        return {
            "businessCode": exc.code,
            "message": f"HTTP_{exc.code}",
            "data": None,
            "http_error": payload,
        }
    except urllib.error.URLError as exc:
        return {
            "businessCode": 16105,
            "message": f"Cannot connect to remote server: {exc.reason}",
            "data": None,
        }


def map_terminal_payload(
    payload: dict[str, Any],
    *,
    expected_serial: str,
    expected_mac: str | None,
) -> dict[str, Any]:
    """Map a PAXSTORE Result/TerminalDTO-shaped payload to an observation receipt."""
    business = payload.get("businessCode")
    data = payload.get("data")
    if business not in (0, "0") or not isinstance(data, dict):
        return {
            "schema": SCHEMA,
            "artifact": "paxstore-terminal-observation",
            "access_state": "API_CALL_FAILED" if business not in (None, 0, "0") else "TERMINAL_NOT_FOUND",
            "business_code": business,
            "message": payload.get("message"),
            "identity_bound": False,
            "current_firmware_value": None,
            "version_domain": VERSION_DOMAIN,
            "mutation_performed": False,
        }

    returned_serial = _norm_text(data.get("serialNo"))
    returned_mac = _norm_mac(data.get("macAddress") or data.get("mac"))
    expected_serial_n = _norm_text(expected_serial)
    expected_mac_n = _norm_mac(expected_mac)

    reasons: list[str] = []
    if not returned_serial:
        reasons.append("response_missing_serialNo")
    elif expected_serial_n and returned_serial != expected_serial_n:
        reasons.append("serial_mismatch")
    if expected_mac_n and returned_mac and returned_mac != expected_mac_n:
        reasons.append("mac_mismatch")

    firmware_obj = data.get("installedFirmware") if isinstance(data.get("installedFirmware"), dict) else {}
    firmware_name = _norm_text(firmware_obj.get("firmwareName"))
    install_time = firmware_obj.get("installTime")

    identity_bound = not reasons and bool(returned_serial)
    access_state = "OBSERVED" if identity_bound and firmware_name else (
        "IDENTITY_MISMATCH" if reasons else "FIRMWARE_FIELD_ABSENT"
    )

    return {
        "schema": SCHEMA,
        "artifact": "paxstore-terminal-observation",
        "access_state": access_state,
        "business_code": business,
        "identity_bound": identity_bound,
        "identity_rejection_reasons": reasons,
        "source_serial": returned_serial,
        "expected_serial": expected_serial_n,
        "returned_mac": returned_mac,
        "expected_mac": expected_mac_n,
        "model_name": _norm_text(data.get("modelName") or data.get("model")),
        "os_version": _norm_text(data.get("osVersion")),
        "ip": _norm_text(data.get("ip")),
        "current_firmware_value": firmware_name,
        "firmware_install_time": install_time,
        "version_domain": VERSION_DOMAIN,
        "version_domain_note": (
            "PAXSTORE installedFirmware.firmwareName is not automatically equal to "
            "campaign target 2.0.15.260522; map domains explicitly before eligibility."
        ),
        "mutation_performed": False,
        "mechanism_id": "paxstore-ota-push",
        "surface": "paxstore_openapi_getTerminalBySn",
    }


def to_baseline_observation(
    observe_receipt: dict[str, Any],
    *,
    live_ipv4: str | None,
    probe_mac_match: bool,
    target_firmware_value: str = "2.0.15.260522",
    source_name: str | None = "Kiosk4",
) -> dict[str, Any]:
    """Build the offline round-trip observation packet from a PAXSTORE observe receipt."""
    mac = observe_receipt.get("expected_mac") or observe_receipt.get("returned_mac")
    return {
        "source_serial": observe_receipt.get("source_serial") or observe_receipt.get("expected_serial"),
        "source_name": source_name,
        "expected_mac": mac,
        "live_mac": observe_receipt.get("returned_mac") or mac,
        "live_ipv4": live_ipv4,
        "probe_mac_match": probe_mac_match,
        "identity_proof_state": "UNIQUE_TARGET_RESOLVED",
        "current_firmware_value": observe_receipt.get("current_firmware_value"),
        "target_firmware_value": target_firmware_value,
        "firmware_observation_source": observe_receipt.get("surface"),
        "firmware_version_domain": observe_receipt.get("version_domain"),
    }


def observe_terminal_by_sn(
    *,
    serial_no: str,
    expected_mac: str | None = None,
    live_ipv4: str | None = None,
    probe_mac_match: bool = True,
    environ: dict[str, str] | None = None,
    transport: Transport | None = None,
    fixture_payload: dict[str, Any] | None = None,
    freeze: bool = False,
) -> dict[str, Any]:
    """Observe installed firmware for one serial via PAXSTORE OpenAPI or a fixture."""
    serial = _norm_text(serial_no)
    if not serial:
        return {
            "schema": SCHEMA,
            "artifact": "paxstore-terminal-observation",
            "access_state": "INVALID_INPUT",
            "identity_bound": False,
            "current_firmware_value": None,
            "version_domain": VERSION_DOMAIN,
            "mutation_performed": False,
            "message": "serial_no required",
        }

    if fixture_payload is not None:
        mapped = map_terminal_payload(
            fixture_payload, expected_serial=serial, expected_mac=expected_mac
        )
        mapped["credential_state"] = "FIXTURE"
        mapped["network_contacted"] = False
    else:
        creds = credentials_from_env(environ)
        if not creds["api_key"] or not creds["api_secret"]:
            access_state = missing_credential_access_state(environ)
            if access_state == "AUTHORIZED_ACCESS_SETUP_REQUIRED":
                message = (
                    f"Estate authority is {ESTATE_AUTHORITY_OWNED}: enable PAXSTORE "
                    "External System Integration, then bind "
                    f"{ENV_API_KEY}/{ENV_API_SECRET} locally (optional "
                    f"{ENV_BASE_URL}; default {DEFAULT_BASE_URL}). "
                    "Missing API keys are setup work, not an external credential gate."
                )
            else:
                message = (
                    f"Set {ENV_API_KEY} and {ENV_API_SECRET} for an authorized "
                    "PAXSTORE External System read; optional "
                    f"{ENV_BASE_URL} (default {DEFAULT_BASE_URL}). "
                    f"If you own/administer this marketplace, set "
                    f"{ENV_ESTATE_AUTHORITY}={ESTATE_AUTHORITY_OWNED}."
                )
            return {
                "schema": SCHEMA,
                "artifact": "paxstore-terminal-observation",
                "access_state": access_state,
                "identity_bound": False,
                "current_firmware_value": None,
                "version_domain": VERSION_DOMAIN,
                "mutation_performed": False,
                "network_contacted": False,
                "estate_authority": creds.get("estate_authority"),
                "message": message,
                "minimum_role": "Readonly Firmware List + Terminal Management / External System Access",
                "expected_serial": serial,
                "expected_mac": _norm_mac(expected_mac),
            }

        url, headers, _query = build_signed_get(
            base_url=str(creds["base_url"]),
            api_key=str(creds["api_key"]),
            api_secret=str(creds["api_secret"]),
            serial_no=serial,
        )
        runner = transport or default_http_transport
        payload = runner(url, headers)
        mapped = map_terminal_payload(payload, expected_serial=serial, expected_mac=expected_mac)
        mapped["credential_state"] = "ENV_PRESENT"
        mapped["network_contacted"] = True
        mapped["base_url_host"] = urllib.parse.urlparse(str(creds["base_url"])).netloc

    if freeze and mapped.get("identity_bound") and mapped.get("current_firmware_value"):
        observation = to_baseline_observation(
            mapped,
            live_ipv4=live_ipv4,
            probe_mac_match=probe_mac_match,
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
        out_dir / f"hh-cc-reader-paxstore-observe-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read-only PAXSTORE getTerminalBySn observation (installed firmware)."
    )
    parser.add_argument("--serial", required=True, help="Terminal serial number")
    parser.add_argument("--expected-mac", default=None, help="Optional MAC bind")
    parser.add_argument("--live-ipv4", default=None, help="Optional live IPv4 for baseline freeze")
    parser.add_argument(
        "--fixture",
        default=None,
        help="Local JSON Result payload (no network; for contract/fixture proof)",
    )
    parser.add_argument(
        "--freeze",
        action="store_true",
        help="If observation is identity-bound with firmware, run freeze_baseline",
    )
    parser.add_argument("--output", default=None, help="Receipt path (ignored survey/output by default)")
    args = parser.parse_args(argv)

    fixture_payload = None
    if args.fixture:
        fixture_payload = json.loads(Path(args.fixture).read_text(encoding="utf-8-sig"))

    result = observe_terminal_by_sn(
        serial_no=args.serial,
        expected_mac=args.expected_mac,
        live_ipv4=args.live_ipv4,
        fixture_payload=fixture_payload,
        freeze=args.freeze,
    )
    path = _write_receipt(result, Path(args.output) if args.output else None)
    print(json.dumps(result, indent=2))
    print(f"RECEIPT={path}", file=sys.stderr)

    if result.get("access_state") in ("CREDENTIAL_GATE", "AUTHORIZED_ACCESS_SETUP_REQUIRED"):
        return 3
    if result.get("access_state") == "OBSERVED" and result.get("current_firmware_value"):
        if args.freeze and not (result.get("baseline") or {}).get("baseline_locked"):
            return 4
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
