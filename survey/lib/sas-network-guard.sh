#!/usr/bin/env bash
# Shared Northwell Wi-Fi guard for live SysAdminSuite Bash scripts.

sas_network_guard_required_prefix="${SAS_NETWORK_GUARD_PREFIX:-NSLIJHS-WAB}"

sas_network_guard_trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

sas_network_guard_parse_netsh_ssid() {
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == *:* ]] || continue
    key="$(sas_network_guard_trim "${line%%:*}")"
    value="$(sas_network_guard_trim "${line#*:}")"
    # Match the currently connected SSID line only; never BSSID.
    if [[ "$key" == "SSID" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  printf 'unknown'
}

sas_network_guard_current_ssid() {
  if command -v netsh.exe >/dev/null 2>&1; then
    netsh.exe wlan show interfaces 2>/dev/null | sas_network_guard_parse_netsh_ssid
  elif command -v netsh >/dev/null 2>&1; then
    netsh wlan show interfaces 2>/dev/null | sas_network_guard_parse_netsh_ssid
  else
    printf 'unknown'
  fi
}

sas_network_guard_ssid_allowed() {
  local ssid="${1:-}"
  [[ -n "$ssid" && "$ssid" != "unknown" && "$ssid" == "$sas_network_guard_required_prefix"* ]]
}

sas_require_northwell_wifi() {
  local ssid
  ssid="$(sas_network_guard_current_ssid)"
  if ! sas_network_guard_ssid_allowed "$ssid"; then
    printf 'Network check failed: this script must be run while connected to a Northwell Wi-Fi network starting with %s. Current SSID: %s. Connect to %s and rerun.\n' \
      "$sas_network_guard_required_prefix" "${ssid:-unknown}" "$sas_network_guard_required_prefix" >&2
    return 1
  fi
}
