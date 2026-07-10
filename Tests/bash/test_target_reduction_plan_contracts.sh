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
[[ -f "$out_dir/operator_handoff.txt" ]] || fail "missing operator_handoff.txt"

grep_required '^alpha,' "$out_dir/reduced_targets.csv"
grep_required '^bravo,' "$out_dir/retry_candidates.csv"
grep_required '^charlie,' "$out_dir/review_required.csv"
grep_required '^,asset-delta,' "$out_dir/review_required.csv"
grep_required '^FixtureSite,RoomD,.*,,DeferredSubnetCandidate,' "$out_dir/location_subnet_candidates.csv"
grep_required '^echo,' "$out_dir/out_of_scope.csv"
grep_required '^foxtrot,' "$out_dir/review_required.csv"
grep_forbidden '^foxtrot,' "$out_dir/reduced_targets.csv"
grep_required '^Golf,' "$out_dir/review_required.csv"
grep_required '^golf,' "$out_dir/review_required.csv"
grep_forbidden '^[Gg]olf,' "$out_dir/reduced_targets.csv"
grep_forbidden '^[Gg]olf,' "$out_dir/retry_candidates.csv"
grep_required '"network_activity_performed": false' "$out_dir/target_reduction_summary.json"
grep_required '"target_mutation_performed": false' "$out_dir/target_reduction_summary.json"
grep_required '"out_of_scope_count": 1' "$out_dir/target_reduction_summary.json"
grep_required '"classification_reconciled": true' "$out_dir/target_reduction_summary.json"

python3 - "$out_dir" "$repo_root/harness/api/sas-harness-api.json" <<'PY'
import csv
import json
import sys
from pathlib import Path

output_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
summary = json.loads((output_dir / "target_reduction_summary.json").read_text(encoding="utf-8"))
primary_count = sum(summary[name] for name in (
    "confirmed_reached_count",
    "retry_candidate_count",
    "review_required_count",
    "out_of_scope_count",
))
assert primary_count == summary["input_row_count"] == summary["classified_row_count"]
assert summary["classification_reconciled"] is True

with (output_dir / "review_required.csv").open(newline="", encoding="utf-8") as fh:
    review_targets = [row["Target"] for row in csv.DictReader(fh)]
assert review_targets == ["charlie", "", "foxtrot", "Golf", "golf"], review_targets

with (output_dir / "location_subnet_candidates.csv").open(newline="", encoding="utf-8") as fh:
    location_rows = list(csv.DictReader(fh))
assert len(location_rows) == 1
assert location_rows[0]["Target"] == ""
assert location_rows[0]["SubnetCIDR"] == "192.0.2.0/28"
assert location_rows[0]["Notes"] == "synthetic candidate, quoted safely"

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
operation = next(item for item in manifest["operations"] if item["id"] == "target_reduction.plan")
expected_outputs = {
    "reduced_targets.csv",
    "retry_candidates.csv",
    "review_required.csv",
    "out_of_scope.csv",
    "location_subnet_candidates.csv",
    "target_reduction_summary.json",
    "operator_handoff.txt",
}
assert set(operation["outputs"]) == expected_outputs
assert {path.name for path in output_dir.iterdir() if path.is_file()} == expected_outputs
PY

malformed_csv="$out_dir/malformed.csv"
malformed_output="$out_dir/malformed-output"
printf 'Unexpected,PortStatus\nexample,Open\n' >"$malformed_csv"
if bash "$planner" \
  --prior-probe-results "$malformed_csv" \
  --output-directory "$malformed_output" \
  >"$out_dir/malformed.log" 2>&1; then
  fail "malformed prior evidence unexpectedly succeeded"
fi
grep_required 'missing a required CSV column' "$out_dir/malformed.log"
[[ ! -e "$malformed_output" ]] || fail "malformed input left a partial output directory"
rm -f "$malformed_csv" "$out_dir/malformed.log"

bad_out_dir="$repo_root/not-approved-target-reduction-output"
if bash "$planner" \
  --prior-probe-results "$fixture_csv" \
  --output-directory "$bad_out_dir" \
  --allow-fixtures \
  --allow-nonstandard-input \
  >"$out_dir/bad-output.log" 2>&1; then
  fail "nonstandard input switch bypassed output guardrails"
fi
grep_required 'outside approved local output roots' "$out_dir/bad-output.log"

echo "PASS: Bash target reduction planner contracts"
