# Replit Extraction Roadmap

## Purpose

Capture which Replit-origin concepts should be turned into real SysAdminSuite product work.

This document is the bridge between exploratory Replit branches and clean GitHub implementation lanes. It exists so future work does not depend on terminal scrollback, chat memory, or branch archaeology.

## Current protected lanes

| Branch | Purpose | Status |
|---|---|---|
| `forensics/sysadminsuite-product-harvest-v1` | PR9 Bash-on-Windows harvest analysis and doctrine preservation | Preserved and pushed |
| `safety/replit-local-main-b42911f` | Divergent local Replit `main` preservation branch | Preserved and pushed |
| `feature/bash-windows-field-survey-v1` | Clean implementation lane from current `origin/main` | Active and pushed |

## Non-negotiable doctrine

- Bash means Bash-on-Windows for Northwell-targeted field tooling.
- Target runtime is usually Git Bash or MSYS2 on Windows.
- Do not rewrite Bash-on-Windows tooling into Linux defaults just because Replit/Linux cannot run Windows executables.
- Preserve PowerShell as active Windows tooling.
- Do not delete, truncate, or deprecate PowerShell files unless explicitly requested.
- Survey before mutation.
- Report before action.
- Keep production `main` untouched until changes are reviewed through a clean branch or PR.

## Extraction priority

### Priority 1: Live Serial Probe

Source branch:

- `feature/2026-05-21-live-serial-probe`

Concept to turn into reality:

- Live serial identity / manifest probe workflow.
- Survey fixture model for serial identity and manifest samples.
- Contract tests for live serial probe behavior.
- Dashboard rendering for probe outputs.
- Productized field workflow for correlating live observed serial/device data against expected deployment records.

Known candidate files from branch comparison:

- `deployment-audit/docs/LIVE_SERIAL_PROBE_SPRINT.md`
- `deployment-audit/sas-render-live-serial-dashboard.py`
- `deployment-audit/tests/test_live_serial_probe_contracts.sh`
- `survey/fixtures/live_serial_identity.sample.csv`
- `survey/fixtures/live_serial_manifest.sample.csv`
- `survey/sas-live-serial-probe.sh`

Implementation posture:

- Do not blindly merge the branch.
- Harvest concepts first.
- Inspect scripts for runtime assumptions.
- Preserve Bash-on-Windows doctrine.
- Preserve read-only / survey-first posture.
- Add code only after documenting the contract.
- Prefer small commits:
  1. Extract live serial concept documentation.
  2. Add fixtures.
  3. Add contract test.
  4. Add probe script.
  5. Add dashboard renderer only after probe output is stable.

Expected clean lane name:

- `feature/live-serial-probe-v1`

### Priority 2: Nmap Cybernet Target Audit

Source branch:

- `feature/nmap-cybernet-target-audit`

Concept to turn into reality:

- Cybernet target audit tooling around Nmap output.
- Guarded network probe runner.
- HTML/report generation.
- Northwell WAB guard / allowlist-style safety layer.
- Windows `.cmd` wrappers for controlled execution.

Known candidate files from branch comparison:

- `deployment-audit/nmap/README.md`
- `deployment-audit/nmap/analyze-cybernet-probe.cmd`
- `deployment-audit/nmap/cybernet_target_audit.py`
- `deployment-audit/nmap/html_report.py`
- `deployment-audit/nmap/nmap_probe_runner.py`
- `deployment-audit/nmap/northwell_wab_guard.example.json`
- `deployment-audit/nmap/northwell_wab_guard.py`
- `deployment-audit/nmap/run-cybernet-nmap.cmd`

Implementation posture:

- Treat as high value but higher risk.
- Do not run against production networks without explicit approval and safe scope.
- Require allowlists, dry-run mode, clear target files, and logging.
- Default to analysis/reporting of known outputs before adding active probing.
- Review for network-safety defaults before any merge.
- Keep this separate from Bash field survey work.

Expected clean lane name:

- `feature/cybernet-target-audit-v1`

### Priority 3: Bash Runtime Contract Docs

Source branches:

- `docs/2026-05-03-bash-windows-runtime-contract`
- `sprint/2026-05-03-docs-shell-contract`

Concept to turn into reality:

- Runtime contract documentation.
- Command catalog.
- Agent rules for Bash-on-Windows versus Linux defaults.

Current posture:

- Much of this appears already represented in `AGENTS.md`, `docs/AI_RUNTIME_CONTRACT.md`, and `docs/COMMAND_CATALOG.md`.
- Treat these branches as reference material, not automatic merge sources.

Implementation posture:

- Compare only if current docs become inconsistent.
- Do not accept doctrine changes that collapse PowerShell or language hierarchy guardrails.
- Do not reintroduce PR9-style `AGENTS.md` truncation.

Expected clean lane name, only if needed:

- `docs/runtime-contract-hardening-v1`

### Priority 4: Bash Field Survey Historical Branch

Source branch:

- `feature/2026-05-03-bash-field-survey-scripts`

Concept to turn into reality:

- Early version of field survey scripts.
- Device snapshot.
- Neuron environment survey.
- Smoke runtime test.

Current posture:

- Likely mostly absorbed into current `main`.
- Current active implementation lane already started from `origin/main` and has:
  - `survey/sas-device-snapshot.sh`
  - `survey/sas-neuron-environment.sh`
  - `tests/bash/smoke-bash-windows-runtime.sh`
  - `docs/AI_RUNTIME_CONTRACT.md`
  - `docs/COMMAND_CATALOG.md`

Implementation posture:

- Use as comparison only.
- Do not merge wholesale.
- Prefer hardening current `main` files.

### Priority 5: Billing Pipeline Directional Use Cases

Source branch:

- `docs/billing-pipeline-directional-use-cases`

Concept to turn into reality:

- Roster Log to Admin Sheet one-shot submission output.
- Roster Log to Task Tracker hours contextualization.
- Task Tracker to Roster Log low-priority updates based on noted contributions.

Implementation posture:

- Keep separate from SysAdminSuite Bash field survey work.
- Treat as admin/billing workflow doctrine.
- Should become its own documentation and tooling lane if/when billing automation returns to scope.

Expected clean lane name:

- `docs/billing-pipeline-directional-use-cases-v1`

## Extraction method

For each concept branch:

1. Create a clean worktree from current `origin/main`.
2. Compare source branch to `origin/main`.
3. Record candidate files.
4. Inspect content before accepting.
5. Reject unsafe doctrine changes.
6. Prefer concept docs first.
7. Add code in small commits.
8. Run only safe local tests.
9. Document Replit/Linux runtime mismatches instead of changing product direction to satisfy Replit.
10. Push branch before moving to the next extraction target.

## Immediate next lane

Next branch to create:

- `feature/live-serial-probe-v1`

First objective:

- Convert the live serial probe concept into a clean product contract document.
- Do not extract code yet.
- Determine expected inputs, outputs, fixtures, test contract, and dashboard handoff.

First expected doc:

- `deployment-audit/docs/LIVE_SERIAL_PROBE_V1.md`

First expected inspection targets:

- `origin/feature/2026-05-21-live-serial-probe:deployment-audit/docs/LIVE_SERIAL_PROBE_SPRINT.md`
- `origin/feature/2026-05-21-live-serial-probe:survey/sas-live-serial-probe.sh`
- `origin/feature/2026-05-21-live-serial-probe:survey/fixtures/live_serial_identity.sample.csv`
- `origin/feature/2026-05-21-live-serial-probe:survey/fixtures/live_serial_manifest.sample.csv`
- `origin/feature/2026-05-21-live-serial-probe:deployment-audit/tests/test_live_serial_probe_contracts.sh`
- `origin/feature/2026-05-21-live-serial-probe:deployment-audit/sas-render-live-serial-dashboard.py`

## Definition of done for this roadmap

- The repo contains a clear list of Replit-origin concepts.
- Each concept has a priority.
- Each concept has a clean target implementation lane.
- The repo records that source branches are references, not merge targets.
- Future work can continue without relying on chat history.
