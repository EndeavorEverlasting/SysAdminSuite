# Pester Baseline Triage — June 2026

Read-only classification of the **46 failing tests** observed on `main` and feature lanes. This document does **not** modify any `.ps1` test or product files.

## Entry point

- Runner: [`tools/Test-Pester5Suite.ps1`](../tools/Test-Pester5Suite.ps1) (Pester 5.7+ required)
- Baseline restoration lane: **PR #58** (`feature/pester-fixture-maintenance`)

## Summary counts

| Branch / tip | Passed | Failed | Skipped | Source |
|---|---:|---:|---:|---|
| `main` (`51155e7`) | 373 | **46** | 1 | Local run 2026-06-24 |
| `feature/cybernet-xlsx-target-ingester-2026-06` (PR #61) | 372 | **46** | 2 | CI run `28134037338` |
| `feature/targets-folder-guard-2026-06` (PR #62) | 372 | **46** | 2 | CI run `28134034486` |
| `feature/pester-fixture-maintenance` (PR #58) | — | — | — | Open baseline-fix lane |

**Conclusion:** The same **46 failures** appear on `main`, PR #61, and PR #62. They are **not introduced** by the Cybernet xlsx ingester (G) or targets-folder guard (X). Treat as pre-existing baseline/fixture debt tracked by PR #58.

## Classification key

| Tag | Meaning |
|---|---|
| `baseline` | Missing fixture, reference file, or script artifact expected by the test harness |
| `environment` | Requires corporate network, AD, or machine state not present in local/CI smoke |
| `feature` | Regression caused by an open feature branch — **none observed in this triage** |

## Failing tests (46) — all classified `baseline`

### Deployment / mapping fixtures

| Test | Classification | Notes |
|---|---|---|
| `Compare-DeploymentToAd.ps1 (CSV, -SkipAd).Runs against fixtures and writes CSV` | baseline | AD/deployment fixture path |
| `Mapping/Config CSV files.host-mappings.csv loads without error and exposes the expected columns` | baseline | Missing `host-mappings.csv` fixture |
| `Mapping/Config CSV files.wcc_printers.csv loads with at least one row` | baseline | Missing `wcc_printers.csv` fixture |

### Neuron maintenance / software reference

| Test | Classification | Notes |
|---|---|---|
| `Get-NeuronMaintenanceSnapshot.ps1 -- script contract.Captures the main maintenance-console inspired sections` | baseline | Snapshot script fixture contract |
| `QR task dispatcher registration -- NeuronMaintenance.Registers the NeuronMaintenance task name` | baseline | Task registration fixture |
| `Neuron maintenance baseline and documentation.Baseline config exists` | baseline | Missing baseline JSON |
| `Neuron maintenance baseline and documentation.Baseline config is valid JSON` | baseline | Missing baseline JSON |
| `Neuron maintenance baseline and documentation.Documentation exists` | baseline | Missing doc artifact |
| `Neuron maintenance baseline and documentation.Documentation includes survey and remote emulation intent` | baseline | Missing doc content |
| `NeuronTargets.example.csv -- template contract.Template file exists` | baseline | Missing template CSV |
| `NeuronTargets.example.csv -- template contract.Provides the expected columns` | baseline | Missing template CSV |
| `Neuron software reference baseline -- 11.8.0.328.Reference JSON exists` | baseline | Missing reference JSON |
| `Neuron software reference baseline -- 11.8.0.328.Reference JSON is valid and has firmware plus DDI sections` | baseline | Missing reference JSON |
| `Neuron software reference baseline -- 11.8.0.328.Includes key DDI packages visible in the console reference` | baseline | Missing reference JSON |
| `Observed package example and docs.Observed package example exists with expected header` | baseline | Missing observed package fixture |
| `Observed package example and docs.Documentation exists and explains survey usage` | baseline | Missing doc artifact |

### Registry install-diff pipeline

| Test | Classification | Notes |
|---|---|---|
| `Compare-RegistrySnapshots script.exists` | baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.contains comment-based help sections` | baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.does not include forbidden registry mutation or remote registry commands` | baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.classifies created/deleted/modified and applies rules and writes outputs` | baseline | Fixture-driven diff test |
| `Registry Install Diff Orchestrator.exists` | baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.has comment based help synopsis` | baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.blocks approved remediation as unsupported` | baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.does not contain forbidden registry write or remoting patterns` | baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.recononly runs or records missing dependency gracefully` | baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.analyzeinstall dry-run emits manifest and summary` | baseline | Orchestrator script missing |
| `Get-RegistrySnapshot Script.script exists` | baseline | Script missing |
| `Get-RegistrySnapshot Script.has comment-based help synopsis` | baseline | Script missing |
| `Get-RegistrySnapshot Script.accepts localhost invocation with narrow key and parses output` | baseline | Script/fixture |
| `Get-RegistrySnapshot Script.creates output JSON when OutputPath is supplied` | baseline | Script/fixture |
| `Get-RegistrySnapshot Script.handles missing paths without fatal crash` | baseline | Script/fixture |
| `Get-RegistrySnapshot Script.accepts exclude patterns array` | baseline | Script/fixture |
| `Get-RegistrySnapshot Script.does not include forbidden write or remoting commands` | baseline | Script/fixture |

### Repo-wide standards

| Test | Classification | Notes |
|---|---|---|
| `Repo-wide BOM compliance.All .ps1 files in the repo have UTF-8 BOM` | baseline | Repo-wide encoding debt |
| `Dollar-sign escaping standards.No repo scripts use unescaped dollar signs in Write-Host string literals that would fail` | baseline | Repo-wide escaping debt |

### Target readiness / tracked install

| Test | Classification | Notes |
|---|---|---|
| `Test-TargetReadiness script.exists` | baseline | Script/fixture |
| `Test-TargetReadiness script.contains comment-based help sections` | baseline | Script/fixture |
| `Test-TargetReadiness script.can run localhost mode without remote dependency` | baseline | Script/fixture |
| `Test-TargetReadiness script.parses CSV targets with common column names` | baseline | Script/fixture |
| `Test-TargetReadiness script.returns structured statuses for unreachable targets without crashing batch` | baseline | Script/fixture |
| `Test-TargetReadiness script.does not contain forbidden registry or remoting mutation commands` | baseline | Script/fixture |
| `Invoke-TrackedInstall.dry-run works with direct InstallerPath and does not execute installer` | baseline | Script/fixture |
| `Invoke-TrackedInstall.creates output JSON when OutputPath is supplied and JSON parses` | baseline | Script/fixture |
| `Invoke-TrackedInstall.non-localhost target returns Unsupported with RemoteInstallNotImplemented` | baseline | Script/fixture |
| `Invoke-TrackedInstall.missing installer path in execution mode fails safely` | baseline | Script/fixture |
| `Invoke-TrackedInstall.attempts source config lookup or reports parser/config issue gracefully` | baseline | Script/fixture |

## Feature-caused failures

**None.** PR #61 and PR #62 CI both report **46 failed** — identical baseline set.

## Recommended next steps

1. Merge or continue **PR #58** to restore missing fixtures and resolve baseline failures.
2. Do **not** block PR #61 (G) or PR #62 (X) on these 46 failures — triage confirms they pre-exist on `main`.
3. Re-run `tools/Test-Pester5Suite.ps1` after PR #58 merges to measure delta.

## Local reproduction

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1
```

Raw log (local `main`): `_out/pester-main-baseline.log` (worktree artifact, not committed).
