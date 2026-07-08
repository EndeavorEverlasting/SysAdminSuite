# PR #142 scope ledger

PR #142 is intentionally a broad harness-foundation PR, so its merge risk must be made explicit and auditable.

## Owned lanes

| Lane | Owned surfaces | Notes |
|---|---|---|
| Harness doctrine | `docs/AI_LAYER_HARNESS_TOOLING_PLAN.md`, `docs/plans/executable-ai-harness-foundation.plan.md`, `docs/handoff/sysadminsuite-agent-coordination.md` | Planning and coordination only. |
| Fixture-backed English reports | `scripts/Render-SasEnglishReport.ps1`, `survey/fixtures/english-log/`, `schemas/harness/operator-report.schema.json` | Uses synthetic fixtures only. |
| Harness command surface | `Run-HarnessContracts.cmd`, `Run-HarnessValidation.cmd`, `Run-EnglishReportFixture.cmd`, `Run-ExportHarnessEvidence.cmd`, `scripts/Invoke-SasHarnessContracts.ps1` | Windows entrypoints are PowerShell-native and must not require Bash. |
| Harness validation helpers | `scripts/validate-sysadmin-harness.ps1`, `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1`, `scripts/run-harness-validation.sh`, `scripts/render-english-report-fixtures.sh`, `scripts/show-harness-evidence-paths.sh` | Runner and helper surfaces only; no live probing, cleanup, or target mutation. |
| CI/static parity | `Tests/bash/run_harness_contracts.sh`, `Tests/bash/test_*.sh`, `.github/workflows/harness-contracts.yml` | Bash remains a CI/static parity surface, not a Windows operator dependency. |
| Run-context boundary documentation | `Tests/bash/RUN_CONTEXT_LANE_BOUNDARY.md` | Boundary note only; does not transfer ownership of `scripts/SasRunContext.psm1`. |
| Workflow specs and schemas | `survey/workflows/`, `schemas/harness/` | Declarative contracts only. |
| Local staging and output discovery | `docs/launch-and-doc-index.md`, `docs/evidence/latest/README.md`, `survey/input/README.md`, `survey/output/README.md`, `survey/artifacts/README.md` | Documents local staging and output locations; generated and operator-provided files stay untracked unless sanitized and reviewed. |

## Explicit non-owned lanes

| Non-owned lane | Owner | PR #142 rule |
|---|---|---|
| Canonical run context module | PR #146 | Do not add or modify `scripts/SasRunContext.psm1`; consume the merged module after rebasing. |
| Target reduction planner | PR #147 | Do not claim `target_reduction.plan` implementation. |
| Low-noise port policy | PR #144 | Do not change Cybernet port fallback behavior here. |
| Windows log classifier | PR #149 | Do not add Windows log taxonomy/classifier behavior here. |
| Manifest-driven deployment | PR #150 | Do not add deployment executor behavior here. |

## Merge-risk controls

- Every owned surface must be tied to a validator, contract test, schema, fixture, or launcher.
- Windows .cmd launchers must be PowerShell-native and must not depend on Git Bash or WSL.
- Bash contract scripts may stay tracked for CI/static parity.
- Fixtures must remain synthetic and must not contain live hostnames, private IP addresses, MAC addresses, serial numbers, crash dumps, or generated runtime evidence.
- The PR must keep run-context ownership out of the harness foundation branch.
- Any future broadening of PR #142 must update this ledger and the scope-boundary contract in the same commit.

## Merge-readiness rule

PR #142 may be treated as reviewable only when:

1. Harness Contracts succeeds on the PR head.
2. Pester succeeds on the PR head.
3. Survey doctrine succeeds on the PR head.
4. Local Windows validation runs `scripts/Invoke-SasHarnessContracts.ps1` or `Run-HarnessContracts.cmd` from the PR #142 worktree.
5. scripts/SasRunContext.psm1 remains outside PR #142-owned changes.
