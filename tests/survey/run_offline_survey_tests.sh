#!/usr/bin/env bash
set -euo pipefail

python3 tests/survey/test_serial_first_identity.py
python3 tests/survey/test_cybernet_cleanup_report.py
python3 Tests/survey/test_ad_probe_resilience_contracts.py
python3 Tests/survey/test_ad_existence_bulk_contracts.py
