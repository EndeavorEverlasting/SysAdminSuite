#!/usr/bin/env bash
# Shared Northwell network posture guard for live SysAdminSuite Bash scripts.
# Passes with approved Wi-Fi SSID or configured local wired-LAN evidence only.

sas_network_guard_required_prefix="${SAS_NETWORK_GUARD_PREFIX:-NSLIJHS-WAB}"
sas_network_guard_config_error=""
sas_network_guard_last_wired_evidence="none"

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
      printf '%s' "${value:-unknown}"
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

sas_network_guard_config_path() {
  if [[ -n "${SAS_NETWORK_GUARD_CONFIG:-}" ]]; then
    printf '%s' "$SAS_NETWORK_GUARD_CONFIG"
  elif [[ -n "${SAS_REPO_ROOT:-}" ]]; then
    printf '%s' "$SAS_REPO_ROOT/Config/sas-network-guard.local.json"
  else
    printf '%s' "Config/sas-network-guard.local.json"
  fi
}

sas_network_guard_csv_to_lines() {
  local key="$1" raw="${2:-}" item
  [[ -z "$raw" ]] && return 0
  IFS=',' read -r -a _sas_items <<< "$raw"
  for item in "${_sas_items[@]}"; do
    item="$(sas_network_guard_trim "$item")"
    [[ -n "$item" ]] && printf '%s=%s\n' "$key" "$item"
  done
}

sas_network_guard_load_config() {
  local cfg
  sas_network_guard_config_error=""
  cfg="$(sas_network_guard_config_path)"
  {
    sas_network_guard_csv_to_lines dns_suffix "${SAS_NETWORK_GUARD_ALLOWED_DNS_SUFFIXES:-}"
    sas_network_guard_csv_to_lines windows_domain "${SAS_NETWORK_GUARD_ALLOWED_WINDOWS_DOMAINS:-}"
    sas_network_guard_csv_to_lines local_ip_cidr "${SAS_NETWORK_GUARD_ALLOWED_LOCAL_IP_CIDRS:-}"
    sas_network_guard_csv_to_lines gateway_cidr "${SAS_NETWORK_GUARD_ALLOWED_GATEWAY_CIDRS:-}"
    sas_network_guard_csv_to_lines dns_server_cidr "${SAS_NETWORK_GUARD_ALLOWED_DNS_SERVER_CIDRS:-}"
  }
  [[ -f "$cfg" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    sas_network_guard_config_error="config_present_but_python3_missing:$cfg"
    return 2
  fi
  local parsed rc
  parsed="$(python3 - "$cfg" <<'PY' 2>&1
import json, sys
path=sys.argv[1]
try:
    with open(path, encoding='utf-8') as f:
        data=json.load(f)
except Exception as exc:
    print(f"ERROR=malformed_config:{exc}")
    sys.exit(2)
if not isinstance(data, dict):
    print("ERROR=malformed_config:top_level_must_be_object")
    sys.exit(2)
keys={
  'allowedDnsSuffixes':'dns_suffix',
  'allowedWindowsDomains':'windows_domain',
  'allowedLocalIpCidrs':'local_ip_cidr',
  'allowedGatewayCidrs':'gateway_cidr',
  'allowedDnsServerCidrs':'dns_server_cidr',
}
for src, dst in keys.items():
    values=data.get(src, [])
    if values is None:
        continue
    if not isinstance(values, list) or any(not isinstance(v, str) or not v.strip() for v in values):
        print(f"ERROR=malformed_config:{src}_must_be_string_array")
        sys.exit(2)
    for value in values:
        print(f"{dst}={value.strip()}")
PY
)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    sas_network_guard_config_error="${parsed#ERROR=}"
    [[ -z "$sas_network_guard_config_error" ]] && sas_network_guard_config_error="malformed_config:$cfg"
    return 2
  fi
  printf '%s\n' "$parsed"
}

sas_network_guard_collect_local_network_text() {
  if [[ -n "${SAS_NETWORK_GUARD_IPCONFIG_FIXTURE:-}" ]]; then
    cat "$SAS_NETWORK_GUARD_IPCONFIG_FIXTURE"
  elif command -v ipconfig.exe >/dev/null 2>&1; then
    ipconfig.exe /all 2>/dev/null
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c ipconfig /all 2>/dev/null
  elif command -v ipconfig >/dev/null 2>&1; then
    ipconfig /all 2>/dev/null
  else
    return 0
  fi
}

sas_network_guard_ip_in_cidr() {
  local ip="$1" cidr="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$ip" "$cidr" <<'PY' >/dev/null 2>&1
import ipaddress, sys
try:
    ip=ipaddress.ip_address(sys.argv[1].split('%',1)[0])
    net=ipaddress.ip_network(sys.argv[2], strict=False)
except Exception:
    sys.exit(1)
sys.exit(0 if ip in net else 1)
PY
}

sas_network_guard_wired_evidence_allowed() {
  local text="${1:-}" config config_rc line key value evidence=""
  local suffixes=() domains=() ip_cidrs=() gateway_cidrs=() dns_cidrs=()
  config="$(sas_network_guard_load_config)"; config_rc=$?
  if [[ $config_rc -ne 0 ]]; then
    sas_network_guard_last_wired_evidence="config_error:${sas_network_guard_config_error:-unknown}"
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      dns_suffix) suffixes+=("$value") ;;
      windows_domain) domains+=("$value") ;;
      local_ip_cidr) ip_cidrs+=("$value") ;;
      gateway_cidr) gateway_cidrs+=("$value") ;;
      dns_server_cidr) dns_cidrs+=("$value") ;;
    esac
  done <<< "$config"
  if [[ ${#suffixes[@]} -eq 0 && ${#domains[@]} -eq 0 && ${#ip_cidrs[@]} -eq 0 && ${#gateway_cidrs[@]} -eq 0 && ${#dns_cidrs[@]} -eq 0 ]]; then
    sas_network_guard_last_wired_evidence="none"
    return 1
  fi

  local lower_text suffix domain cidr ip
  lower_text="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  for suffix in "${suffixes[@]}"; do
    [[ -z "$suffix" ]] && continue
    if printf '%s\n' "$lower_text" | grep -Fqi "$(printf '%s' "$suffix" | tr '[:upper:]' '[:lower:]')"; then
      evidence="dns_suffix=$suffix"; break
    fi
  done
  if [[ -z "$evidence" ]]; then
    for domain in "${domains[@]}"; do
      [[ -z "$domain" ]] && continue
      if printf '%s\n' "$lower_text" | grep -Fqi "$(printf '%s' "$domain" | tr '[:upper:]' '[:lower:]')"; then
        evidence="windows_domain=$domain"; break
      fi
    done
  fi
  if [[ -z "$evidence" ]]; then
    local line_lc ips local_ips=() gateway_ips=() dns_ips=() in_dns=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_lc="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
      ips="$(printf '%s\n' "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
      if [[ "$line_lc" == *"ipv4 address"* || "$line_lc" == *"ip address"* ]]; then
        while IFS= read -r ip; do [[ -n "$ip" ]] && local_ips+=("$ip"); done <<< "$ips"
        in_dns=0
      elif [[ "$line_lc" == *"default gateway"* ]]; then
        while IFS= read -r ip; do [[ -n "$ip" ]] && gateway_ips+=("$ip"); done <<< "$ips"
        in_dns=0
      elif [[ "$line_lc" == *"dns servers"* ]]; then
        while IFS= read -r ip; do [[ -n "$ip" ]] && dns_ips+=("$ip"); done <<< "$ips"
        in_dns=1
      elif [[ "$in_dns" -eq 1 && "$line" =~ ^[[:space:]]+ ]]; then
        while IFS= read -r ip; do [[ -n "$ip" ]] && dns_ips+=("$ip"); done <<< "$ips"
      else
        in_dns=0
      fi
    done <<< "$text"
    for ip in "${local_ips[@]}"; do for cidr in "${ip_cidrs[@]}"; do if sas_network_guard_ip_in_cidr "$ip" "$cidr"; then evidence="local_ip_cidr=$cidr"; break 2; fi; done; done
    if [[ -z "$evidence" ]]; then
      for ip in "${gateway_ips[@]}"; do for cidr in "${gateway_cidrs[@]}"; do if sas_network_guard_ip_in_cidr "$ip" "$cidr"; then evidence="gateway_cidr=$cidr"; break 2; fi; done; done
    fi
    if [[ -z "$evidence" ]]; then
      for ip in "${dns_ips[@]}"; do for cidr in "${dns_cidrs[@]}"; do if sas_network_guard_ip_in_cidr "$ip" "$cidr"; then evidence="dns_server_cidr=$cidr"; break 2; fi; done; done
    fi
  fi
  if [[ -n "$evidence" ]]; then
    sas_network_guard_last_wired_evidence="$evidence"
    return 0
  fi
  sas_network_guard_last_wired_evidence="none"
  return 1
}

sas_network_guard_wired_allowed() {
  local text
  text="$(sas_network_guard_collect_local_network_text)"
  sas_network_guard_wired_evidence_allowed "$text"
}

sas_require_northwell_wifi() {
  local ssid
  ssid="$(sas_network_guard_current_ssid)"
  if sas_network_guard_ssid_allowed "$ssid"; then
    return 0
  fi
  if sas_network_guard_wired_allowed; then
    return 0
  fi
  printf 'Network check failed: this script must be run from an approved Northwell network. Connect to Wi-Fi SSID starting with %s or approved Northwell wired Ethernet and rerun. Current SSID: %s. Wired evidence: %s.\n' \
    "$sas_network_guard_required_prefix" "${ssid:-unknown}" "${sas_network_guard_last_wired_evidence:-none}" >&2
  return 1
}
