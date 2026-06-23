#!/usr/bin/env bash
# Ensure naabu CLI is available: PATH, repo bin/, or GitHub release download.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_JSON="${REPO_ROOT}/Config/cybernet-naabu-profiles.json"
BIN_DIR="${REPO_ROOT}/bin"
NAABU_VERSION=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bash survey/sas-ensure-naabu.sh [--dry-run]

Ensures naabu is on PATH. If missing, downloads the pinned Windows amd64 binary
from ProjectDiscovery GitHub releases into bin/naabu.exe (Git Bash on Windows).

Options:
  --dry-run   Print planned download/install only
  -h, --help  Show help
USAGE
}

log() { printf '[ensure-naabu] %s\n' "$*" >&2; }
fail() { printf '[ensure-naabu] ERROR: %s\n' "$*" >&2; exit 1; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
  if command -v python >/dev/null 2>&1; then echo python; return 0; fi
  fail "Python 3 required to read Config/cybernet-naabu-profiles.json"
}

load_version() {
  local py
  py="$(find_python)"
  NAABU_VERSION="$("$py" - "$PROFILE_JSON" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("naabuVersion", "2.6.1"))
PY
)"
}

naabu_on_path() {
  if command -v naabu.exe >/dev/null 2>&1; then command -v naabu.exe; return 0; fi
  if command -v naabu >/dev/null 2>&1; then command -v naabu; return 0; fi
  return 1
}

repo_naabu() {
  local exe="${BIN_DIR}/naabu.exe"
  [[ -x "$exe" ]] && printf '%s' "$exe" && return 0
  [[ -f "$exe" ]] && printf '%s' "$exe" && return 0
  return 1
}

download_naabu_windows() {
  local ver="$1" zip url tmp
  ver="${ver#v}"
  zip="naabu_${ver}_windows_amd64.zip"
  url="https://github.com/projectdiscovery/naabu/releases/download/v${ver}/${zip}"
  tmp="$(mktemp -d)"
  mkdir -p "$BIN_DIR"
  log "Downloading naabu v${ver} from GitHub releases..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would download $url -> $BIN_DIR/naabu.exe"
    rm -rf "$tmp"
    return 0
  fi
  if command -v curl.exe >/dev/null 2>&1; then
    curl.exe -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${zip}" "$url" || true
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}/${zip}" "$url" || true
  fi
  if [[ ! -s "${tmp}/${zip}" ]] && command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "Invoke-WebRequest -Uri '$url' -OutFile '${tmp}/${zip}' -UseBasicParsing" || true
  fi
  [[ -s "${tmp}/${zip}" ]] || fail "download failed: $url (curl and PowerShell)"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "${tmp}/${zip}" -d "$tmp"
  elif command -v tar >/dev/null 2>&1; then
    (cd "$tmp" && tar -xf "${zip}")
  else
    fail "unzip or tar required to extract naabu archive"
  fi
  local extracted
  extracted="$(find "$tmp" -name 'naabu.exe' -o -name 'naabu' | head -n 1)"
  [[ -n "$extracted" ]] || fail "naabu binary not found inside ${zip}"
  cp "$extracted" "${BIN_DIR}/naabu.exe"
  chmod +x "${BIN_DIR}/naabu.exe" 2>/dev/null || true
  rm -rf "$tmp"
  log "Installed ${BIN_DIR}/naabu.exe"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -f "$PROFILE_JSON" ]] || fail "Missing profile config: $PROFILE_JSON"
load_version

if path_bin="$(naabu_on_path)"; then
  log "Using naabu on PATH: $path_bin"
  printf '%s\n' "$path_bin"
  exit 0
fi

if repo_bin="$(repo_naabu)"; then
  log "Using repo binary: $repo_bin"
  printf '%s\n' "$repo_bin"
  exit 0
fi

download_naabu_windows "$NAABU_VERSION"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN: using planned path ${BIN_DIR}/naabu.exe"
  printf '%s\n' "${BIN_DIR}/naabu.exe"
  exit 0
fi
repo_bin="$(repo_naabu)" || fail "naabu install failed"
log "Using repo binary: $repo_bin"
printf '%s\n' "$repo_bin"
