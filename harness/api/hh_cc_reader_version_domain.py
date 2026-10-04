"""Version-domain classification for H&H PAX A80 / PAXSTORE observations.

Call stacks (success):
  labeled UI observation
    -> classify_labeled_observation
    -> domain bind (LABELED_BIND) without inventing campaign equality

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
DOMAIN_UNRESOLVED = "VERSION_DOMAIN_UNRESOLVED"

KNOWN_DOMAINS = frozenset(
    {
        DOMAIN_PAX_PTS,
        DOMAIN_PAYDROID,
        DOMAIN_EXPERIAN_CC,
        DOMAIN_PAYMENT_APP,
        DOMAIN_PAXSTORE_FW_NAME,
        DOMAIN_UNRESOLVED,
    }
)

_PAYDROID_RE = re.compile(
    r"(?i)(?:PX\w+_A80_PayDroid|A80_PayDroid|PayDroid_\d)",
)
_PTS_RE = re.compile(r"(?i)^(?:25|26)\.\d{2}\.\d+")
_CAMPAIGN_LIKE_RE = re.compile(r"^2\.0\.15\.\d{6}$")


def _norm_text(value: Any) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    return text or None


def _norm_section(value: Any) -> str | None:
    text = _norm_text(value)
    return text.casefold() if text else None


def pattern_hint_domain(value: str | None) -> str | None:
    """Non-authoritative pattern hint only. Never equals a labeled bind."""
    if not value:
        return None
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
        # Authoritative bind uses section/heading labels from the portal.
        if section_cf and "installed firmware" in section_cf:
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
        elif hint:
            domain = DOMAIN_UNRESOLVED
            confidence = "PATTERN_HINT_ONLY"
            reasons.append("labeled_section_or_heading_required_for_bind")
        else:
            confidence = "UNRESOLVED"
            reasons.append("no_label_or_pattern")

    # Numeric similarity alone must never promote a domain bind.
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

    # Primary baseline candidate: prefer Installed Firmware labeled bind, else first labeled.
    primary = None
    for item in classified:
        if item.get("confidence") == "LABELED_BIND" and item.get("section"):
            if "installed firmware" in (item.get("section") or "").casefold():
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


def observations_from_ui_capture(capture: dict[str, Any]) -> list[dict[str, Any]]:
    """Extract labeled observations from a UI capture document."""
    raw = capture.get("labeled_observations") or capture.get("observations")
    if isinstance(raw, list) and raw:
        return [item for item in raw if isinstance(item, dict)]

    # Backward-compatible single-field capture: treat as Installed Firmware only
    # when an explicit section/heading is provided; otherwise leave unresolved.
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
