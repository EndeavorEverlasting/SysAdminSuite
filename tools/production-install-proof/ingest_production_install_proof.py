#!/usr/bin/env python3
"""Validate operator-local live installation evidence and emit a sanitized receipt.

The source evidence is read in place, hashed, and never copied into repository output.
Only public-safe booleans, dates, schema identity, byte count, and the source digest
are emitted. The first supported producer is the Resume Matcher live-acceptance
result introduced by SysAdminSuite PR #222.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Iterable

SCHEMA_VERSION = "sas-production-install-proof-receipt/v1"
WORKFLOW_ID = "production-install-proof-ingest"
SUPPORTED_SOURCE_SCHEMA = "sas-resume-matcher-workstation-result/v1"
SUPPORTED_SOURCE_PR = 222
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
REASON_VALIDATED = "live-production-install-validated"
REASON_CONTRACT_ONLY = "sanitized-contract-fixture-only"
REASON_BLOCKED = "production-proof-requirements-not-met"


class IntakeError(ValueError):
    """Raised when evidence cannot be safely parsed or classified."""


@dataclass(frozen=True)
class ValidationResult:
    accepted: bool
    reasons: tuple[str, ...]
    machine_flags: dict[str, bool]
    source_schema: str
    source_workflow: str


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ensure_regular_file(path: Path) -> Path:
    if not path.exists():
        raise IntakeError(f"evidence file does not exist: {path}")
    if path.is_symlink() or not path.is_file():
        raise IntakeError("evidence must be a regular non-symlink file")
    cursor = path.resolve().parent
    while cursor != cursor.parent:
        if cursor.is_symlink():
            raise IntakeError(f"evidence parent path is a symlink: {cursor}")
        cursor = cursor.parent
    return path.resolve()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise IntakeError(f"evidence is not valid UTF-8 JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise IntakeError("evidence root must be a JSON object")
    return payload


def _get_bool(payload: dict[str, Any], path: Iterable[str]) -> bool:
    current: Any = payload
    walked: list[str] = []
    for key in path:
        walked.append(key)
        if not isinstance(current, dict) or key not in current:
            raise IntakeError(f"missing required evidence field: {'.'.join(walked)}")
        current = current[key]
    if not isinstance(current, bool):
        raise IntakeError(f"evidence field must be boolean: {'.'.join(walked)}")
    return current


def _get_str(payload: dict[str, Any], path: Iterable[str]) -> str:
    current: Any = payload
    walked: list[str] = []
    for key in path:
        walked.append(key)
        if not isinstance(current, dict) or key not in current:
            raise IntakeError(f"missing required evidence field: {'.'.join(walked)}")
        current = current[key]
    if not isinstance(current, str) or not current:
        raise IntakeError(f"evidence field must be a non-empty string: {'.'.join(walked)}")
    return current


def _validate_resume_matcher(payload: dict[str, Any]) -> ValidationResult:
    source_schema = _get_str(payload, ("schema_version",))
    if source_schema != SUPPORTED_SOURCE_SCHEMA:
        raise IntakeError(f"unsupported evidence schema: {source_schema}")
    source_workflow = _get_str(payload, ("workflow_id",))
    if source_workflow != "resume-matcher-workstation":
        raise IntakeError(f"unexpected workflow for {source_schema}: {source_workflow}")

    required_strings = {
        "operation": ("accept", "operation-not-accept"),
        "outcome": ("success", "outcome-not-success"),
        "lifecycle_state": ("accepted", "lifecycle-state-not-accepted"),
    }
    reasons: list[str] = []
    for key, (expected, reason) in required_strings.items():
        actual = _get_str(payload, (key,))
        if actual != expected:
            reasons.append(reason)

    fixture_mode = _get_bool(payload, ("configuration", "fixture_mode"))
    provider_health_required = _get_bool(payload, ("configuration", "provider_health_required"))

    flag_paths = {
        "install_completed": ("proof", "install_completed"),
        "configuration_applied": ("proof", "configuration_applied"),
        "launcher_started": ("proof", "launcher_started"),
        "backend_health_observed": ("proof", "backend_health_observed"),
        "frontend_health_observed": ("proof", "frontend_health_observed"),
        "browser_launch_observed": ("proof", "browser_launch_observed"),
        "pdf_export_observed": ("proof", "pdf_export_observed"),
        "live_runtime": ("proof", "live_runtime"),
        "acceptance_completed": ("proof", "acceptance_completed"),
        "provider_configured": ("acceptance", "provider_configured"),
        "frontend_content_observed": ("acceptance", "frontend_content_observed"),
    }
    flags = {name: _get_bool(payload, path) for name, path in flag_paths.items()}
    for name, value in flags.items():
        if not value:
            reasons.append(f"{name.replace('_', '-')}-false")

    provider_health_observed = _get_bool(payload, ("proof", "provider_health_observed"))
    flags["provider_health_observed"] = provider_health_observed
    if provider_health_required and not provider_health_observed:
        reasons.append("provider-health-required-but-unproven")

    pdf_sha = payload.get("acceptance", {}).get("pdf_sha256")
    pdf_size = payload.get("acceptance", {}).get("pdf_size_bytes")
    if not isinstance(pdf_sha, str) or not SHA256_RE.fullmatch(pdf_sha):
        reasons.append("sanitized-pdf-sha256-invalid")
    if not isinstance(pdf_size, int) or isinstance(pdf_size, bool) or pdf_size <= 0:
        reasons.append("sanitized-pdf-size-not-positive")

    if fixture_mode:
        reasons.append("fixture-mode-evidence")

    return ValidationResult(
        accepted=not reasons,
        reasons=tuple(sorted(set(reasons))),
        machine_flags=flags,
        source_schema=source_schema,
        source_workflow=source_workflow,
    )


def _validate_date(value: str) -> str:
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError as exc:
        raise IntakeError("validation date must use YYYY-MM-DD") from exc


def _safe_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _receipt(
    *,
    evidence: Path,
    evidence_sha: str,
    validation: ValidationResult,
    source_pr: int,
    validation_date: str,
    environment_class: str,
    operator_confirmed: bool,
    contract_fixture: bool,
) -> dict[str, Any]:
    production_accepted = validation.accepted and operator_confirmed and not contract_fixture
    if production_accepted:
        outcome = "validated"
        reason_codes = [REASON_VALIDATED]
        proof_level = "live_production_acceptance"
    elif contract_fixture and validation.accepted:
        outcome = "contract-only"
        reason_codes = [REASON_CONTRACT_ONLY]
        proof_level = "sanitized_fixture_contract"
    else:
        outcome = "blocked"
        reason_codes = [REASON_BLOCKED, *validation.reasons]
        if not operator_confirmed:
            reason_codes.append("operator-confirmation-missing")
        proof_level = "insufficient"

    return {
        "schema_version": SCHEMA_VERSION,
        "workflow_id": WORKFLOW_ID,
        "outcome": outcome,
        "reason_codes": sorted(set(reason_codes)),
        "source": {
            "source_pr": source_pr,
            "source_pr_role": "runtime-lane-authority",
            "source_schema_version": validation.source_schema,
            "source_workflow_id": validation.source_workflow,
            "source_evidence_sha256": evidence_sha,
            "source_evidence_size_bytes": evidence.stat().st_size,
            "source_evidence_retained_operator_local": True,
            "source_evidence_copied_to_output": False,
        },
        "event": {
            "validation_date": validation_date,
            "environment_class": environment_class,
            "operator_confirmed": operator_confirmed,
            "contract_fixture": contract_fixture,
        },
        "proof": {
            "proof_level": proof_level,
            "production_install_accepted": production_accepted,
            "machine_observed": validation.machine_flags,
            "operator_attested": {
                "production_environment": environment_class in {
                    "production_corporate_network",
                    "production_isolated",
                },
                "corporate_network": environment_class == "production_corporate_network",
            },
        },
        "privacy": {
            "hostnames_emitted": False,
            "usernames_emitted": False,
            "credentials_emitted": False,
            "provider_secrets_emitted": False,
            "machine_local_paths_emitted": False,
            "raw_logs_emitted": False,
        },
        "proof_ceiling": (
            "This receipt proves only the exact evidence file identified by its SHA-256, the observed application "
            "acceptance flags, and the operator-attested environment/date. It does not approve another package, "
            "another workstation, fleet rollout, clinical workflow, AutoLogon, or unrelated corporate-network access."
        ),
    }


def _render_text(receipt: dict[str, Any]) -> str:
    proof = receipt["proof"]
    source = receipt["source"]
    event = receipt["event"]
    lines = [
        "PRODUCTION SOFTWARE INSTALL PROOF",
        f"Outcome: {receipt['outcome'].upper()}",
        f"Proof level: {proof['proof_level']}",
        f"Validation date: {event['validation_date']}",
        f"Environment: {event['environment_class']}",
        f"Source PR: #{source['source_pr']}",
        f"Evidence SHA-256: {source['source_evidence_sha256']}",
        "Evidence retained operator-local: yes",
        "Source evidence copied: no",
        "Sensitive paths, hostnames, usernames, credentials, and raw logs emitted: no",
        "",
        receipt["proof_ceiling"],
    ]
    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--source-pr", type=int, default=222)
    parser.add_argument("--validation-date", required=True)
    parser.add_argument(
        "--environment-class",
        choices=("production_corporate_network", "production_isolated", "authorized_pilot"),
        default="production_corporate_network",
    )
    parser.add_argument("--operator-confirmed", action="store_true")
    parser.add_argument("--contract-fixture", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.source_pr != SUPPORTED_SOURCE_PR:
            raise IntakeError(
                f"unsupported source PR for {SUPPORTED_SOURCE_SCHEMA}: #{args.source_pr}; expected #{SUPPORTED_SOURCE_PR}"
            )
        evidence = _ensure_regular_file(args.evidence)
        payload = _load_json(evidence)
        validation = _validate_resume_matcher(payload)
        validation_date = _validate_date(args.validation_date)
        evidence_sha = _sha256(evidence)
        receipt = _receipt(
            evidence=evidence,
            evidence_sha=evidence_sha,
            validation=validation,
            source_pr=args.source_pr,
            validation_date=validation_date,
            environment_class=args.environment_class,
            operator_confirmed=args.operator_confirmed,
            contract_fixture=args.contract_fixture,
        )
        output_dir = args.output_dir.resolve()
        receipt_path = output_dir / "production_install_proof_receipt.json"
        text_path = output_dir / "production_install_proof_receipt.txt"
        _safe_write_json(receipt_path, receipt)
        text_path.parent.mkdir(parents=True, exist_ok=True)
        text_path.write_text(_render_text(receipt), encoding="utf-8")
        print(json.dumps({"receipt": str(receipt_path), "summary": str(text_path), "outcome": receipt["outcome"]}))
        return 0 if receipt["outcome"] in {"validated", "contract-only"} else 2
    except (IntakeError, OSError) as exc:
        print(f"production install proof intake failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
