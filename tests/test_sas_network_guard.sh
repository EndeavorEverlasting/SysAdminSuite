#!/usr/bin/env bash
set -euo pipefail
source survey/lib/sas-network-guard.sh

pass=0
fail=0
check_allowed(){ local ssid="$1" expect="$2"; if sas_network_guard_ssid_allowed "$ssid"; then got=pass; else got=fail; fi; [[ "$got" == "$expect" ]] || { echo "case '$ssid' expected $expect got $got"; fail=$((fail+1)); return; }; pass=$((pass+1)); }
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
check_allowed "$parsed" fail
echo "sas-network-guard tests passed: $pass cases"
