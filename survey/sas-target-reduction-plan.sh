#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "target reduction requires python3 for local CSV transforms" >&2
  echo "No network activity was attempted." >&2
  exit 127
fi

python3 - "$repo_root" "$@" <<'PY'
from __future__ import annotations

import argparse
from collections import Counter
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(sys.argv[1]).resolve()
ARGS = sys.argv[2:]
sys.path.insert(0, str(REPO_ROOT))
from harness.api.low_noise_policy import load_policy

REDUCTION_COLUMNS = [
    "Target", "Serial", "Site", "Location", "SubnetCIDR", "Status", "StatusReason",
    "ReachabilityEvidence", "IdentityEvidence", "LowNoisePolicyVersion", "LowNoiseDisposition",
    "ProbeAgainGuidance", "FreshEvidenceGuidance", "NetworkVisibilityNote", "NetworkActivityPerformed", "SourceEvidence",
]
LOCATION_COLUMNS = [
    "Site", "Location", "Building", "Floor", "SubnetCIDR", "Gateway", "Target", "Status",
    "StatusReason", "SourceEvidence", "LastVerified", "SurveyAllowed", "Confidence", "Notes", "NetworkActivityPerformed",
]

POLICY_DOCUMENT = load_policy()
POLICY = {"policy_version": POLICY_DOCUMENT["policy_version"], **POLICY_DOCUMENT["guidance"]}

TARGET_FIELDS = ["Target", "ProbeTarget", "HostName", "Hostname", "ComputerName", "DeviceName", "Name", "DnsName", "DNSName", "FQDN", "IPAddress", "IP", "IPv4"]
SERIAL_FIELDS = ["Serial", "SerialNumber", "DeviceSerial", "ComputerSerial", "AssetSerial", "SN"]
LOCATION_FIELDS = ["Location", "Room", "Department", "Area"]


def normalize_arg(arg: str) -> str:
    aliases = {
        "-PriorProbeResults": "--prior-probe-results",
        "-LocationSubnetMap": "--location-subnet-map",
        "-IdentityEvidence": "--identity-evidence",
        "-RunId": "--run-id",
        "-OutputDirectory": "--output-directory",
        "-AllowFixtures": "--allow-fixtures",
        "-AllowNonstandardInput": "--allow-nonstandard-input",
    }
    return aliases.get(arg, arg)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Build local target reduction queues from CSV evidence.")
    p.add_argument("--prior-probe-results", required=True)
    p.add_argument("--location-subnet-map")
    p.add_argument("--identity-evidence")
    p.add_argument("--run-id")
    p.add_argument("--output-directory")
    p.add_argument("--allow-fixtures", action="store_true")
    p.add_argument("--allow-nonstandard-input", action="store_true")
    return p


def safe_run_id(candidate: str | None) -> str:
    if candidate:
        cleaned = re.sub(r"[^a-z0-9_-]", "-", candidate.lower()).strip("-")
        if cleaned:
            return cleaned
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def within(path: Path, roots: list[Path]) -> bool:
    try:
        resolved = path.resolve()
    except FileNotFoundError:
        resolved = path.absolute()
    for root in roots:
        try:
            resolved.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False


def assert_input_path(path_text: str, allow_fixtures: bool, allow_nonstandard: bool, label: str) -> Path:
    path = Path(path_text)
    if not path.is_absolute():
        path = REPO_ROOT / path
    path = path.resolve()
    roots = [REPO_ROOT / "survey" / "input", REPO_ROOT / "survey" / "output", REPO_ROOT / "survey" / "artifacts", REPO_ROOT / "logs" / "nmap"]
    if allow_fixtures:
        roots.append(REPO_ROOT / "survey" / "fixtures")
    if not allow_nonstandard and not within(path, roots):
        raise SystemExit(f"{label} is outside approved local input roots: {path}")
    if not path.exists():
        raise SystemExit(f"{label} does not exist: {path}")
    return path


def assert_output_path(path_text: str) -> Path:
    path = Path(path_text)
    if not path.is_absolute():
        path = REPO_ROOT / path
    path = path.resolve()
    roots = [REPO_ROOT / "survey" / "output", REPO_ROOT / "survey" / "artifacts", REPO_ROOT / "logs" / "nmap"]
    if not within(path, roots):
        raise SystemExit(f"target reduction output directory is outside approved local output roots: {path}")
    return path


def read_csv(path: Path, label: str, required_groups: list[list[str]]) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames:
            raise SystemExit(f"{label} has no CSV header: {path}")
        headers = [header.strip() if header is not None else "" for header in reader.fieldnames]
        if any(not header for header in headers):
            raise SystemExit(f"{label} has a blank CSV header: {path}")
        normalized_headers = [header.lower() for header in headers]
        if len(normalized_headers) != len(set(normalized_headers)):
            raise SystemExit(f"{label} has duplicate case-insensitive CSV headers: {path}")
        for group in required_groups:
            if not any(name.lower() in normalized_headers for name in group):
                raise SystemExit(f"{label} is missing a required CSV column ({', '.join(group)}): {path}")

        rows: list[dict[str, str]] = []
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                raise SystemExit(f"{label} row {row_number} has more values than the CSV header: {path}")
            if any(value is None for value in row.values()):
                raise SystemExit(f"{label} row {row_number} has fewer values than the CSV header: {path}")
            cleaned = {str(k).strip(): (v or "").strip() for k, v in row.items()}
            if any(cleaned.values()):
                rows.append(cleaned)
        return rows


def first(row: dict[str, str] | None, names: list[str]) -> str:
    if not row:
        return ""
    lower = {k.lower(): v for k, v in row.items()}
    for name in names:
        value = lower.get(name.lower(), "")
        if value:
            return value.strip()
    return ""


def key(value: str) -> str:
    return value.strip().lower()


def target(row: dict[str, str] | None) -> str:
    return first(row, TARGET_FIELDS)


def serial(row: dict[str, str] | None) -> str:
    return first(row, SERIAL_FIELDS)


def site(row: dict[str, str] | None) -> str:
    return first(row, ["Site"])


def location(row: dict[str, str] | None) -> str:
    return first(row, LOCATION_FIELDS)


def loc_key(row: dict[str, str] | None) -> str:
    return f"{key(site(row))}|{key(location(row))}"


def truthy(value: str) -> bool:
    return key(value) in {"1", "true", "yes", "y", "fresh", "current", "inscope", "in_scope", "in-scope"}


def is_reached(row: dict[str, str]) -> bool:
    values = [
        first(row, ["ReachabilityStatus", "Status", "Result"]),
        first(row, ["PortStatus", "TcpStatus", "TCPStatus"]),
    ]
    return any(key(value) in {"reached", "reachable", "success", "online", "open", "confirmedreached"} for value in values if value)


def is_retry_signal(row: dict[str, str]) -> bool:
    values = [
        first(row, ["ReachabilityStatus", "Status", "Result"]),
        first(row, ["PortStatus", "TcpStatus", "TCPStatus"]),
        first(row, ["DnsStatus", "DNSStatus"]),
    ]
    return any(key(value) in {"notreached", "not_reached", "not_reachable", "closed", "filtered", "dnsfailed", "dns_failed", "unresolved"} for value in values if value)


def identity_review_required(probe_row: dict[str, str], identity_row: dict[str, str] | None) -> bool:
    bad = {"missing", "missingbridge", "missing_bridge", "nobridge", "no_bridge", "conflicting", "conflict", "stale", "serialmismatch", "serial_mismatch", "reviewrequired", "review_required"}
    for row in [probe_row, identity_row]:
        for name in ["IdentityStatus", "IdentityEvidenceStatus", "BridgeStatus", "SerialStatus", "TargetBridgeStatus"]:
            if key(first(row, [name])) in bad:
                return True
    return False


def reachability_text(row: dict[str, str]) -> str:
    return ";".join(v for v in [first(row, ["ReachabilityStatus", "Status", "Result"]), first(row, ["PortStatus", "TcpStatus", "TCPStatus"]), first(row, ["DnsStatus", "DNSStatus"])] if v)


def identity_text(probe_row: dict[str, str], identity_row: dict[str, str] | None) -> str:
    values: list[str] = []
    for row in [probe_row, identity_row]:
        for name in ["IdentityStatus", "IdentityEvidenceStatus", "BridgeStatus", "SerialStatus", "TargetBridgeStatus", "SourceEvidence", "EvidencePath", "EvidenceSource"]:
            value = first(row, [name])
            if value and value not in values:
                values.append(value)
    return ";".join(values) if values else "not_identity_proof"


def reduction_row(probe_row: dict[str, str], status: str, reason: str, identity_row: dict[str, str] | None, location_row: dict[str, str] | None) -> dict[str, str]:
    source = first(probe_row, ["SourceEvidence", "EvidencePath", "EvidenceSource", "SourceFile"]) or "prior_probe_results_csv"
    return {
        "Target": target(probe_row),
        "Serial": serial(probe_row),
        "Site": site(probe_row),
        "Location": location(probe_row),
        "SubnetCIDR": first(location_row, ["SubnetCIDR", "Subnet", "CIDR"]) or first(probe_row, ["SubnetCIDR", "Subnet", "CIDR"]),
        "Status": status,
        "StatusReason": reason,
        "ReachabilityEvidence": reachability_text(probe_row),
        "IdentityEvidence": identity_text(probe_row, identity_row),
        "LowNoisePolicyVersion": POLICY["policy_version"],
        "LowNoiseDisposition": status,
        "ProbeAgainGuidance": POLICY["probe_again_guidance"],
        "FreshEvidenceGuidance": POLICY["fresh_evidence_guidance"],
        "NetworkVisibilityNote": POLICY["network_visibility_note"],
        "NetworkActivityPerformed": "false",
        "SourceEvidence": source,
    }


def location_candidate_row(probe_row: dict[str, str], location_row: dict[str, str]) -> dict[str, str]:
    return {
        "Site": site(location_row),
        "Location": location(location_row),
        "Building": first(location_row, ["Building"]),
        "Floor": first(location_row, ["Floor"]),
        "SubnetCIDR": first(location_row, ["SubnetCIDR", "Subnet", "CIDR"]),
        "Gateway": first(location_row, ["Gateway"]),
        "Target": target(probe_row),
        "Status": "DeferredSubnetCandidate",
        "StatusReason": "local location map suggests a bounded candidate; this is not identity proof",
        "SourceEvidence": first(location_row, ["SourceEvidence", "EvidencePath", "EvidenceSource"]),
        "LastVerified": first(location_row, ["LastVerified"]),
        "SurveyAllowed": first(location_row, ["SurveyAllowed", "Allowed"]),
        "Confidence": first(location_row, ["Confidence"]),
        "Notes": first(location_row, ["Notes"]),
        "NetworkActivityPerformed": "false",
    }


def out_of_scope(probe_row: dict[str, str], identity_row: dict[str, str] | None, location_row: dict[str, str] | None) -> bool:
    for row in [probe_row, identity_row]:
        if key(first(row, ["Scope", "SurveyScope", "Disposition"])) in {"outofscope", "out_of_scope", "out-of-scope"}:
            return True
    allowed = first(location_row, ["SurveyAllowed", "Allowed"])
    return bool(allowed and not truthy(allowed))


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    normalized = [normalize_arg(arg) for arg in ARGS]
    ns = parser().parse_args(normalized)
    prior_path = assert_input_path(ns.prior_probe_results, ns.allow_fixtures, ns.allow_nonstandard_input, "prior evidence CSV")
    location_path = assert_input_path(ns.location_subnet_map, ns.allow_fixtures, ns.allow_nonstandard_input, "location map CSV") if ns.location_subnet_map else None
    identity_path = assert_input_path(ns.identity_evidence, ns.allow_fixtures, ns.allow_nonstandard_input, "identity evidence CSV") if ns.identity_evidence else None

    run_id = safe_run_id(ns.run_id)
    output_dir = assert_output_path(ns.output_directory or str(REPO_ROOT / "survey" / "output" / "target_reduction" / run_id))

    prior_rows = read_csv(prior_path, "prior evidence CSV", [TARGET_FIELDS])
    if not prior_rows:
        raise SystemExit("Prior evidence CSV had no rows.")
    identity_rows = read_csv(identity_path, "identity evidence CSV", [TARGET_FIELDS + SERIAL_FIELDS]) if identity_path else []
    location_rows = read_csv(location_path, "location map CSV", [["Site"], LOCATION_FIELDS]) if location_path else []

    identity_by_target: dict[str, dict[str, str]] = {}
    identity_by_serial: dict[str, dict[str, str]] = {}
    for row in identity_rows:
        if target(row):
            identity_by_target.setdefault(key(target(row)), row)
        if serial(row):
            identity_by_serial.setdefault(key(serial(row)), row)
    locations: dict[str, dict[str, str]] = {}
    for row in location_rows:
        if loc_key(row) != "|":
            locations.setdefault(loc_key(row), row)
    target_counts = Counter(key(target(row)) for row in prior_rows if target(row))

    reduced: list[dict[str, str]] = []
    retry: list[dict[str, str]] = []
    review: list[dict[str, str]] = []
    outscope: list[dict[str, str]] = []
    location_candidates: list[dict[str, str]] = []

    for row in prior_rows:
        identity_row = identity_by_target.get(key(target(row))) or identity_by_serial.get(key(serial(row)))
        location_row = locations.get(loc_key(row))
        if out_of_scope(row, identity_row, location_row):
            outscope.append(reduction_row(row, "OutOfScope", "outside approved survey scope", identity_row, location_row))
            continue
        if not target(row):
            if location_row and truthy(first(location_row, ["SurveyAllowed", "Allowed"])):
                location_candidates.append(location_candidate_row(row, location_row))
            review.append(reduction_row(row, "ReviewRequired", "missing or conflicting identity evidence", identity_row, location_row))
            continue
        if target_counts[key(target(row))] > 1:
            review.append(reduction_row(row, "ReviewRequired", "duplicate or case-variant target rows require review", identity_row, location_row))
            continue
        if identity_review_required(row, identity_row):
            review.append(reduction_row(row, "ReviewRequired", "missing or conflicting identity evidence", identity_row, location_row))
            continue
        if is_reached(row):
            reduced.append(reduction_row(row, "ConfirmedReached", "prior local reachability evidence exists; this is not identity proof", identity_row, location_row))
            continue
        if is_retry_signal(row):
            retry.append(reduction_row(row, "RetryCandidate", "negative local evidence is not proof the device is gone", identity_row, location_row))
        else:
            review.append(reduction_row(row, "ReviewRequired", "ambiguous local evidence requires review", identity_row, location_row))

    classified_row_count = len(reduced) + len(retry) + len(review) + len(outscope)
    if classified_row_count != len(prior_rows):
        raise RuntimeError(f"target reduction classification count mismatch: input={len(prior_rows)} classified={classified_row_count}")

    paths = {
        "reduced_targets_csv": output_dir / "reduced_targets.csv",
        "retry_candidates_csv": output_dir / "retry_candidates.csv",
        "review_required_csv": output_dir / "review_required.csv",
        "out_of_scope_csv": output_dir / "out_of_scope.csv",
        "location_subnet_candidates_csv": output_dir / "location_subnet_candidates.csv",
        "target_reduction_summary_json": output_dir / "target_reduction_summary.json",
        "operator_handoff_path": output_dir / "operator_handoff.txt",
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(paths["reduced_targets_csv"], REDUCTION_COLUMNS, reduced)
    write_csv(paths["retry_candidates_csv"], REDUCTION_COLUMNS, retry)
    write_csv(paths["review_required_csv"], REDUCTION_COLUMNS, review)
    write_csv(paths["out_of_scope_csv"], REDUCTION_COLUMNS, outscope)
    write_csv(paths["location_subnet_candidates_csv"], LOCATION_COLUMNS, location_candidates)

    summary = {
        "workflow_id": "target_reduction",
        "operation_id": "target_reduction.plan",
        "run_id": run_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "prior_probe_results_csv": str(prior_path),
        "input_row_count": len(prior_rows),
        "classified_row_count": classified_row_count,
        "classification_reconciled": True,
        "confirmed_reached_count": len(reduced),
        "retry_candidate_count": len(retry),
        "review_required_count": len(review),
        "deferred_subnet_candidate_count": len(location_candidates),
        "out_of_scope_count": len(outscope),
        "required_statuses": ["ConfirmedReached", "RetryCandidate", "ReviewRequired", "DeferredSubnetCandidate", "OutOfScope"],
        "network_activity_performed": False,
        "target_mutation_performed": False,
        "low_noise_policy_version": POLICY["policy_version"],
        "low_noise_principle": POLICY["low_noise_principle"],
        "network_visibility_note": POLICY["network_visibility_note"],
        "probe_selection_questions": POLICY["probe_selection_questions"],
        "probe_again_guidance": POLICY["probe_again_guidance"],
        "fresh_evidence_guidance": POLICY["fresh_evidence_guidance"],
        "mystery_serial_guidance": POLICY["mystery_serial_guidance"],
        "front_door_guidance": POLICY["front_door_guidance"],
        "packet_profile_guidance": POLICY["packet_profile_guidance"],
        **{key_name: str(value) for key_name, value in paths.items()},
    }
    paths["target_reduction_summary_json"].write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    paths["operator_handoff_path"].write_text("\n".join([
        "SysAdminSuite target reduction handoff",
        f"RunId: {run_id}",
        "Operation: target_reduction.plan",
        f"Rows consumed: {len(prior_rows)}",
        f"Confirmed reached: {len(reduced)}",
        f"Retry candidates: {len(retry)}",
        f"Review required: {len(review)}",
        f"Deferred subnet candidates: {len(location_candidates)}",
        f"Out of scope: {len(outscope)}",
        "",
        "Artifacts:",
        *[f"- {value}" for value in paths.values()],
        "",
        "Planner network activity performed: false",
        "Target mutation performed: false",
        "Next action: review retry, review, and out-of-scope queues before any follow-up action.",
        "",
    ]), encoding="utf-8")

    print(f"Target reduction plan complete: {run_id}")
    print(f"Confirmed reached: {len(reduced)}")
    print(f"Retry candidates: {len(retry)}")
    print(f"Review required: {len(review)}")
    print(f"Deferred subnet candidates: {len(location_candidates)}")
    print(f"Out of scope: {len(outscope)}")
    print(f"Summary: {paths['target_reduction_summary_json']}")
    return 0


raise SystemExit(main())
PY
