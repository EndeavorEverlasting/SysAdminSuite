#!/usr/bin/env bash
# Contract tests for survey lanes and device classification sprint.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f docs/SURVEY_LANES.md ]] || fail "docs/SURVEY_LANES.md missing"
[[ -f survey/sas-survey-device-classify.py ]] || fail "survey/sas-survey-device-classify.py missing"
[[ -f survey/sas-classify-dns-list-output.py ]] || fail "survey/sas-classify-dns-list-output.py missing"

grep -q 'SURVEY_LANES.md' START-HERE-CYBERNET-NEURON-SURVEY.md || fail "START-HERE missing SURVEY_LANES link"
grep -q 'SURVEY_LANES.md' survey/README.md || fail "survey/README missing SURVEY_LANES link"
grep -q 'SURVEY_LANES.md' docs/DASHBOARD_ENTRYPOINT.md || fail "DASHBOARD_ENTRYPOINT missing SURVEY_LANES link"

grep -q 'CLASSIFICATION_FIELDS' survey/sas-resolve-manifest-dns.py || fail "DNS resolver missing classification column wiring"
grep -q 'DeviceRole' survey/sas-merge-cybernet-evidence.py || fail "merge evidence missing DeviceRole"
grep -q 'REVIEW_INFRASTRUCTURE_NOT_TARGET' survey/sas-merge-cybernet-evidence.py || fail "merge missing infrastructure review status"

python tests/survey/test_survey_device_classify.py

pass "survey lanes contracts"
