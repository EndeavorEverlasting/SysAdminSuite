#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${OUT_DIR:-$PWD/output/neuron-maintenance}"
SERVER_TARGET="${SERVER_TARGET:-}"
FOLLOWER_TARGET="${FOLLOWER_TARGET:-}"
VPN_TARGET="${VPN_TARGET:-10.8.0.1}"
INCLUDE_ARP="${INCLUDE_ARP:-1}"

STAMP="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname 2>/dev/null || echo unknown-host)"
BASE="$OUT_DIR/NeuronMaintenanceSnapshot_${HOST}_${STAMP}"
TEXT_PATH="${BASE}.txt"
JSON_PATH="${BASE}.json"
PING_CSV="${BASE}_ping.csv"

mkdir -p "$OUT_DIR"

section() {
  local title="$1"
  shift
  {
    echo
    printf '=%.0s' {1..78}
    echo
    echo "$title"
    printf '=%.0s' {1..78}
    echo
    "$@"
  } >> "$TEXT_PATH" 2>&1 || {
    echo "[section failed] $title" >> "$TEXT_PATH"
  }
}

ping_target() {
  local group="$1"
  local target="$2"

  if [[ -z "$target" ]]; then
    printf '%s,%s,%s,%s\n' "$group" "[not configured]" "UNKNOWN" "No target configured"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  if ping -c 4 "$target" > "$tmp" 2>&1; then
    local detail
    detail="$(tail -n 2 "$tmp" | tr '\n' ' ' | sed 's/"/""/g')"
    printf '%s,%s,%s,"%s"\n' "$group" "$target" "OK" "$detail"
  else
    local detail
    detail="$(tail -n 2 "$tmp" | tr '\n' ' ' | sed 's/"/""/g')"
    printf '%s,%s,%s,"%s"\n' "$group" "$target" "FAIL" "$detail"
  fi
  rm -f "$tmp"
}

cat > "$TEXT_PATH" <<EOF
SysAdminSuite Neuron Maintenance Snapshot
Timestamp: $(date -Is)
Host: $HOST
ReadOnlyDefault: true
EOF

section "Host Identity" sh -c 'hostname; whoami 2>/dev/null || true; uname -a 2>/dev/null || true'
section "IP Configuration" sh -c 'ip addr 2>/dev/null || ifconfig 2>/dev/null || true; echo; ip route 2>/dev/null || route -n 2>/dev/null || true'
section "DNS" sh -c 'cat /etc/resolv.conf 2>/dev/null || true'
section "Listening Ports" sh -c 'ss -tulpn 2>/dev/null || netstat -ano 2>/dev/null || true'
section "Processes" sh -c 'ps aux 2>/dev/null || tasklist 2>/dev/null || true'

if [[ "$INCLUDE_ARP" == "1" ]]; then
  section "ARP / Neighbor Table" sh -c 'ip neigh 2>/dev/null || arp -a 2>/dev/null || true'
fi

{
  echo 'Group,Target,Status,Detail'
  ping_target 'Server' "$SERVER_TARGET"
  ping_target 'Follower' "$FOLLOWER_TARGET"
  ping_target 'VPN' "$VPN_TARGET"
} > "$PING_CSV"

section "Ping Checks" cat "$PING_CSV"

cat > "$JSON_PATH" <<EOF
{
  "timestamp": "$(date -Is)",
  "host": "$HOST",
  "readOnlyDefault": true,
  "textReport": "$TEXT_PATH",
  "pingCsv": "$PING_CSV"
}
EOF

echo "Neuron maintenance snapshot complete"
echo "Text: $TEXT_PATH"
echo "JSON: $JSON_PATH"
echo "Ping CSV: $PING_CSV"
