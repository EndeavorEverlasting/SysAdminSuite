# SysAdminSuite Harness Execution Sprint Plan

## Context banner

**Repo:** `EndeavorEverlasting/SysAdminSuite`  
**Current lane:** harness + survey target reduction + standard corporate tooling  
**Recent merged center of gravity:** PR #139 and PR #140  
**Objective:** turn the harness from contracts/docs into executable local operations.  
**Primary artifact:** this plan, which converts the harness completion work into bounded sprint lanes that can be handed to parallel agents without losing ownership, validation, or artifact discipline.

## Harness operating loop

The harness exists to make field operations repeatable, reviewable, and low-noise. Every lane should preserve this loop:

```text
request
  -> source artifact
  -> local evidence review
  -> low-noise plan
  -> bounded action handoff
  -> artifacts
  -> English-readable report
  -> next iteration decision
```

Docs, manifests, scripts, validators, logs, prompts, reports, and dashboard views are one connected system. Docs are operational inputs, not decoration.

## Global sprint rules

Every sprint agent must name:

```text
Repo
Branch
Sprint / lane
Owned scope
Forbidden scope
Expected artifacts
Validation commands
Merge policy
```

No sprint may claim completion without evidence. Acceptable evidence includes passing tests, validator output, generated fixture artifacts, `git diff`, `git status`, CI result, PR link, or merge confirmation.

Every produced or consumed artifact must preserve these fields where applicable:

```text
role
path
tracked
live_data
description
source_artifact
network_activity
created_at
```

Every report, summary, handoff, or validator output must explicitly declare network activity using language equivalent to one of:

```text
No network activity performed.
Network command rendered only; operator execution required.
Live network evidence consumed from local ignored artifact.
Live network probe executed by approved wrapper.
```

Planner, renderer, dashboard, and static contract lanes should normally declare:

```text
No network activity performed.
```

The identity and uncertainty rules are mandatory:

```text
Reached is not identity proof.
Non-reached is not dead.
Candidate discovery is not identity proof.
DNS failure is not proof of absence.
NoPing / NoTcp is not proof that a device is gone.
Fresh evidence can reduce repeated probing.
Retry should prefer a different time or day over immediate repeat probes.
```

API manifest ownership rule:

```text
Do not change harness/api/sas-harness-api.json unless the sprint explicitly owns an API surface.
```

If a lane discovers a needed API change outside its owned scope, it should document the proposed change in its handoff instead of silently mutating the manifest.

## Sprint waves

### Wave 0 — Stabilize the harness floor

These lanes can run immediately and safely in parallel.

| Sprint | Branch | Purpose |
|---|---|---|
| A0 | `feat/harness-run-context` | canonical run context and artifact registry |
| A1 | `test/probe-executor-boundaries` | shell/subprocess/PowerShell probe guardrails |
| A2 | `test/local-harness-hooks-proof` | prove hooks are installable and safe |
| A3 | `docs/mcp-lsp-code-intelligence-plan` | read-only code-intelligence plan |

### Wave 1 — First executable harness operations

Run these after A0 lands, or with explicit provisional integration if A0 is still open.

| Sprint | Branch | Purpose |
|---|---|---|
| B0 | `feat/target-reduction-plan` | first real local harness operation |
| B1 | `feat/english-report-renderer` | render human-readable reports from artifacts |
| B2 | `feat/standard-command-renderers` | render standard CMD/PowerShell command plans |
| B3 | `feat/location-subnet-candidates` | local location/subnet candidate planning |

### Wave 2 — End-to-end proof and usability

Run after Wave 1 output contracts stabilize.

| Sprint | Branch | Purpose |
|---|---|---|
| C0 | `feat/validate-sysadmin-harness` | one command proving fixture harness path |
| C1 | `feat/probe-results-report` | concrete report from prior probe/preflight artifacts |
| C2 | `feat/dashboard-serial-controls` | dashboard consumes harness artifacts |

### Wave 3 — Agent/tooling layer

Run after the validator and APIs stabilize.

| Sprint | Branch | Purpose |
|---|---|---|
| D0 | `feat/local-mcp-skeletons` | runnable read-only/local-transform MCP skeletons |

## Recommended execution order

Use this order for merge discipline:

```text
1. A0 — Canonical Run Context
2. B0 — Target Reduction Planner With Low-Noise Policy
3. B1 — English Report Renderer
4. B2 — Standard Command Renderers
5. B3 — Location/Subnet Candidate Planner
6. C0 — End-to-End Harness Validator
7. C1 — Probe Results Report
8. C2 — Dashboard Serial Controls
9. D0 — Local MCP Server Skeletons
```

Parallel-safe lanes that can run immediately:

```text
A1 — Probe Executor Guardrail Expansion
A2 — Local Harness Hook Proof
A3 — MCP/LSP Code-Intelligence Plan
```

## Sprint A0 — Canonical Run Context and Artifact Registry

**Branch:** `feat/harness-run-context`  
**Lane:** harness spine  
**Owned scope:** local run-directory creation, workflow ID validation, artifact registry helpers  
**Forbidden scope:** no network execution, no live evidence committed, no dashboard changes unless needed for docs references  
**Expected artifacts:** `scripts/SasRunContext.psm1`, fixture run context, tests, docs update

### Read first

```text
docs/HARNESS_COMPLETION_PLAN.md
docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md
docs/LOCAL_DEVELOPMENT_HARNESS.md
scripts/SasTargetIntake.psm1
harness/api/sas-harness-api.json
Tests/survey/test_local_harness_contracts.py
```

### Mission

Create the canonical harness run context layer so SysAdminSuite stops scattering unlinked outputs.

Target run shape:

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

Survey ignored output root:

```text
survey/output/runs/<workflow_id>/
```

### Implement

```text
New-SasRunId
Test-SasWorkflowId
New-SasRunContext
New-SasArtifactRegistry
Register-SasArtifact
Get-SasRunSummaryPath
Resolve-SasOutputRoot
Assert-SasLocalOutputRoot
```

### Required artifact registry fields

```text
role
path
tracked
live_data
description
source_artifact
network_activity
created_at
```

### Validation

Run the repo's offline survey tests, Pester if PowerShell tests are added or already present, and the survey doctrine/local equivalent. Show `git diff` and `git status` in the final report.

## Sprint B0 — Target Reduction Planner With Low-Noise Policy

**Branch:** `feat/target-reduction-plan`  
**Primary API:** `target_reduction.plan`  
**Owned scope:** local-transform-only target reduction from prior evidence  
**Forbidden scope:** no network probing, no target mutation, no live evidence committed  
**Expected artifacts:** planner script/module, reduced/retry/review queues, summary JSON, tests

### Read first

```text
docs/STANDARD_CORPORATE_SURVEY_TOOLING.md
docs/LOCAL_DEVELOPMENT_HARNESS.md
docs/HARNESS_COMPLETION_PLAN.md
harness/api/sas-harness-api.json
scripts/SasLowNoisePolicy.psm1
scripts/SasRunContext.psm1
Tests/survey/test_standard_corporate_tooling_contracts.py
Tests/survey/test_local_harness_contracts.py
```

### Mission

Implement the first real executable harness operation:

```text
target_reduction.plan
```

The planner consumes prior local probe/preflight evidence and produces reduced target queues without probing anything.

### Preferred output shape

Use canonical run context if present:

```text
survey/output/runs/<workflow_id>/artifacts/target_reduction/
  reduced_targets.csv
  retry_candidates.csv
  review_required.csv
  location_subnet_candidates.csv
  target_reduction_summary.json
```

Fallback only if run context has not landed:

```text
survey/output/target_reduction/<run_id>/
  reduced_targets.csv
  retry_candidates.csv
  review_required.csv
  location_subnet_candidates.csv
  target_reduction_summary.json
```

Do not invent a third shape.

### Required statuses

```text
ConfirmedReached
RetryCandidate
ReviewRequired
DeferredSubnetCandidate
OutOfScope
```

### Required low-noise fields

```text
LowNoiseDisposition
ProbeAgainGuidance
FreshEvidenceGuidance
network_visibility_note
low_noise_policy_version
```

### Rules

```text
NoPing is not proof that a device is dead.
NoTcp is not proof that a device is dead.
DNS failure is not proof that a device is absent.
Reached is not identity proof.
Candidate discovery is not identity proof.
Fresh reachability or identity evidence should reduce repeated probing.
If retrying is justified, prefer a different time/day over immediate repeated probes.
Use scripts/SasLowNoisePolicy.psm1 instead of duplicating retry constants.
```

## Sprint B1 — English Report Renderer

**Branch:** `feat/english-report-renderer`  
**Primary API:** `report.generate_from_artifacts`  
**Owned scope:** fixture-only report rendering from JSON/artifact registries  
**Forbidden scope:** no live evidence, no network commands, no target mutation  
**Expected artifacts:** schemas, renderer, fixture report, tests

### Read first

```text
docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md
docs/HARNESS_COMPLETION_PLAN.md
docs/LOCAL_DEVELOPMENT_HARNESS.md
harness/api/sas-harness-api.json
scripts/SasRunContext.psm1
Tests/survey/test_local_harness_contracts.py
```

### Mission

Implement English-readable report rendering from structured JSON and artifact registries. The report is a rendering of facts, not a new source of truth.

Target shape:

```text
structured JSON
  + artifact registry
  + report template
  -> English-readable report
  -> operator handoff
  -> next-action decision
```

### Required report sections

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

### Deliverables

```text
schemas/harness/run-event.schema.json
schemas/harness/operator-report.schema.json
scripts/Render-SasEnglishReport.ps1
Tests/fixtures/harness/reports/operator_report_input.json
Tests/fixtures/harness/reports/artifact_registry.json
Tests/fixtures/harness/reports/operator_report.md
Tests/fixtures/harness/reports/operator_handoff.txt
```

### Report rules

```text
JSON owns variables.
Artifacts own evidence.
Templates own wording.
Reports own the human-readable explanation.
Avoid raw dumps.
Avoid hiding uncertainty.
Avoid stealth / no-trace / bypass language.
Do not run network commands in renderer tests.
```

## Sprint B2 — Standard CMD/PowerShell Command Renderers

**Branch:** `feat/standard-command-renderers`  
**Primary APIs:** `standard_probe.render_cmd`, `standard_probe.render_powershell`  
**Owned scope:** render-only command plans for approved single-target checks  
**Forbidden scope:** do not execute rendered commands, no broad subnet sweep, no live evidence committed  
**Expected artifacts:** renderer script/module, command plan fixtures, tests

### Read first

```text
docs/STANDARD_CORPORATE_SURVEY_TOOLING.md
harness/api/sas-harness-api.json
mcp/local/servers.json
Tests/survey/test_standard_corporate_tooling_contracts.py
```

### Required CMD examples

```bat
ping -n 1 -w 750 HOSTNAME
nslookup HOSTNAME
arp -a
tracert -d -h 3 HOSTNAME
```

### Required PowerShell examples

```powershell
Resolve-DnsName -Name HOSTNAME -ErrorAction SilentlyContinue
Test-Connection -ComputerName HOSTNAME -Count 1 -Quiet
Test-NetConnection -ComputerName HOSTNAME -Port 445
Get-NetNeighbor -AddressFamily IPv4
```

### Required warning

Rendered plans must include wording equivalent to:

```text
Render-only command plan. Operator review and execution required. This script does not execute probes automatically. Do not use for blind subnet sweeps.
```

## Sprint B3 — Location/Subnet Map and Signature Candidate Planner

**Branch:** `feat/location-subnet-candidates`  
**Owned scope:** local planning/classification only  
**Forbidden scope:** no subnet probing, no live subnet scan, no target mutation  
**Expected artifacts:** location/subnet schema, planner, candidate CSV, summary JSON, tests

### Required schema

```csv
Site,Location,Building,Floor,SubnetCIDR,Gateway,SourceEvidence,LastVerified,SurveyAllowed,Confidence,Notes
```

### Allowed signature sources

```text
Known Cybernet hostname/naming pattern
Known MAC vendor/OUI evidence
Known service expectations from prior approved probes
Location constraints from tracker/install notes/subnet map
```

### Rules

```text
Subnet must be tied to a known location.
SurveyAllowed must be yes or review must be explicit.
Search must be bounded by documented Cybernet signatures.
Do not broaden beyond approved subnet, location, or target class.
Candidate discovery is not identity proof.
Do not probe.
```

## Sprint C0 — End-to-End Harness Validator

**Branch:** `feat/validate-sysadmin-harness`  
**Owned scope:** synthetic fixture-only harness proof  
**Forbidden scope:** no live data, no network execution in planner phases  
**Expected artifacts:** validator script, PASS/FAIL matrix, fixture validation tests

### Suggested file

```text
scripts/validate-sysadmin-harness.ps1
```

### Required validation sequence

```text
1. validate target folder policy
2. validate canonical run context
3. validate artifact registry
4. validate low-noise policy module
5. run serial preflight against fixtures
6. run target reduction against fixtures
7. render English handoff/report from fixture JSON
8. render standard command plan without execution
9. run dashboard/parser smoke for serial outputs if dashboard parser exists
10. run live-data-risk audit in advisory mode against safe fixtures
11. assert no network commands ran in planner phases
12. print PASS/FAIL matrix
```

### Expected output style

```text
SYSADMIN HARNESS VALIDATION

[PASS] target folder policy
[PASS] canonical run context
[PASS] artifact registry
[PASS] low-noise policy module
[PASS] serial preflight fixture run
[PASS] target reduction fixture run
[PASS] English report renderer
[PASS] standard command renderer
[PASS] dashboard serial output parser
[PASS] live-data audit advisory mode
[PASS] planner phases performed no network execution

Result: 11/11 passed
```

## Sprint C1 — Probe Results Report

**Branch:** `feat/probe-results-report`  
**Owned scope:** local report generation from prior probe/preflight artifacts  
**Forbidden scope:** no probes, no target mutation, no live data committed  
**Expected artifacts:** fixture prior-probe input, Markdown report, summary JSON, tests

### Report must answer

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

### Required wording constraints

The report must not say:

```text
non-reached devices are dead
reached devices are serial-confirmed
candidate devices are confirmed Cybernets
```

The report must preserve:

```text
Reached is not identity proof.
Non-reached is not dead.
Candidate discovery is not identity proof.
```

## Sprint C2 — Dashboard Serial Controls Integration

**Branch:** `feat/dashboard-serial-controls`  
**Owned scope:** dashboard reads existing harness artifacts and renders next command/handoff  
**Forbidden scope:** dashboard must not invent targets, bypass harness APIs, or execute probes directly  
**Expected artifacts:** dashboard parser, UI sections, fixture smoke tests

### Dashboard should show

```text
serial count
probe-ready target count
review-required count
reduced targets
retry candidates
location/subnet candidates
network activity status
English operator handoff
next recommended command
artifact list
last run identity
uncertainty buckets
```

### Rules

```text
UI loads artifacts.
UI does not invent target lists.
UI does not execute probes directly.
UI shows uncertainty buckets.
UI preserves reached is not identity proof.
UI preserves non-reached is not dead.
CMD/PowerShell alternatives should be available where standard corporate tooling docs allow them.
```

## Sprint A1 — Probe Executor Guardrail Expansion

**Branch:** `test/probe-executor-boundaries`  
**Owned scope:** static contracts only  
**Forbidden scope:** do not add probing capability  
**Expected artifacts:** new/expanded guardrail tests, allowlist, required-fragment checks

### Target patterns to classify carefully

```text
subprocess running naabu/nmap/nc/ncat
PowerShell Test-Connection
PowerShell Test-NetConnection
PowerShell Resolve-DnsName
direct shell invocation of probe tools
```

### Rules

```text
Avoid false positives from docs.
Avoid false positives from examples.
Avoid false positives from render-only scripts.
Avoid false positives from parsers.
Avoid false positives from installers.
Approved executor surfaces must be explicitly allowlisted.
Render-only helpers must declare that they do not execute.
Any newly approved executor surface must name low-noise controls and local evidence behavior.
Do not weaken existing socket contract.
```

## Sprint A2 — Local Harness Hook Proof

**Branch:** `test/local-harness-hooks-proof`  
**Owned scope:** prove hook installer and hook contracts  
**Forbidden scope:** no live evidence, no network probes, no mutation of real developer Git config outside fixture  
**Expected artifacts:** hook tests, temp repo/mocked fixture, docs update

### Deliverables

Add tests proving:

```text
hook files exist
hook files contain required checks
installer sets core.hooksPath=.githooks in a temporary fixture repo or mockable local path
generated evidence path blocking can be demonstrated without committing real evidence
tests do not mutate real developer Git config
```

Document local usage:

```bash
bash scripts/install-local-harness-hooks.sh
```

## Sprint A3 — MCP/LSP Code-Intelligence Plan

**Branch:** `docs/mcp-lsp-code-intelligence-plan`  
**Owned scope:** read-only planning and skeleton validation  
**Forbidden scope:** no live evidence reads, no target mutation, no network probing  
**Expected artifacts:** code-intelligence plan doc, optional README, static read-only contract

### Planned read-only tools

```text
where_is_command
find_survey_workflows
find_artifact_schema
find_policy_source
find_contract_for_surface
outline_powershell_script
outline_dashboard_parser
```

### Rules

```text
Read-only first.
Prefer tracked docs/code/contracts.
Never read ignored live evidence by default.
Never expose secrets or generated operational artifacts.
Make harness navigation deterministic.
Every tool must map to a documented MCP catalog entry or future API manifest entry.
```

## Sprint D0 — Local MCP Server Skeletons

**Branch:** `feat/local-mcp-skeletons`  
**Owned scope:** read-only/local-transform MCP skeletons only  
**Forbidden scope:** no network probing, no credential access, no target mutation, no reading ignored live evidence by default  
**Expected artifacts:** MCP server skeleton files, manifest loader, tests, startup docs

### Initial planned servers

```text
sas-target-reduction
sas-standard-tools
sas-evidence-reporter
```

### Suggested paths

```text
harness/mcp/target_reduction_server.py
harness/mcp/standard_tools_server.py
harness/mcp/evidence_reporter_server.py
harness/mcp/common.py
```

### Required tools

```text
mcp.catalog.list
standard_probe.render_cmd
standard_probe.render_powershell
report.generate_from_artifacts
target_reduction.plan
```

### Rules

```text
Servers must default to tracked docs/code/fixtures.
Do not read ignored live evidence unless explicitly passed an approved local path.
Do not execute probe commands.
Do not mutate targets.
Do not collect credentials.
Every exposed tool must map to an operation in harness/api/sas-harness-api.json.
Add a validation handshake that prints allowed APIs and posture.
```

## Required final report template for sprint agents

Every serious sprint response must end with:

```text
Completed work
Verification
Gaps / risks
Important paths
Git state
Next command
Copy-paste handoff prompt
```

The handoff prompt should include branch, lane, owned scope, forbidden scope, modified files, validation already run, skipped checks, and the next file or command the following agent should inspect.

## Next launch prompt: A0 Canonical Run Context

```text
You are continuing SysAdminSuite.

Repo: EndeavorEverlasting/SysAdminSuite
Sprint: A0 — Canonical Run Context and Artifact Registry
Branch: create feat/harness-run-context
Lane: harness spine
Owned scope: local run-directory creation, workflow ID validation, artifact registry helpers
Forbidden scope: no network execution, no live evidence committed, no dashboard changes unless needed for docs references
Expected artifacts:
- scripts/SasRunContext.psm1
- run context fixture
- artifact registry fixture
- run context tests
- docs/contracts update only if needed

Read first:
- docs/HARNESS_COMPLETION_PLAN.md
- docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md
- docs/LOCAL_DEVELOPMENT_HARNESS.md
- scripts/SasTargetIntake.psm1
- harness/api/sas-harness-api.json
- Tests/survey/test_local_harness_contracts.py

Mission:
Create the canonical harness run context layer so SysAdminSuite stops scattering unlinked outputs.

Target shape:
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

Survey ignored output root:
survey/output/runs/<workflow_id>/

Implement:
- New-SasRunId
- Test-SasWorkflowId
- New-SasRunContext
- New-SasArtifactRegistry
- Register-SasArtifact
- Get-SasRunSummaryPath
- Resolve-SasOutputRoot
- Assert-SasLocalOutputRoot

Artifact registry entries must include:
- role
- path
- tracked
- live_data
- description
- source_artifact
- network_activity
- created_at

Rules:
- Every run starts from a request or source artifact.
- Every run has a run ID.
- Every artifact must have role, path, tracked flag, live-data flag, description, source artifact, and network activity declaration.
- Real run outputs stay local/ignored.
- Do not run network commands.
- Do not commit live evidence.

Validation:
- Run offline survey tests.
- Run Pester if PowerShell tests are present or added.
- Run survey doctrine or the repo's documented local equivalent.
- Show git diff and git status.

Final response must include:
- Completed work
- Modified files
- Generated fixture artifacts
- Validation commands run
- Validation output summary
- Skipped checks
- Gaps / risks
- Git diff summary
- Git status
- Next recommended sprint
- Copy-paste handoff prompt
```
