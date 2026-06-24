#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/ipconfig_sample.txt" <<'TXT'
Windows IP Configuration

Ethernet adapter Ethernet:

   Connection-specific DNS Suffix  . : example.local
   IPv4 Address. . . . . . . . . . . : 10.42.13.77(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.254.0
   Default Gateway . . . . . . . . . : 10.42.12.1

Wireless LAN adapter Wi-Fi:

   IPv4 Address. . . . . . . . . . . : 169.254.1.55(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.0.0
TXT

python3 survey/sas-local-subnet-candidates.py \
  --ipconfig "$TMP_DIR/ipconfig_sample.txt" \
  --output "$TMP_DIR/subnet_candidates.csv" \
  --list-output "$TMP_DIR/subnet_candidates.txt"

grep -q '^10[.]42[.]12[.]0/24$' "$TMP_DIR/subnet_candidates.txt"
grep -q '^10[.]42[.]13[.]0/24$' "$TMP_DIR/subnet_candidates.txt"

grep -q -- '--cidr CIDR' <(bash survey/sas-find-local-subnets.sh --help)
grep -q -- 'subnet_candidates.txt' <(bash survey/sas-find-local-subnets.sh --help)

bash -n survey/sas-find-local-subnets.sh
python3 -m py_compile survey/sas-local-subnet-candidates.py

printf 'Local subnet finder contracts passed.\n'
