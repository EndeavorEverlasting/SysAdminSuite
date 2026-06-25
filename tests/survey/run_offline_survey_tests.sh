#!/usr/bin/env bash
set -euo pipefail

python tests/survey/test_serial_first_identity.py
python tests/survey/test_cybernet_cleanup_report.py
