# Technician Iterative Probe Handoffs

## Purpose

This document codifies how a field technician should repeatedly run the same approved SysAdminSuite command without asking an AI agent for the next command.

The command should inspect local evidence first, narrow the target set, run only the justified next probe, timestamp the attempt, compare against prior runs, and classify the remaining serials.

The practical goal is:

```text
same command
  -> read local evidence
  -> select only justified targets
  -> produce timestamped attempt artifact
  -> compare against prior attempts
  -> narrow next run
  -> classify stable gaps
```

## Core doctrine

A serial remains the anchor even when the workflow temporarily moves through hostnames, IPs, subnets, DNS, AD, MAC, or packet evidence.

Do not let the workflow become:

```text
serial list
  -> first probe fails
  -> serial is forgotten
  -> hostname-only work continues
```

Correct workflow:

```text
serial list
  -> all available bridges checked
  -> attempt recorded by serial
  -> result compared to prior attempts
  -> next handoff chosen by serial status
```

## Repeatable operator command principle

Technicians should not need to ask for the next command after every run.

The preferred field UX is one repeatable command shape:

```powershell
Set-Location <SysAdminSuite repo root>
.\survey\sas-serial-preflight-plan.ps1 `
  -SerialFile .\targets\local\alejandro_serials.csv `
  -EvidenceFile .\targets\local\approved_serial_hostname_bridge.csv `
  -Ports 135,445,3389,9100
```

The implementation should evolve so this command or its dashboard wrapper automatically:

1. loads the latest local evidence
2. reads prior serial preflight attempts
3. avoids redoing confirmed or recently tested targets
4. stages only the narrowed next target file
5. prints the exact next command when network preflight is still justified
6. writes an operator handoff explaining what changed

## Probe history requirement

Every serial-target attempt must be timestamped.

Required attempt fields:

```text
RunId
AttemptId
Serial
NormalizedSerial
ProbeTarget
TargetKind
Hostname
IPAddress
Subnet
MacAddress
AttemptStartedAt
AttemptFinishedAt
LocalTimeOfDayBucket
CommandProfileName
CommandProfileVersion
PortsRequested
EvidenceSourceFiles
PreviousAttemptCount
PreviousSuccessCount
PreviousFailureCount
Outcome
Classification
ClassificationReason
NextAction
NetworkActivityPerformed
```

Recommended local output path:

```text
survey/output/serial_probe_history/<run_id>/serial_probe_attempts.csv
```

A cumulative local rollup can also be maintained under an ignored output root:

```text
survey/output/serial_probe_history/serial_probe_history_index.csv
```

No live generated history should be committed.

## Time diversity requirement

Repeated non-response is more meaningful when attempts are spread across different times.

Recommended time buckets:

```text
morning
midday
afternoon
evening
overnight
weekend
unknown
```

The suite should not classify a serial as persistently silent just because five retries happened in the same short window.

Recommended diversity fields:

```text
DistinctAttemptDates
DistinctTimeOfDayBuckets
DistinctWeekdayWeekendStates
FirstAttemptAt
LastAttemptAt
AttemptSpanHours
```

## Consistency / plateau detection

The suite should detect when repeated attempts stop improving the result set.

Recommended plateau logic:

```text
if new_successes == 0 across N comparable runs
and mystery_serial_count is unchanged
and attempts are time-diverse enough
then classify the gap as stable_no_improvement_review
```

This does not mean the devices do not exist. It means the probe path has stopped producing new evidence.

## Mystery serial doctrine

Serials with no hostname, IP, MAC, DNS, AD candidate, or identity bridge are not low priority by default.

They are often prime targets because the operational question is:

```text
Where did this serial go?
```

Required classification:

```text
MYSTERY_SERIAL_NO_BRIDGE
```

Rules:

- Do not ping a serial string.
- Do not drop it from the denominator.
- Do not convert it to hostname-only work.
- Keep it in the serial review queue until a bridge or disposition is found.
- Surface it prominently in operator handoffs.

## Repeated failure classifications

After enough timestamped and time-diverse attempts, repeated non-response should be classified with possibilities, not a single false certainty.

Recommended classifications:

```text
PERSISTENTLY_SILENT_TIME_DIVERSE
LIKELY_POWERED_OFF_OR_SLEEPING
POSSIBLE_BROKEN_DEVICE
POSSIBLE_DECOMMISSIONED_OR_REMOVED
POSSIBLE_NETWORK_POLICY_BLOCKED
POSSIBLE_WRONG_HOSTNAME_OR_STALE_DNS
POSSIBLE_WRONG_SUBNET_OR_SITE_CONTEXT
MYSTERY_SERIAL_NO_BRIDGE
REQUIRES_PHYSICAL_AUDIT
REQUIRES_TRACKER_RECONCILIATION
REQUIRES_NETWORK_TEAM_REVIEW
```

Important rule:

```text
Repeated failed probes are evidence of non-response.
They are not proof that the serial does not exist.
```

## Handoff outputs

The iterative command should always leave a human-readable and machine-readable handoff.

Recommended output root:

```text
survey/output/serial_iteration/<run_id>/
```

Required outputs:

```text
iteration_summary.json
operator_handoff.txt
serial_status_rollup.csv
serial_attempt_history.csv
newly_reachable.csv
newly_confirmed_identity.csv
still_silent.csv
mystery_serials_no_bridge.csv
review_required.csv
next_probe_targets.csv
```

If another tool needs a runnable target list, stage it under:

```text
survey/input/serial_iteration/<run_id>/to_probe_targets.txt
```

## Operator handoff text

`operator_handoff.txt` should answer:

```text
What did this run attempt?
What changed since the prior comparable run?
Which serials are now resolved or reachable?
Which serials remain mystery/no-bridge?
Which serials are persistently silent after diverse attempts?
What is the next repeatable command?
What should be reviewed by a human instead of probed again?
```

## Iteration summary JSON

`iteration_summary.json` should include:

```text
run_id
generated_at
input_serial_file
evidence_files_loaded
previous_comparable_run_id
serials_total
serials_with_probe_ready_bridge
serials_mystery_no_bridge
probe_targets_staged
newly_reachable_count
newly_confirmed_identity_count
still_silent_count
persistent_silent_time_diverse_count
review_required_count
new_successes_this_run
plateau_detected
network_activity_performed_by_planner
next_command
```

The planner value must remain:

```text
network_activity_performed_by_planner = false
```

The later network-preflight or packet lane may set its own network activity value to true.

## Command UX expectation

The technician should be able to keep running the same command or dashboard button:

```text
Plan next serial probe iteration
```

The system should decide whether the next handoff is:

```text
run network preflight on staged targets
run DNS/subnet enrichment
review mystery serials
review persistent silence
stop: no improvement plateau detected
```

## Next implementation sprint contract

Preferred implementation surfaces:

```text
survey/sas-serial-iteration-plan.ps1
scripts/SasSerialProbeHistory.psm1
Tests/bash/test_serial_iteration_contracts.sh
docs/TECHNICIAN_ITERATIVE_PROBE_HANDOFFS.md
```

The first implementation can be planner-only. It should not execute network commands itself.

Required behavior:

1. Load Alejandro serial list or normalized serial manifest.
2. Load local evidence from approved roots.
3. Load prior serial probe attempt history.
4. Compute attempt diversity by serial.
5. Preserve mystery serials as first-class review rows.
6. Decide which serials have probe-ready targets.
7. Skip confirmed or recently/stably tested rows.
8. Stage only the next justified target file.
9. Write timestamped attempt planning artifacts.
10. Produce a concise operator handoff with the same repeatable next command.

## Required tests

Tests must prove:

1. A serial-only row remains in `MYSTERY_SERIAL_NO_BRIDGE` and is not staged as a target.
2. Five failed attempts in the same time bucket do not qualify as time-diverse persistent silence.
3. Failed attempts across distinct dates/time buckets can produce `PERSISTENTLY_SILENT_TIME_DIVERSE`.
4. A newly reachable target appears in `newly_reachable.csv`.
5. Stable confirmed identity rows are skipped unless forced.
6. Plateau detection requires no new successes across comparable runs.
7. The planner performs no network commands.
8. The staged target file contains only probe-ready hostnames/IPs.
9. The operator handoff includes the next repeatable command.
10. No live serials, hostnames, IPs, MACs, or generated evidence are committed.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Top focus:
Implement technician-facing serial iteration handoffs so field techs can run the same approved command repeatedly without asking AI for the next command.

Read first:
- docs/TECHNICIAN_ITERATIVE_PROBE_HANDOFFS.md
- docs/ITERATIVE_COMMAND_DELTA_RUNS.md
- docs/SERIAL_EVIDENCE_STRENGTH_RANKING.md
- docs/FIELD_NETWORK_PREFLIGHT.md

Mission:
Create a planner that reads Alejandro's serial list, approved local evidence, and prior probe history, then stages only the next justified probe target file while preserving mystery serials and timestamped attempt history.

Do not create a scanner.
Do not run network commands in the planner.
Do not drop serial-only mystery rows.
Do not treat repeated failed probes as proof that a serial does not exist.
Do not rely on five attempts unless they are time-diverse enough to support the classification.

Required outputs:
- survey/output/serial_iteration/<run_id>/iteration_summary.json
- survey/output/serial_iteration/<run_id>/operator_handoff.txt
- survey/output/serial_iteration/<run_id>/serial_status_rollup.csv
- survey/output/serial_iteration/<run_id>/serial_attempt_history.csv
- survey/output/serial_iteration/<run_id>/mystery_serials_no_bridge.csv
- survey/output/serial_iteration/<run_id>/review_required.csv
- survey/input/serial_iteration/<run_id>/to_probe_targets.txt

Required classifications:
- MYSTERY_SERIAL_NO_BRIDGE
- PERSISTENTLY_SILENT_TIME_DIVERSE
- LIKELY_POWERED_OFF_OR_SLEEPING
- POSSIBLE_BROKEN_DEVICE
- POSSIBLE_DECOMMISSIONED_OR_REMOVED
- POSSIBLE_NETWORK_POLICY_BLOCKED
- POSSIBLE_WRONG_HOSTNAME_OR_STALE_DNS
- POSSIBLE_WRONG_SUBNET_OR_SITE_CONTEXT
- REQUIRES_PHYSICAL_AUDIT
- REQUIRES_TRACKER_RECONCILIATION
- REQUIRES_NETWORK_TEAM_REVIEW

Validation:
- bash/static contracts
- Pester only if PowerShell runtime behavior is implemented
- dashboard smoke if dashboard copy changes

Merge policy:
merge_when_green.
```
