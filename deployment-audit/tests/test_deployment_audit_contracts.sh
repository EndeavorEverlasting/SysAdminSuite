#!/usr/bin/env bash
# Lightweight contract tests for deployment-audit Bash tooling.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT="$ROOT_DIR/deployment-audit/sas-audit-deployments.sh"
MANIFEST="$ROOT_DIR/deployment-audit/sas-build-survey-manifest.sh"
COLLECTOR="$ROOT_DIR/survey/sas-collect-cybernet-evidence.sh"
RECONCILER="$ROOT_DIR/deployment-audit/sas-reconcile-evidence.sh"

fail(){ printf '[deployment-audit-tests] FAIL: %s\n' "$*" >&2; exit 1; }
pass(){ printf '[deployment-audit-tests] PASS: %s\n' "$*"; }

[[ -f "$AUDIT" ]] || fail "Missing audit script"
[[ -f "$MANIFEST" ]] || fail "Missing survey manifest builder"
[[ -f "$COLLECTOR" ]] || fail "Missing Cybernet evidence collector"
[[ -f "$RECONCILER" ]] || fail "Missing evidence reconciler"

bash -n "$AUDIT" || fail "Audit script has Bash syntax errors"
bash -n "$MANIFEST" || fail "Manifest builder has Bash syntax errors"
bash -n "$COLLECTOR" || fail "Collector script has Bash syntax errors"
bash -n "$RECONCILER" || fail "Reconciler script has Bash syntax errors"

HELP="$($AUDIT --help)"
[[ "$HELP" == *"Deployed = Yes"* ]] || fail "Audit help must document deployed-only duplicate rule"
[[ "$HELP" == *"survey_requests_duplicate_resolution.csv"* ]] || fail "Audit help must document survey request output"
[[ "$HELP" == *"--resolution-keys"* ]] || fail "Audit help must document resolution keys"

MANIFEST_HELP="$($MANIFEST --help)"
[[ "$MANIFEST_HELP" == *"survey_requests_duplicate_resolution.csv"* ]] || fail "Manifest help must name expected input"
[[ "$MANIFEST_HELP" == *"sas-survey-targets.sh"* ]] || fail "Manifest help must point to survey target resolver"

COLLECTOR_HELP="$($COLLECTOR --help)"
[[ "$COLLECTOR_HELP" == *"read-only"* || "$COLLECTOR_HELP" == *"Read-only"* ]] || fail "Collector help must document read-only posture"
[[ "$COLLECTOR_HELP" == *"RevisitRecommendation"* ]] || fail "Collector help must document revisit verdict output"
[[ "$COLLECTOR_HELP" == *"--allow-ssh"* ]] || fail "Collector help must require explicit SSH enablement"

RECONCILER_HELP="$($RECONCILER --help)"
[[ "$RECONCILER_HELP" == *"NoRevisit"* ]] || fail "Reconciler help must document NoRevisit"
[[ "$RECONCILER_HELP" == *"NeedsPrivilegedSurvey"* ]] || fail "Reconciler help must document NeedsPrivilegedSurvey"
[[ "$RECONCILER_HELP" == *"RevisitJustified"* ]] || fail "Reconciler help must document RevisitJustified"
[[ "$RECONCILER_HELP" == *"Read-only"* || "$RECONCILER_HELP" == *"read-only"* ]] || fail "Reconciler help must document read-only posture"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
REQ="$TMP_DIR/survey_requests_duplicate_resolution.csv"
OUT="$TMP_DIR/remote_survey_manifest.csv"
EVIDENCE="$TMP_DIR/cybernet_evidence.csv"
DUPS="$TMP_DIR/real_duplicate_values_deployed_yes.csv"
VERDICTS="$TMP_DIR/reconciliation_verdicts.csv"
SUMMARY="$TMP_DIR/reconciliation_summary.txt"
cat > "$REQ" <<'CSV'
ConflictField,ConflictValue,ExcelRow,DeviceType,CurrentBuilding,InstallBuilding,AreaUnitDept,Room,Bay,LocationKey,KnownResolutionIdentifiers,MissingResolutionIdentifiers,RecommendedAction,SurveyTargetHint
Neuron MAC,00:18:7D:E0:AD:F1,134,Neuron,LIJ,LIJ,OR,OR21,,LIJ | LIJ | OR | OR21,Cybernet Hostname=WMH300OPR134,Cybernet Serial=ABC134,Cybernet MAC=00:AA:BB:CC:DD:01,,Remote survey Cybernet identifiers before physical revisit,WMH300OPR134
Neuron MAC,00:18:7D:E0:AD:F1,168,Neuron,LIJ,LIJ,Proc,OR21,,LIJ | LIJ | Proc | OR21,,Cybernet Hostname; Cybernet Serial; Cybernet MAC,Remote survey Cybernet identifiers before physical revisit,00:18:7D:E0:AD:F1
CSV
cat > "$DUPS" <<'CSV'
Field,Value,Rows,Count,DistinctLocations,Severity,Locations
Neuron MAC,00:18:7D:E0:AD:F1,134;168,2,2,RealDuplicate,LIJ | LIJ | OR | OR21 || LIJ | LIJ | Proc | OR21
CSV

bash "$MANIFEST" --requests "$REQ" --output "$OUT" >/dev/null
[[ -f "$OUT" ]] || fail "Manifest builder did not create output CSV"
LINE_COUNT="$(wc -l < "$OUT" | tr -d ' ')"
[[ "$LINE_COUNT" -eq 2 ]] || fail "Manifest builder should skip complete rows by default and emit one pending survey row plus header"
grep -q 'Resolve deployed duplicate before physical revisit' "$OUT" || fail "Manifest output missing revisit-avoidance reason"
grep -q '00:18:7D:E0:AD:F1' "$OUT" || fail "Manifest output missing fallback survey target hint"

bash "$COLLECTOR" --manifest "$OUT" --output "$EVIDENCE" --timeout 1 >/dev/null
[[ -f "$EVIDENCE" ]] || fail "Collector did not create evidence CSV"
grep -q 'RevisitRecommendation' "$EVIDENCE" || fail "Evidence CSV missing RevisitRecommendation column"
grep -Eq 'Unreachable|ReachableNeedsPrivilegedSurvey|Confirmed|Conflict|ReachableNeedsApprovedIdentityTransport|IdentityCollectedNeedsComparisonData' "$EVIDENCE" || fail "Evidence CSV missing evidence status verdict"
grep -q '00:18:7D:E0:AD:F1' "$EVIDENCE" || fail "Evidence CSV missing conflict value trace"

bash "$RECONCILER" --duplicates "$DUPS" --requests "$REQ" --evidence "$EVIDENCE" --output "$VERDICTS" --summary "$SUMMARY" >/dev/null
[[ -f "$VERDICTS" ]] || fail "Reconciler did not create verdict CSV"
[[ -f "$SUMMARY" ]] || fail "Reconciler did not create summary"
grep -q 'FinalVerdict' "$VERDICTS" || fail "Verdict CSV missing FinalVerdict column"
grep -Eq 'NoRevisit|NeedsPrivilegedSurvey|RevisitJustified|ReviewRequired' "$VERDICTS" || fail "Verdict CSV missing known final verdict"
grep -q 'Verdict meanings' "$SUMMARY" || fail "Summary missing verdict meanings"

pass "Bash syntax checks passed"
pass "Help contracts passed"
pass "Survey manifest builder fixture passed"
pass "Cybernet evidence collector fixture passed"
pass "Evidence reconciler fixture passed"
