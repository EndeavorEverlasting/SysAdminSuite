# SysAdminSuite Codebase Map

Use this map to load only the files needed for a task.

## Repo doctrine

- `AGENTS.md` — agent rules, Bash-first hierarchy, PowerShell preservation, low-noise survey doctrine, and local reference guardrails.
- `README.md` — user entrypoint, repo layout, runtime policy, and local source folder policy.
- `docs/HARNESS_COMPLETION_PLAN.md` — source of truth for AI harness completion sequencing.
- `docs/ENGLISH_LOG_ARTIFACT_CONTRACT.md` — source of truth for future English report/run-context artifacts.
- `docs/OPERATIONAL_POSTURE.md` — lane model for survey, dashboard probes, deployment, mapping, and teardown.
- `docs/LOCAL_REFERENCE_POLICY.md` — rules for gitignored operator-local reference material.

## Survey and low-noise files

- `survey/README.md` — Bash-on-Windows survey entrypoints and field command standards.
- `survey/naabu_profiles.json` — doctrine source for approved Naabu profiles.
- `Config/cybernet-naabu-profiles.json` — generated runtime profile config.
- `survey/sas-run-naabu-pipeline.sh` and `survey/sas-run-packet-probe.sh` — preferred packet-probe wrappers.
- `docs/LOW_NOISE_SURVEY_DOCTRINE.md` — narrative low-noise policy.
- `docs/SURVEY_LANES.md` and `targets/README.md` — local target intake and tracked fixture boundaries.

## Dashboard and user entry

- `docs/DASHBOARD_ENTRYPOINT.md` — canonical field and IT/developer launcher guidance.
- `START-HERE-SysAdminSuite-Dashboard.bat` — field-user dashboard launcher.
- `Launch-SysAdminSuiteDashboard.Host.bat` — IT/developer dashboard launcher.

## Validation and tests

- `tools/validate-ai-layer.ps1` — static validator for this AI harness layer.
- `tests/bash/` — Bash contract and smoke tests.
- `Tests/Pester/` — PowerShell test suite for existing Windows tooling.
- `SysAdminSuite.sln` and `managed-tests/` — .NET validation surface.

## Local data boundaries

- `targets/local/`, `logs/targets/`, `survey/input/`, `survey/output/`, `survey/artifacts/`, `logs/nmap/`, and `Mapping/Output/GuiRuns/` are local/evidence areas unless a tracked sample path explicitly says otherwise.
- Tracked examples belong under approved sanitized, fixture, sample, or template paths.
