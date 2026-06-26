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
grep -q 'targets/local/' README.md || fail "README missing targets/local local intake guidance"
grep -q 'logs/targets/' README.md || fail "README missing logs/targets local store guidance"
grep -q 'TARGETS_FOLDER_POLICY.md' README.md || fail "README missing targets folder policy link"
[[ -f logs/targets/.gitkeep ]] || fail "logs/targets/.gitkeep missing"

grep -q 'CLASSIFICATION_FIELDS' survey/sas-resolve-manifest-dns.py || fail "DNS resolver missing classification column wiring"
grep -q 'DeviceRole' survey/sas-merge-cybernet-evidence.py || fail "merge evidence missing DeviceRole"
grep -q 'REVIEW_INFRASTRUCTURE_NOT_TARGET' survey/sas-merge-cybernet-evidence.py || fail "merge missing infrastructure review status"
grep -q 'bucketClassificationRows' dashboard/js/app.js || fail "dashboard missing classification bucket helper"
grep -q 'humanizeClassificationWhy' dashboard/js/app.js || fail "dashboard missing classification why helper"
grep -q 'cybernet-classification-drilldown' dashboard/js/app.js || fail "dashboard missing classification drilldown rendering"
grep -q 'roleConfidence' dashboard/js/parsers.js || fail "parser missing roleConfidence field"

python tests/survey/test_survey_device_classify.py

pass "survey lanes contracts"
