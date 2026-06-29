# Iterative Command Delta Runs

## Purpose

This document codifies the workflow gap where technicians run the same approved command profile repeatedly and then have to manually interpret large output files.

SysAdminSuite should make repeated runs useful by comparing the current structured artifact against the last comparable artifact and producing a clear delta:

```text
what changed
what stayed the same
what should be skipped
what still needs action
```

The goal is to reduce rework, repeated interpretation, and unnecessary follow-up packets.

## Core principle

Do not treat every run as a blank slate.

```text
same approved source
  -> same normalized input
  -> same command profile
  -> new local artifact
  -> compare to previous comparable artifact
  -> delta report
  -> next action handoff
```

The output should tell the operator what is different, not force them to rediscover the whole result set.

## Relationship to other survey docs

This doctrine supports:

- `CYBERNET_XLSX_TARGET_INGESTION.md`
- `FIELD_NETWORK_PREFLIGHT.md`
- `DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md`
- `SERIAL_EVIDENCE_STRENGTH_RANKING.md`
- `go_naabu_packet_pipeline.plan.md`

The spreadsheet/workbook remains the source artifact when it defines the field population. Iterative command outputs are local artifacts and handoffs, not replacements for the spreadsheet.

## Non-goals

This document does not define a new scanner.

It must not introduce:

- unbounded retry loops
- automatic repeated live probing
- live network commands inside comparison logic
- target mutation
- credential collection
- telemetry suppression
- committed live outputs
- generic text diff as the authority

The delta runner compares structured local artifacts. Command execution remains in the existing approved lane for that profile.

## Command profile identity

Each repeatable command profile needs a stable identity so SysAdminSuite can decide whether two runs are comparable.

Required identity fields:

```text
CommandProfileName
CommandProfileVersion
InputSourceFingerprint
InputManifestFingerprint
EffectiveParametersFingerprint
ToolVersion
RunId
PreviousComparableRunId
ScopeSource
GeneratedAt
```

Comparability rule:

```text
Runs are comparable only when the command profile, normalized input fingerprint, and effective parameters match, or when the profile explicitly declares a compatible comparison rule.
```

A different spreadsheet, different normalized manifest, different port profile, different evidence root, or different TTL setting may require a separate baseline.

## Output roots

Run comparison reports are generated local artifacts.

```text
survey/output/command_delta/<profile>/<run_id>/
```

Required files:

```text
current_normalized.csv
previous_normalized.csv
delta_added.csv
delta_removed.csv
delta_changed.csv
delta_unchanged.csv
delta_summary.json
next_actions.csv
operator_handoff.txt
README.txt
```

Generated next-action handoff inputs go under `survey/input/` when another tool needs to consume them:

```text
survey/input/command_delta/<profile>/<run_id>/<next_handoff>.txt
```

No generated comparison output or live operational evidence should be committed.

## Structured comparison, not raw diff

The comparison engine must normalize artifacts before comparing them.

Compare by structured keys such as:

```text
NormalizedSerial
NormalizedHostname
NormalizedIP
NormalizedMAC
EvidenceClass
EvidenceStatus
EvidenceTimestamp
EvidenceSourceFile
Decision
```

Raw text line differences are not authoritative because CSV column order, timestamps, banner text, and formatting noise can change without changing operational meaning.

## Delta statuses

Recommended status values:

```text
NO_CHANGE
NEW_EVIDENCE
LOST_EVIDENCE
CHANGED_STATUS
NEW_REACHABLE
LOST_REACHABILITY
NEW_IDENTITY_CONFIRMED
IDENTITY_CONFLICT
STALE_REQUIRES_RECHECK
SKIP_REWORK
RETRY_REQUIRED
REVIEW_REQUIRED
```

Each changed row must include a plain-language reason.

## Summary contract

`delta_summary.json` should include:

```text
run_id
previous_comparable_run_id
command_profile_name
command_profile_version
input_source_fingerprint
input_manifest_fingerprint
effective_parameters_fingerprint
tool_version
current_artifact_path
previous_artifact_path
added_count
removed_count
changed_count
unchanged_count
review_required_count
retry_required_count
skip_rework_count
next_actions_path
operator_handoff_path
network_activity_performed_by_comparison
```

`network_activity_performed_by_comparison` must be `false`. The comparison phase reads artifacts only.

## Next-action contract

`next_actions.csv` should explain what to do next, not just what changed.

Recommended columns:

```text
ActionId
ActionType
Serial
Hostname
IP
EvidenceClass
PreviousStatus
CurrentStatus
DeltaStatus
Reason
RecommendedHandoff
Priority
```

Recommended `ActionType` values:

```text
SKIP_NO_CHANGE
SKIP_IDENTITY_CONFIRMED
RETRY_STALE
RETRY_LOST_REACHABILITY
REVIEW_CONFLICT
REVIEW_NEW_CANDIDATE
HANDOFF_TO_IDENTITY
HANDOFF_TO_DELTA_PREFLIGHT
HANDOFF_TO_NETWORK_PREFLIGHT
HANDOFF_TO_PACKET_PROFILE
```

## Applicable command profiles

The iterative delta mechanism should support these lanes first:

| Profile | Comparison purpose |
|---|---|
| XLSX ingestion / tracker diff | Show newly tracked, newly untracked, remaining, ambiguous, and resolved serials |
| Delta preflight planner | Show changed decisions, newly probe-worthy rows, and skipped rework |
| Network preflight | Show newly reachable, lost reachability, stable silence, and stale rows |
| AD candidate pool | Show new candidate matches, disappeared candidates, and conflicts |
| Packet pipeline | Show service-level changes without treating them as serial proof |
| Reconciliation report | Show movement between confirmed, remaining, drift, conflict, and review buckets |

## Operator handoff text

`operator_handoff.txt` should be readable without opening the raw CSV first.

It should include:

```text
Command profile name
Current run id
Previous comparable run id
Input source summary
Counts added / removed / changed / unchanged
Skip-rework count
Retry-required count
Review-required count
Next recommended command or dashboard step
Paths to delta CSVs
```

It should not contain live credentials, secrets, or unnecessary raw dumps.

## Rework reduction rules

The comparison engine should prefer skip decisions when evidence is stable and fresh.

Examples:

- Stable identity-confirmed serials should not be pinged again unless forced.
- Stable reachable targets within TTL should not be re-probed by default.
- Stable serial-only rows should remain review-required until new bridging evidence appears.
- Stable AD-variant-only candidates should not become probe targets without review.
- Lost reachability should produce a delta, not erase prior identity evidence.

## Implementation surfaces

Preferred future files:

```text
survey/sas-command-delta-plan.ps1
scripts/SasCommandDelta.psm1
Tests/Pester/CommandDelta.Tests.ps1
Tests/bash/test_iterative_command_delta_contracts.sh
docs/ITERATIVE_COMMAND_DELTA_RUNS.md
```

The first implementation can be planner-only and artifact-only. It does not need to execute the underlying command profile itself.

## Required tests

Future tests must prove:

1. Same profile and same input fingerprint finds the previous comparable run.
2. Different input fingerprint does not compare as the same run.
3. Unchanged rows are marked `NO_CHANGE`.
4. New evidence appears in `delta_added.csv`.
5. Removed evidence appears in `delta_removed.csv`.
6. Status changes appear in `delta_changed.csv`.
7. Identity-confirmed new serials produce `NEW_IDENTITY_CONFIRMED`.
8. Lost reachability does not erase identity evidence.
9. `next_actions.csv` contains only rows needing action or explicit skip explanation.
10. Generated next handoff files contain only rows requiring action.
11. The comparison phase performs no network commands.
12. No live target, serial, MAC, IP, or generated operational artifact is committed.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Top focus:
Implement iterative command delta planning so repeated approved command profiles compare current artifacts against the previous comparable run and output the differences.

Read first:
- docs/ITERATIVE_COMMAND_DELTA_RUNS.md
- docs/SERIAL_EVIDENCE_STRENGTH_RANKING.md
- docs/DELTA_PREFLIGHT_EVIDENCE_CACHE_SPRINT.md
- docs/FIELD_NETWORK_PREFLIGHT.md

Mission:
Create a local artifact comparison planner for repeated command profiles. The planner must normalize current and previous outputs, compare structured evidence rows, and emit delta reports plus next-action handoffs.

Do not create a new scanner.
Do not run network commands in the comparison phase.
Do not commit live generated artifacts.
Do not treat raw text diff as authoritative.
Do not treat reachability or packet output as serial proof.

Required outputs:
- survey/output/command_delta/<profile>/<run_id>/delta_added.csv
- survey/output/command_delta/<profile>/<run_id>/delta_removed.csv
- survey/output/command_delta/<profile>/<run_id>/delta_changed.csv
- survey/output/command_delta/<profile>/<run_id>/delta_unchanged.csv
- survey/output/command_delta/<profile>/<run_id>/delta_summary.json
- survey/output/command_delta/<profile>/<run_id>/next_actions.csv
- survey/output/command_delta/<profile>/<run_id>/operator_handoff.txt

Required behavior:
- identify comparable prior run by command profile and input/parameter fingerprints
- rank evidence using the serial evidence ranking doctrine
- explain skip/retry/review decisions
- stage next-action handoff files under survey/input only when another tool needs them

Validation:
- Pester suite
- bash/static contracts
- offline survey tests if touched

Merge policy:
merge_when_green.
```
