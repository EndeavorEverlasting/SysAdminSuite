#!/usr/bin/env python3
"""Shared device-role classifier for Cybernet manifest and subnet discovery lanes.

Pure offline logic — no network access. Labels DNS/probe findings so technicians
can separate manifest workstations from infrastructure (APs, switches, printers).
"""
from __future__ import annotations

import re
from typing import Iterable

CYBERNET_PREFIX_RE = re.compile(r"^([A-Z]{2,4})(\d{2,4})([A-Z]{2,6})(\d*)$")

AP_PATTERNS = (
    r"\bap[-_]",
    r"\bwap\b",
    r"\bwireless\b",
    r"\bwlc\b",
    r"\baruba\b",
    r"\bmeraki\b",
    r"\bmist[-_]",
    r"\bunifi\b",
    r"\baironet\b",
    r"\baccess[-_]?point\b",
)

NETWORK_PATTERNS = (
    r"\bswitch\b",
    r"\brouter\b",
    r"\bfw[-_]",
    r"\bfirewall\b",
    r"\bcore[-_]",
    r"\bdist[-_]",
    r"\bstack\b",
    r"\bnexus\b",
    r"\bcatalyst\b",
)

PRINTER_NAME_PATTERNS = (
    r"\bprinter\b",
    r"\bprint[-_]",
    r"\bmfp\b",
    r"\bcopier\b",
    r"\bhp[-_]?laser",
    r"\bcanon[-_]",
    r"\bxerox\b",
    r"\bricoh\b",
)

AP_VENDORS = frozenset(
    {
        "aruba",
        "cisco",
        "meraki",
        "mist",
        "ruckus",
        "ubiquiti",
        "unifi",
        "aerohive",
        "extreme",
    }
)

PRINTER_VENDORS = frozenset({"hp", "hewlett", "canon", "xerox", "ricoh", "lexmark", "konica", "epson", "brother"})

WIN_WORKSTATION_PORTS = frozenset({"445", "3389", "5985", "5986", "135"})
PRINTER_PORTS = frozenset({"9100", "515", "631"})


def clean(value: object) -> str:
    return str(value or "").strip()


def norm_host(value: object) -> str:
    text = clean(value).upper()
    return text.split(".", 1)[0] if text else ""


def _matches_any(text: str, patterns: tuple[str, ...]) -> bool:
    lowered = text.lower()
    return any(re.search(p, lowered) for p in patterns)


def _parse_ports(open_ports: Iterable[str] | str | None) -> set[str]:
    if open_ports is None:
        return set()
    if isinstance(open_ports, str):
        parts = re.split(r"[,;|\s]+", open_ports)
    else:
        parts = list(open_ports)
    out: set[str] = set()
    for part in parts:
        token = clean(part)
        if not token:
            continue
        m = re.match(r"^(\d+)", token)
        if m:
            out.add(m.group(1))
    return out


def _identifier_type_from_row(
    identifier_type: str = "",
    serial: str = "",
    hostname: str = "",
    mac: str = "",
) -> str:
    itype = clean(identifier_type).lower()
    if "serial" in itype or itype in {"sn", "s/n", "service_tag", "servicetag"}:
        return "Serial"
    if "mac" in itype:
        return "MAC"
    if "host" in itype or itype in {"hostname", "dns", "fqdn"}:
        return "HostName"
    if clean(serial):
        return "Serial"
    if clean(hostname):
        return "HostName"
    if clean(mac):
        return "MAC"
    return "HostName"


def _survey_authority(
    identifier_type: str,
    survey_lane: str,
    in_manifest: bool,
) -> str:
    if survey_lane == "subnet_discovery":
        return "subnet_inference_only"
    if identifier_type == "Serial":
        return "serial"
    if identifier_type == "MAC":
        return "mac_supporting"
    if in_manifest:
        return "hostname_fallback"
    return "subnet_inference_only"


def is_cybernet_hostname(hostname: str) -> bool:
    host = norm_host(hostname)
    return bool(host and CYBERNET_PREFIX_RE.match(host))


class ClassificationResult:
    __slots__ = (
        "survey_lane",
        "identifier_type",
        "survey_authority",
        "device_role",
        "role_confidence",
        "role_signals",
        "counts_toward_cybernet_population",
        "next_action",
    )

    def __init__(
        self,
        *,
        survey_lane: str,
        identifier_type: str,
        survey_authority: str,
        device_role: str,
        role_confidence: str,
        role_signals: str,
        counts_toward_cybernet_population: str,
        next_action: str,
    ) -> None:
        self.survey_lane = survey_lane
        self.identifier_type = identifier_type
        self.survey_authority = survey_authority
        self.device_role = device_role
        self.role_confidence = role_confidence
        self.role_signals = role_signals
        self.counts_toward_cybernet_population = counts_toward_cybernet_population
        self.next_action = next_action

    def as_dict(self) -> dict[str, str]:
        return {
            "SurveyLane": self.survey_lane,
            "IdentifierType": self.identifier_type,
            "SurveyAuthority": self.survey_authority,
            "DeviceRole": self.device_role,
            "RoleConfidence": self.role_confidence,
            "RoleSignals": self.role_signals,
            "CountsTowardCybernetPopulation": self.counts_toward_cybernet_population,
            "NextAction": self.next_action,
        }


def classify_device(
    *,
    hostname: str = "",
    reverse_dns_names: Iterable[str] | str = (),
    mac_vendor: str = "",
    open_ports: Iterable[str] | str | None = None,
    device_type: str = "",
    identifier_type: str = "",
    serial: str = "",
    mac: str = "",
    survey_lane: str = "cybernet_manifest",
    in_manifest: bool = True,
) -> ClassificationResult:
    """Classify a device row for survey lane review.

    survey_lane: ``cybernet_manifest`` or ``subnet_discovery``
    in_manifest: whether the row came from an approved manifest (vs discovery-only)
    """
    lane = clean(survey_lane).lower() or "cybernet_manifest"
    if lane not in {"cybernet_manifest", "subnet_discovery"}:
        lane = "cybernet_manifest"

    host = norm_host(hostname)
    if isinstance(reverse_dns_names, str):
        rev_list = [n.strip() for n in re.split(r"[;,|]+", reverse_dns_names) if n.strip()]
    else:
        rev_list = [clean(n) for n in reverse_dns_names if clean(n)]

    names_to_check = " ".join([host, *rev_list]).lower()
    vendor = clean(mac_vendor).lower()
    ports = _parse_ports(open_ports)
    dtype = clean(device_type) or "Cybernet"
    id_type = _identifier_type_from_row(identifier_type, serial, host, mac)
    authority = _survey_authority(id_type, lane, in_manifest)

    signals: list[str] = []

    # Infrastructure: access points
    ap_by_name = _matches_any(names_to_check, AP_PATTERNS)
    ap_by_vendor = bool(vendor and any(v in vendor for v in AP_VENDORS))
    if ap_by_name:
        signals.append("reverse_dns:ap-pattern")
    if ap_by_vendor:
        signals.append(f"vendor:{vendor.split()[0]}")
    if ap_by_name or ap_by_vendor:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="infrastructure_access_point",
            role_confidence="high" if ap_by_name and ap_by_vendor else "medium",
            role_signals=";".join(signals),
            counts_toward_cybernet_population="No",
            next_action="Infrastructure AP — informational for subnet review; not a Cybernet workstation target.",
        )

    # Infrastructure: network gear
    if _matches_any(names_to_check, NETWORK_PATTERNS):
        signals.append("reverse_dns:network-gear")
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="infrastructure_network",
            role_confidence="medium",
            role_signals=";".join(signals),
            counts_toward_cybernet_population="No",
            next_action="Network infrastructure — review for subnet/location context only.",
        )

    # Printers
    printer_hit = _matches_any(names_to_check, PRINTER_NAME_PATTERNS)
    if vendor and any(v in vendor for v in PRINTER_VENDORS):
        signals.append(f"vendor:{vendor.split()[0]}")
        printer_hit = True
    if ports & PRINTER_PORTS:
        for p in sorted(ports & PRINTER_PORTS):
            signals.append(f"port:{p}")
        printer_hit = True
    if printer_hit:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="infrastructure_print",
            role_confidence="high" if ports & PRINTER_PORTS else "medium",
            role_signals=";".join(signals) or "name:printer-pattern",
            counts_toward_cybernet_population="No",
            next_action="Print device — validate queue/driver path; not a Cybernet workstation.",
        )

    # Workstation signals
    win_ports = ports & WIN_WORKSTATION_PORTS
    cybernet_host = dtype.lower() == "cybernet" and is_cybernet_hostname(host)
    has_win_ports = bool(win_ports)
    if cybernet_host:
        signals.append("hostname:cybernet-prefix")
    if win_ports:
        for p in sorted(win_ports):
            signals.append(f"port:{p}")

    if cybernet_host or has_win_ports:
        counts = "Yes" if lane == "cybernet_manifest" and in_manifest else "No"
        conf = "high" if cybernet_host and win_ports else "medium" if cybernet_host or win_ports else "low"
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="target_workstation",
            role_confidence=conf,
            role_signals=";".join(signals) or "manifest:cybernet",
            counts_toward_cybernet_population=counts,
            next_action="Manifest workstation target — proceed with serial-first identity and reachability probes.",
        )

    if win_ports:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="target_workstation",
            role_confidence="medium",
            role_signals=";".join(signals),
            counts_toward_cybernet_population="Yes" if lane == "cybernet_manifest" and in_manifest else "No",
            next_action="Possible Windows endpoint — confirm serial identity before treating as confirmed Cybernet target.",
        )

    # Discovery-only / unknown
    if lane == "subnet_discovery" or not in_manifest:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="discovery_only",
            role_confidence="low",
            role_signals=";".join(signals) or "lane:subnet_discovery",
            counts_toward_cybernet_population="No",
            next_action="Discovery-only host — use for subnet/location inference; never serial proof.",
        )

    if lane == "cybernet_manifest" and in_manifest:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=authority,
            device_role="target_workstation",
            role_confidence="low",
            role_signals=";".join(signals) or "manifest:present",
            counts_toward_cybernet_population="Yes",
            next_action="Manifest row — collect serial-first identity evidence.",
        )

    return ClassificationResult(
        survey_lane=lane,
        identifier_type=id_type,
        survey_authority=authority,
        device_role="infrastructure_unknown",
        role_confidence="low",
        role_signals=";".join(signals) or "role:unknown",
        counts_toward_cybernet_population="No",
        next_action="Unknown infrastructure — review before adding to manifest.",
    )


def classify_from_dns_row(row: dict[str, str], survey_lane: str = "cybernet_manifest") -> dict[str, str]:
    """Classify from a DNS resolution CSV row."""
    hostname = clean(row.get("HostName") or row.get("Hostname") or row.get("Identifier"))
    reverse = clean(row.get("ReverseNames") or row.get("ReverseDNS"))
    result = classify_device(
        hostname=hostname,
        reverse_dns_names=reverse,
        device_type=clean(row.get("DeviceType")),
        identifier_type=clean(row.get("IdentifierType")),
        serial=clean(row.get("Serial")),
        mac=clean(row.get("MACAddress") or row.get("MacAddress")),
        survey_lane=survey_lane,
        in_manifest=True,
    )
    return result.as_dict()


def classify_from_unresolved_manifest_row(row: dict[str, str], survey_lane: str = "cybernet_manifest") -> dict[str, str]:
    """Classify manifest rows with no resolvable hostname (NO_HOSTNAME path)."""
    lane = clean(survey_lane).lower() or "cybernet_manifest"
    if lane not in {"cybernet_manifest", "subnet_discovery"}:
        lane = "cybernet_manifest"

    serial = clean(row.get("Serial") or row.get("SerialNumber"))
    mac = clean(row.get("MACAddress") or row.get("MacAddress") or row.get("MAC"))
    identifier = clean(row.get("Identifier") or row.get("Target"))
    identifier_type = clean(row.get("IdentifierType") or row.get("Type"))

    if serial:
        return ClassificationResult(
            survey_lane=lane,
            identifier_type="Serial",
            survey_authority="serial",
            device_role="target_workstation",
            role_confidence="needs_review",
            role_signals="manifest:no-hostname;identifier:serial",
            counts_toward_cybernet_population="Yes",
            next_action="Manifest serial without hostname — verify hostname against AD and collect serial-first identity evidence.",
        ).as_dict()

    if mac or identifier_type.lower() == "mac":
        return ClassificationResult(
            survey_lane=lane,
            identifier_type="MAC",
            survey_authority="mac_supporting",
            device_role="target_workstation",
            role_confidence="needs_review",
            role_signals="manifest:no-hostname;identifier:mac",
            counts_toward_cybernet_population="No",
            next_action="Manifest MAC without hostname — resolve hostname via DHCP or AD before treating as confirmed target.",
        ).as_dict()

    if identifier:
        id_type = _identifier_type_from_row(identifier_type, "", identifier, mac)
        return ClassificationResult(
            survey_lane=lane,
            identifier_type=id_type,
            survey_authority=_survey_authority(id_type, lane, True),
            device_role="discovery_only",
            role_confidence="needs_review",
            role_signals="manifest:no-hostname;identifier:ambiguous",
            counts_toward_cybernet_population="No",
            next_action="Unresolved manifest identifier — confirm serial or hostname before adding to probe list.",
        ).as_dict()

    return ClassificationResult(
        survey_lane=lane,
        identifier_type="HostName",
        survey_authority="hostname_fallback",
        device_role="infrastructure_unknown",
        role_confidence="needs_review",
        role_signals="manifest:no-hostname;identifier:none",
        counts_toward_cybernet_population="No",
        next_action="Manifest row lacks hostname and usable identifier — review source file and fix manifest row.",
    ).as_dict()


def classify_from_nmap_row(row: dict[str, str], survey_lane: str = "cybernet_manifest") -> dict[str, str]:
    """Classify from an Nmap evidence export row."""
    observed_hostname = clean(row.get("observed_hostname") or row.get("HostName"))
    target = clean(row.get("Target"))
    hostname = observed_hostname or (target if observed_hostname == "" and target and not re.match(r"^\d+\.\d+\.\d+\.\d+$", target) else "")
    notes = clean(row.get("Notes"))
    port_match = re.findall(r"(\d+)/tcp", notes)
    mac = clean(row.get("observed_mac") or row.get("MACAddress"))
    serial = clean(row.get("observed_serial") or row.get("Serial"))
    id_type = _identifier_type_from_row("", serial, hostname, mac)

    result = classify_device(
        hostname=hostname,
        reverse_dns_names=hostname,
        open_ports=port_match,
        mac=mac,
        serial=serial,
        identifier_type=id_type,
        survey_lane=survey_lane,
        in_manifest=True,
    )
    out = result.as_dict()

    if not observed_hostname:
        signals = [s for s in out.get("RoleSignals", "").split(";") if s]
        signals.append("nmap:no-hostname")
        out["RoleSignals"] = ";".join(signals)
        if result.device_role == "target_workstation":
            out["RoleConfidence"] = "needs_review"
            out["NextAction"] = (
                "Nmap observed IP or MAC without hostname — confirm hostname via AD or DHCP before serial proof."
            )
        elif result.device_role in {"discovery_only", "infrastructure_unknown"}:
            out["RoleConfidence"] = "needs_review"

    return out


CLASSIFICATION_FIELDS = [
    "SurveyLane",
    "IdentifierType",
    "SurveyAuthority",
    "DeviceRole",
    "RoleConfidence",
    "RoleSignals",
    "CountsTowardCybernetPopulation",
    "NextAction",
]
