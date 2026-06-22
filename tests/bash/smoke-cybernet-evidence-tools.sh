#!/usr/bin/env bash
set -euo pipefail

# Smoke test for Cybernet evidence correlation Python helpers.
# This test only checks CLI help output. It does not perform DNS lookup,
# query AD/DHCP, scan networks, or require field data.

PYTHON_BIN=""

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v py >/dev/null 2>&1; then
  PYTHON_BIN="py -3"
else
  echo "FAIL: python3, python, or py not found"
  exit 1
fi

echo "Using Python: $PYTHON_BIN"

$PYTHON_BIN survey/sas-resolve-manifest-dns.py --help >/dev/null
echo "PASS: sas-resolve-manifest-dns.py --help"

$PYTHON_BIN survey/sas-import-ad-computers.py --help >/dev/null
echo "PASS: sas-import-ad-computers.py --help"

$PYTHON_BIN survey/sas-import-dhcp-leases.py --help >/dev/null
echo "PASS: sas-import-dhcp-leases.py --help"

$PYTHON_BIN survey/sas-merge-cybernet-evidence.py --help >/dev/null
echo "PASS: sas-merge-cybernet-evidence.py --help"

echo "Cybernet evidence tool smoke test passed."
