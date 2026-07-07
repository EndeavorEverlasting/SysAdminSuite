#!/usr/bin/env bash
set -euo pipefail
source survey/lib/sas-network-guard.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export SAS_NETWORK_GUARD_CONFIG="$tmpdir/guard.json"

pass=0
check_allowed(){ local ssid="$1" expect="$2"; if sas_network_guard_ssid_allowed "$ssid"; then got=pass; else got=fail; fi; [[ "$got" == "$expect" ]] || { echo "case '$ssid' expected $expect got $got"; exit 1; }; pass=$((pass+1)); }

check_allowed 'NSLIJHS-WAB' pass
check_allowed 'NSLIJHS-WAB2' pass
check_allowed 'NSLIJHS-WAB-TEST' pass
check_allowed 'Guest-WiFi' fail
check_allowed '' fail
check_allowed 'unknown' fail

sample=$'Name : Wi-Fi\nState : connected\nBSSID : NSLIJHS-WAB-BSSID-SHOULD-NOT-MATCH\nSSID : Guest-WiFi\n'
parsed="$(printf '%s' "$sample" | sas_network_guard_parse_netsh_ssid)"
[[ "$parsed" == 'Guest-WiFi' ]] || { echo "BSSID parse failed: $parsed"; exit 1; }
check_allowed "$parsed" fail

missing=$'Name : Wi-Fi\nState : disconnected\nBSSID : NSLIJHS-WAB-BSSID-SHOULD-NOT-MATCH\n'
parsed="$(printf '%s' "$missing" | sas_network_guard_parse_netsh_ssid)"
[[ "$parsed" == 'unknown' ]] || { echo "missing parse failed: $parsed"; exit 1; }

ipconfig_fixture=$'Windows IP Configuration\n   Primary Dns Suffix  . . . . . . . : corp.example.invalid\nEthernet adapter Ethernet:\n   Connection-specific DNS Suffix  . : wired.example.invalid\n   IPv4 Address. . . . . . . . . . . : 192.0.2.25(Preferred)\n   Default Gateway . . . . . . . . . : 192.0.2.1\n   DNS Servers . . . . . . . . . . . : 198.51.100.10\n'
cat > "$SAS_NETWORK_GUARD_CONFIG" <<'JSON'
{
  "allowedDnsSuffixes": ["wired.example.invalid"],
  "allowedLocalIpCidrs": ["192.0.2.0/24"],
  "allowedGatewayCidrs": ["192.0.2.1/32"],
  "allowedDnsServerCidrs": ["198.51.100.0/24"]
}
JSON
sas_network_guard_wired_evidence_allowed "$ipconfig_fixture" || { echo 'approved wired evidence should pass'; exit 1; }
[[ "$sas_network_guard_last_wired_evidence" != 'none' ]] || { echo 'wired evidence summary missing'; exit 1; }
pass=$((pass+1))

sas_network_guard_ssid_allowed 'Guest-WiFi' && { echo 'guest wifi should not pass wifi check'; exit 1; }
sas_network_guard_wired_evidence_allowed "$ipconfig_fixture" || { echo 'approved wired evidence should pass with guest Wi-Fi'; exit 1; }
pass=$((pass+1))

printf '{}' > "$SAS_NETWORK_GUARD_CONFIG"
if sas_network_guard_wired_evidence_allowed "$ipconfig_fixture"; then echo 'missing wired allowlist should fail'; exit 1; fi
pass=$((pass+1))

printf '{ not json' > "$SAS_NETWORK_GUARD_CONFIG"
if sas_network_guard_wired_evidence_allowed "$ipconfig_fixture"; then echo 'malformed config should fail closed'; exit 1; fi
[[ "$sas_network_guard_last_wired_evidence" == config_error:* ]] || { echo "expected config_error evidence, got $sas_network_guard_last_wired_evidence"; exit 1; }
pass=$((pass+1))

echo "sas-network-guard tests passed: $pass cases"
