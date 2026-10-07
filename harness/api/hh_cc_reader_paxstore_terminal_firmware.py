"""PAXSTORE Terminal + Firmware control adapter (observe/preview default; fail-closed push).

Reuses authentication/signing/base-url conventions from
hh_cc_reader_paxstore_terminal_observe.py. Does not import a Java runtime.
Mutation is false by default and unreachable without explicit authority.
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

from harness.api.hh_cc_reader_paxstore_terminal_observe import (
    DEFAULT_BASE_URL,
    ENV_API_KEY,
    ENV_API_SECRET,
    ENV_BASE_URL,
    ENV_ESTATE_AUTHORITY,
    credentials_from_env,
    missing_credential_access_state,
    observe_terminal_by_sn,
)

SCHEMA = "sas-hh-cc-reader-paxstore-terminal-firmware/v1"
FIRMWARE_PUSH_PATH = "/v1/3rdsys/terminalFirmwares"
FIRMWARE_HISTORY_PATH = "/v1/3rdsys/terminalFirmwares/history"
FIRMWARE_TASK_PATH = "/v1/3rdsys/terminalFirmwares/task"
FIRMWARE_SUSPEND_PATH = "/v1/3rdsys/terminalFirmwares/suspend"
FIRMWARE_DELETE_PATH = "/v1/3rdsys/terminalFirmwares"

Transport = Callable[[str, str, dict[str, str], bytes | None], dict[str, Any]]

TYPED_FAILURES = frozenset(
    {
        "TERMINAL_NOT_FOUND",
        "FIRMWARE_NOT_FOUND",
        "FIRMWARE_NOT_ONLINE",
        "FIRMWARE_MODEL_MISMATCH",
        "SAME_FIRMWARE_PENDING",
        "SAME_FIRMWARE_TASK_ACTIVE",
        "AUTHORIZATION_UNAVAILABLE",
        "IDENTITY_MISMATCH",
        "CREDENTIAL_GATE",
        "AUTHORIZED_ACCESS_SETUP_REQUIRED",
        "LIVE_MUTATION_REFUSED_BY_DEFAULT",
        "POLICY_REFUSAL",
        "INVALID_INPUT",
        "API_CALL_FAILED",
    }
)


def _norm_text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    return text or None


def _redact(payload: dict[str, Any]) -> dict[str, Any]:
    banned = {"api_key", "api_secret", "secret", "token", "password", "authorization"}

    def walk(node: Any) -> Any:
        if isinstance(node, dict):
            return {
                k: ("[REDACTED]" if str(k).lower() in banned or "secret" in str(k).lower() else walk(v))
                for k, v in node.items()
            }
        if isinstance(node, list):
            return [walk(x) for x in node]
        return node

    return walk(payload)


def build_signed_request(
    *,
    base_url: str,
    api_key: str,
    api_secret: str,
    path: str,
    params: list[tuple[str, str]] | None = None,
    timestamp_ms: int | None = None,
) -> tuple[str, dict[str, str], str]:
    ts = str(timestamp_ms if timestamp_ms is not None else int(time.time() * 1000))
    ordered = list(params or [])
    ordered.extend([("sysKey", api_key), ("timestamp", ts)])
    # Stable order for signing
    ordered.sort(key=lambda kv: kv[0])
    query = urllib.parse.urlencode(ordered, encoding="utf-8")
    signature = (
        hmac.new(api_secret.encode("utf-8"), query.encode("utf-8"), hashlib.sha256)
        .hexdigest()
        .upper()
    )
    url = f"{base_url.rstrip('/')}{path}?{query}"
    headers = {
        "signature": signature,
        "SDK-Language": "Python",
        "SDK-Version": "sas-hh-cc-firmware/0.1",
        "Time-Zone": "UTC",
        "Accept-Language": "en-US",
        "Content-Type": "application/json",
    }
    return url, headers, query


def default_http_transport(
    method: str, url: str, headers: dict[str, str], body: bytes | None
) -> dict[str, Any]:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
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


def map_vendor_failure(payload: dict[str, Any]) -> str | None:
    """Preserve vendor semantics; do not flatten all failures to ERROR."""
    code = payload.get("businessCode")
    message = str(payload.get("message") or "").lower()
    if code in (0, "0"):
        return None
    if "terminal" in message and ("not found" in message or "not exist" in message):
        return "TERMINAL_NOT_FOUND"
    if "firmware" in message and "not online" in message:
        return "FIRMWARE_NOT_ONLINE"
    if "firmware" in message and ("not found" in message or "not exist" in message):
        return "FIRMWARE_NOT_FOUND"
    if "model" in message and "mismatch" in message:
        return "FIRMWARE_MODEL_MISMATCH"
    if "pending" in message and "same" in message:
        return "SAME_FIRMWARE_PENDING"
    if "active" in message and ("same" in message or "already" in message):
        return "SAME_FIRMWARE_TASK_ACTIVE"
    if "unauthorized" in message or "forbidden" in message or code in (401, 403, "401", "403"):
        return "AUTHORIZATION_UNAVAILABLE"
    # Allow fixtures to set typed_state directly
    typed = payload.get("typed_state")
    if isinstance(typed, str) and typed in TYPED_FAILURES:
        return typed
    return "API_CALL_FAILED"


def resolve_firmware_candidate(
    *,
    fm_name: str | None,
    model_name: str | None,
    compatible_models: list[str] | None = None,
    online: bool | None = True,
    fixture: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if fixture is not None:
        data = fixture.get("data") if isinstance(fixture.get("data"), dict) else fixture
        fm_name = _norm_text(data.get("fmName") or data.get("firmwareName") or fm_name)
        model_name = _norm_text(data.get("modelName") or model_name)
        online = data.get("online") if "online" in data else online
        compatible_models = data.get("compatibleModels") or compatible_models
        typed = map_vendor_failure(fixture) if fixture.get("businessCode") not in (0, "0", None) else None
        if typed:
            return _redact(
                {
                    "schema": SCHEMA,
                    "operation": "FIRMWARE_CANDIDATE_RESOLUTION",
                    "access_state": typed,
                    "mutation_performed": False,
                    "fm_name": fm_name,
                }
            )
    name = _norm_text(fm_name)
    if not name:
        return {
            "schema": SCHEMA,
            "operation": "FIRMWARE_CANDIDATE_RESOLUTION",
            "access_state": "FIRMWARE_NOT_FOUND",
            "mutation_performed": False,
        }
    if online is False:
        return {
            "schema": SCHEMA,
            "operation": "FIRMWARE_CANDIDATE_RESOLUTION",
            "access_state": "FIRMWARE_NOT_ONLINE",
            "fm_name": name,
            "mutation_performed": False,
        }
    models = [str(m) for m in (compatible_models or [])]
    model = _norm_text(model_name)
    if model and models and model not in models:
        return {
            "schema": SCHEMA,
            "operation": "FIRMWARE_CANDIDATE_RESOLUTION",
            "access_state": "FIRMWARE_MODEL_MISMATCH",
            "fm_name": name,
            "model_name": model,
            "compatible_models": models,
            "mutation_performed": False,
        }
    return {
        "schema": SCHEMA,
        "operation": "FIRMWARE_CANDIDATE_RESOLUTION",
        "access_state": "RESOLVED",
        "fm_name": name,
        "model_name": model,
        "compatible_models": models,
        "online": True if online is None else bool(online),
        "mutation_performed": False,
    }


def preview_firmware_push(
    *,
    serial_no: str,
    fm_name: str,
    expected_mac: str | None = None,
    observe_fixture: dict[str, Any] | None = None,
    candidate_fixture: dict[str, Any] | None = None,
    history_fixture: dict[str, Any] | None = None,
    network_policy: str = "wifi_or_cabled_only",
    allow_mutation: bool = False,
    environ: dict[str, str] | None = None,
) -> dict[str, Any]:
    observe = observe_terminal_by_sn(
        serial_no=serial_no,
        expected_mac=expected_mac,
        fixture_payload=observe_fixture,
        environ=environ,
    )
    observe_state = observe.get("access_state")
    observe_msg = str(observe.get("message") or "").lower()
    if observe_state == "API_CALL_FAILED" and "terminal" in observe_msg and "not found" in observe_msg:
        observe_state = "TERMINAL_NOT_FOUND"
    if observe_state in {
        "CREDENTIAL_GATE",
        "AUTHORIZED_ACCESS_SETUP_REQUIRED",
        "TERMINAL_NOT_FOUND",
        "IDENTITY_MISMATCH",
        "INVALID_INPUT",
        "API_CALL_FAILED",
    }:
        return _redact(
            {
                "schema": SCHEMA,
                "operation": "PREVIEW",
                "access_state": observe_state,
                "observation": observe,
                "mutation_authorized": False,
                "mutation_performed": False,
            }
        )

    candidate = resolve_firmware_candidate(
        fm_name=fm_name,
        model_name=observe.get("model_name"),
        fixture=candidate_fixture,
    )
    history = push_history(
        serial_no=serial_no,
        fixture_payload=history_fixture,
        environ=environ,
        transport=None,
    )
    tasks = history.get("tasks") or []
    same_pending = any(
        t.get("fm_name") == fm_name and t.get("status") in {"PENDING", "pending"} for t in tasks
    )
    same_active = any(
        t.get("fm_name") == fm_name and t.get("status") in {"ACTIVE", "active", "IN_PROGRESS"}
        for t in tasks
    )
    gate = "READY_FOR_AUTHORIZED_PUSH"
    if candidate.get("access_state") != "RESOLVED":
        gate = candidate.get("access_state")
    elif same_active:
        gate = "SAME_FIRMWARE_TASK_ACTIVE"
    elif same_pending:
        gate = "SAME_FIRMWARE_PENDING"
    elif not allow_mutation:
        gate = "LIVE_MUTATION_REFUSED_BY_DEFAULT"

    return _redact(
        {
            "schema": SCHEMA,
            "operation": "PREVIEW",
            "access_state": "PREVIEW",
            "mutation_gate": gate,
            "mutation_authorized": False,
            "mutation_performed": False,
            "terminal_identity": {
                "serial": observe.get("source_serial") or serial_no,
                "model_name": observe.get("model_name"),
                "identity_bound": observe.get("identity_bound"),
            },
            "current_firmware_value": observe.get("current_firmware_value"),
            "candidate": candidate,
            "network_policy": network_policy,
            "timing": {"default_mode": "observe_preview"},
            "existing_tasks": tasks,
            "observation": {
                "access_state": observe.get("access_state"),
                "version_domain": observe.get("version_domain"),
            },
        }
    )


def push_firmware(
    *,
    serial_no: str,
    fm_name: str,
    allow_mutation: bool = False,
    mutation_authority: str | None = None,
    environ: dict[str, str] | None = None,
    transport: Transport | None = None,
    fixture_payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Push is implemented but fail-closed unless explicit authority is present."""
    env = environ if environ is not None else os.environ
    authority = _norm_text(mutation_authority) or _norm_text(
        env.get("SAS_PAXSTORE_FIRMWARE_MUTATION_AUTHORITY")
    )
    if not allow_mutation or authority != "EXPLICIT_FIRMWARE_PUSH_AUTHORIZED":
        return {
            "schema": SCHEMA,
            "operation": "PUSH",
            "access_state": "LIVE_MUTATION_REFUSED_BY_DEFAULT",
            "mutation_authorized": False,
            "mutation_performed": False,
            "message": (
                "Push requires --allow-mutation and "
                "SAS_PAXSTORE_FIRMWARE_MUTATION_AUTHORITY=EXPLICIT_FIRMWARE_PUSH_AUTHORIZED"
            ),
        }

    if fixture_payload is not None:
        typed = map_vendor_failure(fixture_payload)
        if typed:
            return {
                "schema": SCHEMA,
                "operation": "PUSH",
                "access_state": typed,
                "mutation_authorized": True,
                "mutation_performed": False,
            }
        return {
            "schema": SCHEMA,
            "operation": "PUSH",
            "access_state": "PUSH_ACCEPTED",
            "mutation_authorized": True,
            "mutation_performed": True,
            "task": fixture_payload.get("data"),
            "fm_name": fm_name,
            "serial": serial_no,
        }

    creds = credentials_from_env(environ)
    if not creds["api_key"] or not creds["api_secret"]:
        return {
            "schema": SCHEMA,
            "operation": "PUSH",
            "access_state": missing_credential_access_state(environ),
            "mutation_authorized": True,
            "mutation_performed": False,
            "network_contacted": False,
        }

    body = json.dumps({"serialNo": serial_no, "fmName": fm_name}).encode("utf-8")
    url, headers, _ = build_signed_request(
        base_url=str(creds["base_url"]),
        api_key=str(creds["api_key"]),
        api_secret=str(creds["api_secret"]),
        path=FIRMWARE_PUSH_PATH,
        params=[("serialNo", serial_no), ("fmName", fm_name)],
    )
    runner = transport or default_http_transport
    payload = runner("POST", url, headers, body)
    typed = map_vendor_failure(payload)
    if typed:
        return _redact(
            {
                "schema": SCHEMA,
                "operation": "PUSH",
                "access_state": typed,
                "mutation_authorized": True,
                "mutation_performed": False,
                "business_code": payload.get("businessCode"),
                "message": payload.get("message"),
            }
        )
    return _redact(
        {
            "schema": SCHEMA,
            "operation": "PUSH",
            "access_state": "PUSH_ACCEPTED",
            "mutation_authorized": True,
            "mutation_performed": True,
            "task": payload.get("data"),
            "fm_name": fm_name,
            "serial": serial_no,
        }
    )


def push_history(
    *,
    serial_no: str,
    fixture_payload: dict[str, Any] | None = None,
    environ: dict[str, str] | None = None,
    transport: Transport | None = None,
) -> dict[str, Any]:
    if fixture_payload is not None:
        typed = map_vendor_failure(fixture_payload) if fixture_payload.get("businessCode") not in (
            0,
            "0",
            None,
        ) else None
        data = fixture_payload.get("data")
        tasks = data if isinstance(data, list) else (data or {}).get("list") or []
        if typed:
            return {
                "schema": SCHEMA,
                "operation": "HISTORY",
                "access_state": typed,
                "tasks": [],
                "mutation_performed": False,
            }
        return {
            "schema": SCHEMA,
            "operation": "HISTORY",
            "access_state": "OBSERVED",
            "tasks": [_normalize_task(t) for t in tasks if isinstance(t, dict)],
            "mutation_performed": False,
            "serial": serial_no,
        }

    creds = credentials_from_env(environ)
    if not creds["api_key"] or not creds["api_secret"]:
        return {
            "schema": SCHEMA,
            "operation": "HISTORY",
            "access_state": missing_credential_access_state(environ),
            "tasks": [],
            "mutation_performed": False,
            "network_contacted": False,
        }
    url, headers, _ = build_signed_request(
        base_url=str(creds["base_url"]),
        api_key=str(creds["api_key"]),
        api_secret=str(creds["api_secret"]),
        path=FIRMWARE_HISTORY_PATH,
        params=[("serialNo", serial_no)],
    )
    runner = transport or default_http_transport
    payload = runner("GET", url, headers, None)
    typed = map_vendor_failure(payload)
    if typed:
        return {
            "schema": SCHEMA,
            "operation": "HISTORY",
            "access_state": typed,
            "tasks": [],
            "mutation_performed": False,
        }
    data = payload.get("data")
    tasks = data if isinstance(data, list) else (data or {}).get("list") or []
    return {
        "schema": SCHEMA,
        "operation": "HISTORY",
        "access_state": "OBSERVED",
        "tasks": [_normalize_task(t) for t in tasks if isinstance(t, dict)],
        "mutation_performed": False,
        "serial": serial_no,
    }


def task_status(
    *,
    task_id: str | None = None,
    serial_no: str | None = None,
    fixture_payload: dict[str, Any] | None = None,
    environ: dict[str, str] | None = None,
    transport: Transport | None = None,
) -> dict[str, Any]:
    if fixture_payload is not None:
        typed = map_vendor_failure(fixture_payload) if fixture_payload.get("businessCode") not in (
            0,
            "0",
            None,
        ) else None
        if typed:
            return {
                "schema": SCHEMA,
                "operation": "TASK_STATUS",
                "access_state": typed,
                "mutation_performed": False,
            }
        data = fixture_payload.get("data") if isinstance(fixture_payload.get("data"), dict) else {}
        return {
            "schema": SCHEMA,
            "operation": "TASK_STATUS",
            "access_state": "OBSERVED",
            "task": _normalize_task(data),
            "mutation_performed": False,
        }

    if not task_id and not serial_no:
        return {
            "schema": SCHEMA,
            "operation": "TASK_STATUS",
            "access_state": "INVALID_INPUT",
            "mutation_performed": False,
        }

    creds = credentials_from_env(environ)
    if not creds["api_key"] or not creds["api_secret"]:
        return {
            "schema": SCHEMA,
            "operation": "TASK_STATUS",
            "access_state": missing_credential_access_state(environ),
            "mutation_performed": False,
            "network_contacted": False,
        }
    params: list[tuple[str, str]] = []
    if task_id:
        params.append(("taskId", task_id))
    if serial_no:
        params.append(("serialNo", serial_no))
    url, headers, _ = build_signed_request(
        base_url=str(creds["base_url"]),
        api_key=str(creds["api_key"]),
        api_secret=str(creds["api_secret"]),
        path=FIRMWARE_TASK_PATH,
        params=params,
    )
    runner = transport or default_http_transport
    payload = runner("GET", url, headers, None)
    typed = map_vendor_failure(payload)
    if typed:
        return {
            "schema": SCHEMA,
            "operation": "TASK_STATUS",
            "access_state": typed,
            "mutation_performed": False,
        }
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    return {
        "schema": SCHEMA,
        "operation": "TASK_STATUS",
        "access_state": "OBSERVED",
        "task": _normalize_task(data),
        "mutation_performed": False,
    }


def suspend_or_disable_task(
    *,
    task_id: str,
    allow_mutation: bool = False,
    fixture_payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not allow_mutation:
        return {
            "schema": SCHEMA,
            "operation": "SUSPEND",
            "access_state": "LIVE_MUTATION_REFUSED_BY_DEFAULT",
            "mutation_performed": False,
        }
    if fixture_payload is not None:
        typed = map_vendor_failure(fixture_payload)
        return {
            "schema": SCHEMA,
            "operation": "SUSPEND",
            "access_state": typed or "SUSPENDED",
            "task_id": task_id,
            "mutation_performed": typed is None,
        }
    return {
        "schema": SCHEMA,
        "operation": "SUSPEND",
        "access_state": "AUTHORIZATION_UNAVAILABLE",
        "mutation_performed": False,
        "task_id": task_id,
    }


def delete_or_cancel_task(
    *,
    task_id: str,
    allow_mutation: bool = False,
    fixture_payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not allow_mutation:
        return {
            "schema": SCHEMA,
            "operation": "DELETE",
            "access_state": "LIVE_MUTATION_REFUSED_BY_DEFAULT",
            "mutation_performed": False,
        }
    if fixture_payload is not None:
        typed = map_vendor_failure(fixture_payload)
        return {
            "schema": SCHEMA,
            "operation": "DELETE",
            "access_state": typed or "DELETED",
            "task_id": task_id,
            "mutation_performed": typed is None,
        }
    return {
        "schema": SCHEMA,
        "operation": "DELETE",
        "access_state": "AUTHORIZATION_UNAVAILABLE",
        "mutation_performed": False,
        "task_id": task_id,
    }


def post_verify(
    *,
    serial_no: str,
    intended_fm_name: str,
    expected_mac: str | None = None,
    observe_fixture: dict[str, Any] | None = None,
    environ: dict[str, str] | None = None,
) -> dict[str, Any]:
    observe = observe_terminal_by_sn(
        serial_no=serial_no,
        expected_mac=expected_mac,
        fixture_payload=observe_fixture,
        environ=environ,
    )
    current = observe.get("current_firmware_value")
    match = bool(current and intended_fm_name and current == intended_fm_name)
    return _redact(
        {
            "schema": SCHEMA,
            "operation": "POST_VERIFY",
            "access_state": observe.get("access_state"),
            "identity_bound": observe.get("identity_bound"),
            "intended_fm_name": intended_fm_name,
            "current_firmware_value": current,
            "matches_intended": match,
            "mutation_performed": False,
        }
    )


def _normalize_task(task: dict[str, Any]) -> dict[str, Any]:
    status = _norm_text(task.get("status") or task.get("taskStatus")) or "UNKNOWN"
    normalized = status.upper()
    if normalized in {"RUNNING", "IN_PROGRESS", "PROCESSING"}:
        family = "active"
    elif normalized in {"SUCCESS", "COMPLETED", "DONE"}:
        family = "completed"
    elif normalized in {"FAILED", "ERROR", "FAIL"}:
        family = "failed"
    elif normalized in {"SUSPENDED", "DISABLED", "PAUSED"}:
        family = "suspended"
    elif normalized in {"PENDING", "WAITING"}:
        family = "pending"
    else:
        family = normalized.lower()
    return {
        "task_id": _norm_text(task.get("taskId") or task.get("id")),
        "fm_name": _norm_text(task.get("fmName") or task.get("firmwareName")),
        "status": normalized,
        "status_family": family,
        "serial": _norm_text(task.get("serialNo")),
    }


def _write_receipt(payload: dict[str, Any], output: Path | None) -> Path:
    out_dir = ROOT / "survey" / "output" / "hh-cc-reader"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = output or (
        out_dir / f"hh-cc-reader-paxstore-firmware-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    path.write_text(json.dumps(_redact(payload), indent=2) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PAXSTORE terminal firmware adapter (fail-closed)")
    parser.add_argument(
        "--mode",
        required=True,
        choices=(
            "observe",
            "preview",
            "history",
            "task-status",
            "push",
            "post-verify",
            "suspend",
            "delete",
            "resolve-candidate",
        ),
    )
    parser.add_argument("--serial", default=None)
    parser.add_argument("--fm-name", default=None)
    parser.add_argument("--expected-mac", default=None)
    parser.add_argument("--task-id", default=None)
    parser.add_argument("--fixture", default=None)
    parser.add_argument("--observe-fixture", default=None)
    parser.add_argument("--candidate-fixture", default=None)
    parser.add_argument("--history-fixture", default=None)
    parser.add_argument("--allow-mutation", action="store_true")
    parser.add_argument("--output", default=None)
    args = parser.parse_args(argv)

    def load(path: str | None) -> dict[str, Any] | None:
        if not path:
            return None
        return json.loads(Path(path).read_text(encoding="utf-8-sig"))

    fixture = load(args.fixture)
    if args.mode == "observe":
        if not args.serial:
            print(json.dumps({"access_state": "INVALID_INPUT", "message": "--serial required"}))
            return 2
        result = observe_terminal_by_sn(
            serial_no=args.serial,
            expected_mac=args.expected_mac,
            fixture_payload=fixture,
        )
        result = {
            "schema": SCHEMA,
            "operation": "TERMINAL_OBSERVE",
            **result,
        }
    elif args.mode == "preview":
        if not args.serial or not args.fm_name:
            print(json.dumps({"access_state": "INVALID_INPUT"}))
            return 2
        result = preview_firmware_push(
            serial_no=args.serial,
            fm_name=args.fm_name,
            expected_mac=args.expected_mac,
            observe_fixture=load(args.observe_fixture) or fixture,
            candidate_fixture=load(args.candidate_fixture),
            history_fixture=load(args.history_fixture),
            allow_mutation=args.allow_mutation,
        )
    elif args.mode == "history":
        result = push_history(serial_no=args.serial or "", fixture_payload=fixture)
    elif args.mode == "task-status":
        result = task_status(task_id=args.task_id, serial_no=args.serial, fixture_payload=fixture)
    elif args.mode == "push":
        if not args.serial or not args.fm_name:
            print(json.dumps({"access_state": "INVALID_INPUT"}))
            return 2
        result = push_firmware(
            serial_no=args.serial,
            fm_name=args.fm_name,
            allow_mutation=args.allow_mutation,
            fixture_payload=fixture,
        )
    elif args.mode == "post-verify":
        result = post_verify(
            serial_no=args.serial or "",
            intended_fm_name=args.fm_name or "",
            expected_mac=args.expected_mac,
            observe_fixture=fixture,
        )
    elif args.mode == "suspend":
        result = suspend_or_disable_task(
            task_id=args.task_id or "",
            allow_mutation=args.allow_mutation,
            fixture_payload=fixture,
        )
    elif args.mode == "delete":
        result = delete_or_cancel_task(
            task_id=args.task_id or "",
            allow_mutation=args.allow_mutation,
            fixture_payload=fixture,
        )
    else:
        result = resolve_firmware_candidate(fm_name=args.fm_name, model_name=None, fixture=fixture)

    path = _write_receipt(result, Path(args.output) if args.output else None)
    print(json.dumps(result, indent=2))
    print(f"RECEIPT={path}", file=sys.stderr)
    state = result.get("access_state") or result.get("mutation_gate")
    if state in {"CREDENTIAL_GATE", "AUTHORIZED_ACCESS_SETUP_REQUIRED"}:
        return 3
    if state == "LIVE_MUTATION_REFUSED_BY_DEFAULT":
        return 4
    if state in {"PREVIEW", "OBSERVED", "RESOLVED", "PUSH_ACCEPTED"} or result.get("matches_intended"):
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
