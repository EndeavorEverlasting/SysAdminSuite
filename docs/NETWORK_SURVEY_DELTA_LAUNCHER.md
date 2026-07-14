# Network Survey Delta Launcher

## Technician entrypoint

Double-click:

```text
Run-NetworkSurveyDelta.cmd
```

Technicians do not need to remember PowerShell cmdlets, RunIds, generated target paths, or evidence-file arguments. The CMD launcher opens a stateful menu:

```text
[1] Smart delta survey
[2] Time-diverse repeat survey
[3] Compare/plan only
[4] Open latest evidence folder
[5] Reset saved survey source and cycle state
```

## What the launcher does

The launcher keeps artifact intake, the packet-free planner, and the live read-only survey as separate proof stages:

```text
approved requested/evidence artifacts
  -> registered format adapters
  -> canonical denominator validation
  -> load prior local evidence
  -> rank strongest evidence per row
  -> compare latest and previous observations
  -> stage only justified targets
  -> explicit operator confirmation
  -> existing sas-network-preflight.ps1
  -> automatically rebuild the delta comparison
```

Every source artifact must pass `schemas/survey/network-survey-artifact-denominator.schema.json` through `scripts/SasSurveyArtifactNormalizer.psm1` before planning begins. Source-specific aliases live only in `survey/network_survey_artifact_adapters.json`; they are not copied into the planner. See [`NETWORK_SURVEY_ARTIFACT_DENOMINATOR.md`](NETWORK_SURVEY_ARTIFACT_DENOMINATOR.md).

`survey/sas-delta-preflight-plan.ps1` never sends packets. It writes:

```text
survey/output/delta_preflight/<run_id>/artifact_intake_manifest.json
survey/output/delta_preflight/<run_id>/normalized_artifacts/
survey/output/delta_preflight/<run_id>/delta_preflight_plan.csv
survey/output/delta_preflight/<run_id>/skipped_recent_evidence.csv
survey/output/delta_preflight/<run_id>/review_required.csv
survey/output/delta_preflight/<run_id>/survey_observation_delta.csv
survey/output/delta_preflight/<run_id>/delta_summary.json
survey/output/delta_preflight/<run_id>/operator_handoff.txt
survey/input/delta_preflight/<run_id>/to_probe_targets.txt
```

The live step reuses the existing bounded `survey/sas-network-preflight.ps1` entrypoint. It remains read-only toward target machines and writes evidence locally.

## Delta meanings

`survey_observation_delta.csv` compares the latest two timestamped observations for each requested target:

```text
FIRST_OBSERVATION
BECAME_REACHABLE
BECAME_SILENT
SERVICE_PORTS_CHANGED
UNCHANGED_REACHABLE
UNCHANGED_SILENT
NO_TIMESTAMPED_OBSERVATION
```

The planner also assigns one primary decision per requested row, including fresh-evidence skips, stale/missing reprobes, operator-forced time-diverse repeats, ambiguity review, and serial-only review.

## Repeated times of day

The stateful launcher records the attempt count and distinct local time buckets. A time-diverse repeat is an explicit menu action rather than an automatic immediate retry. The saved cycle enforces the low-noise cap of five network attempts.

Five attempts in one narrow window do not prove persistent silence. The delta artifacts preserve non-response as evidence and never turn it into proof that a device or serial does not exist.

## State and paths

Local operator state is stored under the ignored output root:

```text
survey/output/network_survey_delta/operator-state.json
```

The state stores repo-relative source and artifact paths. Paths are resolved against the current repo root for each action.

**Future/unsupported behavior:** Dynamic path rewriting or path rehydration after copying or moving an in-progress continuation state is unsupported. When saved state no longer resolves, the launcher fails closed and asks the operator to reselect the approved source. It does not guess replacement paths.

## Safety boundaries

- No live source, normalized package, evidence, state, or generated delta artifact is committed.
- The normalizer and planner perform no DNS, ping, TCP, Nmap, Naabu, AD, or target-side operation.
- An artifact with one denominator-invalid row fails closed before planning.
- A live survey requires an explicit `SURVEY` confirmation.
- The launcher cannot broaden the selected ports beyond the existing preflight policy.
- Serial-only values are never staged as network targets.
- Reachability and open ports do not confirm serial identity.
- Dynamic path rewriting is not part of this sprint.
