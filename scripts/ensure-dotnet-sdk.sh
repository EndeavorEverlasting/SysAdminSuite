#!/usr/bin/env bash
# Ensure .NET 8 SDK is installed system-wide for source-checkout dashboard builds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${REPO_ROOT}/Config/dotnet-bootstrap.json"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/ensure-dotnet-sdk.sh [--dry-run]

Ensures a system-wide .NET 8 SDK is available. If missing, downloads the pinned
Microsoft SDK installer from Config/dotnet-bootstrap.json, verifies SHA512, and
runs the official installer.

Options:
  --dry-run   Print planned download/install actions only
  -h, --help  Show help
USAGE
}

log() { printf '[ensure-dotnet-sdk] %s\n' "$*" >&2; }
fail() { printf '[ensure-dotnet-sdk] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -f "$CONFIG" ]] || fail "Missing bootstrap config: $CONFIG"

json_value() {
  local section="$1" key="$2"
  awk -v section="\"${section}\"" -v key="\"${key}\"" '
    $0 ~ section { in_section=1; next }
    in_section && $0 ~ /^[[:space:]]*}/ { exit }
    in_section && $0 ~ key {
      sub(/^[^:]*:[[:space:]]*"/, "")
      sub(/",[[:space:]]*$/, "")
      sub(/"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$CONFIG"
}

cache_dir() {
  local configured
  configured="$(awk '
    /"cacheDir"/ {
      sub(/^[^:]*:[[:space:]]*"/, "")
      sub(/",[[:space:]]*$/, "")
      sub(/"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$CONFIG")"
  printf '%s\n' "${REPO_ROOT}/${configured:-tools/cache/dotnet}"
}

dotnet_cmd() {
  if command -v dotnet.exe >/dev/null 2>&1; then command -v dotnet.exe; return 0; fi
  if command -v dotnet >/dev/null 2>&1; then command -v dotnet; return 0; fi
  if [[ -x "/c/Program Files/dotnet/dotnet.exe" ]]; then printf '%s\n' "/c/Program Files/dotnet/dotnet.exe"; return 0; fi
  if [[ -x "/c/Program Files (x86)/dotnet/dotnet.exe" ]]; then printf '%s\n' "/c/Program Files (x86)/dotnet/dotnet.exe"; return 0; fi
  return 1
}

sdk_present() {
  local version_prefix="$1" dotnet_bin
  dotnet_bin="$(dotnet_cmd)" || return 1
  "$dotnet_bin" --list-sdks 2>/dev/null | grep -Eq "^${version_prefix}"
}

download_file() {
  local url="$1" target="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would download $url -> $target"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  if command -v curl.exe >/dev/null 2>&1; then
    curl.exe -fsSL --retry 3 --retry-delay 2 -o "$target" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 2 -o "$target" "$url"
  else
    fail "curl.exe or curl is required to download Microsoft .NET installers" 2
  fi
}

windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

actual_sha512() {
  local path="$1"
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$path" | awk '{print tolower($1)}'
    return 0
  fi
  if command -v certutil.exe >/dev/null 2>&1; then
    certutil.exe -hashfile "$(windows_path "$path")" SHA512 2>/dev/null \
      | tr -d '\r ' \
      | awk 'length($0) == 128 { print tolower($0); exit }'
    return 0
  fi
  fail "sha512sum or certutil.exe is required to verify .NET installers" 2
}

verify_hash() {
  local path="$1" expected="$2" actual
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would verify SHA512 for $path"
    return 0
  fi
  actual="$(actual_sha512 "$path")"
  [[ "${actual,,}" == "${expected,,}" ]] || fail "SHA512 mismatch for $path" 2
}

install_exe() {
  local path="$1" silent_args="$2" display="$3"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would install $display system-wide with: $silent_args"
    return 0
  fi
  log "Installing $display system-wide. This may require administrator approval..."
  cmd.exe /c "\"$(windows_path "$path")\" $silent_args" || fail "$display installer failed; IT/admin elevation may be required" 3
}

display="$(json_value sdk displayName)"
version_prefix="$(json_value sdk sdkVersionPrefix)"
file_name="$(json_value sdk fileName)"
url="$(json_value sdk url)"
hash="$(json_value sdk sha512)"
silent_args="$(json_value sdk silentArgs)"

[[ -n "$display" && -n "$version_prefix" && -n "$file_name" && -n "$url" && -n "$hash" ]] \
  || fail "Incomplete SDK config"

if sdk_present "$version_prefix"; then
  log "$display already present."
  exit 0
fi

cache="$(cache_dir)"
installer="${cache}/${file_name}"
log "$display is missing; preparing Microsoft installer."
if [[ ! -s "$installer" || "$DRY_RUN" -eq 1 ]]; then
  download_file "$url" "$installer"
else
  log "Using cached installer: $installer"
fi
verify_hash "$installer" "$hash"
install_exe "$installer" "$silent_args" "$display"

if [[ "$DRY_RUN" -eq 0 ]]; then
  sdk_present "$version_prefix" || fail "$display is still not visible to dotnet after install" 3
fi
log "Dashboard .NET SDK dependency is ready."
