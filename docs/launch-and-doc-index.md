# SysAdminSuite Launch Guide and Documentation Index

Start here when you need to know which local surface to use.

## Human entrypoints

| Goal | Use |
|---|---|
| Open the dashboard | `START-HERE-SysAdminSuite-Dashboard.bat` |
| Run the synthetic harness validator | `Run-HarnessValidation.cmd` |
| Render fixture English reports | `Run-EnglishReportFixture.cmd` |
| Print harness output locations | `Run-ExportHarnessEvidence.cmd` |

## Implementation paths

| Surface | Implementation |
|---|---|
| Harness validation | `scripts/run-harness-validation.sh` -> `scripts/validate-sysadmin-harness.ps1` |
| English report rendering | `scripts/render-english-report-fixtures.sh` -> `scripts/Render-SasEnglishReport.ps1` |
| Evidence path summary | `scripts/show-harness-evidence-paths.sh` |
| Run context helpers | `scripts/SasRunContext.psm1` |
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
