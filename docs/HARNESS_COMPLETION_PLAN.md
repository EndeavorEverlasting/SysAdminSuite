# SysAdminSuite Harness Completion Plan

## Purpose

This document converts the useful patterns from `coleam00/helpline` and `coleam00/Archon` into a SysAdminSuite-specific harness completion plan.

The target state is a repeatable local harness where survey work is not a pile of one-off commands. It should be a structured loop:

```text
request
  -> source artifact
  -> local evidence review
  -> low-noise plan
  -> bounded action handoff
  -> timestamped artifacts
  -> English-readable report
  -> next iteration decision
```

## Reference repo lessons

### Helpline lesson: the harness is a first-class repo layer

Helpline treats the AI harness as an explicit layer beside code and tests. It maps every harness extension point to a concrete artifact and proof:

```text
CLAUDE.md hierarchy
hooks
skills
read-only explorer subagent
LSP
MCP structured search
plugin distribution
validation script
```

SysAdminSuite should copy the pattern, not the product content.

The equivalent SysAdminSuite layer should make field survey work navigable, testable, and reusable:

```text
repo doctrine
survey command dispatchers
low-noise policy module
artifact schemas
English report templates
validation contracts
future MCP/LSP/code-intelligence hooks
```

### Archon lesson: deterministic workflow structure around AI work

Archon encodes development work as workflows with phases, dependencies, fresh-context nodes, deterministic bash nodes, human gates, artifact directories, validation, review, and final summaries.

SysAdminSuite should copy this shape for field survey and repo sprint work:

```text
explore / plan / stage / run / validate / review / summarize / iterate
```

The agent or technician can still make judgment calls, but the harness owns the sequence and required artifacts.

## Current SysAdminSuite foundation

SysAdminSuite already has several pieces of the harness:

- `.gitignore` excludes live local artifacts and generated outputs.
- `targets/README.md` defines tracked vs local target intake.
- `scripts/SasTargetIntake.psm1` centralizes approved input/output roots.
- `scripts/SasLowNoisePolicy.psm1` centralizes pragmatic retry/noise doctrine.
- `survey/sas-serial-preflight-plan.ps1` stages host/IP targets from serial evidence.
- `survey/sas-network-preflight.ps1` runs bounded PowerShell DNS/ping/TCP checks.
- `survey/sas-target-intake-dispatch.ps1` prints use-case commands.
- Static contracts enforce several survey, dashboard, and preflight guardrails.
- Docs codify serial-first planning, iterative probe handoffs, dashboard gaps, low-noise probing, and target folder policy.

## Remaining harness gaps

### Gap 1: English-readable logs are not yet a first-class product

Current artifacts are increasingly structured, but the user-facing result should also read like English.

Needed:

```text
JSON event/state files
  -> variable dictionary
  -> English template renderer
  -> operator report
  -> next-action handoff
```

Each report should answer:

```text
What was requested?
What sources were used?
What did we already know locally?
What action was justified?
What packets, if any, were sent?
What changed from last time?
What still needs review?
What should the operator run next?
```

See `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` for the concrete contract.

### Gap 2: Workflow/state directories need one canonical shape

Adopt an Archon-like run directory for each SysAdminSuite workflow run:

```text
runs/<workflow_id>/
  request.json
  context.json
  plan.json
  plan.md
  actions/
  artifacts/
  evidence/
  reports/
  review/
  summary.json
  summary.md
  operator_handoff.txt
```

For survey-specific runs, mirror that under ignored survey output roots when appropriate:

```text
survey/output/runs/<workflow_id>/
```

Each command should either create or append to a run directory instead of scattering unlinked artifacts.

### Gap 3: Workflow definitions are not yet explicit

Adopt a lightweight local workflow definition format inspired by Archon, without requiring Archon itself yet.

Suggested path:

```text
survey/workflows/
  serial-to-preflight.yaml
  serial-iteration.yaml
  network-preflight.yaml
  live-data-risk-audit.yaml
  dashboard-serial-controls.yaml
```

Each workflow should define:

```text
name
description
inputs
nodes
artifacts
validation
next_actions
```

Example nodes:

```text
load-request
load-local-evidence
classify-serials
stage-targets
run-preflight
load-results
render-english-report
classify-next-iteration
```

### Gap 4: Harness validation should prove the layer end to end

Helpline has one validator that proves the harness works end to end. SysAdminSuite needs the same product shape.

Suggested file:

```text
scripts/validate-sysadmin-harness.ps1
```

It should run a synthetic, no-live-data harness proof:

```text
1. validate target folder policy
2. validate low-noise policy module
3. run serial preflight against fixtures
4. render English handoff/report from fixture JSON
5. run dashboard/parser smoke for serial outputs
6. run live-data-risk audit in advisory mode against safe fixtures
7. assert no network commands ran in planner phases
8. print PASS/FAIL matrix
```

Expected output style:

```text
SYSADMIN HARNESS VALIDATION
[PASS] target folder policy
[PASS] low-noise policy module
[PASS] serial preflight fixture run
[PASS] English report renderer
[PASS] dashboard serial output parser
[PASS] live-data audit advisory mode

Result: 6/6 passed
```

### Gap 5: Future MCP/code-intelligence layer remains planned, not implemented

Helpline's MCP lesson matters for SysAdminSuite because this repo is becoming large enough that grep-only work causes drift.

Future local MCP should expose read-only tools such as:

```text
where_is_command
find_survey_workflows
find_artifact_schema
find_policy_source
find_contract_for_surface
outline_powershell_script
outline_dashboard_parser
```

Rules:

- read-only first
- never read ignored live evidence by default
- never expose secrets or live generated artifacts
- prefer tracked docs/code/contracts
- make harness navigation deterministic

## Harness completion phases

### Phase 1: Artifact and English log foundation

Deliver:

```text
docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md
schemas/harness/run-event.schema.json
schemas/harness/operator-report.schema.json
scripts/Render-SasEnglishReport.ps1
Tests/bash/test_english_log_artifact_contracts.sh
```

Done when fixture JSON can render a human-readable report and handoff without live data.

### Phase 2: Canonical run directory

Deliver:

```text
scripts/SasRunContext.psm1
survey/output/runs/<workflow_id>/ fixture-only proof
run_id / workflow_id helpers
artifact registry JSON
```

Done when serial and network preflight artifacts can be registered to a run context.

### Phase 3: Lightweight workflow specs

Deliver:

```text
survey/workflows/serial-to-preflight.yaml
survey/workflows/network-preflight.yaml
survey/workflows/serial-iteration.yaml
```

Done when docs and static tests can prove each workflow declares inputs, nodes, outputs, validation, and next actions.

### Phase 4: End-to-end harness validator

Deliver:

```text
scripts/validate-sysadmin-harness.ps1
Tests/bash/test_harness_validator_contracts.sh
```

Done when one command proves the synthetic harness path and prints a PASS/FAIL matrix.

### Phase 5: Dashboard integration

Deliver:

```text
dashboard serial-first controls
dashboard parser for summary/report artifacts
dashboard display of English operator handoff
```

Done when the UI can load serial preflight outputs, show counts, and render the next command without asking AI.

### Phase 6: MCP/LSP/code-intelligence layer

Deliver:

```text
docs/MCP_LSP_CODE_INTELLIGENCE_PLAN.md
tooling/mcp/sysadmin-codebase-search/
read-only tools
validation handshake
```

Done when an agent can ask structured questions about command surfaces, schemas, and contracts without ad hoc grep.

## Acceptance criteria for the completed harness

A completed SysAdminSuite harness must satisfy:

- Every survey action starts from a source artifact or explicit request.
- Every packet-producing action is preceded by local evidence review and low-noise policy context.
- Every run has a run ID and artifact registry.
- Every major run can render an English report from JSON/artifacts.
- Every report includes next actions and review buckets.
- Every planner declares whether network activity occurred.
- Live evidence remains ignored/local.
- Synthetic fixtures prove the paths.
- A single validator can prove the harness end to end.
- The dashboard exposes the same workflow the docs and scripts support.

## Copy-ready next-agent prompt

```text
You are continuing SysAdminSuite.

Top focus:
Complete the harness layer by implementing English-readable report rendering from JSON/artifacts and a canonical run context.

Read first:
- docs/HARNESS_COMPLETION_PLAN.md
- docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md
- docs/LOW_NOISE_PROBE_PRINCIPLES.md
- docs/TECHNICIAN_ITERATIVE_PROBE_HANDOFFS.md
- docs/DASHBOARD_SERIAL_PROBE_CONTROLS_SPRINT.md

Reference patterns already analyzed:
- Helpline: AI layer maps extension point -> artifact -> proof.
- Archon: workflow phases, dependencies, artifact directories, validation gates, final workflow summary.

Mission:
Build the first implementation slice: English report rendering and run-context registration for SysAdminSuite survey artifacts.

Required behavior:
1. Add fixture-only JSON events for serial preflight and network preflight.
2. Add a renderer that turns those JSON events into English operator reports.
3. Add an artifact registry format that links request, plan, evidence, action, report, and next handoff.
4. Add static/fixture tests proving no live data is required.
5. Keep outputs local/ignored for real runs.
6. Do not run network commands in renderer tests.

Validation:
- Dashboard Smoke if touched
- Pester if touched
- Survey/static contracts if touched
- New English log artifact tests

Merge policy:
merge_when_green.
```
