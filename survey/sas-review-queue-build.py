#!/usr/bin/env python3
"""
Build a SysAdminSuite artifact delivery review queue from reconciliation CSV output.

Read-only behavior: reads the reconciliation CSV and writes a new review queue CSV.
It never edits source evidence or workbook files.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


REVIEW_QUEUE_HEADERS = [
    "ReviewID",
    "SourceFile",
    "SourceRow",
    "SiteCode",
    "Location",
    "Room",
    "Workstation",
    "Hostname",
    "IPAddress",
    "MACAddress",
    "SerialNumber",
    "IssueType",
    "Severity",
    "EvidenceSummary",
    "RecommendedAction",
    "Owner",
    "ReviewStatus",
    "Notes",
]


DANGEROUS_CSV_PREFIXES = ("=", "+", "-", "@")


def csv_safe(value: object) -> str:
    text = "" if value is None else str(value)
    if text and text[0] in DANGEROUS_CSV_PREFIXES:
        return "'" + text
    return text


def csv_safe_row(row: dict[str, str], headers: list[str]) -> dict[str, str]:
    return {header: csv_safe(row.get(header, "")) for header in headers}


def clean(value: object) -> str:
    return "" if value is None else str(value).strip()


def get(row: dict[str, str], *names: str) -> str:
    lowered = {key.lower(): key for key in row.keys() if key}
    for name in names:
        if name in row:
            return clean(row.get(name))
        key = lowered.get(name.lower())
        if key:
            return clean(row.get(key))
    return ""


def truthy(value: str) -> bool:
    return clean(value).lower() in {"1", "true", "yes", "y", "needed", "required", "x"}


def falsey(value: str) -> bool:
    return clean(value).lower() in {"0", "false", "no", "n", "unreachable", "failed", "timeout"}


def contains_any(value: str, needles: list[str]) -> bool:
    haystack = clean(value).lower()
    return any(needle.lower() in haystack for needle in needles)


def normalize_hostname(value: str) -> str:
    return clean(value).upper()


def normalize_mac(value: str) -> str:
    raw = clean(value)
    compact = re.sub(r"[^0-9A-Fa-f]", "", raw)
    if len(compact) == 12 and re.fullmatch(r"[0-9A-Fa-f]{12}", compact):
        compact = compact.upper()
        return ":".join(compact[i : i + 2] for i in range(0, 12, 2))
    return raw.upper()


def normalize_serial(value: str) -> str:
    return re.sub(r"\s+", "", clean(value)).upper()


def row_context(row: dict[str, str]) -> dict[str, str]:
    return {
        "SourceFile": get(row, "SourceFile") or get(row, "Source") or "",
        "SourceRow": get(row, "SourceRow") or "",
        "SiteCode": get(row, "SiteCode"),
        "Location": get(row, "Location"),
        "Room": get(row, "Room"),
        "Workstation": get(row, "Workstation"),
        "Hostname": normalize_hostname(get(row, "Hostname", "HostName", "ComputerName", "Computer")),
        "IPAddress": get(row, "IPAddress", "IP", "Address"),
        "MACAddress": normalize_mac(get(row, "MACAddress", "MAC", "MacAddress")),
        "SerialNumber": normalize_serial(get(row, "SerialNumber", "Serial", "ServiceTag", "AssetSerial")),
    }


def device_text(row: dict[str, str]) -> str:
    parts = [
        get(row, "DeviceType"),
        get(row, "ExpectedDeviceType"),
        get(row, "TargetType"),
        get(row, "OS"),
        get(row, "OperatingSystem"),
        get(row, "Classification"),
        get(row, "EvidenceSummary"),
        get(row, "Notes"),
    ]
    return " ".join(part for part in parts if part).lower()


def expected_cybernet_related(row: dict[str, str]) -> bool:
    text = device_text(row)
    return any(token in text for token in ["cybernet", "workstation", "windows"])


def windows_like_endpoint(row: dict[str, str]) -> bool:
    text = device_text(row)
    hostname = get(row, "Hostname", "HostName", "ComputerName", "Computer")
    return "windows" in text or "workstation" in text or bool(re.match(r"^SAMPLE-(WS|CYB)-", hostname.upper()))


def confidence_value(row: dict[str, str]) -> str:
    return get(row, "Confidence", "MatchConfidence", "ResultConfidence", "ReconciliationConfidence").lower()


def status_text(row: dict[str, str]) -> str:
    parts = [
        get(row, "SurveyStatus"),
        get(row, "Status"),
        get(row, "IssueType"),
        get(row, "Finding"),
        get(row, "EvidenceSummary"),
        get(row, "RecommendedAction"),
        get(row, "Notes"),
    ]
    return " ".join(part for part in parts if part).lower()


def add_review(
    reviews: list[dict[str, str]],
    context: dict[str, str],
    issue_type: str,
    severity: str,
    evidence: str,
    action: str,
    notes: str = "",
) -> None:
    reviews.append(
        {
            "ReviewID": f"RQ-{len(reviews) + 1:05d}",
            **context,
            "IssueType": issue_type,
            "Severity": severity,
            "EvidenceSummary": evidence,
            "RecommendedAction": action,
            "Owner": "",
            "ReviewStatus": "New",
            "Notes": notes,
        }
    )


def build_reviews(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    reviews: list[dict[str, str]] = []
    serial_counts: dict[str, int] = {}
    hostname_counts: dict[str, int] = {}

    for row in rows:
        serial = normalize_serial(get(row, "SerialNumber", "Serial", "ServiceTag", "AssetSerial"))
        hostname = normalize_hostname(get(row, "Hostname", "HostName", "ComputerName", "Computer"))
        if serial:
            serial_counts[serial] = serial_counts.get(serial, 0) + 1
        if hostname:
            hostname_counts[hostname] = hostname_counts.get(hostname, 0) + 1

    for row in rows:
        ctx = row_context(row)
        text = status_text(row)
        confidence = confidence_value(row)
        cybernet_related = expected_cybernet_related(row)

        if not ctx["SerialNumber"]:
            severity = "high" if cybernet_related else "medium"
            add_review(reviews, ctx, "Missing serial evidence", severity, "No serial number was present in the reconciliation row.", "Collect local field capture or verify against an approved source artifact before workbook update.")

        field_capture_flag = truthy(get(row, "NeedsFieldCapture", "FieldCaptureNeeded", "FieldCaptureRequired"))
        if field_capture_flag or contains_any(text, ["needs field capture", "field capture needed"]):
            add_review(reviews, ctx, "Needs field capture", "high" if cybernet_related else "medium", "Reconciliation indicates local/manual capture is needed.", "Assign a technician to capture serial, MAC, computer name, and location locally.")

        if contains_any(text, ["needs manual review", "manual review"]):
            add_review(reviews, ctx, "Needs manual review", "high", "Reconciliation flagged this row for operator judgment.", "Compare source evidence, survey output, and workbook row before import.")

        reachable = get(row, "Reachable", "IsReachable")
        if falsey(reachable) or contains_any(text, ["surveyed unreachable", "unreachable", "timeout"]):
            add_review(reviews, ctx, "Surveyed unreachable", "medium", "Target was surveyed or expected but could not be reached.", "Confirm power, network, location, hostname, and IP. Record documented preflight checks and exact command text before rerun.")

        if not ctx["Hostname"] or not ctx["IPAddress"]:
            add_review(reviews, ctx, "Hostname/IP missing", "medium", "Hostname or IP address is missing.", "Fill the missing network identifier from source evidence before survey or workbook import.")

        if truthy(get(row, "SerialPrefixConflict", "PrefixConflict")) or contains_any(text, ["serial prefix conflict", "prefix conflict"]):
            add_review(reviews, ctx, "Serial prefix conflict", "critical", "Serial evidence conflicts with approved Cybernet prefix expectations.", "Do not import until the prefix list or serial evidence is confirmed.")

        if truthy(get(row, "MACConflict", "MacConflict")) or contains_any(text, ["mac conflict"]):
            add_review(reviews, ctx, "MAC conflict", "critical", "MAC evidence conflicts across source or survey records.", "Resolve the MAC conflict before workbook update.")

        if ctx["SerialNumber"] and serial_counts.get(ctx["SerialNumber"], 0) > 1:
            add_review(reviews, ctx, "Duplicate serial", "critical", "The same serial number appears on more than one reconciliation row.", "Identify the correct row and quarantine duplicates for manual review.")

        if ctx["Hostname"] and hostname_counts.get(ctx["Hostname"], 0) > 1:
            add_review(reviews, ctx, "Duplicate hostname", "high", "The same hostname appears on more than one reconciliation row.", "Resolve duplicate hostname mapping before workbook update.")

        if windows_like_endpoint(row) and not ctx["SerialNumber"]:
            add_review(reviews, ctx, "Windows-like endpoint seen but no serial evidence", "high", "Endpoint appears to be a Windows/workstation-like device, but no serial evidence was captured.", "Use local field capture or approved source files to obtain serial evidence.")

        if confidence in {"low", "conflict", "none"}:
            if confidence == "conflict":
                issue_type = "Needs manual review"
                severity = "high"
                action = "Resolve conflict before workbook import."
            elif confidence == "none":
                issue_type = "No confidence"
                severity = "medium"
                action = "Add stronger evidence before workbook import."
            else:
                issue_type = "Low confidence"
                severity = "medium"
                action = "Review supporting evidence before workbook import."
            add_review(reviews, ctx, issue_type, severity, f"Confidence value is {confidence}.", action)

        if not ctx["Room"]:
            add_review(reviews, ctx, "Missing room", "low", "Room is missing.", "Fill room when practical before workbook import.")

        if not ctx["SiteCode"]:
            add_review(reviews, ctx, "Missing site", "low", "SiteCode is missing.", "Fill SiteCode when practical before workbook import.")

        notes = get(row, "Notes")
        if contains_any(notes, ["todo", "cleanup", "tbd", "??"]):
            add_review(reviews, ctx, "Notes cleanup", "low", "Notes contain placeholder or cleanup language.", "Clean notes before dashboard or workbook handoff.")

    return reviews


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=REVIEW_QUEUE_HEADERS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(csv_safe_row(row, REVIEW_QUEUE_HEADERS) for row in rows)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build artifact delivery review queue from reconciliation CSV.")
    parser.add_argument("--reconciliation", required=True, help="Reconciliation CSV path.")
    parser.add_argument("--output", required=True, help="Review queue CSV output path.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    rows = read_csv(Path(args.reconciliation))
    reviews = build_reviews(rows)
    write_csv(Path(args.output), reviews)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
