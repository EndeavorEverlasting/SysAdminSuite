#!/usr/bin/env python3
"""Cybernet subnet/location inference from approved hostname and IP CSV evidence.

Read-only local enrichment. Does not scan networks, query AD, or mutate endpoints.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import ipaddress
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

PREFIX_RE = re.compile(r"^([A-Z]{2,4})(\d{2,4})([A-Z]{2,6})(\d*)$")
EMPTY = {"", "N/A", "NA", "NONE", "NULL", "-", "--", "TBD", "UNKNOWN", "#N/A"}


def _load_classifier():
    module_path = Path(__file__).with_name("sas-survey-device-classify.py")
    spec = importlib.util.spec_from_file_location("sas_survey_device_classify", module_path)
    if not spec or not spec.loader:
        raise RuntimeError(f"could not load classifier module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_CLASSIFY = _load_classifier()

HOST_FIELDS = [
    "NormalizedHostName",
    "HostName",
    "IPAddress",
    "Subnet",
    "FacilityPrefix",
    "LocationCode",
    "LocationLabel",
    "Status",
    "Confidence",
    "Score",
    "ReviewReason",
    "IPSource",
    "SurveyAuthority",
    "PrimaryKey",
    "PrimaryKeyType",
    "FallbackUsed",
    "FallbackType",
    "FallbackReason",
    "SerialEvidenceStatus",
    "HostnameEvidenceStatus",
    "Blocker",
    "NextAction",
    "EvidenceSources",
    "Site",
    "SourceFiles",
    "DeviceRole",
    "RoleConfidence",
    "RoleSignals",
    "CountsTowardCybernetPopulation",
]

MAP_FIELDS = [
    "Subnet",
    "LocationCodes",
    "LocationLabels",
    "HostCount",
    "FacilityPrefixes",
    "Status",
    "Confidence",
    "Score",
    "ScoreSignals",
    "ReviewReason",
]

FACILITY_PAIR_REVIEW = frozenset({"WNH", "WMH"})
SERIAL_ALIASES = [
    "ObservedSerial",
    "Serial",
    "SerialNumber",
    "SystemSerialNumber",
    "BiosSerial",
    "ResolvedSerial",
    "ExpectedSerial",
    "ExpectedCybernetSerial",
    "Cybernet Serial",
    "Cybernet S/N",
]
PROOF_STATUS_ALIASES = [
    "IdentityStatus",
    "EvidenceStatus",
    "SerialProbeStatus",
    "ProbeStatus",
    "WmiStatus",
    "serial_probe_status",
]
SERIAL_PROOF_TOKENS = (
    "identitycollected",
    "wmiidentitycollected",
    "serial_confirmed",
    "live_serial_confirmed",
    "identity_resolved",
    "identitycollected",
    "confirmed",
    "match",
    "found",
)


def clean(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def first(row: dict[str, str], names: Iterable[str]) -> str:
    lowered = {str(k).lower(): clean(v) for k, v in row.items()}
    for name in names:
        if name in row and clean(row[name]):
            return clean(row[name])
        key = name.lower()
        if key in lowered and lowered[key]:
            return lowered[key]
    return ""


def is_empty_value(value: str) -> bool:
    return clean(value).upper() in EMPTY


def is_serial_identifier(row: dict[str, str]) -> bool:
    ident_type = first(row, ["IdentifierType", "Type", "KeyType"]).lower()
    return "serial" in ident_type or ident_type in {"sn", "s/n", "service_tag", "servicetag"}


def usable_serial(value: str) -> str:
    text = clean(value).upper()
    if not text or text in EMPTY:
        return ""
    return text


def status_has_serial_proof(value: str) -> bool:
    text = re.sub(r"[^a-z0-9_]+", "", clean(value).lower())
    return any(token in text for token in SERIAL_PROOF_TOKENS)


def normalize_host(value: str) -> str:
    text = clean(value).upper()
    if not text:
        return ""
    short = text.split(".", 1)[0]
    short = re.sub(r"[^A-Z0-9_-]", "", short)
    return short


def usable_ipv4(value: str) -> bool:
    text = clean(value)
    if not text or text.upper() in EMPTY:
        return False
    try:
        ip = ipaddress.ip_address(text)
    except ValueError:
        return False
    if not isinstance(ip, ipaddress.IPv4Address):
        return False
    return not (ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_unspecified)


def subnet_of(ip_value: str, prefix_len: int = 24) -> str:
    ip = ipaddress.ip_address(ip_value.strip())
    network = ipaddress.ip_network(f"{ip}/{prefix_len}", strict=False)
    return str(network)


def parse_hostname_location(hostname: str) -> dict[str, str]:
    host = normalize_host(hostname)
    base = {
        "raw_hostname": clean(hostname),
        "normalized_hostname": host,
        "facility_prefix": "",
        "numeric_block": "",
        "role_code": "",
        "suffix": "",
        "location_code": "",
    }
    if not host:
        return base
    match = PREFIX_RE.match(host)
    if match:
        facility, numeric, role, suffix = match.groups()
        base.update(
            {
                "facility_prefix": facility,
                "numeric_block": numeric,
                "role_code": role,
                "suffix": suffix or "",
                "location_code": f"{facility}{numeric}{role}",
            }
        )
        return base
    lead = re.match(r"^([A-Z]{2,4})", host)
    if lead:
        base["facility_prefix"] = lead.group(1)
        base["location_code"] = lead.group(1)
    return base


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def load_prefix_config(path: Path | None) -> dict[str, dict[str, str]]:
    if not path:
        return {}
    if not path.exists():
        print(f"WARN: prefix config not found: {path}", file=sys.stderr)
        return {}
    rows = read_csv(path)
    out: dict[str, dict[str, str]] = {}
    for row in rows:
        prefix = (
            first(row, ["HostnamePrefix", "Prefix", "FacilityPrefix", "LocationPrefix"])
            or first(row, ["LocationCode", "Code"])
        ).upper()
        if not prefix:
            continue
        out[prefix] = {
            "HostnamePrefix": prefix,
            "LocationCode": first(row, ["LocationCode", "Code"]) or prefix,
            "LocationLabel": first(row, ["LocationLabel", "Label", "SiteLabel"]),
            "Region": first(row, ["Region"]),
            "SiteAffinity": first(row, ["SiteAffinity", "Site"]),
            "AllowMixedWith": first(row, ["AllowMixedWith", "AllowPairingWith"]),
            "Notes": first(row, ["Notes"]),
        }
    return out


def inference_location_key(parsed: dict[str, str], prefix_config: dict[str, dict[str, str]]) -> str:
    facility = parsed.get("facility_prefix", "")
    if facility and facility in prefix_config:
        return prefix_config[facility].get("LocationCode", facility) or facility
    return parsed.get("location_code", "") or facility


def mixed_pairing_allowed(prefixes: set[str], prefix_config: dict[str, dict[str, str]]) -> bool:
    facilities = {p for p in prefixes if p in FACILITY_PAIR_REVIEW}
    if len(facilities) < 2:
        return True
    if facilities != FACILITY_PAIR_REVIEW:
        return False
    allowed: set[str] = set()
    for facility in facilities:
        cfg = prefix_config.get(facility, {})
        mixed = cfg.get("AllowMixedWith", "")
        allowed.update(part.strip().upper() for part in mixed.split(";") if part.strip())
    return "WNH" in allowed and "WMH" in allowed


def score_subnet_location(
    hosts: list[dict[str, object]],
    prefix_config: dict[str, dict[str, str]],
) -> tuple[int, str, str, str, list[str]]:
    """Return score, status, confidence, review_reason, signals for one subnet."""
    signals: list[str] = []
    score = 0
    valid_hosts = [h for h in hosts if h.get("ip_status") == "ok"]
    if not valid_hosts:
        return 0, "ip_missing", "low", "No hosts with valid IP in subnet", ["missing_or_invalid_ip"]

    facilities = {str(h.get("facility_prefix") or "") for h in valid_hosts if h.get("facility_prefix")}
    location_codes = {
        str(h.get("inference_location_key") or h.get("location_code") or "")
        for h in valid_hosts
        if h.get("inference_location_key") or h.get("location_code")
    }
    mapped_prefixes = [f for f in facilities if f in prefix_config]
    if mapped_prefixes:
        score += 40
        signals.append("prefix_maps_via_config:+40")

    same_location_counts: dict[str, int] = defaultdict(int)
    for host in valid_hosts:
        code = str(host.get("inference_location_key") or host.get("location_code") or "")
        if code:
            same_location_counts[code] += 1
    max_same = max(same_location_counts.values()) if same_location_counts else 0
    if max_same >= 2:
        score += 25
        signals.append("two_plus_hosts_same_location:+25")
    if max_same >= 5:
        score += 25
        signals.append("five_plus_hosts_same_location:+25")

    sources = {str(s) for h in valid_hosts for s in str(h.get("evidence_sources") or "").split(";") if s}
    if "identity" in sources:
        score += 20
        signals.append("ad_dns_export:+20")
    if "preflight" in sources:
        score += 15
        signals.append("also_in_preflight:+15")

    if len(valid_hosts) == 1:
        score -= 30
        signals.append("only_one_host:-30")

    allowed_mixed_pairing = len(facilities & FACILITY_PAIR_REVIEW) >= 2 and mixed_pairing_allowed(
        facilities, prefix_config
    )
    if len(location_codes) > 1 and not allowed_mixed_pairing:
        score -= 40
        signals.append("conflicting_location_codes:-40")

    invalid_count = sum(1 for h in hosts if h.get("ip_status") in {"missing", "invalid"})
    if invalid_count:
        score -= 30
        signals.append("missing_or_invalid_ip:-30")

    review_reason = ""
    status = "subnet_location_candidate"
    confidence = "medium"

    if not mapped_prefixes and facilities:
        status = "prefix_unknown"
        confidence = "low"
        review_reason = "Hostname facility prefix not present in prefix config"
    elif allowed_mixed_pairing:
        status = "subnet_location_allowed_mixed"
        confidence = "medium"
        review_reason = (
            "Allowed mixed prefix pairing WNH<->WMH from prefix config; verify with "
            "network/site context before expanding survey scope."
        )
        signals.append("allowed_mixed_pairing:review")
    elif len(facilities & FACILITY_PAIR_REVIEW) >= 2:
        status = "subnet_location_mixed"
        confidence = "low"
        review_reason = "WNH and WMH share subnet; pairing requires explicit config allowance"
    elif len(location_codes) > 1:
        status = "subnet_location_mixed"
        confidence = "low"
        review_reason = "Multiple location codes observed in subnet"
    elif score >= 80 and max_same >= 5:
        status = "subnet_location_strong"
        confidence = "high"
    elif score >= 50 or max_same >= 2:
        status = "subnet_location_candidate"
        confidence = "medium" if score >= 50 else "low"
    elif score >= 20:
        status = "subnet_location_candidate"
        confidence = "low"
        review_reason = review_reason or "Limited corroboration for subnet-location mapping"
    else:
        status = "needs_manual_review"
        confidence = "low"
        review_reason = review_reason or "Score below review threshold"

    if len(valid_hosts) == 1 and status == "subnet_location_candidate":
        review_reason = review_reason or "Single-host subnet mapping"

    return score, status, confidence, review_reason, signals


class HostRecord:
    def __init__(self, normalized: str) -> None:
        self.normalized = normalized
        self.hostname = normalized
        self.ip = ""
        self.ip_status = "missing"
        self.ip_source = ""
        self.site = ""
        self.sources: set[str] = set()
        self.source_files: set[str] = set()
        self.identity_ip = ""
        self.preflight_ip = ""
        self.tracker_ip = ""
        self.identity_serial = ""
        self.preflight_serial = ""
        self.tracker_serial = ""
        self.proof_statuses: set[str] = set()

    def add_source(self, source: str, path: Path, row: dict[str, str]) -> None:
        host = normalize_host(
            first(
                row,
                [
                    "HostName",
                    "Hostname",
                    "ComputerName",
                    "Computer",
                    "Name",
                    "Target",
                    "ExpectedHostname",
                    "CandidateHostname",
                    "DNSHostName",
                    "Identifier",
                ],
            )
        )
        if host:
            self.hostname = host
        site = first(row, ["Site", "SiteCode", "Practice", "Location"])
        if site:
            self.site = site
        ip = first(row, ["IPv4Address", "IPAddress", "IP", "ResolvedIP", "ResolvedAddress", "Address"])
        if ip:
            if source == "identity":
                self.identity_ip = ip
            elif source == "preflight":
                self.preflight_ip = ip
            elif source == "tracker":
                self.tracker_ip = ip
        serial = usable_serial(first(row, SERIAL_ALIASES))
        if not serial and is_serial_identifier(row):
            serial = usable_serial(first(row, ["Identifier", "Target", "AssetTag"]))
        if serial:
            if source == "identity":
                self.identity_serial = serial
            elif source == "preflight":
                self.preflight_serial = serial
            elif source == "tracker":
                self.tracker_serial = serial
        proof_status = first(row, PROOF_STATUS_ALIASES)
        if proof_status:
            self.proof_statuses.add(proof_status)
        self.sources.add(source)
        self.source_files.add(str(path))

    def finalize_ip(self) -> None:
        invalid_seen = False
        invalid_candidate = ""
        for source, candidate in (
            ("identity", self.identity_ip),
            ("preflight", self.preflight_ip),
            ("tracker", self.tracker_ip),
        ):
            if not candidate or is_empty_value(candidate):
                continue
            if usable_ipv4(candidate):
                self.ip = candidate
                self.ip_status = "ok"
                self.ip_source = source
                return
            if clean(candidate):
                invalid_seen = True
                invalid_candidate = invalid_candidate or candidate
        self.ip = invalid_candidate if invalid_seen else ""
        self.ip_status = "invalid" if invalid_seen else "missing"
        self.ip_source = ""

    def serial_value(self) -> str:
        for candidate in (self.identity_serial, self.preflight_serial, self.tracker_serial):
            serial = usable_serial(candidate)
            if serial:
                return serial
        return ""

    def has_serial_proof(self) -> bool:
        return any(status_has_serial_proof(status) for status in self.proof_statuses)


def ingest_rows(
    rows: list[dict[str, str]],
    source: str,
    path: Path,
    hosts: dict[str, HostRecord],
) -> None:
    for row in rows:
        normalized = normalize_host(
            first(
                row,
                [
                    "HostName",
                    "Hostname",
                    "ComputerName",
                    "Computer",
                    "Name",
                    "Target",
                    "ExpectedHostname",
                    "CandidateHostname",
                    "DNSHostName",
                    "Identifier",
                ],
            )
        )
        if not normalized:
            continue
        rec = hosts.setdefault(normalized, HostRecord(normalized))
        rec.add_source(source, path, row)


def fallback_audit_fields(rec: HostRecord) -> dict[str, str]:
    serial = rec.serial_value()
    has_host = bool(normalize_host(rec.hostname))
    has_valid_ip = rec.ip_status == "ok"
    has_proof = rec.has_serial_proof()

    hostname_status = "hostname_validated" if has_host and has_valid_ip else "hostname_candidate" if has_host else "hostname_missing"

    if serial and has_proof:
        return {
            "SurveyAuthority": "serial",
            "PrimaryKey": serial,
            "PrimaryKeyType": "Serial",
            "FallbackUsed": "No",
            "FallbackType": "none",
            "FallbackReason": "serial_confirmed_by_identity_status",
            "SerialEvidenceStatus": "serial_confirmed",
            "HostnameEvidenceStatus": hostname_status,
            "Blocker": "none",
            "NextAction": "Use serial authority",
        }

    if serial:
        if has_host:
            return {
                "SurveyAuthority": "hostname_fallback",
                "PrimaryKey": rec.hostname,
                "PrimaryKeyType": "HostName",
                "FallbackUsed": "Yes",
                "FallbackType": "serial_unresolved",
                "FallbackReason": "serial_present_without_identity_proof",
                "SerialEvidenceStatus": "serial_candidate",
                "HostnameEvidenceStatus": hostname_status,
                "Blocker": "needs_privileged_identity",
                "NextAction": "Collect approved privileged identity evidence",
            }
        if has_valid_ip:
            return {
                "SurveyAuthority": "subnet_inference_only",
                "PrimaryKey": rec.ip,
                "PrimaryKeyType": "IP",
                "FallbackUsed": "Yes",
                "FallbackType": "ip_only_evidence",
                "FallbackReason": "serial_present_ip_used_without_identity_proof",
                "SerialEvidenceStatus": "serial_candidate",
                "HostnameEvidenceStatus": hostname_status,
                "Blocker": "needs_privileged_identity",
                "NextAction": "Collect approved privileged identity evidence",
            }

    if has_host:
        blocker = "invalid_ip" if rec.ip_status == "invalid" else "missing_dns_ip" if rec.ip_status == "missing" else "missing_serial"
        next_action = (
            "Fix IP evidence"
            if blocker == "invalid_ip"
            else "Resolve hostname or provide approved IP evidence"
            if blocker == "missing_dns_ip"
            else "Collect approved privileged identity evidence"
        )
        return {
            "SurveyAuthority": "hostname_fallback",
            "PrimaryKey": rec.hostname,
            "PrimaryKeyType": "HostName",
            "FallbackUsed": "Yes",
            "FallbackType": "hostname_only_evidence" if not has_valid_ip else "serial_missing",
            "FallbackReason": "serial_missing_hostname_ip_used" if has_valid_ip else "hostname_resolved_no_serial_proof",
            "SerialEvidenceStatus": "not_serial_proof",
            "HostnameEvidenceStatus": hostname_status,
            "Blocker": blocker,
            "NextAction": next_action,
        }

    if has_valid_ip:
        return {
            "SurveyAuthority": "subnet_inference_only",
            "PrimaryKey": rec.ip,
            "PrimaryKeyType": "IP",
            "FallbackUsed": "Yes",
            "FallbackType": "ip_only_evidence",
            "FallbackReason": "subnet_inferred_from_hostname_ip",
            "SerialEvidenceStatus": "not_serial_proof",
            "HostnameEvidenceStatus": "hostname_missing",
            "Blocker": "missing_serial",
            "NextAction": "Collect approved hostname and serial evidence",
        }

    return {
        "SurveyAuthority": "blocked",
        "PrimaryKey": "",
        "PrimaryKeyType": "None",
        "FallbackUsed": "Yes",
        "FallbackType": "blocked_no_key",
        "FallbackReason": "missing_hostname_and_ip",
        "SerialEvidenceStatus": "serial_missing",
        "HostnameEvidenceStatus": "hostname_missing",
        "Blocker": "missing_dns_ip",
        "NextAction": "Resolve hostname or provide approved IP evidence",
    }


def build_host_rows(
    hosts: dict[str, HostRecord],
    prefix_config: dict[str, dict[str, str]],
    prefix_len: int,
    subnet_scores: dict[str, tuple[int, str, str, str, list[str]]],
    location_subnet_map: dict[str, set[str]],
) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for normalized in sorted(hosts):
        rec = hosts[normalized]
        rec.finalize_ip()
        parsed = parse_hostname_location(rec.hostname)
        facility = parsed["facility_prefix"]
        cfg = prefix_config.get(facility, {})
        location_code = inference_location_key(parsed, prefix_config) or parsed["location_code"]
        location_label = cfg.get("LocationLabel", "")

        subnet = ""
        status = "hostname_unresolved"
        confidence = "low"
        score = 0
        review = ""

        if not rec.hostname:
            status = "hostname_unresolved"
            review = "Hostname missing after normalization"
        elif rec.ip_status == "invalid":
            status = "ip_invalid"
            review = "IPAddress is not a usable IPv4 value"
        elif rec.ip_status == "missing":
            status = "ip_missing"
            review = "No approved IP evidence for host"
        elif facility and facility not in prefix_config:
            status = "prefix_unknown"
            review = "Facility prefix not mapped in prefix config"
        else:
            try:
                subnet = subnet_of(rec.ip, prefix_len)
            except ValueError:
                status = "ip_invalid"
                review = "Could not derive subnet from IP"
            else:
                subnet_score = subnet_scores.get(subnet, (0, "needs_manual_review", "low", "", []))
                score = subnet_score[0]
                status = subnet_score[1]
                confidence = subnet_score[2]
                review = subnet_score[3]
                codes = location_subnet_map.get(location_code, set())
                if location_code and len(codes) > 1 and status not in {"subnet_location_mixed"}:
                    status = "location_spans_multiple_subnets"
                    confidence = "low"
                    review = f"Location code {location_code} appears across multiple subnets"

        audit = fallback_audit_fields(rec)
        if status == "subnet_location_mixed":
            audit["Blocker"] = "mixed_subnet_prefixes"
            audit["NextAction"] = "Review hostname prefix and site context"
        elif status == "prefix_unknown":
            audit["Blocker"] = "unknown_prefix"
            audit["NextAction"] = "Review prefix config or hostname source"
        elif status == "ip_invalid":
            audit["Blocker"] = "invalid_ip"
            audit["NextAction"] = "Fix IP evidence"
        elif status == "ip_missing":
            audit["Blocker"] = "missing_dns_ip"
            audit["NextAction"] = "Resolve hostname or provide approved IP evidence"

        cls = _CLASSIFY.classify_device(
            hostname=rec.hostname,
            survey_lane="subnet_discovery",
            in_manifest=False,
            identifier_type=audit.get("PrimaryKeyType", ""),
            serial=rec.serial_value(),
        )

        out.append(
            {
                "NormalizedHostName": normalized,
                "HostName": rec.hostname,
                "IPAddress": rec.ip,
                "Subnet": subnet,
                "FacilityPrefix": facility,
                "LocationCode": location_code,
                "LocationLabel": location_label,
                "Status": status,
                "Confidence": confidence,
                "Score": str(score),
                "ReviewReason": review,
                "IPSource": rec.ip_source,
                **audit,
                "EvidenceSources": ";".join(sorted(rec.sources)),
                "Site": rec.site,
                "SourceFiles": ";".join(sorted(rec.source_files)),
                "DeviceRole": cls.device_role,
                "RoleConfidence": cls.role_confidence,
                "RoleSignals": cls.role_signals,
                "CountsTowardCybernetPopulation": cls.counts_toward_cybernet_population,
            }
        )
    return out


def build_subnet_rows(
    hosts: dict[str, HostRecord],
    prefix_config: dict[str, dict[str, str]],
    prefix_len: int,
) -> tuple[list[dict[str, str]], dict[str, tuple[int, str, str, str, list[str]]], dict[str, set[str]]]:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    location_subnet_map: dict[str, set[str]] = defaultdict(set)

    for normalized, rec in hosts.items():
        rec.finalize_ip()
        parsed = parse_hostname_location(rec.hostname)
        subnet = ""
        if rec.ip_status == "ok":
            try:
                subnet = subnet_of(rec.ip, prefix_len)
            except ValueError:
                subnet = ""
        loc_key = inference_location_key(parsed, prefix_config)
        if loc_key and subnet:
            location_subnet_map[loc_key].add(subnet)
        grouped[subnet].append(
            {
                "normalized_hostname": normalized,
                "facility_prefix": parsed["facility_prefix"],
                "location_code": parsed["location_code"],
                "inference_location_key": loc_key,
                "evidence_sources": ";".join(sorted(rec.sources)),
                "ip_status": rec.ip_status,
            }
        )

    spanning_locations = {key for key, subnets in location_subnet_map.items() if key and len(subnets) > 1}

    subnet_scores: dict[str, tuple[int, str, str, str, list[str]]] = {}
    rows: list[dict[str, str]] = []
    for subnet in sorted(grouped):
        if not subnet:
            continue
        host_bucket = grouped[subnet]
        score, status, confidence, review, signals = score_subnet_location(host_bucket, prefix_config)
        loc_keys = {
            str(h.get("inference_location_key") or "")
            for h in host_bucket
            if h.get("inference_location_key")
        }
        if loc_keys & spanning_locations:
            status = "location_spans_multiple_subnets"
            confidence = "low"
            review = review or "Mapped location appears across multiple subnets"
        subnet_scores[subnet] = (score, status, confidence, review, signals)
        facilities = sorted({str(h.get("facility_prefix") or "") for h in host_bucket if h.get("facility_prefix")})
        codes = sorted(
            {
                code
                for h in host_bucket
                for code in [str(h.get("inference_location_key") or h.get("location_code") or "").strip()]
                if code
            }
        )
        labels = []
        for facility in facilities:
            if facility in prefix_config:
                label = prefix_config[facility].get("LocationLabel", "")
                if label:
                    labels.append(label)
        rows.append(
            {
                "Subnet": subnet,
                "LocationCodes": ";".join(codes),
                "LocationLabels": ";".join(sorted(set(labels))),
                "HostCount": str(len(host_bucket)),
                "FacilityPrefixes": ";".join(facilities),
                "Status": status,
                "Confidence": confidence,
                "Score": str(score),
                "ScoreSignals": ";".join(signals),
                "ReviewReason": review,
            }
        )
    return rows, subnet_scores, location_subnet_map


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def render_html(report_dir: Path, payload: dict[str, object]) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    data_js = "window.SUBNET_LOCATION_DATA = " + json.dumps(payload, indent=2) + ";\n"
    (report_dir / "data.js").write_text(data_js, encoding="utf-8")
    (report_dir / "style.css").write_text(
        """\
:root {
  color-scheme: dark;
  --bg: #04110c;
  --panel: #071b14;
  --text: #d8ffe7;
  --muted: #86b89a;
  --green: #49ff91;
  --amber: #ffd166;
  --red: #ff5d73;
  --line: rgba(73, 255, 145, 0.24);
}
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  background: radial-gradient(circle at top right, rgba(73,255,145,.14), transparent 28rem), var(--bg);
  color: var(--text);
  font: 15px/1.45 "Segoe UI", system-ui, sans-serif;
}
.nav {
  position: fixed;
  inset: 0 auto 0 0;
  width: 250px;
  padding: 24px 18px;
  background: rgba(3, 13, 9, .92);
  border-right: 1px solid var(--line);
}
.brand { color: var(--green); font-weight: 800; letter-spacing: .08em; text-transform: uppercase; }
.subbrand { color: var(--muted); margin: 4px 0 18px; }
.nav a { display: block; color: var(--text); text-decoration: none; padding: 8px 10px; margin: 4px 0; border-radius: 10px; }
.nav a:hover { background: rgba(73,255,145,.08); }
main { margin-left: 250px; padding: 28px; }
.hero, .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 16px; padding: 24px; margin-bottom: 20px; }
.eyebrow { color: var(--green); text-transform: uppercase; letter-spacing: .12em; font-size: 12px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; }
.tile { background: rgba(11,38,28,.7); border: 1px solid var(--line); border-radius: 12px; padding: 16px; }
.tile strong { display: block; color: var(--green); font-size: 28px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { border-bottom: 1px solid rgba(134,184,154,.18); padding: 8px; text-align: left; vertical-align: top; }
th { color: var(--green); }
input { width: min(360px, 100%); background: #020b07; color: var(--text); border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; }
@media (max-width: 860px) { .nav { position: static; width: auto; } main { margin-left: 0; } }
""",
        encoding="utf-8",
    )
    index_html = """\
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cybernet subnet location inference</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <aside class="nav">
    <div class="brand">SysAdminSuite</div>
    <div class="subbrand">Subnet / Location</div>
    <a href="#overview">Overview</a>
    <a href="#subnets">Subnet map</a>
    <a href="#hosts">Host evidence</a>
    <a href="#review">Review queue</a>
  </aside>
  <main>
    <section class="hero" id="overview">
      <p class="eyebrow">Read-only local enrichment</p>
      <h1>Cybernet subnet location inference</h1>
      <p>Approved hostname and IP CSV evidence grouped into subnet-to-location candidates. Confidence evidence only — not serial proof.</p>
      <div class="tiles" id="tiles"></div>
    </section>
    <section class="panel" id="subnets">
      <div class="toolbar"><h2>Subnet map</h2><input id="subnet-filter" type="search" placeholder="Filter subnets"></div>
      <div id="subnet-table"></div>
    </section>
    <section class="panel" id="hosts">
      <div class="toolbar"><h2>Host evidence</h2><input id="host-filter" type="search" placeholder="Filter hosts"></div>
      <div id="host-table"></div>
    </section>
    <section class="panel" id="review">
      <div class="toolbar"><h2>Review queue</h2><input id="review-filter" type="search" placeholder="Filter review rows"></div>
      <div id="review-table"></div>
    </section>
  </main>
  <script src="data.js"></script>
  <script>
    const data = window.SUBNET_LOCATION_DATA || {};
    const summary = data.summary || {};
    const subnets = data.subnets || [];
    const hosts = data.hosts || [];
    const reviewStatuses = new Set([
      'subnet_location_mixed', 'subnet_location_allowed_mixed', 'location_spans_multiple_subnets',
      'hostname_unresolved', 'ip_missing', 'ip_invalid', 'prefix_unknown', 'needs_manual_review',
      'needs_network_team_confirmation'
    ]);
    const reviewHosts = hosts.filter((row) => reviewStatuses.has(row.Status) || row.FallbackUsed === 'Yes');
    document.getElementById('tiles').innerHTML = [
      ['Subnets mapped', summary.subnet_count || 0],
      ['Strong mappings', summary.strong_count || 0],
      ['Review rows', summary.review_count || 0],
      ['Unresolved hosts', summary.unresolved_count || 0],
      ['Serial authority', summary.serial_authority_count || 0],
      ['Fallback rows', summary.fallback_used_count || 0],
      ['Blockers', summary.blocker_count || 0],
    ].map(([label, value]) => `<div class="tile"><strong>${value}</strong><span>${label}</span></div>`).join('');
    function escapeHtml(value) {
      return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[ch]));
    }
    function renderTable(targetId, rows, columns, filterId) {
      const target = document.getElementById(targetId);
      const filter = document.getElementById(filterId);
      function draw() {
        const needle = (filter.value || '').toLowerCase();
        const filtered = rows.filter((row) => JSON.stringify(row).toLowerCase().includes(needle));
        if (!filtered.length) {
          target.innerHTML = '<p class="empty">No rows match.</p>';
          return;
        }
        const head = columns.map((col) => `<th>${escapeHtml(col)}</th>`).join('');
        const body = filtered.map((row) => `<tr>${columns.map((col) => `<td>${escapeHtml(row[col])}</td>`).join('')}</tr>`).join('');
        target.innerHTML = `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
      }
      filter.addEventListener('input', draw);
      draw();
    }
    renderTable('subnet-table', subnets, ['Subnet', 'LocationCodes', 'HostCount', 'Status', 'Confidence', 'Score'], 'subnet-filter');
    renderTable('host-table', hosts, ['NormalizedHostName', 'IPAddress', 'Subnet', 'LocationCode', 'Status', 'Confidence', 'SurveyAuthority', 'FallbackUsed', 'SerialEvidenceStatus', 'Blocker'], 'host-filter');
    renderTable('review-table', reviewHosts, ['NormalizedHostName', 'Subnet', 'Status', 'ReviewReason', 'FallbackReason', 'Blocker', 'NextAction'], 'review-filter');
  </script>
</body>
</html>
"""
    (report_dir / "index.html").write_text(index_html, encoding="utf-8")


def print_summary(subnet_rows: list[dict[str, str]], host_rows: list[dict[str, str]]) -> None:
    strong = sum(1 for row in subnet_rows if row["Status"] == "subnet_location_strong")
    review = sum(
        1
        for row in host_rows
        if row["Status"]
        in {
            "subnet_location_mixed",
            "subnet_location_allowed_mixed",
            "location_spans_multiple_subnets",
            "needs_manual_review",
            "needs_network_team_confirmation",
            "prefix_unknown",
            "ip_missing",
            "ip_invalid",
            "hostname_unresolved",
        }
    )
    unresolved = sum(1 for row in host_rows if row["Status"] in {"hostname_unresolved", "ip_missing", "ip_invalid"})
    print(
        f"[sas-cybernet-subnet-location-map] {len(subnet_rows)} subnets mapped | "
        f"{strong} strong | {review} review | {unresolved} unresolved"
    )
    serial_authority = sum(1 for row in host_rows if row.get("SurveyAuthority") == "serial")
    hostname_fallback = sum(1 for row in host_rows if row.get("SurveyAuthority") == "hostname_fallback")
    subnet_fallback = sum(1 for row in host_rows if row.get("SurveyAuthority") == "subnet_inference_only")
    blockers = sum(1 for row in host_rows if row.get("Blocker") not in {"", "none"})
    print(
        "[sas-cybernet-subnet-location-map] serial-first: "
        f"{serial_authority} serial-authority | {hostname_fallback} hostname fallback | "
        f"{subnet_fallback} ip/subnet fallback | {blockers} blockers"
    )
    print("[sas-cybernet-subnet-location-map] Top mappings:")
    top = sorted(subnet_rows, key=lambda row: (-int(row.get("Score") or 0), row.get("Subnet", "")))[:5]
    for row in top:
        label = row.get("LocationLabels") or row.get("LocationCodes") or row.get("FacilityPrefixes") or "unknown"
        print(
            f"  {row['Subnet']} -> {label} | {row['HostCount']} hosts | {row['Confidence']}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Infer Cybernet subnet-to-location mappings from approved CSV hostname/IP evidence"
    )
    parser.add_argument("--identity-csv", action="append", default=[], help="Identity or AD export CSV. Repeatable.")
    parser.add_argument("--identity-glob", default="", help="Glob for identity CSV files (expanded by wrapper).")
    parser.add_argument("--preflight-csv", action="append", default=[], help="Preflight CSV. Repeatable.")
    parser.add_argument("--tracker-csv", action="append", default=[], help="Tracker or diff CSV. Repeatable.")
    parser.add_argument("--prefix-config", default="", help="Hostname prefix to location mapping CSV")
    parser.add_argument("--prefix-len", type=int, default=24, help="IPv4 prefix length for subnet grouping")
    parser.add_argument(
        "--output-prefix",
        default="survey/output/cybernet_subnet_location",
        help="Output path prefix (writes _map.csv, _hosts.csv, _map.json)",
    )
    parser.add_argument(
        "--format",
        default="all",
        help="Output format: csv, json, all, or comma-separated (e.g. csv,json)",
    )
    parser.add_argument("--html", action="store_true", help="Write offline HTML report directory")
    args = parser.parse_args()

    if args.prefix_len < 8 or args.prefix_len > 32:
        print("ERROR: --prefix-len must be between 8 and 32", file=sys.stderr)
        return 2

    identity_paths = [Path(p) for p in args.identity_csv]
    preflight_paths = [Path(p) for p in args.preflight_csv]
    tracker_paths = [Path(p) for p in args.tracker_csv]

    for path in identity_paths:
        if not path.exists():
            print(f"ERROR: identity CSV not found: {path}", file=sys.stderr)
            return 2
    for path in preflight_paths + tracker_paths:
        if not path.exists():
            print(f"WARN: optional CSV not found: {path}", file=sys.stderr)

    prefix_config_path = Path(args.prefix_config) if args.prefix_config else None
    prefix_config = load_prefix_config(prefix_config_path)

    hosts: dict[str, HostRecord] = {}
    for path in tracker_paths:
        if path.exists():
            ingest_rows(read_csv(path), "tracker", path, hosts)
    for path in preflight_paths:
        if path.exists():
            ingest_rows(read_csv(path), "preflight", path, hosts)
    for path in identity_paths:
        ingest_rows(read_csv(path), "identity", path, hosts)

    if not hosts:
        print("WARN: no host evidence ingested from supplied CSV inputs", file=sys.stderr)

    subnet_rows, subnet_scores, location_subnet_map = build_subnet_rows(hosts, prefix_config, args.prefix_len)
    host_rows = build_host_rows(hosts, prefix_config, args.prefix_len, subnet_scores, location_subnet_map)

    output_prefix = Path(args.output_prefix)
    map_csv = Path(f"{output_prefix}_map.csv")
    hosts_csv = Path(f"{output_prefix}_hosts.csv")
    map_json = Path(f"{output_prefix}_map.json")
    report_dir = Path(f"{output_prefix}_report")

    summary = {
        "subnet_count": len(subnet_rows),
        "strong_count": sum(1 for row in subnet_rows if row["Status"] == "subnet_location_strong"),
        "review_count": sum(
            1
            for row in host_rows
            if row["Status"]
            not in {"subnet_location_strong", "subnet_location_candidate"}
        ),
        "unresolved_count": sum(
            1 for row in host_rows if row["Status"] in {"hostname_unresolved", "ip_missing", "ip_invalid"}
        ),
        "serial_authority_count": sum(1 for row in host_rows if row.get("SurveyAuthority") == "serial"),
        "hostname_fallback_count": sum(1 for row in host_rows if row.get("SurveyAuthority") == "hostname_fallback"),
        "subnet_inference_only_count": sum(
            1 for row in host_rows if row.get("SurveyAuthority") == "subnet_inference_only"
        ),
        "fallback_used_count": sum(1 for row in host_rows if row.get("FallbackUsed") == "Yes"),
        "serial_not_proof_count": sum(
            1 for row in host_rows if row.get("SerialEvidenceStatus") == "not_serial_proof"
        ),
        "blocker_count": sum(1 for row in host_rows if row.get("Blocker") not in {"", "none"}),
    }
    payload: dict[str, object] = {"summary": summary, "subnets": subnet_rows, "hosts": host_rows}

    format_tokens = {part.strip().lower() for part in args.format.split(",") if part.strip()}
    if not format_tokens or format_tokens == {"all"}:
        format_tokens = {"csv", "json"}
    if "all" in format_tokens:
        format_tokens = {"csv", "json"}
    invalid_formats = format_tokens - {"csv", "json"}
    if invalid_formats:
        print(f"ERROR: unsupported --format value(s): {', '.join(sorted(invalid_formats))}", file=sys.stderr)
        return 2

    if "csv" in format_tokens:
        write_csv(map_csv, MAP_FIELDS, subnet_rows)
        write_csv(hosts_csv, HOST_FIELDS, host_rows)
        print(f"Wrote {map_csv}")
        print(f"Wrote {hosts_csv}")
    if "json" in format_tokens:
        write_json(map_json, payload)
        print(f"Wrote {map_json}")
    if args.html:
        render_html(report_dir, payload)
        print(f"Wrote {report_dir / 'index.html'}")

    print_summary(subnet_rows, host_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
