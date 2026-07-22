# SysAdminSuite Launch Guide and Documentation Index

Start here when you need to know which local surface to use.

## Human entrypoints

| Goal | Use |
|---|---|
| Configure one Cybernet with hardware preferences and approved software | `Run-CybernetClientConfiguration.cmd Help` → `Plan` → `Apply` → technician acceptance → `Validate` |
| Read the complete Cybernet operator tutorial | `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md` |
| Troubleshoot a Cybernet combined run or restore display-button state | `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md` |
| Configure Cybernet hardware only | `Run-CybernetBatchConfiguration.cmd` and `Hardware/Cybernet/README.md` |
| Start Cybernet software-only deployment | `START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md` |
| Open the dashboard | `START-HERE-SysAdminSuite-Dashboard.bat` |
| Run the canonical browser software-deployment tutorial | Dashboard → **Start Software Deployment** |
| Open the browser deployment tutorial directly | `http://127.0.0.1:5000/dashboard/?tutorial=software-deployment` |
| Read the supporting generic deployment runbook | `docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md` |
| Create or enter the PR #142 harness-foundation worktree | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Run the full harness contract suite on Windows | `Run-HarnessContracts.cmd` |
| Run the synthetic harness validator | `Run-HarnessValidation.cmd` |
| Render fixture English reports | `Run-EnglishReportFixture.cmd` |
| Print harness output locations | `Run-ExportHarnessEvidence.cmd` |

## Cybernet operating-surface boundary

| Surface | Current role |
|---|---|
| Windows admin workstation or approved admin VM | Runs the composed Cybernet PowerShell workflow and reviews evidence. |
| Git Bash on that Windows controller | Internal approved package-set stage launched by the composed PowerShell workflow. |
| Browser dashboard | Generic software-only tutorial; it does not apply Cybernet hardware policy. |
| Cybernet target | Technician application acceptance, separately gated local COM repair, and separately authorized reboot observation. |
| Native Linux/macOS | Not a current execution surface for the composed Cybernet client configuration. |

## Implementation paths

| Surface | Implementation |
|---|---|
| Cybernet complete one-target launcher | `Run-CybernetClientConfiguration.cmd` |
| Cybernet complete PowerShell controller | `Hardware/Cybernet/Invoke-CybernetClientConfiguration.ps1` |
| Cybernet client preference profile | `Config/cybernet-client-preferences.json` |
| Cybernet approved package-set catalog | `configs/software-packages/windows-native-package-sets.json` |
| Cybernet operator tutorial | `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md` |
| Cybernet troubleshooting and rollback | `docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md` |
| Cybernet hardware-only reference | `Hardware/Cybernet/README.md` |
| Browser deployment tutorial | `dashboard/js/software-deployment-tutorial.js` |
| Browser approval-state guard | `dashboard/js/software-deployment-input-invalidation.js` |
| Browser tutorial loader | `dashboard/js/launch-repo-setup-tutorial.js` |
| Supporting generic deployment runbook | `docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md` |
| Transport selection contract | `docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md` |
| Deployment transport convergence and public-safe receipt ledger | `docs/handoff/deployment-transport-convergence.md` |
| Transport preflight | `scripts/Test-SasSoftwareDeploymentTransport.ps1` |
| Harmless SMB live certification | `scripts/Invoke-SasSoftwareDeploymentTransportLiveCert.ps1` |
| Public-safe transport proof ingest | `scripts/Invoke-SasTransportProofIngest.ps1` |
| SMB/Task Scheduler compatibility controller | `bash/apps/sas-install-apps.sh` |
| Canonical transport adapter | `scripts/SasSoftwareDeploymentAdapter.psm1` |
| Validated PowerShell deployment front door | `scripts/Invoke-SasValidatedSoftwareDeployment.ps1` |
| Generated dummy installer | `Tests/fixtures/software-install/DummyInstaller.cs` → `scripts/Build-SasSoftwareInstallFixtureExecutable.ps1` |
| Software-install E2E | `scripts/Invoke-SasSoftwareInstallE2E.ps1` → `scripts/Invoke-SasSoftwareInstall.ps1` |
| PR #142 worktree bootstrap | `scripts/Ensure-Pr142HarnessFoundationWorktree.ps1` |
| Windows harness contract suite | `Run-HarnessContracts.cmd` → `scripts/Invoke-SasHarnessContracts.ps1` |
| CI/static Bash harness contract suite | `Tests/bash/run_harness_contracts.sh` |
| Harness validation | `Run-HarnessValidation.cmd` → `scripts/validate-sysadmin-harness.ps1` |
| English report rendering | `Run-EnglishReportFixture.cmd` → `scripts/Render-SasEnglishReport.ps1` |
| Evidence path summary | `Run-ExportHarnessEvidence.cmd` |
| Workflow specs | `survey/workflows/` |
| Synthetic fixtures | `survey/fixtures/` |
| Harness schemas | `schemas/harness/` |

The Cybernet complete workflow is CLI-first because it composes hardware and software authorities. `Plan` is the safe default and performs no target or software-share contact. `Apply` performs hardware Apply/readback, the approved six-package installation with AutoLogon last, cleanup verification, and post-software hardware validation. Technician application acceptance and any restart/AutoLogon observation remain separate human proof.

The dashboard is the canonical technician interface for the generic software-only deployment tutorial. Its wizard starts with the generated-executable fixture dry run, validates one pilot target and relative package path, generates the WhatIf and confirmation-enabled live commands, and requires evidence and approval gates before advancement. Editing pilot-defining inputs revokes copied, reviewed, and approved state.

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
Cybernet complete help: Run-CybernetClientConfiguration.cmd Help
Cybernet complete guide: docs/tutorials/CYBERNET_CLIENT_CONFIGURATION.md
Cybernet troubleshooting: docs/tutorials/CYBERNET_CLIENT_CONFIGURATION_TROUBLESHOOTING.md
Cybernet complete evidence: survey/output/cybernet_hardware/client-configuration-*
Cybernet start page: START-HERE-CYBERNET-SOFTWARE-DEPLOYMENT.md
Dashboard: START-HERE-SysAdminSuite-Dashboard.bat
Generic software deployment UI: http://127.0.0.1:5000/dashboard/?tutorial=software-deployment
Supporting generic deployment runbook: docs/tutorials/SOFTWARE_DEPLOYMENT_DRY_RUN_AND_PILOT.md
Software install E2E: scripts/Invoke-SasSoftwareInstallE2E.ps1
Transport contract: docs/SOFTWARE_DEPLOYMENT_TRANSPORT_CONTRACT.md
Transport convergence: docs/handoff/deployment-transport-convergence.md
Bootstrap: scripts/Ensure-Pr142HarnessFoundationWorktree.ps1
Contracts: Run-HarnessContracts.cmd
Contracts implementation: scripts/Invoke-SasHarnessContracts.ps1
Harness: Run-HarnessValidation.cmd
Reports: Run-EnglishReportFixture.cmd
Evidence: Run-ExportHarnessEvidence.cmd
Docs: docs/launch-and-doc-index.md
Agents: docs/handoff/sysadminsuite-agent-coordination.md
```

## Rules

- Use the composed Cybernet launcher when hardware and software are assigned together.
- Run one authorized Cybernet `Plan` before `Apply`; expand only after technician acceptance.
- Use the browser dashboard for the generic software-only tutorial, not as a substitute for Cybernet hardware configuration.
- Never place passwords in Cybernet commands.
- Keep live target lists and live evidence out of Git.
- Use the exact generated display restore manifest; never invent a VCP factory value.
- Treat COM repair and restart as separate local/reboot-gated workflows.
- Use synthetic fixtures for tracked harness proof.
- Run the dummy-installer E2E before a real generic software-deployment pilot.
- Keep the first live software pilot to one authorized workstation with confirmation enabled.
- Keep generated run output and installer executables out of normal commits unless intentionally sanitized.
- Keep PowerShell as active Windows tooling.
- Keep Bash contract scripts for CI/static parity, but do not make Windows `.cmd` launchers depend on Bash unless the documented workflow explicitly composes the existing Git Bash controller.
- Bootstrap scripts must create the expected local directory/worktree when it is missing instead of assuming the operator is already inside it.
