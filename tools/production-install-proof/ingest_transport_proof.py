#!/usr/bin/env python3
"""Ingest an operator-local transport live-cert result and emit a public-safe receipt.

The source evidence is read in place, hashed, and never copied into repository
output.  Only public-safe booleans, schema identity, byte count, and the source
digest are emitted.  The receipt conforms to
sas-software-deployment-transport-receipt/v1.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "sas-software-deployment-transport-receipt/v1"
WORKFLOW_ID = "software-deployment-transport-proof-ingest"
SOURCE_SCHEMA_VERSION = "sas-software-deployment-transport-live-cert-result/v1"
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")

VALID_CLASSIFICATIONS = {
    "kerberos_smb_task_ready",
    "winrm_ready",
    "no_supported_transport",
    "transport_reachable_authorization_denied",
    "inconclusive",
}
VALID_TRANSPORTS = {"kerberos_smb_task", "winrm", "none"}
CERTIFICATION_KEYS = {
    "task_created",
    "executed_as_system",
    "result_retrieved",
    "task_deleted",
    "staging_deleted",
    "zero_remnants_verified",
    "software_installation_performed",
    "harmless_payload_only",
}
PRIVACY_KEYS = {
    "hostnames_emitted",
    "usernames_emitted",
    "ticket_bytes_emitted",
    "credentials_emitted",
    "package_paths_emitted",
    "machine_local_paths_emitted",
    "raw_evidence_emitted",
}
REASON_CONTRACT_FIXTURE = "sanitized_fixture_contract"
REASON_EXECUTION_PROVEN = "execution_and_cleanup_proven"
REASON_EXECUTION_FAILED = "execution_failed"
REASON_CLEANUP_INCOMPLETE = "cleanup_incomplete"
REASON_OPERATOR_MISSING = "operator_confirmation_missing"
REASON_SOURCE_DIGEST_MISMATCH = "source_digest_mismatch"
REASON_PRIVATE_FIELD = "private_field_detected"

FORBIDDEN_FIELDS = (
    "hostname",
    "username",
    "ticket_bytes",
    "credential",
    "package_path",
    "machine_local_path",
    "raw_evidence",
)
FORBIDDEN_SERIALIZED = ("target_hostname", "ticket_cache", "begin kerberos", "c:\\users\\", "/home/")


class IngestError(ValueError):
    """Raised when evidence cannot be safely parsed or classified."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise IngestError(f"source evidence is not valid UTF-8 JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise IngestError("source evidence root must be a JSON object")
    return payload


def _validate_source_schema(payload: dict[str, Any]) -> None:
    sv = payload.get("schema_version", "")
    if sv != SOURCE_SCHEMA_VERSION:
        raise IngestError(
            f"unsupported source schema version: {sv} (expected {SOURCE_SCHEMA_VERSION})"
        )
    wf = payload.get("workflow_id", "")
    if wf != "software-deployment-transport-live-cert":
        raise IngestError(f"unexpected source workflow_id: {wf}")


def _validate_decision(decision: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    classification = decision.get("preflight_classification", "")
    transport = decision.get("selected_transport", "")
    if classification not in VALID_CLASSIFICATIONS:
        raise IngestError(f"invalid preflight_classification: {classification}")
    if transport not in VALID_TRANSPORTS:
        raise IngestError(f"invalid selected_transport: {transport}")
    return reasons


def _validate_certification(cert: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    if set(cert) != CERTIFICATION_KEYS:
        missing = CERTIFICATION_KEYS - set(cert)
        extra = set(cert) - CERTIFICATION_KEYS
        parts = []
        if missing:
            parts.append(f"missing: {sorted(missing)}")
        if extra:
            parts.append(f"extra: {sorted(extra)}")
        raise IngestError(f"certification block is not closed: {'; '.join(parts)}")
    if cert.get("software_installation_performed") is not False:
        raise IngestError("live cert must not install software")
    if cert.get("harmless_payload_only") is not True:
        raise IngestError("live cert payload must be harmless")
    # For a live_cert_pass, all certification flags must be true
    for flag in (
        "task_created",
        "executed_as_system",
        "result_retrieved",
        "task_deleted",
        "staging_deleted",
        "zero_remnants_verified",
    ):
        if cert.get(flag) is not True:
            reasons.append(REASON_CLEANUP_INCOMPLETE)
            break
    return reasons


def _validate_privacy(privacy: dict[str, Any]) -> None:
    if set(privacy) != PRIVACY_KEYS:
        raise IngestError("privacy block is not closed")
    for key, value in privacy.items():
        if value is not False:
            raise IngestError(f"privacy flag {key} must be false in public receipt")


def _scan_forbidden_fields(payload: dict[str, Any], path: tuple[str, ...] = ()) -> None:
    """Recursively scan for forbidden private fields in the payload."""
    if not isinstance(payload, dict):
        return
    for key, value in payload.items():
        if key in FORBIDDEN_FIELDS:
            raise IngestError(f"private field detected in source: {'.'.join((*path, key))}")
        if isinstance(value, dict):
            _scan_forbidden_fields(value, (*path, key))


def _determine_outcome_and_reasons(
    cert: dict[str, Any],
    contract_fixture: bool,
    operator_confirmed: bool,
) -> tuple[str, list[str]]:
    if contract_fixture:
        return "contract_only", [REASON_CONTRACT_FIXTURE]

    reasons: list[str] = []
    cert_reasons = _validate_certification(cert)
    reasons.extend(cert_reasons)

    if not operator_confirmed:
        reasons.append(REASON_OPERATOR_MISSING)

    if reasons:
        if REASON_CLEANUP_INCOMPLETE in reasons:
            return "live_cert_failed", reasons
        return "live_cert_failed", reasons

    return "live_cert_pass", [REASON_EXECUTION_PROVEN]


def _build_receipt(
    source: dict[str, Any],
    source_sha256: str,
    source_size: int,
    contract_fixture: bool,
    operator_confirmed: bool,
    outcome: str,
    reason_codes: list[str],
) -> dict[str, Any]:
    decision = source.get("decision", {})
    cert = source.get("certification", {})

    # For contract_only outcomes, use placeholder decision
    if outcome == "contract_only":
        receipt_decision = {
            "preflight_classification": "kerberos_smb_task_ready",
            "selected_transport": "kerberos_smb_task",
        }
        receipt_cert = {k: False for k in CERTIFICATION_KEYS if k not in ("software_installation_performed", "harmless_payload_only")}
        receipt_cert["software_installation_performed"] = False
        receipt_cert["harmless_payload_only"] = True
        proof_level = "sanitized_fixture_contract"
    else:
        receipt_decision = {
            "preflight_classification": decision.get("preflight_classification", "inconclusive"),
            "selected_transport": decision.get("selected_transport", "none"),
        }
        receipt_cert = {k: cert.get(k, False) for k in CERTIFICATION_KEYS}
        receipt_cert["software_installation_performed"] = False
        receipt_cert["harmless_payload_only"] = True
        if outcome == "live_cert_pass":
            proof_level = "live_transport_execution_and_cleanup"
        else:
            proof_level = "insufficient"

    return {
        "schema_version": SCHEMA_VERSION,
        "workflow_id": WORKFLOW_ID,
        "outcome": outcome,
        "reason_codes": reason_codes,
        "source": {
            "source_schema_version": SOURCE_SCHEMA_VERSION,
            "source_evidence_sha256": source_sha256,
            "source_evidence_size_bytes": source_size,
            "source_evidence_retained_operator_local": True,
            "source_evidence_copied_to_output": False,
            "contract_fixture": contract_fixture,
            "operator_confirmed": operator_confirmed,
        },
        "decision": receipt_decision,
        "certification": receipt_cert,
        "privacy": {k: False for k in PRIVACY_KEYS},
        "proof_level": proof_level,
        "proof_ceiling": _proof_ceiling(outcome, proof_level),
    }


def _proof_ceiling(outcome: str, proof_level: str) -> str:
    if outcome == "contract_only":
        return (
            "Sanitized fixture validation of the public receipt shape and privacy "
            "boundary only; no live transport execution or cleanup is claimed."
        )
    if proof_level == "live_transport_execution_and_cleanup":
        return (
            "Public-safe receipt derived from operator-local live-cert evidence. "
            "Source evidence hashed in place and never copied. "
            "No hostnames, usernames, ticket bytes, credentials, package paths, "
            "machine-local paths, or raw evidence are emitted."
        )
    return (
        "Receipt produced from incomplete or failed live-cert evidence. "
        "Proof ceiling is insufficient for live_transport_execution_and_cleanup claim."
    )


def _write_summary(receipt: dict[str, Any], summary_path: Path) -> None:
    summary = {
        "schema_version": "sas-run-summary/v1",
        "workflow_id": WORKFLOW_ID,
        "outcome": receipt["outcome"],
        "proof_level": receipt["proof_level"],
        "reason_codes": receipt["reason_codes"],
        "source_evidence_sha256": receipt["source"]["source_evidence_sha256"],
        "source_evidence_size_bytes": receipt["source"]["source_evidence_size_bytes"],
        "operator_confirmed": receipt["source"]["operator_confirmed"],
        "privacy_clean": all(v is False for v in receipt["privacy"].values()),
    }
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Ingest a transport live-cert result and emit a public-safe receipt."
    )
    parser.add_argument(
        "--source",
        required=True,
        help="Path to the operator-local live-cert result JSON file.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory to write the receipt and summary.",
    )
    parser.add_argument(
        "--contract-fixture",
        action="store_true",
        help="Mark as a sanitized contract fixture (not live evidence).",
    )
    parser.add_argument(
        "--operator-confirmed",
        action="store_true",
        help="Operator has confirmed the live-cert result is authentic.",
    )
    args = parser.parse_args(argv)

    source_path = Path(args.source).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not source_path.is_file():
        raise IngestError(f"source evidence not found: {source_path}")

    # Hash the source evidence in place
    source_size = source_path.stat().st_size
    if source_size < 2:
        raise IngestError("source evidence is too small to be a valid result")
    source_sha256 = _sha256(source_path)

    # Load and validate
    source = _load_json(source_path)
    _validate_source_schema(source)
    decision = source.get("decision", {})
    _validate_decision(decision)
    cert = source.get("certification", {})
    privacy = source.get("privacy", {})

    # Scan for forbidden private fields
    _scan_forbidden_fields(source)

    # Validate privacy block
    _validate_privacy(privacy)

    # Determine outcome
    outcome, reason_codes = _determine_outcome_and_reasons(
        cert, args.contract_fixture, args.operator_confirmed
    )

    # Build receipt
    receipt = _build_receipt(
        source, source_sha256, source_size,
        args.contract_fixture, args.operator_confirmed,
        outcome, reason_codes,
    )

    # Write outputs
    receipt_path = output_dir / "software_deployment_transport_receipt.json"
    receipt_path.write_text(
        json.dumps(receipt, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )

    summary_path = output_dir / "receipt_summary.json"
    _write_summary(receipt, summary_path)

    # Emit machine-readable result to stdout
    result = {
        "receipt": str(receipt_path),
        "summary": str(summary_path),
        "outcome": outcome,
        "proof_level": receipt["proof_level"],
        "source_evidence_sha256": source_sha256,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except IngestError as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)
