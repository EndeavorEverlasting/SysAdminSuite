# PR #142 scope ledger

PR #142 is intentionally a broad harness-foundation PR, so its merge risk must be made explicit and auditable.

## Owned lanes

| Lane | Owned surfaces | Notes |
|---|---|---|
| Harness doctrine | `docs/AI_LAYER_HARNESS_TOOLING_PLAN.md`, `docs/plans/executable-ai-harness-foundation.plan.md`, `docs/handoff/sysadminsuite-agent-coordination.md` | Planning and coordination only. |
| Fixture-backed English reports | `scripts/Render-SasEnglishReport.ps1`, `survey/fixtures/english-log/`, `schemas/harness/operator-report.schema.json` | Uses synthetic fixtures only. |
| Harness command surface | `Run-HarnessContracts.cmd`, `Run-HarnessValidation.cmd`, `Run-EnglishReportFixture.cmd`, `Run-ExportHarnessEvidence.cmd`, `scripts/Invoke-SasHarnessContracts.ps1` | Windows entrypoints are PowerShell-native and must not require Bash. |
| CI/static parity | `Tests/bash/run_harness_contracts.sh`, `Tests/bash/test_*.sh`, `.github/workflows/harness-contracts.yml` | Bash remains a CI/static parity surface, not a Windows operator dependency. |
| Workflow specs and schemas | `survey/workflows/`, `schemas/harness/` | Declarative contracts only. |
| Local output discovery | `docs/launch-and-doc-index.md`, `docs/evidence/latest/README.md`, `survey/output/README.md` | Documents local output locations; generated outputs stay untracked unless sanitized. |

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
5. scripts/SasRunContext.psm1 remains absent from this PR branch.
