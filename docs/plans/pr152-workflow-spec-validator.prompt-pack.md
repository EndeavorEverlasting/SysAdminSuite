# PR #152 next harness feature plan: workflow spec validator

Date: 2026-07-08

## Decision

The next feature sprint after PR #142 should be a small, fixture-backed workflow-spec validator.

Recommended PR lane:

```text
PR #152 - feat(harness): add workflow spec validator
Branch: feat/harness-workflow-spec-validator
Mode: local_read + local_transform only
Network activity: none
Target mutation: none
```

Why this is the next slice:

- PR #142 introduces the executable harness foundation, workflow specs, schemas, fixture-backed English reports, command surfaces, and validators.
- The workflow YAML files are the narrowest next seam because they can be validated without implementing target reduction, probing, deployment, or dashboard behavior.
- Existing open PRs already own target reduction, low-noise policy, Windows log classification, manifest deployment, and software install work. This lane must not collide with them.

## Evidence reviewed

| Evidence | How this plan uses it |
|---|---|
| `docs/handoff/pr142-scope-ledger.md` | Keeps PR #142 behavior frozen and treats run context, target reduction, low-noise policy, Windows logs, and deployment as non-owned lanes. |
| `docs/plans/executable-ai-harness-foundation.plan.md` | Selects the listed next-slice candidate: fixture-backed workflow-spec validator. |
| `docs/launch-and-doc-index.md` | Preserves the Windows operator path and PR #142 command-surface pattern. |
| `survey/workflows/serial-to-preflight.yaml` | Validates local-read, local-transform, local-write, local-render nodes and no-network planner posture. |
| `survey/workflows/network-preflight.yaml` | Allows only explicit bounded-probe nodes to declare network activity, but does not execute them. |
| `survey/workflows/serial-iteration.yaml` | Validates time-diverse retry planning stays local-transform only. |
| `schemas/harness/run-event.schema.json` | Reuses required run-event fields for validator summary output. |
| `schemas/harness/artifact-registry.schema.json` | Reuses artifact registry shape and artifact role discipline. |
| `schemas/harness/operator-report.schema.json` | Reuses English report summary fields and next-action fields. |
| `scripts/Invoke-SasHarnessContracts.ps1` | Future PR should wire the validator into this runner only after PR #142 has merged or the branch is intentionally stacked. |
| `scripts/validate-sysadmin-harness.ps1` | Future PR should add a synthetic validator check, not runtime probing. |
| `scripts/SasRunContext.psm1` | Consume only after PR #146 has merged; do not edit it in this lane. |
| `harness/api/sas-harness-api.json` | Reuse operation posture: local-only by default, no target mutation, explicit modes. |
| `docs/LOCAL_DEVELOPMENT_HARNESS.md` | Preserve harness doctrine that reports come from local artifacts and do not invent certainty. |

## Open PR map and collision rules

| PR | Lane | Rule for PR #152 |
|---|---|---|
| #142 | executable AI harness foundation | Do not modify its behavior. Wait for merge or intentionally stack after approval. |
| #144 | low-noise Cybernet port fallback policy | Do not change port policy or `scripts/SasLowNoisePolicy.psm1`. |
| #147 | target reduction planner | Do not implement or claim `target_reduction.plan`. |
| #149 | Windows log classification system | Do not add log taxonomy or classifier behavior. |
| #150 | manifest-driven deployment | Do not add deployment execution behavior. |
| #151 | software install operator lane | Do not add install or remote cleanup behavior. |
| #146 | canonical run context module, merged | Consume the module only; do not edit `scripts/SasRunContext.psm1`. |

## PR #152 owned scope

Add a validator that proves workflow specs are internally consistent and harness-safe.

Owned surfaces for the future PR:

- `schemas/harness/workflow-spec.schema.json`
- `scripts/Test-SasWorkflowSpecs.ps1`
- `Tests/bash/test_workflow_spec_contracts.sh`
- `Tests/Pester/WorkflowSpec.Tests.ps1`
- optional fixtures under `survey/fixtures/workflow-spec/`
- optional renderer fixture summary under `survey/fixtures/english-log/` if the validator emits an English report fixture
- minimal wiring in `scripts/Invoke-SasHarnessContracts.ps1` and `scripts/validate-sysadmin-harness.ps1` after PR #142 is merged or intentionally stacked

The validator should check:

- every workflow declares `schema_version`, `workflow_id`, `name`, `inputs`, `nodes`, `artifacts`, `validation`, `next_actions`, `network_activity_policy`, and `target_mutation_policy`;
- every node declares `id`, `kind`, `description`, `inputs`, `outputs`, `network_activity`, `target_mutation`, and `validation`;
- planner workflows do not mark local-read, local-transform, local-write, or local-render nodes as network-active;
- bounded-probe nodes may only appear in explicitly probe-bearing workflows and still must set `target_mutation: false`;
- artifact names are stable and map cleanly to artifact registry roles;
- workflow IDs are valid for `New-SasRunContext` after PR #146 is consumed;
- no workflow spec contains live-looking hostnames, private IPs, MAC addresses, serials, or generated runtime evidence;
- no validator code invokes `ping`, `Test-Connection`, `Test-NetConnection`, `Resolve-DnsName`, `nmap`, `naabu`, sockets, deployment commands, log mutation commands, or target-side writes.

## PR #152 forbidden scope

- Do not edit `scripts/SasRunContext.psm1`.
- Do not implement target reduction planner behavior.
- Do not execute network preflight or live probing.
- Do not add deployment, software install, or Windows log classifier behavior.
- Do not create a dashboard feature.
- Do not add generated runtime evidence to the repo.
- Do not broaden PR #142 or move files across existing PR lanes.

## Expected outputs from PR #152

The future validator may emit only local, gitignored output such as:

```text
survey/output/workflow-spec-validator/<run_id>/workflow_spec_validation_summary.json
survey/output/workflow-spec-validator/<run_id>/artifact_registry.json
survey/output/workflow-spec-validator/<run_id>/operator_handoff.txt
survey/output/workflow-spec-validator/<run_id>/workflow_spec_validation_report.md
```

Tracked fixtures may use sanitized workflow examples only.

## Validation for PR #152

Required local validation:

```bash
git diff --check
bash Tests/bash/test_workflow_spec_contracts.sh
bash tests/survey/run_offline_survey_tests.sh
```

Required Windows validation:

```powershell
pwsh -NoProfile -File .\scripts\Test-SasWorkflowSpecs.ps1 -WorkflowRoot .\survey\workflows
pwsh -NoProfile -Command "Invoke-Pester -Path .\Tests\Pester\WorkflowSpec.Tests.ps1 -CI"
pwsh -NoProfile -File .\scripts\Invoke-SasHarnessContracts.ps1
pwsh -NoProfile -File .\scripts\validate-sysadmin-harness.ps1
```

Skipped validation should be listed explicitly in the PR body. No runtime validation is required unless scripts are changed, and even then the runtime must stay local-only.

## Parked future lanes

Keep these separate. Do not fold them into PR #152.

| Future PR lane | Owned scope | Forbidden scope |
|---|---|---|
| Operator report index viewer | Read local report summaries and artifact registries, then render a local index or dashboard-friendly JSON. | No dashboard rewrite, no live probing, no target mutation, no deployment. |
| Schema/API normalization | Add compatibility mirrors or docs for stable schema/API paths if needed after PR #142 merges. | No behavior changes and no migration that breaks existing scripts. |
| Local reference cache docs | Document how to keep Archon/Helpline as external reference inputs without vendoring them. | Do not clone, fork, or commit external repos into SysAdminSuite. |

## Recommended next execution prompt

```text
EXECUTE THE REPO SPRINT. DO NOT REWRITE THIS PROMPT.

Repo:
EndeavorEverlasting/SysAdminSuite

Branch:
feat/harness-workflow-spec-validator

Base:
main after PR #142 merges, unless explicitly instructed to stack on PR #142.

Lane:
Workflow-spec validator feature sprint

Owned scope:
- Add a fixture-backed, local-only workflow-spec validator.
- Validate `survey/workflows/*.yaml` against harness safety contracts.
- Reuse schemas, artifact registry shape, English report summary fields, run-context workflow-id rules, and harness command surfaces.
- Add focused Bash and Pester/static tests.
- Wire into harness contracts only after PR #142 surfaces are available on the branch.

Forbidden scope:
- Do not edit `scripts/SasRunContext.psm1`.
- Do not implement target reduction planner behavior.
- Do not execute live probing, deployment, software install, or Windows log classification.
- Do not add generated runtime evidence.
- Do not broaden PR #142.

Read first:
- docs/plans/pr152-workflow-spec-validator.prompt-pack.md
- docs/handoff/pr142-scope-ledger.md
- docs/launch-and-doc-index.md
- survey/workflows/
- schemas/harness/
- harness/api/sas-harness-api.json
- scripts/Invoke-SasHarnessContracts.ps1
- scripts/validate-sysadmin-harness.ps1
- scripts/SasRunContext.psm1

Validation:
- git diff --check
- bash Tests/bash/test_workflow_spec_contracts.sh
- bash tests/survey/run_offline_survey_tests.sh
- pwsh -NoProfile -File .\scripts\Test-SasWorkflowSpecs.ps1 -WorkflowRoot .\survey\workflows
- pwsh -NoProfile -Command "Invoke-Pester -Path .\Tests\Pester\WorkflowSpec.Tests.ps1 -CI"

Final handoff:
Report changed files, generated local outputs, validation output, skipped checks, risks, git state, commit SHA, pushed yes/no, and next command.
```
