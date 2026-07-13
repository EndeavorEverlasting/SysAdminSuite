# English Log Artifact Contract

## Purpose

SysAdminSuite logs and reports should read like English while remaining driven by machine-readable JSON and artifacts.

The operator should not need to inspect raw CSV/JSON first to understand what happened. Raw artifacts should populate variables in a narrative report.

Target shape:

```text
structured JSON + artifact registry + report template
  -> English-readable report
  -> operator handoff
  -> next-action decision
```

## Design principle

The English report is a rendering of facts, not a separate source of truth.

```text
JSON owns the variables.
Artifacts own the evidence.
Templates own the wording.
Reports own the human-readable explanation.
```

The same contract applies to event streams. Raw `events.jsonl` remains unchanged; `scripts/render-sas-structured-log.py` resolves each safe named placeholder into an `english_message` and emits separate `events_english.jsonl` and `events_english.txt` artifacts. Machine JSON remains parser-facing output, while English is a registered derived artifact for agents and operators.

Low-noise summaries should carry one profile-agnostic `low_noise_context` object containing policy/schema version, profile and profile source, target/evidence source, effective constraints, disposition and reason, activity/mutation status, and next action. This lets posture and platform policy change in the provider without adding workflow-specific renderer branches.

## Required run variables

Every workflow run should expose these core variables:

```text
workflow_id
run_id
request_summary
source_artifacts
loaded_evidence_artifacts
planner_name
planner_version
network_activity_performed
low_noise_policy_version
started_at
finished_at
operator_handoff_path
summary_json_path
report_markdown_path
next_action
```

## Survey-specific variables

Serial and network preflight reports should support:

```text
serials_total
serials_with_probe_ready_bridge
serials_mystery_no_bridge
review_required_count
probe_targets_staged
probe_target_file
ports_requested
network_preflight_csv
newly_reachable_count
still_silent_count
stale_or_conflicting_count
persistent_silent_time_diverse_count
plateau_detected
```

## English report template

A serial preflight report should read like:

```text
SysAdminSuite reviewed {serials_total} serials from {source_artifact_name}.

Before sending packets, it checked local evidence from {evidence_artifact_count} artifact(s).
{serials_with_probe_ready_bridge} serial(s) had approved host/IP bridge evidence and were staged for network preflight.
{serials_mystery_no_bridge} serial(s) still have no approved host/IP bridge and remain review-required.

The planner did not perform network activity.
The next network preflight target file is {probe_target_file}.

Low-noise context:
{low_noise_principle}
{probe_again_guidance}

Next action:
{next_action}
```

A network preflight report should read like:

```text
SysAdminSuite ran a bounded network preflight for {target_count} target(s) from {target_file}.

It checked ports {ports_requested} and wrote {network_preflight_csv}.
This run performed network activity.

Fresh reachability evidence should reduce re-probing. If a target is still silent and retrying is justified, retry later at a different time of day or day of week rather than repeating immediately.

Next action:
{next_action}
```

## Required report sections

Every rendered report should include:

```text
Title
Run identity
Request summary
Source artifacts
Local evidence used
Action decision
Network activity status
Low-noise context
Results summary
Review-required rows
Next action
Artifact list
```

## Artifact registry contract

Every run should produce an artifact registry:

```text
artifact_registry.json
```

Minimum shape:

```json
{
  "workflow_id": "serial-to-preflight",
  "run_id": "20260701-serial-preflight-demo",
  "artifacts": [
    {
      "role": "source_serial_list",
      "path": "targets/local/alejandro_serials.csv",
      "tracked": false,
      "contains_live_data": true,
      "description": "Approved local serial source"
    },
    {
      "role": "summary_json",
      "path": "survey/output/serial_preflight/demo/serial_preflight_summary.json",
      "tracked": false,
      "contains_live_data": true,
      "description": "Machine-readable run summary"
    },
    {
      "role": "operator_report",
      "path": "survey/output/serial_preflight/demo/operator_report.md",
      "tracked": false,
      "contains_live_data": true,
      "description": "English-readable report generated from JSON and artifacts"
    }
  ]
}
```

Synthetic test registries may be tracked only under approved fixture/sample paths.

## Log event contract

Each major phase should append a structured event:

```json
{
  "timestamp": "2026-07-01T10:15:00-04:00",
  "level": "INFO",
  "event_type": "serial_preflight.plan.created",
  "workflow_id": "serial-to-preflight",
  "run_id": "20260701-101500",
  "message_template": "Reviewed {serials_total} serials and staged {probe_targets_staged} target(s).",
  "variables": {
    "serials_total": 120,
    "probe_targets_staged": 35,
    "review_required_count": 85
  },
  "artifact_refs": [
    "serial_preflight_plan.csv",
    "review_required.csv"
  ],
  "network_activity_performed": false
}
```

The rendered English line becomes:

```text
[2026-07-01 10:15] Reviewed 120 serials and staged 35 target(s). 85 serial(s) require review.
```

## English line rules

English logs should be concise and factual:

- Use complete sentences.
- Include counts and artifact names.
- Say whether network activity occurred.
- Say why rows were staged, skipped, or routed to review.
- Include low-noise retry context when relevant.
- Avoid raw dumps.
- Avoid hiding uncertainty.
- Avoid stealth/no-trace/bypass language.

## Example event-to-English mappings

| Event type | Template |
|---|---|
| `serial_preflight.source.loaded` | `Loaded {serials_total} serial(s) from {source_artifact_name}.` |
| `serial_preflight.evidence.loaded` | `Loaded {evidence_artifact_count} local evidence artifact(s).` |
| `serial_preflight.targets.staged` | `Staged {probe_targets_staged} host/IP target(s) because approved bridge evidence exists.` |
| `serial_preflight.review.required` | `{review_required_count} serial(s) remain review-required because no probe-ready bridge was found.` |
| `network_preflight.started` | `Started bounded network preflight for {target_count} target(s) on ports {ports_requested}.` |
| `network_preflight.completed` | `Network preflight completed and wrote {network_preflight_csv}.` |
| `iteration.plateau.detected` | `No new successful evidence appeared across comparable runs; route the remaining rows to review instead of repeating immediately.` |
| `live_data.audit.warning` | `The advisory audit found {warning_count} possible live-data risk(s). Review before committing.` |

## Renderer implementation plan

Preferred first implementation:

```text
scripts/Render-SasEnglishReport.ps1
```

Inputs:

```text
-SummaryJson <path>
-ArtifactRegistry <path>
-Template serial-preflight|network-preflight|iteration|audit
-OutputPath <path>
```

Rules:

- Renderer performs no network activity.
- Renderer reads JSON/artifacts only.
- Renderer should not require live data for tests.
- Renderer should fail clearly if required variables are missing.
- Renderer should preserve uncertainty instead of inventing conclusions.

## Fixture strategy

Synthetic fixtures should live under:

```text
survey/fixtures/english-log/
```

Suggested fixtures:

```text
serial_preflight_summary.sample.json
serial_preflight_artifact_registry.sample.json
network_preflight_summary.sample.json
network_preflight_artifact_registry.sample.json
```

## Required tests

Add:

```text
Tests/bash/test_english_log_artifact_contracts.sh
```

Tests must prove:

1. Renderer exists and parses.
2. Fixture summary JSON contains required variables.
3. Fixture artifact registry contains source, summary, report, and handoff roles.
4. Rendered report includes request/source/evidence/action/network status/next action.
5. Serial report says planner performed no network activity.
6. Network preflight report says network activity occurred.
7. Missing required variables fail clearly.
8. Output does not contain raw live-looking hostnames, serials, MACs, or IPs in tracked fixtures.
9. Report includes low-noise retry guidance.
10. Renderer does not run network commands.

## Acceptance criteria

This contract is satisfied when a future sprint can run:

```powershell
.\scripts\Render-SasEnglishReport.ps1 `
  -SummaryJson .\survey\fixtures\english-log\serial_preflight_summary.sample.json `
  -ArtifactRegistry .\survey\fixtures\english-log\serial_preflight_artifact_registry.sample.json `
  -Template serial-preflight `
  -OutputPath .\survey\output\english-log\serial_preflight_report.md
```

and the result reads like an operator report rather than a raw data dump.
