"""Version-domain classification for H&H PAX A80 / PAXSTORE observations.

Call stacks (success):
  labeled UI observation
    -> classify_labeled_observation
    -> domain bind (LABELED_BIND) without inventing campaign equality

  current installed firmware gate (Kiosk4 / device-local management)
    -> classify_current_firmware_observation
    -> evaluate_baseline_transition_eligibility

  multi-domain capture
    -> evaluate_version_domains
    -> campaign_target_domain_state VERSION_DOMAIN_UNRESOLVED | BOUND

Failure:
  bare value / numeric similarity alone
    -> VERSION_DOMAIN_UNRESOLVED or SIMILARITY_MAPPING_REJECTED

Domains are first-class. Campaign target 2.0.15.260522 remains
VERSION_DOMAIN_UNRESOLVED until a labeled observation binds it.
Never treat an unlabeled public/leaked binary as a deployable package.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

SCHEMA = "sas-hh-cc-reader-version-domain/v1"
CAMPAIGN_TARGET = "2.0.15.260522"

DOMAIN_PAX_PTS = "pax_pts_device_firmware"
DOMAIN_PAYDROID = "paydroid_os_build"
DOMAIN_EXPERIAN_CC = "experian_control_center_payment_package"
DOMAIN_PAYMENT_APP = "payment_application"
DOMAIN_PAXSTORE_FW_NAME = "paxstore_installed_firmware_name"
DOMAIN_PACKAGE_CATALOG = "package_catalog_version"
DOMAIN_SYNTHETIC_DEVICE_FIRMWARE = "synthetic_device_firmware"
DOMAIN_UNRESOLVED = "VERSION_DOMAIN_UNRESOLVED"

KNOWN_DOMAINS = frozenset(
    {
        DOMAIN_PAX_PTS,
        DOMAIN_PAYDROID,
        DOMAIN_EXPERIAN_CC,
        DOMAIN_PAYMENT_APP,
        DOMAIN_PAXSTORE_FW_NAME,
        DOMAIN_PACKAGE_CATALOG,
        DOMAIN_SYNTHETIC_DEVICE_FIRMWARE,
        DOMAIN_UNRESOLVED,
    }
)

# Recognized management / observation surfaces for current-firmware binding.
RECOGNIZED_SOURCE_SURFACES = frozenset(
    {
        "device_local_software_versions",
        "synthetic-device-local-management",
        "synthetic_read_only_version_screen",
        "synthetic-read-only-version-screen",
        "paxstore_terminal_management",
        "experian_control_center",
        "provider_tms_ntms",
    }
)

CANONICAL_OBSERVATION_FRESHNESS_SECONDS = 7 * 24 * 3600

_PAYDROID_RE = re.compile(
    r"(?i)(?:PX\w+_A80_PayDroid|A80_PayDroid|PayDroid_\d)",
)
_PTS_RE = re.compile(r"(?i)^(?:25|26)\.\d{2}\.\d+")
_CAMPAIGN_LIKE_RE = re.compile(r"^2\.0\.15\.\d{6}$")
_SYNTHETIC_FW_RE = re.compile(r"^FW\.TEST\.\d+$", re.IGNORECASE)
_SYNTHETIC_PKG_RE = re.compile(r"^PKG\.TEST\.\d+$", re.IGNORECASE)
_SYNTHETIC_APP_RE = re.compile(r"^APP\.TEST\.\d+$", re.IGNORECASE)


def _norm_text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    return text or None


def _norm_section(value: Any) -> str | None:
    text = _norm_text(value)
    return text.casefold() if text else None


def _device_model_from_observation(observation: dict[str, Any]) -> str | None:
    device = observation.get("device") or observation.get("device_identity")
    if isinstance(device, dict):
        return _norm_text(device.get("model") or device.get("device_family"))
    return _norm_text(observation.get("device_model") or observation.get("model"))


def _is_a80_device(model: str | None) -> bool:
    if not model:
        return False
    folded = model.casefold().replace(" ", "")
    return folded in {"a80", "paxa80"} or "a80" in folded and "non_a80" not in folded


def _parse_observed_at(observation: dict[str, Any]) -> datetime | None:
    raw = _norm_text(observation.get("observed_at"))
    if not raw:
        return None
    text = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def observation_freshness_ok(
    observation: dict[str, Any],
    *,
    now: datetime | None = None,
    max_age_seconds: int = CANONICAL_OBSERVATION_FRESHNESS_SECONDS,
) -> tuple[bool, str | None]:
    observed = _parse_observed_at(observation)
    if observed is None:
        return False, "observed_at_missing_or_unparseable"
    reference = now or datetime.now(timezone.utc)
    age = (reference - observed).total_seconds()
    if age < 0:
        return True, None
    if age > max_age_seconds:
        return False, "observation_stale_vs_canonical_freshness_policy"
    return True, None


def _is_current_firmware_heading(heading_cf: str | None) -> bool:
    if not heading_cf:
        return False
    if heading_cf in {"version"}:
        return False
    return "current firmware" in heading_cf or heading_cf == "installed firmware"


def _is_target_firmware_context(section_cf: str | None, heading_cf: str | None) -> bool:
    if section_cf and "available update" in section_cf:
        return True
    if heading_cf and "target firmware" in heading_cf:
        return True
    return False


def _is_package_catalog_context(section_cf: str | None, heading_cf: str | None) -> bool:
    if section_cf and "package catalog" in section_cf:
        return True
    if heading_cf and "package version" in heading_cf:
        return True
    return False


def _is_application_context(section_cf: str | None, heading_cf: str | None) -> bool:
    if section_cf and section_cf == "applications":
        return True
    if heading_cf and "application version" in heading_cf:
        return True
    return False


def _is_device_information_current_firmware(section_cf: str | None, heading_cf: str | None) -> bool:
    if not section_cf or not heading_cf:
        return False
    return "device information" in section_cf and _is_current_firmware_heading(heading_cf)


def pattern_hint_domain(value: str | None) -> str | None:
    """Non-authoritative pattern hint only. Never equals a labeled bind."""
    if not value:
        return None
    if _SYNTHETIC_FW_RE.match(value):
        return DOMAIN_SYNTHETIC_DEVICE_FIRMWARE
    if _SYNTHETIC_PKG_RE.match(value):
        return DOMAIN_PACKAGE_CATALOG
    if _SYNTHETIC_APP_RE.match(value):
        return DOMAIN_PAYMENT_APP
    if _PTS_RE.match(value):
        return DOMAIN_PAX_PTS
    if _PAYDROID_RE.search(value):
        return DOMAIN_PAYDROID
    if _CAMPAIGN_LIKE_RE.match(value):
        return DOMAIN_EXPERIAN_CC
    return None


def classify_labeled_observation(observation: dict[str, Any]) -> dict[str, Any]:
    """Classify one labeled UI/API observation into a version domain."""
    section = _norm_text(observation.get("section"))
    field_heading = _norm_text(observation.get("field_heading") or observation.get("label"))
    value = _norm_text(
        observation.get("value")
        or observation.get("installed_firmware")
        or observation.get("current_firmware_value")
    )
    package_name = _norm_text(observation.get("package_name") or observation.get("application_name"))
    package_id = _norm_text(observation.get("package_id"))
    section_cf = _norm_section(section)
    heading_cf = _norm_section(field_heading)

    reasons: list[str] = []
    if not value:
        reasons.append("missing_value")
    if not section and not field_heading:
        reasons.append("label_required")

    hint = pattern_hint_domain(value)
    domain = DOMAIN_UNRESOLVED
    confidence = "UNRESOLVED"

    if not reasons:
        if _is_device_information_current_firmware(section_cf, heading_cf):
            domain = DOMAIN_SYNTHETIC_DEVICE_FIRMWARE if hint == DOMAIN_SYNTHETIC_DEVICE_FIRMWARE else (
                DOMAIN_PAYDROID if hint == DOMAIN_PAYDROID else DOMAIN_PAXSTORE_FW_NAME
            )
            confidence = "LABELED_BIND"
        elif _is_package_catalog_context(section_cf, heading_cf):
            domain = DOMAIN_PACKAGE_CATALOG
            confidence = "LABELED_BIND"
        elif _is_target_firmware_context(section_cf, heading_cf):
            domain = DOMAIN_SYNTHETIC_DEVICE_FIRMWARE if hint == DOMAIN_SYNTHETIC_DEVICE_FIRMWARE else DOMAIN_PAXSTORE_FW_NAME
            confidence = "LABELED_BIND"
        elif section_cf and "installed firmware" in section_cf:
            domain = DOMAIN_PAYDROID if hint == DOMAIN_PAYDROID else DOMAIN_PAXSTORE_FW_NAME
            confidence = "LABELED_BIND"
        elif section_cf and ("installed app" in section_cf or section_cf == "installed apps"):
            if hint == DOMAIN_EXPERIAN_CC or (
                package_name
                and any(tok in package_name.casefold() for tok in ("experian", "paymentsafe", "control center", "axia"))
            ):
                domain = DOMAIN_EXPERIAN_CC
            else:
                domain = DOMAIN_PAYMENT_APP
            confidence = "LABELED_BIND"
        elif section_cf and "push firmware" in section_cf:
            domain = DOMAIN_PAYDROID if hint == DOMAIN_PAYDROID else DOMAIN_PAXSTORE_FW_NAME
            confidence = "LABELED_BIND"
        elif section_cf and "push app" in section_cf:
            domain = DOMAIN_EXPERIAN_CC if hint == DOMAIN_EXPERIAN_CC else DOMAIN_PAYMENT_APP
            confidence = "LABELED_BIND"
        elif heading_cf and "installed firmware" in heading_cf:
            domain = DOMAIN_PAYDROID if hint == DOMAIN_PAYDROID else DOMAIN_PAXSTORE_FW_NAME
            confidence = "LABELED_BIND"
        elif _is_application_context(section_cf, heading_cf):
            domain = DOMAIN_PAYMENT_APP
            confidence = "LABELED_BIND"
        elif heading_cf and heading_cf == "version":
            domain = DOMAIN_UNRESOLVED
            confidence = "UNRESOLVED"
            reasons.append("ambiguous_version_heading")
        elif hint:
            domain = DOMAIN_UNRESOLVED
            confidence = "PATTERN_HINT_ONLY"
            reasons.append("labeled_section_or_heading_required_for_bind")
        else:
            confidence = "UNRESOLVED"
            reasons.append("no_label_or_pattern")

    similarity_rejected = False
    if (
        value == CAMPAIGN_TARGET
        and confidence != "LABELED_BIND"
        and not section
        and not field_heading
    ):
        similarity_rejected = True
        reasons.append("similarity_mapping_rejected")

    return {
        "schema": SCHEMA,
        "artifact": "version-domain-observation",
        "section": section,
        "field_heading": field_heading,
        "value": value,
        "package_name": package_name,
        "package_id": package_id,
        "install_time": observation.get("install_time") or observation.get("firmware_install_time"),
        "version_domain": domain,
        "confidence": confidence,
        "pattern_hint": hint,
        "campaign_target": CAMPAIGN_TARGET,
        "matches_campaign_target_value": value == CAMPAIGN_TARGET,
        "similarity_mapping_rejected": similarity_rejected,
        "reasons": reasons,
        "mutation_performed": False,
    }


def classify_current_firmware_observation(observation: dict[str, Any]) -> dict[str, Any]:
    """Classify whether a labeled observation may bind current/installed firmware semantics."""
    domain_result = classify_labeled_observation(observation)
    section_cf = _norm_section(observation.get("section"))
    heading_cf = _norm_section(observation.get("field_heading") or observation.get("label"))
    source_surface = _norm_text(observation.get("source_surface"))
    device_model = _device_model_from_observation(observation)

    reasons: list[str] = list(domain_result.get("reasons") or [])
    classification = "REJECT"
    current_semantic = "rejected"

    if source_surface == "SYNTHETIC_UNKNOWN_SOURCE":
        reasons.append("unsupported_source_surface")
        classification = "FAIL_CLOSED"
        current_semantic = "fail_closed_unsupported_source"
    elif source_surface and source_surface not in RECOGNIZED_SOURCE_SURFACES:
        reasons.append("unsupported_source_surface")
        classification = "FAIL_CLOSED"
        current_semantic = "fail_closed_unsupported_source"
    elif device_model and not _is_a80_device(device_model):
        reasons.append("device_not_a80")
        classification = "REJECT"
        current_semantic = "rejected_wrong_device"
    elif not observation.get("field_heading") and not observation.get("label"):
        if "label_required" not in reasons:
            reasons.append("label_required")
        classification = "REJECT"
        current_semantic = "rejected_unlabeled"
    elif heading_cf == "version":
        reasons.append("ambiguous_version_heading")
        classification = "AMBIGUOUS"
        current_semantic = "ambiguous_version_heading"
    elif _is_target_firmware_context(section_cf, heading_cf):
        reasons.append("reject_as_current_firmware_value_target_context")
        classification = "REJECT"
        current_semantic = "rejected_target_firmware_value"
    elif _is_package_catalog_context(section_cf, heading_cf):
        reasons.append("reject_as_installed_firmware_package_domain")
        classification = "REJECT"
        current_semantic = "rejected_package_version_as_firmware"
    elif _is_application_context(section_cf, heading_cf):
        reasons.append("reject_as_firmware_application_domain")
        classification = "REJECT"
        current_semantic = "rejected_application_version_as_firmware"
    elif (
        domain_result.get("confidence") == "LABELED_BIND"
        and _is_current_firmware_heading(heading_cf)
        and (
            _is_device_information_current_firmware(section_cf, heading_cf)
            or (section_cf and "installed firmware" in section_cf)
            or heading_cf == "installed firmware"
        )
    ):
        fresh_ok, fresh_reason = observation_freshness_ok(observation)
        if not fresh_ok:
            if fresh_reason:
                reasons.append(fresh_reason)
            classification = "REJECT"
            current_semantic = "rejected_stale_observation"
        elif source_surface is None:
            reasons.append("source_surface_required_for_current_bind")
            classification = "REJECT"
            current_semantic = "rejected_missing_source_surface"
        else:
            classification = "CURRENT_FIRMWARE_BOUND"
            current_semantic = "installed_current"
    elif domain_result.get("confidence") != "LABELED_BIND":
        classification = "REJECT"
        current_semantic = "rejected_unbound_domain"

    return {
        **domain_result,
        "artifact": "current-firmware-classification",
        "classification": classification,
        "current_firmware_semantic": current_semantic,
        "source_surface": source_surface,
        "device_model": device_model,
        "reasons": sorted(set(reasons)),
        "mutation_performed": False,
    }


def evaluate_baseline_transition_eligibility(
    classification: dict[str, Any],
    observation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Determine whether a domain-bound current value may advance toward baseline freeze."""
    observation = observation or {}
    state = classification.get("classification")
    reason: str | None = None
    transition = "REJECT"

    if state == "CURRENT_FIRMWARE_BOUND":
        fresh_ok, fresh_reason = observation_freshness_ok(observation)
        if fresh_ok:
            transition = "ALLOWED"
            reason = "current_firmware_domain_bound_with_valid_freshness"
        else:
            transition = "REQUIRE_REFRESH"
            reason = fresh_reason or "observation_stale"
    elif state == "AMBIGUOUS":
        transition = "REJECT"
        reason = "ambiguous_field_heading"
    elif state == "FAIL_CLOSED":
        transition = "REJECT"
        reason = classification.get("current_firmware_semantic") or "fail_closed"
    else:
        semantic = classification.get("current_firmware_semantic") or "rejected"
        transition = "REQUIRE_REFRESH" if semantic == "rejected_stale_observation" else "REJECT"
        reason = semantic

    return {
        "schema": SCHEMA,
        "artifact": "baseline-transition-eligibility",
        "baseline_transition": transition,
        "reason": reason,
        "mutation_authorized": False,
    }


def evaluate_version_domains(
    observations: list[dict[str, Any]],
    *,
    campaign_target: str = CAMPAIGN_TARGET,
) -> dict[str, Any]:
    """Evaluate a set of labeled observations and campaign-target domain state."""
    classified = [classify_labeled_observation(item) for item in observations]
    by_domain: dict[str, list[dict[str, Any]]] = {}
    for item in classified:
        by_domain.setdefault(item["version_domain"], []).append(item)

    bound_campaign = [
        item
        for item in classified
        if item.get("matches_campaign_target_value")
        and item.get("confidence") == "LABELED_BIND"
        and item.get("version_domain") != DOMAIN_UNRESOLVED
    ]
    if bound_campaign:
        campaign_state = "BOUND"
        campaign_domain = bound_campaign[0]["version_domain"]
    else:
        campaign_state = "VERSION_DOMAIN_UNRESOLVED"
        campaign_domain = DOMAIN_UNRESOLVED

    primary = None
    for item in classified:
        if item.get("confidence") != "LABELED_BIND":
            continue
        section_cf = _norm_section(item.get("section"))
        heading_cf = _norm_section(item.get("field_heading"))
        if section_cf and "installed firmware" in section_cf:
            primary = item
            break
        if _is_device_information_current_firmware(section_cf, heading_cf):
            primary = item
            break
    if primary is None:
        for item in classified:
            if item.get("confidence") == "LABELED_BIND" and item.get("value"):
                primary = item
                break

    sourcing_path = {
        "state": "MARKETPLACE_MEDIATED",
        "path": [
            "experian_or_control_center_owner_defines_accepted_package_domain",
            "paxstore_marketplace_or_reseller_exposes_model_eligible_package",
            "terminal_management_push_firmware_or_push_app",
            "kiosk_terminal_installs_and_reports_labeled_value",
        ],
        "forbidden_sources": [
            "unlabeled_public_zip",
            "leaked_or_darkweb_image",
            "numeric_similarity_guess",
            "tracker_chronology_inference",
        ],
    }

    return {
        "schema": SCHEMA,
        "artifact": "version-domain-evaluation",
        "campaign_target": campaign_target,
        "campaign_target_domain_state": campaign_state,
        "campaign_target_version_domain": campaign_domain,
        "observations": classified,
        "domains_present": sorted(d for d in by_domain if d != DOMAIN_UNRESOLVED),
        "primary_observation": primary,
        "sourcing_path": sourcing_path,
        "mutation_performed": False,
        "deploy_eligible_on_domain_alone": False,
    }


def evaluate_fixture_receipt(fixture: dict[str, Any]) -> dict[str, Any]:
    """Run one synthetic fixture and return a pass/fail receipt with exit status."""
    fixture_id = _norm_text(fixture.get("fixture_id")) or "UNKNOWN"
    observation = fixture.get("input") or fixture.get("observation") or {}
    expected = fixture.get("expected") or {}

    classification = classify_current_firmware_observation(observation)
    transition = evaluate_baseline_transition_eligibility(classification, observation)

    expected_classification = expected.get("classification")
    expected_transition = expected.get("baseline_transition")
    expected_domain = expected.get("version_domain")

    actual_classification = classification.get("classification")
    actual_transition = transition.get("baseline_transition")
    actual_domain = classification.get("version_domain")

    checks: list[str] = []
    if expected_classification is not None and actual_classification != expected_classification:
        checks.append("classification_mismatch")
    if expected_transition is not None and actual_transition != expected_transition:
        checks.append("baseline_transition_mismatch")
    if expected_domain is not None and actual_domain != expected_domain:
        checks.append("version_domain_mismatch")

    passed = not checks
    exit_status = 0 if passed else 2
    reason = ";".join(checks) if checks else transition.get("reason") or classification.get("current_firmware_semantic")

    return {
        "schema": SCHEMA,
        "artifact": "version-domain-fixture-receipt",
        "fixture_id": fixture_id,
        "input": observation,
        "expected_classification": expected_classification,
        "actual_classification": actual_classification,
        "expected_transition": expected_transition,
        "actual_transition": actual_transition,
        "expected_version_domain": expected_domain,
        "actual_version_domain": actual_domain,
        "reason": reason,
        "exit_status": exit_status,
        "passed": passed,
        "classification_detail": classification,
        "transition_detail": transition,
        "mutation_performed": False,
    }


def observations_from_ui_capture(capture: dict[str, Any]) -> list[dict[str, Any]]:
    """Extract labeled observations from a UI capture document."""
    raw = capture.get("labeled_observations") or capture.get("observations")
    if isinstance(raw, list) and raw:
        enriched: list[dict[str, Any]] = []
        capture_context = {
            "source_surface": capture.get("source_surface"),
            "observed_at": capture.get("observed_at"),
        }
        device_identity = capture.get("device_identity")
        if isinstance(device_identity, dict):
            capture_context["device"] = device_identity
        for item in raw:
            if not isinstance(item, dict):
                continue
            merged = {**capture_context, **item}
            enriched.append(merged)
        return enriched

    value = _norm_text(
        capture.get("installed_firmware")
        or capture.get("current_firmware_value")
        or capture.get("installedFirmware")
    )
    if not value:
        return []
    return [
        {
            "section": capture.get("installed_firmware_section") or capture.get("section"),
            "field_heading": capture.get("installed_firmware_field_heading")
            or capture.get("field_heading"),
            "value": value,
            "package_name": capture.get("package_name"),
            "package_id": capture.get("package_id") or capture.get("target_package_id"),
            "install_time": capture.get("firmware_install_time") or capture.get("install_time"),
            "source_surface": capture.get("source_surface"),
            "observed_at": capture.get("observed_at"),
            "device": capture.get("device_identity"),
        }
    ]


def _write_receipt(payload: dict[str, Any], output: Path | None) -> Path:
    out_dir = ROOT / "survey" / "output" / "hh-cc-reader"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = output or (
        out_dir / f"hh-cc-reader-version-domain-{time.strftime('%Y%m%d-%H%M%S')}.json"
    )
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Classify labeled PAXSTORE/UI version-domain observations (read-only)."
    )
    parser.add_argument("--input", required=True, help="UI capture or observations JSON")
    parser.add_argument("--output", default=None, help="Receipt path")
    args = parser.parse_args(argv)

    payload = json.loads(Path(args.input).read_text(encoding="utf-8-sig"))
    if isinstance(payload, list):
        result = evaluate_version_domains(payload)
    else:
        result = evaluate_version_domains(observations_from_ui_capture(payload))

    path = _write_receipt(result, Path(args.output) if args.output else None)
    print(json.dumps(result, indent=2))
    print(f"RECEIPT={path}", file=sys.stderr)

    if result.get("campaign_target_domain_state") == "BOUND":
        return 0
    if result.get("primary_observation"):
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
