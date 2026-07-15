# SysAdminSuite Codebase Map

Use this map to load only the files needed for a task.

## Agent instruction architecture

- `AGENTS.md` — compact universal invariants and task-to-skill router; keep detailed procedures out of this file.
- `CLAUDE.md` — progressive-disclosure front door for Claude-compatible agents.
- `.claude/skills/*/SKILL.md` — task workflows that compose reusable capabilities.
- `.claude/capabilities/*.md` — stable atomic rules shared by multiple skills.
- `harness/api/agent-capability-manifest.json` — machine-readable skill/capability catalog and dependency graph.
- `schemas/harness/agent-capability-manifest.schema.json` — fail-closed catalog schema.
- `tools/validate-ai-layer.ps1` — validates the instruction architecture, required safety language, and local-data exclusions.
- `Tests/survey/test_agent_instruction_factoring_contracts.py` — dependency-free factoring and anti-bloat contract.
- `Tests/survey/test_agent_capability_manifest_contracts.py` — machine-readable catalog contract.

## End-to-end validation

- `docs/END_TO_END_TESTING_POSTURE.md` — default merge/release proof posture and E2E safety classes.
- `docs/SOFTWARE_INSTALL_E2E.md` — fixture software-install proof, deltas, logs, artifacts, and proof ceiling.
- `.claude/skills/end-to-end-validation/SKILL.md` — task workflow for composed integration and runtime gates.
- `.claude/capabilities/end-to-end-testing.md` — reusable E2E invariants.
- `harness/e2e/e2e-profiles.json` — default fixture/loopback journey catalog.
- `schemas/harness/e2e-validation-profiles.schema.json` — E2E profile schema.
- `scripts/Invoke-SasEndToEndValidation.ps1` — one-command E2E gate and evidence emitter.
- `scripts/Invoke-SasSoftwareInstallE2E.ps1` — runs the real operator wrapper and installer process against an isolated fixture target.
- `Tests/survey/test_e2e_default_posture_contracts.py` — default-posture, software-install, and profile contract.
- `.github/workflows/default-e2e-validation.yml` — executable default E2E CI gate.

## Developer workstation

- `docs/tutorials/DEVELOPER_WORKSTATION.md` — canonical operator and developer tutorial: inventory, plan, apply, launch, verify, rollback, proof interpretation.
- `docs/DEVELOPER_WORKSTATION_PROVISIONING.md` — bimodal Windows/Linux profile contract, ownership boundary, safety posture, proof ceiling.
- `docs/DEVELOPER_WORKSTATION_INVENTORY.md` — read-only inventory surface, detected fields, reason codes, fixtures, proof ceiling.
- `docs/DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md` — 12-journey validation matrix and merge readiness.
- `docs/DEVELOPER_WORKSTATION_CONVERGENCE_REPORT.md` — PR stack, merge order, superseded branches, unresolved checks.
- `Config/developer-workstation-profile.sample.json` — canonical v2 profile: bimodal platform support, WezTerm required, WSL optional.
- `Config/wezterm-windows.lua.template` — WezTerm Lua template with managed-block placeholders.
- `schemas/harness/developer-workstation-profile.schema.json` — profile schema (fail-closed, `additionalProperties: false`).
- `schemas/harness/developer-workstation-inventory.schema.json` — inventory schema.
- `schemas/harness/developer-workstation-proof.schema.json` — E2E proof result schema.
- `scripts/Get-SasDeveloperWorkstationInventory.ps1` — Windows read-only inventory collector.
- `scripts/get-sas-developer-workstation-inventory.sh` — Linux read-only inventory collector.
- `scripts/Render-SasWorkstationInventoryEnglish.py` — dependency-free English summary renderer.
- `scripts/Invoke-SasWezTermWindowsNativeProfile.ps1` — Windows WezTerm Plan/Apply/Rollback orchestrator.
- `scripts/Invoke-SasWorkstationE2E.ps1` — 12-journey bimodal E2E executor.
- `Launch-WorkstationWezTerm.ps1` / `Launch-WorkstationWezTerm.cmd` — Windows workspace launcher.
- `configs/linux-native/wezterm-linux-template.lua` — Linux-native WezTerm Lua module.
- `configs/linux-native/sas-bashrc.sh` — SysAdminSuite bash fragment for Linux.
- `configs/linux-native/tmux-linux.conf` — SysAdminSuite tmux fragment for Linux.
- `Tests/survey/test_developer_workstation_profile_contracts.py` — 9 profile contract tests.
- `Tests/survey/test_developer_workstation_inventory_contracts.py` — 5 inventory contract tests.
- `Tests/survey/test_wezterm_windows_native_contracts.py` — 4 WezTerm Windows-native contract tests.
- `Tests/survey/test_developer_workstation_proof_contracts.py` — 4 E2E proof contract tests.
- `Tests/Pester/WezTermWindowsNativeProfile.Tests.ps1` — Pester tests for Windows WezTerm profile.
- `Tests/Pester/DeveloperWorkstationInventory.Tests.ps1` — Pester tests for inventory collector.
- `Tests/Fixtures/workstation-inventory/*.json` — 6 inventory fixture files.
- `.github/workflows/developer-workstation-inventory.yml` — inventory CI workflow.
- `.github/workflows/wezterm-windows-native-profile.yml` — WezTerm profile CI workflow.

## Repo doctrine

- `README.md` — user entrypoint, repo layout, runtime policy, and local source folder policy.
- `docs/HARNESS_COMPLETION_PLAN.md` — AI harness completion sequencing; load for harness work, not every task.
- `docs/PYDANTIC_AI_CAPABILITY_ADAPTER_DECISION.md` — boundary for capability-oriented adapters; repo-local skills/capabilities remain authoritative.
- `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` — future English report/run-context artifact contract.
- `docs/OPERATIONAL_POSTURE.md` — lane model for survey, dashboard probes, deployment, mapping, and teardown.
- `docs/HARNESS_DISCIPLINE.md` — full repository mutation and PR/worktree operation contract.
- `docs/LOCAL_REFERENCE_POLICY.md` — gitignored operator-local reference rules.

## Cybernet power and display-button control

- `docs/CYBERNET_POWER_HARDENING.md` — operator contract, proof ceilings, pilot sequence, and rollback guidance for Windows power-button and MCCS display-button control.
- `scripts/Invoke-SasCybernetPowerHardening.ps1` — bounded network lane for the Windows physical power-button action.
- `scripts/Invoke-SasCybernetDisplayButtonControl.ps1` — bounded Probe, Apply, and Restore lane for MCCS 2.2 VCP `0xCA` display-controller buttons.
- `scripts/SasDdcciMonitorControl.cs` — repo-owned Windows Monitor Configuration API helper with eligibility, readback, and rollback enforcement.
- `QRTasks/Test-DisplayMenuButtonEvent.ps1` — read-only local Windows-event probe; it does not apply DDC/CI changes.
- `Tests/Pester/CybernetPowerHardening.Tests.ps1` and `Tests/Pester/CybernetDisplayButtonControl.Tests.ps1` — Windows parser, compilation, and mutation-boundary contracts.
- `Tests/survey/test_cybernet_power_hardening_contracts.py` and `Tests/survey/test_cybernet_display_button_control_contracts.py` — dependency-free contract checks.
- `.github/workflows/cybernet-power-hardening.yml` and `.github/workflows/cybernet-display-button-control.yml` — executable Windows fixture gates.

## Survey and low-noise files

- `survey/README.md` — Bash-on-Windows survey entrypoints and field command standards.
- `survey/naabu_profiles.json` — doctrine source for approved Naabu profiles.
- `Config/cybernet-naabu-profiles.json` — generated runtime profile config.
- `survey/sas-run-naabu-pipeline.sh` and `survey/sas-run-packet-probe.sh` — preferred packet-probe wrappers.
- `docs/LOW_NOISE_SURVEY_DOCTRINE.md` — narrative low-noise policy.
- `docs/SURVEY_LANES.md` and `targets/README.md` — local target intake and tracked fixture boundaries.

## Dashboard and field entry

- `docs/DASHBOARD_ENTRYPOINT.md` — canonical field and IT/developer launcher guidance.
- `START-HERE-SysAdminSuite-Dashboard.bat` — field-user dashboard launcher.
- `Launch-SysAdminSuiteDashboard.Host.bat` — IT/developer dashboard launcher.
- `dashboard/test_relay_cancel_e2e.py` — real relay cancellation journey over loopback.
- `dashboard/test_relay_abort_e2e.js` — real relay/client abort journey over loopback.

## Validation and tests

- `tools/validate-ai-layer.ps1` — PowerShell validator for the AI harness layer.
- `tests/survey/run_offline_survey_tests.sh` — offline survey/harness contract runner.
- `tests/bash/` — Bash contract and smoke tests.
- `Tests/Pester/` — PowerShell test suite for Windows tooling.
- `SysAdminSuite.sln` and `managed-tests/` — .NET validation surface.

## Local data boundaries

- `targets/local/`, `logs/targets/`, `survey/input/`, `survey/output/`, `survey/artifacts/`, `logs/nmap/`, and `Mapping/Output/GuiRuns/` are local/evidence areas unless a tracked sample path explicitly says otherwise.
- Tracked examples belong under approved sanitized, fixture, sample, or template paths.
