#!/usr/bin/env bash
# Render a naabu command from survey/naabu_profiles.json without running it.
# Low-noise survey doctrine: see docs/LOW_NOISE_SURVEY_DOCTRINE.md.
# Render-only. This script never executes naabu and never touches target hosts.
set -euo pipefail

VERSION="0.1.0"
PROFILE=""
LIST=""
HOST=""
OUT=""
ALLOW_ANY_LIST=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_JSON="${REPO_ROOT}/survey/naabu_profiles.json"

usage() {
  cat <<'USAGE'
SysAdminSuite Naabu Profile Command Renderer (render-only)

Prints the naabu command for a doctrine profile from survey/naabu_profiles.json.
It does not run naabu and does not contact any host.

Usage:
  bash survey/sas-naabu-profile-command.sh --profile NAME [options]

Required:
  --profile NAME       Profile id from survey/naabu_profiles.json

Target input:
  --list PATH          Approved AD-derived host/subnet list (one entry per line)
  --host URL           Hostname/URL for load-balanced -sa profiles

Options:
  --out PATH           Output file path (logs/nmap/ convention preferred)
  --allow-any-list     Permit a --list path outside logs/targets/
  -h, --help           Show help
  --version            Print version

Doctrine: AD-derived targets first; naabu validates reachability only.
USAGE
}

log() { printf '[naabu-profile-command] %s\n' "$*" >&2; }
fail() { printf '[naabu-profile-command] ERROR: %s\n' "$*" >&2; exit 1; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required to read survey/naabu_profiles.json"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:?missing --profile value}"; shift 2 ;;
    --list) LIST="${2:?missing --list value}"; shift 2 ;;
    --host) HOST="${2:?missing --host value}"; shift 2 ;;
    --out) OUT="${2:?missing --out value}"; shift 2 ;;
    --allow-any-list) ALLOW_ANY_LIST=1; shift ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$PROFILE" ]] || fail "--profile is required"
[[ -f "$PROFILE_JSON" ]] || fail "Missing $PROFILE_JSON"

# Approved target-input convention check (unless explicitly overridden).
# --allow-any-list bypasses both the convention check and the existence check.
if [[ -n "$LIST" && "$ALLOW_ANY_LIST" -ne 1 ]]; then
  if [[ "$LIST" != logs/targets/* ]]; then
    fail "--list must be under logs/targets/ (AD-derived store) or pass --allow-any-list: $LIST"
  fi
  [[ -f "$LIST" ]] || fail "Target list not found: $LIST (render expects an existing approved list)"
fi

PY="$(find_python)"
"$PY" - "$PROFILE_JSON" "$PROFILE" "$LIST" "$HOST" "$OUT" <<'PY'
import json, sys

profile_path, profile_id, list_path, host, out_path = sys.argv[1:6]
with open(profile_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
profiles = cfg.get("profiles", {})
if profile_id not in profiles:
    sys.stderr.write(f"[naabu-profile-command] ERROR: unknown profile: {profile_id}\n")
    sys.exit(2)
p = profiles[profile_id]

argv = ["naabu"]

if p.get("requiresHostnameInput"):
    if not host:
        sys.stderr.write(f"[naabu-profile-command] ERROR: profile {profile_id} requires --host\n")
        sys.exit(3)
    argv += ["-host", host]
elif list_path:
    argv += ["-list", list_path]
else:
    sys.stderr.write(f"[naabu-profile-command] ERROR: profile {profile_id} requires --list (or --host)\n")
    sys.exit(4)

ports = p.get("ports")
if ports and p.get("mode") != "host-discovery":
    argv += ["-p", str(ports)]

argv += [str(flag) for flag in p.get("flags", [])]

if out_path:
    argv += ["-o", out_path]

print(" ".join(argv))
PY
