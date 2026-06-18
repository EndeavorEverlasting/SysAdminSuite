#!/usr/bin/env python3
"""
Validate and normalize SysAdminSuite artifact delivery CSVs.

Read-only behavior: this script reads an input CSV and writes new output, error,
and warning CSV files. It never edits the input file.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import ipaddress
import re
import sys
from pathlib import Path


WORKSTATION_HEADERS = [
    "SourceFile",
    "SourceRow",
    "SiteCode",
    "SiteName",
    "Location",
    "Room",
    "Workstation",
    "Hostname",
    "IPAddress",
    "MACAddress",
    "SerialNumber",
    "DeviceType",
    "AssociatedNeuron",
    "Notes",
]

SERIAL_PREFIX_HEADERS = [
    "PrefixName",
    "SerialPrefix",
    "DeviceType",
    "Confidence",
    "Notes",
]

FIELD_CAPTURE_HEADERS = [
    "CapturedAt",
    "CaptureMethod",
    "TechInitials",
    "SiteCode",
    "SiteName",
    "Location",
    "Room",
    "Workstation",
    "ComputerName",
    "IPAddress",
    "MACAddress",
    "SerialNumber",
    "Manufacturer",
    "Model",
    "AssociatedNeuron",
    "Notes",
]

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

MESSAGE_HEADERS = [
    "SourceFile",
    "SourceRow",
    "Field",
    "ErrorType",
    "ErrorMessage",
    "RawValue",
]

WARNING_HEADERS = [
    "SourceFile",
    "SourceRow",
    "Field",
    "WarningType",
    "WarningMessage",
    "RawValue",
]

ARTIFACT_HEADERS = {
    "workstation-source": WORKSTATION_HEADERS,
    "serial-prefixes": SERIAL_PREFIX_HEADERS,
    "field-capture": FIELD_CAPTURE_HEADERS,
    "review-queue": REVIEW_QUEUE_HEADERS,
}

VALID_SEVERITIES = {"low", "medium", "high", "critical"}
VALID_REVIEW_STATUSES = {"New", "In Review", "Resolved", "Deferred", "Rejected"}
STATUS_NORMALIZATION = {
    "new": "New",
    "in review": "In Review",
    "in_review": "In Review",
    "resolved": "Resolved",
    "deferred": "Deferred",
    "rejected": "Rejected",
}


def clean_text(value: object) -> str:
    return "" if value is None else str(value).strip()


def row_lookup(row: dict[str, str], name: str) -> str:
    if name in row:
        return clean_text(row.get(name, ""))
    lowered = name.lower()
    for key, value in row.items():
        if key and key.lower() == lowered:
            return clean_text(value)
    return ""


def canonical_row(row: dict[str, str], headers: list[str]) -> dict[str, str]:
    return {header: row_lookup(row, header) for header in headers}


def normalize_hostname(value: str) -> str:
    return clean_text(value).upper()


def normalize_serial(value: str) -> str:
    return re.sub(r"\s+", "", clean_text(value)).upper()


def normalize_prefix(value: str) -> str:
    return clean_text(value).upper()


def normalize_mac(value: str) -> tuple[str, bool]:
    raw = clean_text(value)
    if not raw:
        return "", True

    compact = re.sub(r"[^0-9A-Fa-f]", "", raw)
    if len(compact) != 12 or not re.fullmatch(r"[0-9A-Fa-f]{12}", compact):
        return raw.upper(), False

    compact = compact.upper()
    return ":".join(compact[i : i + 2] for i in range(0, 12, 2)), True


def normalize_ipv4(value: str) -> tuple[str, bool]:
    raw = clean_text(value)
    if not raw:
        return "", True

    try:
        address = ipaddress.ip_address(raw)
    except ValueError:
        return raw, False

    if address.version != 4:
        return raw, False

    return str(address), True


def parseable_datetime(value: str) -> bool:
    raw = clean_text(value)
    if not raw:
        return True

    candidates = [raw, raw.replace("Z", "+00:00")]
    for candidate in candidates:
        try:
            _dt.datetime.fromisoformat(candidate)
            return True
        except ValueError:
            pass

    for pattern in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%Y %H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            _dt.datetime.strptime(raw, pattern)
            return True
        except ValueError:
            pass

    return False


def message(source_file: str, source_row: str, field: str, msg_type: str, text: str, raw_value: str) -> dict[str, str]:
    return {
        "SourceFile": source_file,
        "SourceRow": source_row,
        "Field": field,
        "ErrorType": msg_type,
        "ErrorMessage": text,
        "RawValue": raw_value,
    }


def warning(source_file: str, source_row: str, field: str, msg_type: str, text: str, raw_value: str) -> dict[str, str]:
    return {
        "SourceFile": source_file,
        "SourceRow": source_row,
        "Field": field,
        "WarningType": msg_type,
        "WarningMessage": text,
        "RawValue": raw_value,
    }


def source_identity(row: dict[str, str], input_path: Path, physical_row: int) -> tuple[str, str]:
    source_file = row_lookup(row, "SourceFile") or input_path.name
    source_row = row_lookup(row, "SourceRow") or str(physical_row)
    return source_file, source_row


def normalize_common_network_fields(row: dict[str, str]) -> tuple[dict[str, str], list[tuple[str, str, str, str]]]:
    warnings: list[tuple[str, str, str, str]] = []

    for hostname_field in ("Hostname", "ComputerName"):
        if hostname_field in row:
            row[hostname_field] = normalize_hostname(row[hostname_field])

    for serial_field in ("SerialNumber", "Serial"):
        if serial_field in row:
            row[serial_field] = normalize_serial(row[serial_field])

    if "MACAddress" in row:
        normalized_mac, ok = normalize_mac(row["MACAddress"])
        raw = row["MACAddress"]
        row["MACAddress"] = normalized_mac
        if raw and not ok:
            warnings.append(("MACAddress", "InvalidMACFormat", "MAC address could not be normalized to colon-separated form.", raw))

    if "IPAddress" in row:
        normalized_ip, ok = normalize_ipv4(row["IPAddress"])
        raw = row["IPAddress"]
        row["IPAddress"] = normalized_ip
        if raw and not ok:
            warnings.append(("IPAddress", "InvalidIPv4", "IP address is not a valid IPv4 address.", raw))

    return row, warnings


def validate_workstation(rows: list[dict[str, str]], input_path: Path, pass_thru: bool) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    clean_rows: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []

    for offset, row in enumerate(rows, start=2):
        out = canonical_row(row, WORKSTATION_HEADERS)
        source_file, source_row = source_identity(out, input_path, offset)
        out["SourceFile"] = out["SourceFile"] or source_file
        out["SourceRow"] = out["SourceRow"] or source_row

        raw_ip = out["IPAddress"]

        out, network_warnings = normalize_common_network_fields(out)

        row_errors: list[dict[str, str]] = []
        if not any([out["Hostname"], out["IPAddress"], out["MACAddress"], out["SerialNumber"]]):
            row_errors.append(
                message(source_file, source_row, "Hostname/IPAddress/MACAddress/SerialNumber", "MissingIdentifier", "At least one identifier is required.", "")
            )

        if raw_ip:
            _, ok = normalize_ipv4(raw_ip)
            if not ok:
                row_errors.append(message(source_file, source_row, "IPAddress", "InvalidIPv4", "IP address must be a valid IPv4 address.", raw_ip))

        if not out["SiteCode"]:
            warnings.append(warning(source_file, source_row, "SiteCode", "MissingSiteCode", "SiteCode is missing. Survey can proceed, but workbook reconciliation may be weaker.", ""))
        for field_name in ("Location", "Room"):
            if not out[field_name]:
                warnings.append(warning(source_file, source_row, field_name, f"Missing{field_name}", f"{field_name} is missing. This is a workbook review warning.", ""))

        for field_name, warn_type, warn_text, raw_value in network_warnings:
            if field_name == "IPAddress":
                continue
            warnings.append(warning(source_file, source_row, field_name, warn_type, warn_text, raw_value))

        errors.extend(row_errors)
        if not row_errors or pass_thru:
            clean_rows.append(out)

    return clean_rows, errors, warnings


def validate_serial_prefixes(rows: list[dict[str, str]], input_path: Path, pass_thru: bool, production_mode: bool) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    clean_rows: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    seen: dict[str, tuple[str, str]] = {}

    for offset, row in enumerate(rows, start=2):
        out = canonical_row(row, SERIAL_PREFIX_HEADERS)
        source_file, source_row = source_identity(row, input_path, offset)
        raw_prefix = out["SerialPrefix"]
        out["SerialPrefix"] = normalize_prefix(raw_prefix)

        row_errors: list[dict[str, str]] = []
        if not out["SerialPrefix"]:
            row_errors.append(message(source_file, source_row, "SerialPrefix", "MissingSerialPrefix", "SerialPrefix is required.", raw_prefix))

        if out["SerialPrefix"].startswith("REPLACE_WITH"):
            if production_mode:
                row_errors.append(message(source_file, source_row, "SerialPrefix", "PlaceholderSerialPrefix", "Placeholder prefixes are not allowed in production mode.", raw_prefix))
            else:
                warnings.append(warning(source_file, source_row, "SerialPrefix", "PlaceholderSerialPrefix", "Placeholder prefix found. Replace before production use.", raw_prefix))

        if out["SerialPrefix"]:
            if out["SerialPrefix"] in seen:
                first_file, first_row = seen[out["SerialPrefix"]]
                warnings.append(
                    warning(
                        source_file,
                        source_row,
                        "SerialPrefix",
                        "DuplicateSerialPrefix",
                        f"Duplicate prefix also appears in {first_file} row {first_row}.",
                        raw_prefix,
                    )
                )
            else:
                seen[out["SerialPrefix"]] = (source_file, source_row)

        errors.extend(row_errors)
        if not row_errors or pass_thru:
            clean_rows.append(out)

    return clean_rows, errors, warnings


def validate_field_capture(rows: list[dict[str, str]], input_path: Path, pass_thru: bool) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    clean_rows: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    seen_serials: dict[str, tuple[str, str]] = {}

    for offset, row in enumerate(rows, start=2):
        out = canonical_row(row, FIELD_CAPTURE_HEADERS)
        source_file, source_row = source_identity(row, input_path, offset)
        raw_serial = out["SerialNumber"]
        raw_ip = out["IPAddress"]

        out, network_warnings = normalize_common_network_fields(out)

        row_errors: list[dict[str, str]] = []

        if not out["SerialNumber"]:
            warnings.append(warning(source_file, source_row, "SerialNumber", "MissingSerialNumber", "SerialNumber is strongly preferred for field captures.", ""))
            if not out["ComputerName"] and not out["Workstation"]:
                row_errors.append(message(source_file, source_row, "ComputerName/Workstation", "MissingFallbackIdentifier", "ComputerName or Workstation is required when SerialNumber is missing.", ""))

        if out["CapturedAt"] and not parseable_datetime(out["CapturedAt"]):
            warnings.append(warning(source_file, source_row, "CapturedAt", "UnparseableCapturedAt", "CapturedAt should be parseable.", out["CapturedAt"]))

        if not out["TechInitials"]:
            warnings.append(warning(source_file, source_row, "TechInitials", "MissingTechInitials", "TechInitials is missing.", ""))

        if raw_ip:
            _, ok = normalize_ipv4(raw_ip)
            if not ok:
                row_errors.append(message(source_file, source_row, "IPAddress", "InvalidIPv4", "IP address must be a valid IPv4 address.", raw_ip))

        for field_name, warn_type, warn_text, raw_value in network_warnings:
            if field_name == "IPAddress":
                continue
            warnings.append(warning(source_file, source_row, field_name, warn_type, warn_text, raw_value))

        if out["SerialNumber"]:
            if out["SerialNumber"] in seen_serials:
                first_file, first_row = seen_serials[out["SerialNumber"]]
                warnings.append(
                    warning(
                        source_file,
                        source_row,
                        "SerialNumber",
                        "DuplicateSerialNumber",
                        f"Duplicate serial also appears in {first_file} row {first_row}.",
                        raw_serial,
                    )
                )
            else:
                seen_serials[out["SerialNumber"]] = (source_file, source_row)

        errors.extend(row_errors)
        if not row_errors or pass_thru:
            clean_rows.append(out)

    return clean_rows, errors, warnings


def validate_review_queue(rows: list[dict[str, str]], input_path: Path, pass_thru: bool) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    clean_rows: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []

    for offset, row in enumerate(rows, start=2):
        out = canonical_row(row, REVIEW_QUEUE_HEADERS)
        source_file, source_row = source_identity(out, input_path, offset)
        out["SourceFile"] = out["SourceFile"] or source_file
        out["SourceRow"] = out["SourceRow"] or source_row

        out, network_warnings = normalize_common_network_fields(out)

        severity_raw = out["Severity"]
        out["Severity"] = severity_raw.lower()
        status_raw = out["ReviewStatus"]
        out["ReviewStatus"] = STATUS_NORMALIZATION.get(status_raw.strip().lower(), status_raw)

        row_errors: list[dict[str, str]] = []
        if not out["IssueType"]:
            row_errors.append(message(source_file, source_row, "IssueType", "MissingIssueType", "IssueType is required.", ""))

        if out["Severity"] not in VALID_SEVERITIES:
            row_errors.append(message(source_file, source_row, "Severity", "InvalidSeverity", "Severity must be one of: low, medium, high, critical.", severity_raw))

        if out["ReviewStatus"] not in VALID_REVIEW_STATUSES:
            row_errors.append(message(source_file, source_row, "ReviewStatus", "InvalidReviewStatus", "ReviewStatus must be one of: New, In Review, Resolved, Deferred, Rejected.", status_raw))

        for field_name, warn_type, warn_text, raw_value in network_warnings:
            if field_name == "IPAddress":
                row_errors.append(message(source_file, source_row, field_name, "InvalidIPv4", "IP address must be a valid IPv4 address.", raw_value))
            else:
                warnings.append(warning(source_file, source_row, field_name, warn_type, warn_text, raw_value))

        errors.extend(row_errors)
        if not row_errors or pass_thru:
            clean_rows.append(out)

    return clean_rows, errors, warnings


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate SysAdminSuite artifact delivery CSVs.")
    parser.add_argument("--input", required=True, help="Input artifact CSV path.")
    parser.add_argument("--artifact-type", required=True, choices=sorted(ARTIFACT_HEADERS), help="Artifact type to validate.")
    parser.add_argument("--output", required=True, help="Clean normalized CSV output path.")
    parser.add_argument("--errors", required=True, help="Validation errors CSV output path.")
    parser.add_argument("--warnings", required=True, help="Validation warnings CSV output path.")
    parser.add_argument("--pass-thru", action="store_true", help="Write normalized rows even when row-level errors exist.")
    parser.add_argument("--production-mode", action="store_true", help="Treat placeholders as production-blocking errors.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    input_path = Path(args.input)
    rows = read_csv(input_path)

    if args.artifact_type == "workstation-source":
        clean_rows, errors, warnings = validate_workstation(rows, input_path, args.pass_thru)
    elif args.artifact_type == "serial-prefixes":
        clean_rows, errors, warnings = validate_serial_prefixes(rows, input_path, args.pass_thru, args.production_mode)
    elif args.artifact_type == "field-capture":
        clean_rows, errors, warnings = validate_field_capture(rows, input_path, args.pass_thru)
    elif args.artifact_type == "review-queue":
        clean_rows, errors, warnings = validate_review_queue(rows, input_path, args.pass_thru)
    else:
        raise AssertionError(f"Unhandled artifact type: {args.artifact_type}")

    write_csv(Path(args.output), ARTIFACT_HEADERS[args.artifact_type], clean_rows)
    write_csv(Path(args.errors), MESSAGE_HEADERS, errors)
    write_csv(Path(args.warnings), WARNING_HEADERS, warnings)

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
