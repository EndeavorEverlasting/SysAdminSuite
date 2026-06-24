#!/usr/bin/env bash
# Generate the runtime naabu profile config (Config/cybernet-naabu-profiles.json)
# from the low-noise survey doctrine contract (survey/naabu_profiles.json).
#
# Doctrine is the single source of truth. The runtime config is a deterministic,
# generated representation consumed by survey/sas-run-naabu-pipeline.sh. Do not
# hand-edit Config/cybernet-naabu-profiles.json; edit survey/naabu_profiles.json
# and re-run this generator. See docs/LOW_NOISE_SURVEY_DOCTRINE.md.
#
# Read-only doctrine input. No network, no targets.
set -euo pipefail

MODE="write"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTRINE_JSON="${REPO_ROOT}/survey/naabu_profiles.json"
RUNTIME_JSON="${REPO_ROOT}/Config/cybernet-naabu-profiles.json"

usage() {
  cat <<'USAGE'
Generate runtime naabu profile config from the doctrine contract.

Usage:
  bash survey/sas-generate-naabu-runtime-profiles.sh [--check]

Options:
  --check      Verify Config/cybernet-naabu-profiles.json matches the generated
               output. Exit non-zero (and print a diff) if stale. Writes nothing.
  -h, --help   Show help

Source : survey/naabu_profiles.json (low-noise survey doctrine)
Output : Config/cybernet-naabu-profiles.json (runtime, consumed by pipeline)
USAGE
}

log() { printf '[generate-naabu-profiles] %s\n' "$*" >&2; }
fail() { printf '[generate-naabu-profiles] ERROR: %s\n' "$*" >&2; exit 1; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required to read survey/naabu_profiles.json"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -f "$DOCTRINE_JSON" ]] || fail "Missing doctrine contract: $DOCTRINE_JSON"

PY="$(find_python)"

render() {
  "$PY" - "$DOCTRINE_JSON" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)

# Runtime-only constants. Keep deterministic.
NAABU_VERSION = "2.6.1"
INSTALL_DIR = "bin"

# Backward-compatible runtime aliases -> doctrine profile ids.
ALIASES = {
    "keyports_cdn": "web_reachability_only",
    "keyports_cdn_json": "web_reachability_only_json",
    "windows_selected": "keyports_cybernet_json",
    "host_discovery_tcp80": "host_discovery_web_syn_txt",
    "udp_infrastructure": "udp_dns_snmp_json",
    "hostname_all_ips": "load_balanced_hostname_all_ips_json",
    "full_ports_cdn_guarded": "allports_low_noise_json",
}


def max_targets(profile, flags, mode):
    if profile.get("requiresHostnameInput"):
        return 1
    if mode == "host-discovery":
        return 256
    if profile.get("ports") == "-":
        return 32
    if "-uP" in flags:
        return 64
    return 256


def syn_ports(flags):
    ports = []
    i = 0
    while i < len(flags):
        if flags[i] == "-ps" and i + 1 < len(flags):
            ports.append(str(flags[i + 1]))
            i += 2
            continue
        i += 1
    return ports


out_profiles = {}
for name, prof in doc.get("profiles", {}).items():
    flags = prof.get("flags", [])
    mode = prof.get("mode", "")
    is_hd = mode == "host-discovery"
    ports = prof.get("ports")

    entry = {"description": prof.get("description", "")}

    if is_hd:
        entry["hostDiscoveryOnly"] = True
        if "-pe" in flags:
            entry["probeIcmpEcho"] = True
        syn = syn_ports(flags)
        if syn:
            entry["probeTcpSynPorts"] = syn
    else:
        entry["hostDiscoveryOnly"] = False
        if ports is not None:
            entry["ports"] = str(ports)

    entry["excludeCdn"] = "-ec" in flags
    if "-sa" in flags:
        entry["scanAllIps"] = True
    entry["udpProbes"] = "-uP" in flags
    entry["silent"] = "-silent" in flags
    entry["disableUpdateCheck"] = True
    entry["outputFormat"] = prof.get("output", "txt")
    entry["maxTargets"] = max_targets(prof, flags, mode)
    entry["allowFullPorts"] = ports == "-"
    entry["pipelineFollowup"] = bool(prof.get("pipelineFollowup", False))
    if prof.get("requiresHostnameInput"):
        entry["requiresHost"] = True
    if prof.get("requiresApprovedSubnetScope"):
        entry["requiresApprovedSubnetScope"] = True
    if prof.get("requiresJustification"):
        entry["requiresJustification"] = True

    out_profiles[name] = entry

config = {
    "_generated": "DO NOT EDIT BY HAND. Generated from survey/naabu_profiles.json by survey/sas-generate-naabu-runtime-profiles.sh. Edit the doctrine contract and re-run the generator.",
    "naabuVersion": NAABU_VERSION,
    "defaultProfile": doc.get("defaultProfile", "keyports_cybernet_json"),
    "installDir": INSTALL_DIR,
    "profileAliases": ALIASES,
    "profiles": out_profiles,
}

sys.stdout.write(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY
}

if [[ "$MODE" == "check" ]]; then
  [[ -f "$RUNTIME_JSON" ]] || fail "Missing runtime config: $RUNTIME_JSON (run without --check to generate)"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  render > "$tmp"
  if diff -u "$RUNTIME_JSON" "$tmp"; then
    log "runtime config is in sync with doctrine contract"
    exit 0
  else
    fail "Config/cybernet-naabu-profiles.json is stale. Run: bash survey/sas-generate-naabu-runtime-profiles.sh"
  fi
fi

render > "$RUNTIME_JSON"
log "wrote $RUNTIME_JSON"
