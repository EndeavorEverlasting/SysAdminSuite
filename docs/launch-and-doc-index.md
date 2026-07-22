# SysAdminSuite Launch Guide and Documentation Index

Start here when you need to know which local surface to use.

## Human entrypoints

| Goal | Use |
|---|---|
| Open the dashboard | `START-HERE-SysAdminSuite-Dashboard.bat` |
| Run the canonical software-deployment tutorial | Dashboard → **Start Software Deployment** |
| Open the deployment tutorial directly | `http://127.0.0.1:5000/dashboard/?tutorial=software-deployment` |
| Read the supporting deployment runbook | `docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md` |
| Run an approved AutoLogon pilot | `docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md` |
| Inspect the latest AutoLogon result safely | `Inspect-LatestAutoLogon.cmd` |
| Create or enter the PR #142 harness-foundation worktree | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Run the full harness contract suite on Windows | `Run-HarnessContracts.cmd` |
| Run the synthetic harness validator | `Run-HarnessValidation.cmd` |
| Render fixture English reports | `Run-EnglishReportFixture.cmd` |
| Print harness output locations | `Run-ExportHarnessEvidence.cmd` |

## Implementation paths

| Surface | Implementation |
|---|---|
| Browser deployment tutorial | `dashboard/js/software-deployment-tutorial.js` |
| Browser tutorial loader | `dashboard/js/launch-repo-setup-tutorial.js` |
| Supporting written runbook | `docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md` |
| Transport selection contract | `docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md` |
| Deployment transport convergence and public-safe receipt ledger | `docs/handoff/deployment-transport-convergence.md` |
| Transport preflight | `scripts/Test-SasSoftwareDeploymentTransport.ps1` |
| Harmless SMB live certification | `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1` |
| Public-safe transport proof ingest | `scripts/Invoke-SasTransportProofIngest.ps1` |
| SMB/Task Scheduler compatibility controller | `bash/apps/sas-install-apps.sh` |
| Canonical transport adapter | `scripts/SasSoftwareDeploymentAdapter.psm1` |
| Validated PowerShell deployment front door | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` |
| Canonical AutoLogon administrator deployment | `scripts/Invoke-SasAutoLogonDeployment.ps1` |
| Public-safe AutoLogon result presenter | `scripts/Show-SasAutoLogonResult.ps1` |
| Signed-in AutoLogon access proof | `scripts/Invoke-SasAutoLogonSessionAccessProof.ps1` |
| AutoLogon technician runtime proof | `scripts/Start-SasAutoLogonTechnicianRuntimeProof.cmd` |
| Dedicated AutoLogon fixture E2E | `scripts/Invoke-SasEndToEndValidation.ps1 -Profile autologon` |
| Generated dummy installer | `Tests/fixtures/software-install/DummyInstaller.cs` -> `scripts/Build-SasSoftwareInstallFixtureExecutable.ps1` |
| Software-install E2E | `scripts/Invoke-SasSoftwareInstallE2E.ps1` -> `scripts/Invoke-SasSoftwareInstall.ps1` |
| PR #142 worktree bootstrap | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Windows harness contract suite | `Run-HarnessContracts.cmd` -> `scripts/Invoke-SasHarnessContracts.ps1` |
| CI/static Bash harness contract suite | `Tests/bash/run_harness_contracts.sh` |
| Harness validation | `Run-HarnessValidation.cmd` -> `scripts/validate-sysadmin-harness.ps1` |
| English report rendering | `Run-EnglishReportFixture.cmd` -> `scripts/Render-SasEnglishReport.ps1` |
| Evidence path summary | `Run-ExportHarnessEvidence.cmd` |
| Workflow specs | `survey/workflows/` |
| Synthetic fixtures | `survey/fixtures/` |
| Harness schemas | `schemas/harness/` |

The dashboard is the canonical technician interface for software deployment. Its eight-stage wizard starts with the generated-executable fixture dry run, validates one pilot target and relative package path, generates the WhatIf and confirmation-enabled live commands, and requires evidence and approval gates before advancement. The Markdown tutorial is the supporting runbook.

The harness validator is a synthetic, offline proof only. One command detects the repo root, records the branch and commit, exercises run-context and artifact-registry creation, renders a fixture report, checks cross-lane API/workflow preservation, runs safe local contracts, reports optional dependencies as `SKIP`, and writes both an English matrix and JSON result under `survey/output/harness-validator/`. It does not launch the dashboard, execute installers, probe a network, or mutate target systems or operator data.

## Agent start points

| Question | Read |
|---|---|
| AI harness doctrine | `docs/AI_LAYER_HARNESS_TOOLING_PLAN.md` |
| Parallel-agent coordination | `docs/handoff/sysadminsuite-agent-coordination.md` |
| BCA one-target runtime floor | `docs/handoff/bca-one-target-runtime-floor.md` |
| Deployment transport convergence | `docs/handoff/deployment-transport-convergence.md` |
| English report variables | `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` |
| Local harness usage | `docs/LOCAL_DEVELOPMENT_HARNESS.md` |
| Harness plan | `docs/plans/executable-ai-harness-foundation.plan.md` |

## Cheat sheet

```text
Dashboard: START-HERE-SysAdminSuite-Dashboard.bat
Software deployment UI: http://127.0.0.1:5000/dashboard/?tutorial=software-deployment
Supporting deployment runbook: docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md
Software install E2E: scripts/Invoke-SasSoftwareInstallE2E.ps1
AutoLogon runbook: docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md
AutoLogon result: Inspect-LatestAutoLogon.cmd
AutoLogon fixture E2E: scripts/Invoke-SasEndToEndValidation.ps1 -Profile autologon
Transport contract: docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md
Transport convergence: docs/handoff/deployment-transport-convergence.md
Bootstrap: scripts/Ensure-Pr142HarnessFoundationWorktree.ps1
Contracts: Run-HarnessContracts.cmd
Contracts implementation: scripts/Invoke-SasHarnessContracts.ps1
Harness:   Run-HarnessValidation.cmd
Reports:   Run-EnglishReportFixture.cmd
Evidence:  Run-ExportHarnessEvidence.cmd
Docs:      docs/launch-and-doc-index.md
Agents:    docs/handoff/sysadminsuite-agent-coordination.md
```

## Rules

- Use the dashboard as the default technician surface; use written runbooks as support and fallback.
- Use synthetic fixtures for tracked harness proof.
- Run the dummy-installer E2E before a real software-deployment pilot.
- Keep the first live software pilot to one authorized workstation with confirmation enabled.
- Keep generated run output and installer executables out of normal commits unless intentionally sanitized.
- Keep PowerShell as active Windows tooling.
- Keep Bash contract scripts for CI/static parity, but do not make Windows `.cmd` launchers depend on Bash.
- Bootstrap scripts must create the expected local directory/worktree when it is missing instead of assuming the operator is already inside it.
