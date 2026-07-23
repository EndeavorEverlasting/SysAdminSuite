# SysAdminSuite Codebase Map

Use this map to load only the files needed for a task.

## Agent instruction architecture

- `AGENTS.md` — compact universal invariants and task-to-skill router; keep detailed procedures out of this file.
- `CLAUDE.md` — progressive-disclosure front door for Claude-compatible agents.
- `.claude/skills/*/SKILL.md` — task workflows that compose reusable capabilities.
- `.claude/capabilities/*.md` — stable atomic rules shared by multiple skills.
- `harness/api/agent-capability-manifest.json` — machine-readable skill/capability catalog and dependency graph.
- `harness/api/agent-routing-manifest.json` — deterministic task-signal catalog; equal-priority primary conflicts fail closed.
- `schemas/harness/agent-capability-manifest.schema.json` — fail-closed catalog schema.
- `tools/validate-ai-layer.ps1` — validates the instruction architecture, required safety language, and local-data exclusions.
- `Tests/survey/test_agent_instruction_factoring_contracts.py` — dependency-free factoring and anti-bloat contract.
- `Tests/survey/test_agent_capability_manifest_contracts.py` — machine-readable catalog contract.
- `Tests/survey/test_agent_routing_manifest_contracts.py` — deterministic routing and package-operation wiring contract.

## Operational harness infrastructure

- `harness/api/operational-harness-manifest.json` — central machine-readable inventory of maps, workflows, validators, hooks, skills, reports, run context, handoff, text policy, and CI.
- `schemas/harness/operational-harness-manifest.schema.json` — fail-closed schema for the central harness inventory.
- `harness/workflows/operational-harness-maintenance.yaml` — task pickup, workflow selection, bounded implementation, validation, failure handling, commit, and handoff sequence.
- `harness/api/harness-artifact-registry.json` — artifact types, generators, locations, naming conventions, tracking, and live-data boundaries.
- `Tests/survey/test_operational_harness_completeness_contracts.py` — proves required components exist, are tracked, and are wired into hooks, CI, reports, and the codebase map.
- `scripts/check-repo-text-policy.py` and `.gitattributes` — validate canonical LF storage in Git while allowing Windows checkout endings; prevent CRLF from being misreported as trailing whitespace.
- `.githooks/pre-commit`, `.githooks/pre-push`, and `scripts/install-local-harness-hooks.sh` — local staged, push, evidence, and contract guardrails.
- `docs/HARNESS_STATUS.md` — English operator report of working components, repaired boundaries, known gaps, and proof ceilings.
- `.github/workflows/harness-infrastructure.yml` — dedicated completeness, schema, local-harness, text-policy, syntax, and whitespace CI gate.

## Package analysis

- `.claude/skills/package-static-analysis/SKILL.md` — umbrella package workflow across static, semantic, offline trust, and VM qualification.
- `.claude/capabilities/package-*.md` — atomic package inspection, semantic enrichment, offline trust, and VM-qualification capabilities.
- `harness/workflows/package-analysis.yaml` — canonical package-analysis workflow mapping inputs to entrypoints.
- `harness/api/package-static-analysis-skill.json`, `package-semantic-analysis-skill.json`, `package-trust-verification-skill.json`, `package-vm-qualification-skill.json` — operation manifests.
- `scripts/Invoke-SasPackageTrust.ps1` and `tools/package-analysis/SasPackageTrustInterop.cs` — cache-only WinTrust trust gate.
- `tools/package-analysis/validate_vm_qualification_profile.py` — fail-closed disposable-VM qualification validator; never starts a VM.
- `docs/PACKAGE_STATIC_ANALYSIS.md`, `PACKAGE_SEMANTIC_ANALYSIS.md`, `PACKAGE_TRUST_VERIFICATION.md`, `PACKAGE_VM_QUALIFICATION_PROFILES.md` — operator guides and proof ceilings.
- `Tests/survey/test_package_*_contracts.py` and `Tests/survey/Test-PackageTrustVerificationContracts.ps1` — focused package contracts.
- `.github/workflows/package-static-analysis.yml` — Ubuntu/Windows package-analysis CI gate.

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

## AutoLogon proof contract floor

- `docs/AUTOLOGON_PROOF_CONTRACT_FLOOR.md` — frozen operation IDs, existing-emission ledger, migration boundaries, proof classifications, and privacy ceiling.
- `schemas/harness/autologon-*.schema.json` — canonical deployment, final-gate, state, session-access, technician-runtime, operator-local source-evidence, and public-receipt contracts.
- `harness/api/autologon-artifact-types.json` — closed artifact-role registry and canonical run-context requirements.
- `harness/workflows/autologon-proof-contract-floor.yaml` — frozen workflow mapping without application or live-execution authority.
- `Tests/Fixtures/autologon-contract-floor/` — sanitized success, failure, overclaim, and private-field fixtures.
- `Tests/survey/test_autologon_proof_contract_floor_contracts.py` — dependency-free schema, fixture, operation, artifact, privacy, proof-ceiling, migration, and CI validator.
- `.github/workflows/autologon-proof-contract-floor.yml` — focused offline contract and Draft 2020-12 validation gate.

## AutoLogon agent routing

- `.claude/skills/autologon-deployment/SKILL.md` — progressive-disclosure orchestration for planning, canonical admin deployment, and post-reboot proof.
- `.claude/capabilities/autologon-deployment-orchestration.md` — admin identity, authority, canonical entrypoint, guardrail, and deployment-ceiling contract.
- `.claude/capabilities/autologon-runtime-proof.md` — signed-in identity, current-token access, application observation, and runtime-ceiling contract.
- `harness/api/agent-capability-manifest.json` and `harness/api/agent-routing-manifest.json` — deterministic plan, admin, and runtime activation authority.
- `Tests/survey/test_autologon_agent_harness_contracts.py` — activation, collision, ambiguity, negative-routing, prompt/application separation, and proof-ceiling contracts.

## AutoLogon canonical fixture E2E

- `scripts/Invoke-SasAutoLogonE2E.ps1` — composed zero-network runner for the real AutoLogon entrypoint, harmless generated installer, canonical SMB/task fixture adapter, final gate, state failure matrix, teardown, and sanitized receipt ingest.
- `Tests/Fixtures/autologon-canonical-e2e/scenarios.json` — closed success and deterministic failure matrix; fixture identity and S-1-5-18 markers never become live proof.
- `schemas/harness/autologon-canonical-e2e-result.schema.json` — closed composed-result contract with explicit simulated-SYSTEM and no-live-proof boundaries.
- `harness/e2e/e2e-profiles.json` — dedicated `autologon` profile and `autologon-canonical-fixture-e2e` journey; the default profile remains unchanged.
- `Tests/survey/test_autologon_canonical_e2e_contracts.py`, `Tests/Pester/AutoLogonCanonicalE2E.Tests.ps1`, and `.github/workflows/autologon-canonical-e2e.yml` — offline, Windows PowerShell 5.1 parser/Pester, executable journey, and sanitized artifact gates.

## AutoLogon administrator and runtime operations

- `docs/AUTOLOGON_DEPLOYMENT_WORKFLOW.md` — launch-order authority for plan, fixture, one-target canonical deployment, result review, controlled reboot observation, signed-in access, application behavior, failure review, and recovery.
- `docs/AUTOLOGON_PHYSICAL_PILOT_CHECKLIST.md` — one-target go/no-go checklist; it is not an alternate command authority.
- `scripts/Invoke-SasAutoLogonDeployment.ps1` — canonical administrator entrypoint with closed request, fresh P02 preflight, Before snapshot, final-step gate, Kerberos/SMB scheduled-task execution, cleanup, and normalized results.
- `scripts/Show-SasAutoLogonResult.ps1` and `Inspect-LatestAutoLogon.cmd` — read-only public-safe classification, cleanup/remnant, digest-continuity, and proof-ceiling presentation without identities or paths.
- `scripts/Invoke-SasAutoLogonSessionAccessProof.ps1` — bounded expected-account current-token path access and optional create/remove marker proof from the real signed-in session.
- `scripts/Start-SasAutoLogonTechnicianRuntimeProof.cmd` and `scripts/Invoke-SasAutoLogonTechnicianRuntimeProof.ps1` — bounded application readiness and technician behavior observation from the real signed-in session.
- `Tests/Fixtures/autologon-result-inspector/`, `Tests/Pester/AutoLogonCanonicalResultPresenter.Tests.ps1`, and `Tests/survey/test_autologon_admin_runtime_runbook_contracts.py` — safe presenter fixture, Windows execution, documentation, privacy, command, index, and CI contracts.

## Repo doctrine

- `README.md` — user entrypoint, repo layout, runtime policy, and local source folder policy.
- `docs/HARNESS_COMPLETION_PLAN.md` — AI harness completion sequencing; load for harness work, not every task.
- `docs/PYDANTIC_AI_CAPABILITY_ADAPTER_DECISION.md` — boundary for capability-oriented adapters; repo-local skills/capabilities remain authoritative.
- `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` — future English report/run-context artifact contract.
- `docs/OPERATIONAL_POSTURE.md` — lane model for survey, dashboard probes, deployment, mapping, and teardown.
- `docs/HARNESS_DISCIPLINE.md` — full repository mutation and PR/worktree operation contract.
- `docs/LOCAL_REFERENCE_POLICY.md` — gitignored operator-local reference rules.

## Cybernet hardware batch configuration

- `Hardware/Cybernet/README.md` — operator sequence, authority boundaries, COM local-only rule, and proof ceiling.
- `Hardware/Cybernet/Invoke-CybernetBatchConfiguration.ps1` — Plan/Apply/Validate orchestrator; Plan is the default.
- `Hardware/Cybernet/Set-NoSleep.ps1` — bounded AC/DC standby and hibernate idle timeout configuration with readback.
- `Hardware/Cybernet/Set-PowerButtonDoNothing.ps1` — wrapper for the canonical Windows physical power-button hardening lane.
- `Hardware/Cybernet/Disable-PrivacyButton.ps1` and `Enable-PrivacyButton.ps1` — DDC/CI VCP `0xCA` apply and exact-manifest restore wrappers.
- `Hardware/Cybernet/COM-Port-Check.ps1` — read-only COM1-COM4 validation and local AutoFix routing.
- `Hardware/Cybernet/PostInstall-Validation.ps1` — read-only composed hardware validation.
- `Run-CybernetBatchConfiguration.cmd` — one-target Plan/Apply/Validate launcher.
- `Tests/survey/test_cybernet_hardware_batch_contracts.py`, `Tests/Pester/CybernetHardwareBatch.Tests.ps1`, and `.github/workflows/cybernet-hardware-batch.yml` — static, parser, fixture, composition, and CI proof.

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
