#!/usr/bin/env bash
# Contract validator for survey/naabu_profiles.json (low-noise survey doctrine).
# See docs/LOW_NOISE_SURVEY_DOCTRINE.md. Read-only. No network, no targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE_JSON="${REPO_ROOT}/survey/naabu_profiles.json"

fail() { printf 'smoke-naabu-profiles: FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$PROFILE_JSON" ]] || fail "missing survey/naabu_profiles.json"

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required"
}

PY="$(find_python)"

"$PY" - "$PROFILE_JSON" <<'PY'
import ipaddress
import json
import re
import sys

path = sys.argv[1]

try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"smoke-naabu-profiles: FAIL: JSON parse error: {exc}", file=sys.stderr)
    sys.exit(1)

errors = []

profiles = cfg.get("profiles")
if not isinstance(profiles, dict) or not profiles:
    print("smoke-naabu-profiles: FAIL: no profiles object", file=sys.stderr)
    sys.exit(1)

# Live-looking domain detection. example.invalid is the only permitted placeholder.
DOMAIN_RE = re.compile(r"\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9-]+)+\b", re.IGNORECASE)
ALLOWED_DOMAINS = {"example.invalid"}


def iter_strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, list):
        for item in obj:
            yield from iter_strings(item)
    elif isinstance(obj, dict):
        for value in obj.values():
            yield from iter_strings(value)


def looks_like_private_ip(token):
    try:
        ip = ipaddress.ip_address(token)
    except ValueError:
        return False
    return ip.is_private or ip.is_loopback or ip.is_link_local


for name, prof in profiles.items():
    if not isinstance(prof, dict):
        errors.append(f"profile {name} is not an object")
        continue

    flags = prof.get("flags", [])
    if not isinstance(flags, list):
        errors.append(f"profile {name} flags must be a list")
        flags = []

    mode = prof.get("mode", "")
    ports = prof.get("ports")
    is_host_discovery = mode == "host-discovery"
    # A port-scanning profile validates TCP/UDP ports (has ports OR -p flag),
    # and is not a pure host-discovery profile.
    is_port_scan = (ports is not None or "-p" in flags) and not is_host_discovery

    # -silent required for any TCP/UDP port-scanning profile.
    if is_port_scan and "-silent" not in flags:
        errors.append(f"profile {name} missing -silent")
    # host-discovery profiles also emit local output; require -silent for hygiene.
    if is_host_discovery and "-silent" not in flags:
        errors.append(f"profile {name} (host-discovery) missing -silent")

    # -ec required on reachability profiles unless explicitly allowing CDN edges.
    is_reachability = is_port_scan or is_host_discovery
    if is_reachability and not prof.get("allowCdnEdges", False) and "-ec" not in flags:
        errors.append(f"profile {name} missing -ec (set allowCdnEdges:true to opt out)")

    # UDP profiles require explicit justification.
    is_udp = "-uP" in flags or (isinstance(ports, str) and "u:" in ports)
    if is_udp and prof.get("requiresJustification") is not True:
        errors.append(f"profile {name} is UDP and must set requiresJustification:true")

    # Subnet host discovery profiles require approved subnet scope.
    if is_host_discovery and prof.get("requiresApprovedSubnetScope") is not True:
        errors.append(f"profile {name} (host-discovery) must set requiresApprovedSubnetScope:true")

    # Pipe profile: silent stream for local enrichment, no -json in flags.
    if name == "keyports_cybernet_pipe":
        if "-json" in flags:
            errors.append("keyports_cybernet_pipe must not include -json")
        if "-silent" not in flags or "-ec" not in flags:
            errors.append("keyports_cybernet_pipe must include -silent and -ec")
        if prof.get("pipelineFollowup") is not True:
            errors.append("keyports_cybernet_pipe must set pipelineFollowup:true")

    # Pipeline-capable profiles must be silent.
    if prof.get("pipelineFollowup") is True and "-silent" not in flags:
        errors.append(f"profile {name} with pipelineFollowup must include -silent")

    # No live-looking domains or real private/corp targets in any field.
    for token in iter_strings(prof):
        for match in DOMAIN_RE.findall(token):
            if match.lower() in ALLOWED_DOMAINS:
                continue
            # Skip pure flag/port tokens that the domain regex won't match anyway.
            errors.append(f"profile {name} contains live-looking domain: {match}")
        for word in re.split(r"[\s,]+", token):
            if looks_like_private_ip(word):
                errors.append(f"profile {name} contains private/corp IP: {word}")

if errors:
    for err in errors:
        print(f"smoke-naabu-profiles: FAIL: {err}", file=sys.stderr)
    sys.exit(1)
PY

echo "smoke-naabu-profiles: PASS"
