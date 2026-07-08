# SysAdminSuite Launch Guide and Documentation Index

Start here when you need to know which local surface to use.

## Human entrypoints

| Goal | Use |
|---|---|
| Open the dashboard | `START-HERE-SysAdminSuite-Dashboard.bat` |
| Create or enter the PR #142 harness-foundation worktree | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Run the full Bash harness contract suite | `Run-HarnessContracts.cmd` |
| Run the synthetic harness validator | `Run-HarnessValidation.cmd` |
| Render fixture English reports | `Run-EnglishReportFixture.cmd` |
| Print harness output locations | `Run-ExportHarnessEvidence.cmd` |

## Implementation paths

| Surface | Implementation |
|---|---|
| PR #142 worktree bootstrap | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Harness contract suite | `Run-HarnessContracts.cmd` -> `Tests/bash/run_harness_contracts.sh` |
| Harness validation | `scripts/run-harness-validation.sh` -> `scripts/validate-sysadmin-harness.ps1` |
| English report rendering | `scripts/render-english-report-fixtures.sh` -> `scripts/Render-SasEnglishReport.ps1` |
| Evidence path summary | `scripts/show-harness-evidence-paths.sh` |
| Workflow specs | `survey/workflows/` |
| Synthetic fixtures | `survey/fixtures/` |
| Harness schemas | `schemas/harness/` |

## Agent start points

| Question | Read |
|---|---|
| AI harness doctrine | `docs/AI_LAYER_HARNESS_TOOLING_PLAN.md` |
| Parallel-agent coordination | `docs/handoff/sysadminsuite-agent-coordination.md` |
| English report variables | `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` |
| Local harness usage | `docs/LOCAL_DEVELOPMENT_HARNESS.md` |
| Harness plan | `docs/plans/executable-ai-harness-foundation.plan.md` |

## Cheat sheet

```text
Dashboard: START-HERE-SysAdminSuite-Dashboard.bat
Bootstrap: scripts/Ensure-Pr142HarnessFoundationWorktree.ps1
Contracts: Run-HarnessContracts.cmd
Harness:   Run-HarnessValidation.cmd
Reports:   Run-EnglishReportFixture.cmd
Evidence:  Run-ExportHarnessEvidence.cmd
Docs:      docs/launch-and-doc-index.md
Agents:    docs/handoff/sysadminsuite-agent-coordination.md
```

## Rules

- Use synthetic fixtures for tracked harness proof.
- Keep generated run output out of normal commits unless it is intentionally sanitized.
- Keep PowerShell as active Windows tooling.
- Preserve Bash-first survey conventions for new Northwell-oriented work.
- Bootstrap scripts must create the expected local directory/worktree when it is missing instead of assuming the operator is already inside it.
