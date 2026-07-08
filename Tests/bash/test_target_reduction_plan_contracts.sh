#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
planner="$repo_root/survey/sas-target-reduction-plan.sh"
fixture_csv="survey/fixtures/target_reduction/local_evidence.csv"
fixture_map="survey/fixtures/target_reduction/location_subnet_map.csv"
run_id="contract-test-$$"
out_dir="$repo_root/survey/output/target_reduction/$run_id"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

grep_required() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "missing pattern '$pattern' in $file"
}

grep_forbidden() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "$pattern" "$file"; then
    fail "forbidden pattern '$pattern' in $file"
  fi
}

[[ -f "$planner" ]] || fail "missing Bash target reduction entrypoint: $planner"

rm -rf "$out_dir"
trap 'rm -rf "$out_dir"' EXIT

grep_required '^#!/usr/bin/env bash' "$planner"
grep_required 'set -euo pipefail' "$planner"
grep_required 'python3 -' "$planner"
grep_required 'operation_id.*target_reduction\.plan' "$planner"
grep_required 'out_of_scope\.csv' "$planner"
grep_required 'network_activity_performed.*False' "$planner"
grep_required 'target_mutation_performed.*False' "$planner"
grep_required 'No network activity was attempted' "$planner"
grep_required 'outside approved local output roots' "$planner"
grep_required 'allow_nonstandard_input' "$planner"
grep_forbidden 'exec pwsh|exec powershell\.exe' "$planner"

bash "$planner" \
  --prior-probe-results "$fixture_csv" \
  --location-subnet-map "$fixture_map" \
  --run-id "$run_id" \
  --allow-fixtures \
  >/dev/null

[[ -f "$out_dir/reduced_targets.csv" ]] || fail "missing reduced_targets.csv"
[[ -f "$out_dir/retry_candidates.csv" ]] || fail "missing retry_candidates.csv"
[[ -f "$out_dir/review_required.csv" ]] || fail "missing review_required.csv"
[[ -f "$out_dir/out_of_scope.csv" ]] || fail "missing out_of_scope.csv"
[[ -f "$out_dir/location_subnet_candidates.csv" ]] || fail "missing location_subnet_candidates.csv"
[[ -f "$out_dir/target_reduction_summary.json" ]] || fail "missing target_reduction_summary.json"

grep_required '^alpha,' "$out_dir/reduced_targets.csv"
grep_required '^bravo,' "$out_dir/retry_candidates.csv"
grep_required '^charlie,' "$out_dir/review_required.csv"
grep_required '^delta,' "$out_dir/location_subnet_candidates.csv"
grep_required '^echo,' "$out_dir/out_of_scope.csv"
grep_required '^foxtrot,' "$out_dir/review_required.csv"
grep_forbidden '^foxtrot,' "$out_dir/reduced_targets.csv"
grep_required '"network_activity_performed": false' "$out_dir/target_reduction_summary.json"
grep_required '"target_mutation_performed": false' "$out_dir/target_reduction_summary.json"
grep_required '"out_of_scope_count": 1' "$out_dir/target_reduction_summary.json"

bad_out_dir="$repo_root/not-approved-target-reduction-output"
if bash "$planner" \
  --prior-probe-results "$fixture_csv" \
  --output-directory "$bad_out_dir" \
  --allow-fixtures \
  --allow-nonstandard-input \
  >/tmp/sas-target-reduction-bad-output.log 2>&1; then
  fail "nonstandard input switch bypassed output guardrails"
fi
grep_required 'outside approved local output roots' /tmp/sas-target-reduction-bad-output.log
rm -f /tmp/sas-target-reduction-bad-output.log

echo "PASS: Bash target reduction planner contracts"
