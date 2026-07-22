#!/usr/bin/env python3
"""Validate durable AutoLogon E2E artifacts against their closed schemas."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FLOOR_VALIDATOR = (
    ROOT / "Tests" / "survey" / "test_autologon_proof_contract_floor_contracts.py"
)
ALLOWED_SCHEMAS = {
    "schemas/harness/autologon-deployment-result.schema.json",
    "schemas/harness/autologon-final-step-gate-result.schema.json",
    "schemas/harness/autologon-state-proof-result.schema.json",
    "schemas/harness/autologon-session-access-proof.schema.json",
    "schemas/harness/autologon-technician-runtime-proof.schema.json",
    "schemas/harness/autologon-proof-source-evidence.schema.json",
    "schemas/harness/autologon-proof-receipt.schema.json",
    "schemas/harness/autologon-canonical-e2e-result.schema.json",
}
PUBLIC_RECEIPT_KEYS = {
    "schema_version",
    "source_evidence_sha256",
    "source_evidence_size_bytes",
    "classification",
    "proof_level",
    "reason_codes",
    "operator_confirmed",
    "privacy_status",
}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_floor_validator() -> Any:
    spec = importlib.util.spec_from_file_location("sas_autologon_floor_validator", FLOOR_VALIDATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load validator: {FLOOR_VALIDATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resolve_repo_path(value: str, role: str) -> Path:
    candidate = (ROOT / value).resolve() if not Path(value).is_absolute() else Path(value).resolve()
    try:
        candidate.relative_to(ROOT)
    except ValueError as exc:
        raise ValueError(f"{role} escapes the repository root: {value}") from exc
    return candidate


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()

    manifest_path = resolve_repo_path(args.manifest, "manifest")
    manifest = load(manifest_path)
    if manifest.get("schema_version") != "sas-autologon-e2e-artifact-validation/v1":
        raise ValueError("unsupported validation manifest schema")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("validation manifest must contain at least one artifact")

    validator = load_floor_validator()
    validated = 0
    for item in artifacts:
        if set(item) != {"role", "path", "schema"}:
            raise ValueError("artifact records must contain only role, path, and schema")
        schema_name = item["schema"].replace("\\", "/")
        if schema_name not in ALLOWED_SCHEMAS:
            raise ValueError(f"schema is outside the AutoLogon E2E allowlist: {schema_name}")
        artifact_path = resolve_repo_path(item["path"], f"artifact {item['role']}")
        schema_path = resolve_repo_path(schema_name, f"schema {item['role']}")
        if not artifact_path.is_file() or not schema_path.is_file():
            raise FileNotFoundError(f"missing artifact or schema for {item['role']}")
        payload = load(artifact_path)
        schema = load(schema_path)
        validator.validate_instance(payload, schema)
        if payload.get("schema_version") == "sas-autologon-proof-receipt/v1":
            if set(payload) != PUBLIC_RECEIPT_KEYS:
                raise ValueError("public receipt contains a private or unknown field")
            if payload["classification"] != "contract_only":
                raise ValueError("fixture receipt promoted beyond contract_only")
        validated += 1

    print(f"PASS: {validated} durable AutoLogon E2E artifacts validated")


if __name__ == "__main__":
    main()
