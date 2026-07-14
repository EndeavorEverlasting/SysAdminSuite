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

## Host eligibility gate

- `schemas/harness/host-eligibility-policy.schema.json` — fail-closed host eligibility policy schema (sas-host-eligibility-policy/v1).
- `Config/host-eligibility-policy.sample.json` — sanitized sample policy with fixture, VM, local, remote, and Cybernet-physical contexts.
- `Config/host-eligibility-policy.local.json` — operator-local policy (gitignored, never committed).
- `scripts/Test-SasHostEligibility.ps1` — executable eligibility gate: validates hostname match and request authorization.
- `Tests/Pester/HostEligibility.Tests.ps1` — Pester unit proof for all gate paths (fail-closed, authorization, context).
- `Tests/survey/test_host_eligibility_policy_contracts.py` — dependency-free contract tests for schema and fixtures.
- `Tests/fixtures/host-eligibility/` — sanitized valid, malformed, missing, and rejection fixtures.

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
