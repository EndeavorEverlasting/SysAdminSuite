#!/usr/bin/env bash
# SysAdminSuite deployment evidence reconciler
# Joins duplicate conflicts, survey requests, and collected Cybernet identity evidence into final revisit verdicts.

set -euo pipefail

DUPLICATES=""
REQUESTS=""
EVIDENCE=""
OUTPUT="deployment-audit/output/reconciliation_verdicts.csv"
SUMMARY=""
PASS_THRU=0

usage(){ cat <<'USAGE'
Deployment Evidence Reconciler

Usage:
  ./deployment-audit/sas-reconcile-evidence.sh --duplicates real_duplicate_values_deployed_yes.csv --requests survey_requests_duplicate_resolution.csv --evidence cybernet_evidence.csv [options]

Options:
  --duplicates PATH    CSV from sas-audit-deployments.sh: real_duplicate_values_deployed_yes.csv
  --requests PATH      CSV from sas-audit-deployments.sh: survey_requests_duplicate_resolution.csv
  --evidence PATH      CSV from sas-collect-cybernet-evidence.sh: cybernet_evidence.csv
  --output PATH        Output verdict CSV. Default: deployment-audit/output/reconciliation_verdicts.csv
  --summary PATH       Optional text summary path. Default: same base as output + .txt
  --pass-thru          Print verdict CSV after writing
  -h, --help           Show help

Final verdicts:
  NoRevisit              Evidence confirms the tracker can be reconciled remotely.
  NeedsPrivilegedSurvey  Target is reachable or partially known, but current evidence is insufficient.
  RevisitJustified       Conflict, unreachable after available checks, or no usable evidence.
  ReviewRequired         Data shape is incomplete or ambiguous and needs human review.

Safety:
  - Read-only.
  - Does not modify the workbook.
  - Produces management-facing verdicts from audit/evidence outputs.
USAGE
}

fail(){ printf '[evidence-reconcile] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[evidence-reconcile] %s\n' "$*" >&2; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duplicates) DUPLICATES="${2:?missing value for --duplicates}"; shift 2 ;;
    --requests) REQUESTS="${2:?missing value for --requests}"; shift 2 ;;
    --evidence) EVIDENCE="${2:?missing value for --evidence}"; shift 2 ;;
    --output) OUTPUT="${2:?missing value for --output}"; shift 2 ;;
    --summary) SUMMARY="${2:?missing value for --summary}"; shift 2 ;;
    --pass-thru) PASS_THRU=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "$DUPLICATES" ]] || fail "--duplicates is required"
[[ -n "$REQUESTS" ]] || fail "--requests is required"
[[ -n "$EVIDENCE" ]] || fail "--evidence is required"
[[ -f "$DUPLICATES" ]] || fail "duplicates CSV not found: $DUPLICATES"
[[ -f "$REQUESTS" ]] || fail "requests CSV not found: $REQUESTS"
[[ -f "$EVIDENCE" ]] || fail "evidence CSV not found: $EVIDENCE"
has_cmd python3 || fail "python3 is required"
mkdir -p "$(dirname "$OUTPUT")"
if [[ -z "$SUMMARY" ]]; then SUMMARY="${OUTPUT%.*}.txt"; fi

python3 - "$DUPLICATES" "$REQUESTS" "$EVIDENCE" "$OUTPUT" "$SUMMARY" <<'PY'
import csv
import sys
from collections import Counter, defaultdict

duplicates_path, requests_path, evidence_path, output_path, summary_path = sys.argv[1:6]

def rows(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))

def first(row, names):
    lower = {k.lower(): v for k, v in row.items()}
    for name in names:
        v = lower.get(name.lower())
        if v is not None and str(v).strip():
            return str(v).strip()
    return ''

def key_for(row):
    return (first(row, ['ConflictField']), first(row, ['ConflictValue']), first(row, ['ExcelRow']))

def conflict_key(row):
    return (first(row, ['ConflictField']), first(row, ['ConflictValue']))

def verdict_for(evidence_status, ping_status, missing_resolution, observed_serial, observed_macs, expected_serial, expected_mac):
    evidence_status = (evidence_status or '').strip()
    ping_status = (ping_status or '').strip()
    missing_resolution = (missing_resolution or '').strip()
    has_observed_identity = bool((observed_serial or '').strip() or (observed_macs or '').strip())
    has_expected_identity = bool((expected_serial or '').strip() or (expected_mac or '').strip())

    if evidence_status == 'Confirmed':
        return 'NoRevisit', 'Cybernet evidence matches tracker expectation.'
    if evidence_status == 'Conflict':
        return 'RevisitJustified', 'Collected Cybernet evidence conflicts with tracker expectation.'
    if evidence_status == 'IdentityCollectedNeedsComparisonData':
        if missing_resolution:
            return 'NeedsPrivilegedSurvey', 'Identity was collected, but tracker lacks enough expected Cybernet identifiers for a hard comparison.'
        return 'ReviewRequired', 'Identity was collected but comparison data is ambiguous.'
    if evidence_status == 'ReachableNeedsPrivilegedSurvey':
        return 'NeedsPrivilegedSurvey', 'Target is reachable but current transport did not collect serial/MAC identity.'
    if evidence_status == 'Unreachable':
        return 'RevisitJustified', 'Target could not be reached by available remote checks.'
    if has_observed_identity and not has_expected_identity:
        return 'NeedsPrivilegedSurvey', 'Observed identity exists but tracker lacks expected Cybernet fields.'
    if ping_status == 'Reachable':
        return 'NeedsPrivilegedSurvey', 'Reachable target requires approved identity transport before onsite revisit.'
    return 'ReviewRequired', 'Insufficient evidence to decide automatically.'

duplicates = rows(duplicates_path)
requests = rows(requests_path)
evidence = rows(evidence_path)
request_by_key = {key_for(r): r for r in requests}
evidence_by_key = {key_for(r): r for r in evidence}
requests_by_conflict = defaultdict(list)
evidence_by_conflict = defaultdict(list)
for r in requests:
    requests_by_conflict[conflict_key(r)].append(r)
for r in evidence:
    evidence_by_conflict[conflict_key(r)].append(r)

out_fields = [
    'ConflictField','ConflictValue','ConflictRows','DuplicateSeverity','DuplicateLocations',
    'ExcelRow','LocationKey','Target','ExpectedSerial','ExpectedMAC','ObservedSerial','ObservedMACs','PingStatus','EvidenceStatus','FinalVerdict','Reason','RecommendedNextAction','Notes'
]
out = []

for dup in duplicates:
    ckey = conflict_key(dup)
    reqs = requests_by_conflict.get(ckey, [])
    evs = evidence_by_conflict.get(ckey, [])
    if not reqs and not evs:
        out.append({
            'ConflictField': ckey[0], 'ConflictValue': ckey[1], 'ConflictRows': first(dup, ['Rows']),
            'DuplicateSeverity': first(dup, ['Severity']), 'DuplicateLocations': first(dup, ['Locations']),
            'ExcelRow': '', 'LocationKey': '', 'Target': '', 'ExpectedSerial': '', 'ExpectedMAC': '',
            'ObservedSerial': '', 'ObservedMACs': '', 'PingStatus': '', 'EvidenceStatus': '',
            'FinalVerdict': 'ReviewRequired', 'Reason': 'No survey request/evidence rows found for duplicate conflict.',
            'RecommendedNextAction': 'Regenerate survey requests and collect remote evidence.', 'Notes': ''
        })
        continue
    row_keys = sorted(set([key_for(r) for r in reqs] + [key_for(r) for r in evs]), key=lambda x: x[2])
    for rk in row_keys:
        req = request_by_key.get(rk, {})
        ev = evidence_by_key.get(rk, {})
        expected_serial = first(ev, ['ExpectedSerial']) or ''
        expected_mac = first(ev, ['ExpectedMAC']) or ''
        observed_serial = first(ev, ['ObservedSerial'])
        observed_macs = first(ev, ['ObservedMACs'])
        evidence_status = first(ev, ['EvidenceStatus'])
        ping_status = first(ev, ['PingStatus'])
        missing = first(req, ['MissingResolutionIdentifiers'])
        verdict, reason = verdict_for(evidence_status, ping_status, missing, observed_serial, observed_macs, expected_serial, expected_mac)
        if verdict == 'NoRevisit':
            action = 'Update/reconcile tracker remotely; no physical revisit indicated.'
        elif verdict == 'NeedsPrivilegedSurvey':
            action = 'Use approved privileged identity transport before requesting onsite revisit.'
        elif verdict == 'RevisitJustified':
            action = 'Prepare onsite revisit justification with conflict/evidence rows attached.'
        else:
            action = 'Human review required; data/evidence shape is incomplete.'
        out.append({
            'ConflictField': ckey[0],
            'ConflictValue': ckey[1],
            'ConflictRows': first(dup, ['Rows']),
            'DuplicateSeverity': first(dup, ['Severity']),
            'DuplicateLocations': first(dup, ['Locations']),
            'ExcelRow': rk[2],
            'LocationKey': first(req, ['LocationKey']) or first(ev, ['LocationKey']),
            'Target': first(ev, ['Target']) or first(req, ['SurveyTargetHint']),
            'ExpectedSerial': expected_serial,
            'ExpectedMAC': expected_mac,
            'ObservedSerial': observed_serial,
            'ObservedMACs': observed_macs,
            'PingStatus': ping_status,
            'EvidenceStatus': evidence_status,
            'FinalVerdict': verdict,
            'Reason': reason,
            'RecommendedNextAction': action,
            'Notes': first(ev, ['Notes']),
        })

with open(output_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=out_fields, quoting=csv.QUOTE_ALL, lineterminator='\n')
    writer.writeheader()
    writer.writerows(out)

counts = Counter(r['FinalVerdict'] for r in out)
with open(summary_path, 'w', encoding='utf-8') as f:
    f.write('SysAdminSuite Deployment Evidence Reconciliation\n')
    f.write('===============================================\n\n')
    f.write(f'Duplicate conflicts: {len(duplicates)}\n')
    f.write(f'Survey request rows: {len(requests)}\n')
    f.write(f'Evidence rows: {len(evidence)}\n')
    f.write(f'Verdict rows: {len(out)}\n\n')
    f.write('Final verdict counts:\n')
    for verdict, count in counts.most_common():
        f.write(f'  {verdict}: {count}\n')
    f.write('\nVerdict meanings:\n')
    f.write('  NoRevisit: reconcile remotely; evidence supports avoiding physical revisit.\n')
    f.write('  NeedsPrivilegedSurvey: use approved stronger remote transport first.\n')
    f.write('  RevisitJustified: conflict/unreachable condition supports onsite justification.\n')
    f.write('  ReviewRequired: insufficient or ambiguous evidence.\n')

print(f'Wrote {len(out)} verdict row(s) to {output_path}')
print(f'Wrote summary to {summary_path}')
PY

log "Reconciliation complete: $OUTPUT"
log "Summary: $SUMMARY"
[[ "$PASS_THRU" -eq 1 ]] && cat "$OUTPUT"
