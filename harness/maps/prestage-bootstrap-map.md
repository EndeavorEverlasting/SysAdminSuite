# Pre-stage AutoLogon Bootstrap Map

Use this map when an AutoLogon/S4U field attempt fails before stage 1, especially under Windows PowerShell 5.1/StrictMode.

## Repository authority first

- `AGENTS.md` — governance and preservation rules; do not modify from this lane.
- `CODEBASE_MAP.md` — repository-wide routing map.
- `harness/workflows/fresh-agent-intake.yaml` — canonical intake detects the pre-stage/StrictMode signature, proves repository freshness first, then loads this scoped workflow/skill without changing P00 routers.
- `harness/workflows/repository-freshness-before-launch.yaml` — canonical stale-checkout convergence workflow. Fetching a remote ref alone does not update the executing tree.
- `harness/workflows/prestage-bootstrap-safety.yaml` — incident-specific workflow for failures before S4U stage 1.
- `harness/skills/prestage-bootstrap-safety/SKILL.md` — repeatable diagnostic procedure and handoff contract.

## Pre-stage product surfaces — read only in this harness lane

These files explain the bootstrap path but are forbidden mutation scope for this sprint:

- `scripts/SasNetworkGuard.psm1` — local protected-network assertion.
- `scripts/SasTargetNameResolution.psm1` — canonical short-name/FQDN resolver used before S4U stage execution.
- `scripts/Invoke-SasAutoLogonKerberosS4UPilot.ps1` — S4U pilot entrypoint whose stage markers begin only after bootstrap succeeds.
- `Tests/Pester/TargetNameResolution.Tests.ps1` — executable regression proving an already-canonical FQDN resolves with zero suffix candidates under StrictMode.
- `Tests/survey/test_autologon_kerberos_s4u_contracts.py` — static S4U safety/ordering contract.

## Known trap

Windows PowerShell 5.1 pipeline enumeration can unwrap an `if` expression that emits `@()` into `$null`. Under StrictMode, later reading `.Count` from that value throws before S4U stage 1. Current repository truth avoids that shape by assigning the FQDN suffix collection directly and carries a focused Pester regression.

A controller checkout that predates that repair can therefore fail locally before target-stage establishment even when an outer resolver already canonicalized the hostname. Do not diagnose that signature as an S4U task failure until repository freshness is proven.

## Commands

Harness-focused validation:

```text
python harness/validators/validate-prestage-bootstrap-safety.py
python Tests/survey/test_prestage_bootstrap_harness_completeness.py
python harness/validators/validate-repository-freshness-contracts.py
```

Focused Windows regression:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1 -TestPath Tests/Pester/TargetNameResolution.Tests.ps1
```

Broader offline admission gate:

```text
bash tests/survey/run_offline_survey_tests.sh
```

Field front door after freshness and normal deployment authorization are both proven:

```text
Run-AutoLogonCrashSafe.cmd HOST
```

The harness does not authorize or perform that deployment command.

## Build / artifact behavior

No product build is required for this harness slice. Python validators are syntax-checked with `python -m py_compile`. Tracked operator status lives at `harness/reports/PRESTAGE_BOOTSTRAP_SAFETY_STATUS.md`; validation results remain console/CI evidence and are not committed.
