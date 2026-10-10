#!/usr/bin/env python3
"""One-write, offline SAS finding intake. Private first; public projection is review-only.

This is an operational-event producer under sas-operational-publication-boundary/v1.
It does not access Git, Drive, a target machine, or any network service.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "sas-finding-event/v1"
RECEIPT_VERSION = "sas-finding-ingest-receipt/v1"
CANDIDATE_VERSION = "sas-finding-publication-candidate/v1"
CATEGORIES = frozenset({"hardware", "software", "network", "storage", "workstation", "deployment", "automation", "workflow", "other"})
PROOF = frozenset({"operator_reported", "historical_capture", "observed_runtime", "locally_validated", "integration_validated"})
PRIVACY = frozenset({"private_operational", "restricted_organization"})
REQUIRED = frozenset({"schema_version", "event_id", "logical_subject_key", "event_type", "occurred_at", "evidence_ref", "category", "proof_level", "privacy", "finding"})
PATTERNS = {
    "hardware": "Evaluate hardware compatibility and physical service evidence before approving changes.",
    "software": "Bind software setup findings to reproducible environment and validation contracts.",
    "network": "Separate network observations from inferred causes and authorization.",
    "storage": "Verify device identity and backup before changing storage state.",
    "workstation": "Retain profile separation and verify each workstation independently.",
    "deployment": "Preserve authorization and runtime proof gates for deployments.",
    "automation": "Preserve idempotency, replay evidence, and explicit action boundaries.",
    "workflow": "Remove repeated manual transcription by using one event and typed projections.",
    "other": "Review evidence before promoting a reusable generalization.",
}
ROOT = Path(__file__).resolve().parents[2]


class AdmissionError(ValueError):
    """Finding cannot be safely admitted."""


def _canonical(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _inside(candidate: Path, parent: Path) -> bool:
    return candidate == parent or parent in candidate.parents


def _root(path: str | None) -> Path:
    if path:
        directory = Path(path).expanduser().resolve()
    elif os.name == "nt":
        directory = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local")) / "SysAdminSuite" / "Evidence" / "Findings"
    else:
        directory = Path.home() / ".local" / "share" / "SysAdminSuite" / "Evidence" / "Findings"
    directory = directory.resolve()
    # An explicit test/output root may be inside the repository, but only in the already ignored output lane.
    if _inside(directory, ROOT) and not _inside(directory, ROOT / "survey" / "output"):
        raise AdmissionError("Evidence root inside tracked repository scope is forbidden")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory


def validate(event: Any) -> dict[str, Any]:
    if not isinstance(event, dict) or set(event) != REQUIRED:
        raise AdmissionError("Event must contain exactly the required typed fields")
    if event["schema_version"] != SCHEMA_VERSION or event["event_type"] != "FINDING_RECORDED":
        raise AdmissionError("Unsupported finding event contract")
    if not isinstance(event["event_id"], str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{7,79}", event["event_id"]):
        raise AdmissionError("event_id must be a stable safe opaque identifier")
    if not isinstance(event["logical_subject_key"], str) or not event["logical_subject_key"].strip() or len(event["logical_subject_key"]) > 200:
        raise AdmissionError("Missing bounded logical subject key")
    if not isinstance(event["evidence_ref"], str) or not event["evidence_ref"].strip() or len(event["evidence_ref"]) > 2048:
        raise AdmissionError("Missing bounded private evidence reference")
    if (
        not isinstance(event["category"], str) or event["category"] not in CATEGORIES
        or not isinstance(event["proof_level"], str) or event["proof_level"] not in PROOF
        or not isinstance(event["privacy"], str) or event["privacy"] not in PRIVACY
    ):
        raise AdmissionError("Unknown category, evidence level, or privacy classification")
    if not isinstance(event["occurred_at"], str):
        raise AdmissionError("occurred_at must be an offset-aware ISO8601 timestamp")
    try:
        dt = datetime.fromisoformat(event["occurred_at"].replace("Z", "+00:00"))
        if dt.tzinfo is None or dt.utcoffset() is None:
            raise ValueError("timezone missing")
    except ValueError as exc:
        raise AdmissionError("occurred_at must be an offset-aware ISO8601 timestamp") from exc
    finding = event["finding"]
    if not isinstance(finding, dict) or not isinstance(finding.get("summary"), str) or not finding["summary"].strip() or len(finding["summary"]) > 2000:
        raise AdmissionError("finding.summary must be a bounded non-empty string")
    if set(finding) - {"summary", "details", "measurements"}:
        raise AdmissionError("finding has unknown fields")
    if "details" in finding and (not isinstance(finding["details"], str) or len(finding["details"]) > 20000):
        raise AdmissionError("finding.details must be a bounded string")
    if "measurements" in finding and (not isinstance(finding["measurements"], dict) or len(_canonical(finding["measurements"])) > 20000):
        raise AdmissionError("finding.measurements must be a bounded object")
    if len(_canonical(event)) > 48000:
        raise AdmissionError("event size exceeds limit")
    return event


def _atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".sas-finding-", dir=path.parent)
    try:
        if os.name != "nt":
            os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def ingest(event: dict[str, Any], output_root: Path) -> dict[str, Any]:
    validate(event)
    raw = _canonical(event)
    digest = hashlib.sha256(raw).hexdigest()
    event_file = output_root / "private" / (event["event_id"] + ".json")
    candidate_file = output_root / "candidates" / (event["event_id"] + ".json")
    receipt_file = output_root / "receipts" / (event["event_id"] + ".json")
    existed = event_file.exists()
    if existed and hashlib.sha256(event_file.read_bytes()).hexdigest() != digest:
        raise AdmissionError("CONFLICT: event_id already binds different evidence; no files changed")

    # Only constant, allowlisted values can pass into this *local* public-candidate projection.
    # No caller-provided title, machine identity, evidence path, event id, notes, links, or timestamps.
    candidate = {
        "schema_version": CANDIDATE_VERSION,
        "category": event["category"],
        "proof_level": event["proof_level"],
        "publication_state": "CANDIDATE",
        "approval_state": "REVIEW_REQUIRED",
        "reusable_pattern": PATTERNS[event["category"]],
        "provenance": "PRIVATE_LOCAL_EVIDENCE_NOT_PUBLISHED",
    }
    receipt = {
        "schema_version": RECEIPT_VERSION,
        "admission_state": "IDEMPOTENT_REPLAY" if existed else "RECORDED_PRIVATE",
        "private_evidence_state": "PERSISTED_LOCAL",
        "repository_publication_state": "CANDIDATE_ONLY_NOT_COMMITTED",
        "private_provider_sync_state": "NOT_CONFIGURED",
        "external_push_performed": False,
        "event_sha256": digest,
    }
    # Recover safely from a partial interrupted first write; no network or target contact.
    _atomic_write(event_file, raw)
    _atomic_write(candidate_file, _canonical(candidate))
    _atomic_write(receipt_file, _canonical(receipt))
    return receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Record one SAS event once, locally, with a private evidence receipt and gated reusable candidate")
    parser.add_argument("--input", required=True, help="JSON event file, or - for stdin")
    parser.add_argument("--output-root", help="Private evidence directory (default: per-user local SAS evidence)")
    args = parser.parse_args(argv)
    try:
        raw = sys.stdin.buffer.read() if args.input == "-" else Path(args.input).read_bytes()
        if len(raw) > 48000:
            raise AdmissionError("event size exceeds limit")
        event = json.loads(raw)
        result = ingest(event, _root(args.output_root))
    except (AdmissionError, OSError, ValueError, UnicodeError) as exc:
        # Do not echo raw input, private data or file paths in errors.
        label = "CONFLICT" if "CONFLICT" in str(exc) else "ADMISSION_REJECTED"
        print(json.dumps({"admission_state": label, "external_push_performed": False}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
