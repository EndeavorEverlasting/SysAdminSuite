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

## Developer workstation provisioning

- `docs/DEVELOPER_WORKSTATION_PROVISIONING.md` — layered WezTerm terminal, tmux workspace, Windows WSL backend, native-Linux backend, PowerShell fallback, and ownership contract.
- `docs/DEVELOPER_WORKSTATION_PR_STACK.md` — preservation, blocking, repair, and supersession decisions for workstation PRs #199–#204.
- `schemas/harness/developer-workstation-profile.schema.json` — fail-closed v3 terminal/workspace/backend/shell/agent-domain contract.
- `Config/developer-workstation-profile.sample.json` — sanitized v3 sample with Windows WSL and native-Linux tmux backends plus Windows PowerShell fallback.
- `Tests/survey/test_developer_workstation_profile_contracts.py` — dependency-free layer, domain, safety, negative-case, discoverability, and optional JSON Schema validation.
- `schemas/harness/developer-workstation-run.schema.json` — canonical workstation operation/run envelope.
- `schemas/harness/developer-workstation-lifecycle-result.schema.json` — lifecycle outcomes, states, reason codes, artifact references, and proof flags.
- `harness/api/developer-workstation-artifact-types.json` — closed artifact role registry; runtime output stays under ignored run roots.
- `Tests/Fixtures/developer-workstation-lifecycle/` — sanitized success, partial, failure, action-required, and unsupported lifecycle fixtures.
- `Tests/survey/test_developer_workstation_lifecycle_contracts.py` — dependency-free lifecycle schema, registry, fixture, API, workflow, and evidence-boundary contracts.
- `scripts/Invoke-SasWindowsTmuxWorkspace.ps1` — Plan/Apply/Start/Status/Stop/Repair/Rollback service for the Windows WezTerm → WSL → tmux workspace.
- `scripts/*-SasWindowsTmuxWorkspace.ps1` — stable technician-facing lifecycle entrypoints.
- `Config/wezterm-windows-tmux.lua.template` — managed native Windows WezTerm configuration that enters WSL tmux `dev` and retains a PowerShell fallback.
- `Launch-WorkstationWezTerm.ps1` and `.cmd` — detached daily launcher; the GUI is always started through `wezterm-gui.exe`.
- `Tests/Fixtures/windows-tmux-workspace/` — sanitized healthy, missing, stale, malformed, nested, failure, and rollback fixture inputs.
- `Tests/survey/test_windows_wezterm_tmux_service_contracts.py` and `Tests/Pester/WindowsWezTermTmuxService.Tests.ps1` — temporary-HOME lifecycle, preservation, launcher, and ownership proof.
- `.github/workflows/windows-wezterm-tmux-service.yml` — Windows fixture lifecycle and Pester CI gate.
- `schemas/harness/developer-workstation-proof.schema.json` — JSON Schema for bimodal developer workstation E2E validation proof results.
- `scripts/Invoke-SasWorkstationE2E.ps1` — dynamic E2E validation journey script executing mock-based platform and failure cases.
- `Tests/survey/test_developer_workstation_proof_contracts.py` — contract and schema validation tests for E2E proof results.
- `.github/workflows/developer-workstation-e2e-proof.yml` — CI workflow executing Windows and Linux workstation E2E proof validation.
- `docs/DEVELOPER_WORKSTATION_E2E_PROOF_MERGE_READINESS.md` — merge readiness validation report detailing journeys status and proof ceilings.

## Developer workstation inventory

- `docs/DEVELOPER_WORKSTATION_INVENTORY.md` — read-only host inventory surface, detected fields, reason codes, proof ceiling, and fixture strategy.
- `schemas/harness/developer-workstation-inventory.schema.json` — typed terminal, domain, tmux, service, agent, lifecycle, and proof-ceiling inventory v2.
- `scripts/Get-SasDeveloperWorkstationInventory.ps1` — read-only Windows/WSL domain collector with lifecycle artifact output.
- `scripts/get-sas-developer-workstation-inventory.sh` — read-only native-Linux/WSL-context collector with lifecycle artifact output.
- `scripts/Render-SasWorkstationInventoryEnglish.py` — dependency-free English renderer for inventory results.
- `Tests/Fixtures/workstation-inventory/` — Windows-native, Linux-native, WSL, missing-tools, malformed-output, and unsupported-platform fixtures.
- `Tests/survey/test_developer_workstation_inventory_contracts.py` — dependency-free schema, fixture, renderer, script, and wiring contracts.
- `.github/workflows/developer-workstation-inventory.yml` — contract, schema, PowerShell fixture, and Bash fixture CI gates.

## Developer workstation agent routing

- `.claude/skills/developer-workstation/SKILL.md` — progressive-disclosure workflow that routes to application entrypoints.
- `.claude/capabilities/workstation-*.md` and `.claude/capabilities/agentswitchboard-invocation.md` — atomic inventory, plan, configuration, backend, session, agent, adapter, and rollback rules.
- `harness/api/developer-workstation-agent-routing.json` — deterministic trigger and terminal-context record.
- `schemas/harness/developer-workstation-agent-routing.schema.json` — fail-closed routing contract.
- `Tests/survey/test_developer_workstation_agent_harness_contracts.py` — trigger uniqueness, path, manifest, context, and prompt/application separation tests.

## Developer workstation orchestration

- `scripts/Invoke-SasDeveloperWorkstation.py` — one-command Inventory/Plan/Apply/Start/Status/Stop/Repair/Validate/Rollback composition.
- `scripts/Invoke-SasDeveloperWorkstation.ps1`, `scripts/invoke-sas-developer-workstation.sh`, and `Developer-Workstation.cmd` — structured platform and technician entrypoints.
- `scripts/Invoke-SasAgentSwitchboard.py` — version-pinned, timeout-bounded external AgentSwitchboard v2 adapter.
- `scripts/Render-SasDeveloperWorkstationEnglish.py` — concise PASS/SKIP/FAIL/ACTION_REQUIRED renderer with terminal-context labels.
- `schemas/harness/developer-workstation-operation.schema.json` and `developer-workstation-orchestrator-result.schema.json` — operation gate and result/artifact contracts.
- `Tests/Fixtures/developer-workstation-orchestrator/` and `Tests/Fixtures/agent-switchboard-v2/` — sanitized integration and external-boundary fixtures.
- `.github/workflows/developer-workstation-orchestrator-v2.yml` — Windows composed fixture and Linux entrypoint gates.

## Native Linux workstation host

- `scripts/invoke-sas-linux-tmux-workspace.sh` — native Plan/Apply/Start/Status/Stop/Repair/Rollback lifecycle implementation.
- `scripts/*-sas-linux-tmux-workspace.sh` — stable operator entrypoints with Plan as the installation default.
- `Config/wezterm-linux-tmux.lua.template`, `Config/tmux-sysadminsuite.conf`, and `Config/bashrc-sysadminsuite.sh` — bounded native-Linux managed fragments.
- `Tests/Fixtures/linux-tmux-workspace/` and `Tests/survey/test_linux_wezterm_tmux_contracts.py` — required-failure and temporary-HOME lifecycle proof.
- `docs/DEVELOPER_WORKSTATION_LINUX_HOST.md` — operator commands, preservation rules, and the native-GUI proof ceiling.
- `.github/workflows/linux-wezterm-tmux-host.yml` — Ubuntu fixture contract gate; it is not a native desktop GUI claim.

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
