"""Resolve independently approved Platform-Tools archive pins for prepare_bundle.

Pin authority is a reviewed catalog entry. Post-download hashes, WinGet YAML, and
mutable latest URLs never promote a pin. This module performs no network I/O.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "sas-platform-tools-archive-pins/v1"
ARTIFACT_ID = "android-platform-tools-windows"
IMMUTABLE_URL = re.compile(
    r"^https://dl\.google\.com/android/repository/platform-tools_r[0-9]+\.[0-9]+\.[0-9]+-win\.zip$"
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ROLES = frozenset({"ptop_lab", "adminbox_reference", "technician_adminbox_field"})
APPROVED = "approved_for_provider_prepare"
DEFAULT_CATALOG = (
    Path(__file__).resolve().parents[2]
    / "configs/android-provider/sas-platform-tools-archive-pins.json"
)


class PinResolutionError(RuntimeError):
    """Typed pin/policy failure; message is a stable reason code."""


def load_catalog(path: Path | None = None) -> dict[str, Any]:
    catalog_path = path or DEFAULT_CATALOG
    try:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise PinResolutionError("INDEPENDENT_APPROVAL_REQUIRED") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise PinResolutionError("SOURCE_POLICY_DENIED") from exc
    if catalog.get("schema_version") != SCHEMA_VERSION or not isinstance(catalog.get("pins"), list):
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    return catalog


def _validate_pin_shape(pin: dict[str, Any]) -> None:
    if pin.get("artifact_id") != ARTIFACT_ID:
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    url = str(pin.get("acquisition_url", ""))
    if "platform-tools-latest-windows.zip" in url or not IMMUTABLE_URL.fullmatch(url):
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    digest = str(pin.get("expected_archive_sha256", "")).lower()
    if not SHA256.fullmatch(digest):
        raise PinResolutionError("INDEPENDENT_APPROVAL_REQUIRED")
    if digest == "0" * 64:
        raise PinResolutionError("INDEPENDENT_APPROVAL_REQUIRED")
    if not str(pin.get("approval_reference") or "").strip():
        raise PinResolutionError("INDEPENDENT_APPROVAL_REQUIRED")
    if str(pin.get("approval_reference")).upper().startswith("PENDING"):
        raise PinResolutionError("INDEPENDENT_APPROVAL_REQUIRED")
    roles = pin.get("allowed_node_roles")
    if not isinstance(roles, list) or not roles or set(roles) - ROLES:
        raise PinResolutionError("SOURCE_POLICY_DENIED")


def resolve(
    node_role: str,
    *,
    artifact_id: str = ARTIFACT_ID,
    catalog_path: Path | None = None,
) -> dict[str, Any]:
    """Return the single approved pin for artifact+role or raise a typed code."""
    if node_role not in ROLES:
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    catalog = load_catalog(catalog_path)
    candidates = [
        pin for pin in catalog["pins"]
        if isinstance(pin, dict) and pin.get("artifact_id") == artifact_id
    ]
    if not candidates:
        raise PinResolutionError("QUALIFICATION_AUTHORITY_REQUIRED")
    approved = [
        pin for pin in candidates
        if pin.get("promotion_status") == APPROVED
    ]
    if not approved:
        # Placeholder/blocked rows document the intended version without enabling prepare.
        raise PinResolutionError("QUALIFICATION_AUTHORITY_REQUIRED")
    matching = [pin for pin in approved if node_role in set(pin.get("allowed_node_roles") or [])]
    if not matching:
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    if len(matching) != 1:
        raise PinResolutionError("SOURCE_POLICY_DENIED")
    pin = matching[0]
    _validate_pin_shape(pin)
    return {
        "artifact_id": pin["artifact_id"],
        "version": pin["version"],
        "acquisition_url": pin["acquisition_url"],
        "expected_archive_sha256": str(pin["expected_archive_sha256"]).lower(),
        "approval_reference": pin["approval_reference"],
        "allowed_node_roles": list(pin["allowed_node_roles"]),
        "promotion_status": pin["promotion_status"],
        "acquisition_evidence": pin.get("acquisition_evidence"),
    }
