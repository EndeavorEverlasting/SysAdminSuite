# Pester Baseline Triage — June 2026

Read-only historical classification of the **46 failing tests** observed on the pre-PR #46 `main` baseline and selected feature lanes. This document does **not** modify any `.ps1` test or product files.

## Current status

This triage is now historical. PR #46 was merged after the runs below and changed the Pester baseline materially.

Latest known post-PR #46 local validation:

| Branch / context | Passed | Failed | Skipped | Source |
|---|---:|---:|---:|---|
| PR #46 branch, before merge | 418 | **0** | 2 | Local Windows PowerShell run 2026-06-24 |

Do not use the old **46 failures** count as the current `main` baseline without rerunning the suite on current `main`.

## Entry point

- Runner: [`tools/Test-Pester5Suite.ps1`](../tools/Test-Pester5Suite.ps1) (Pester 5.7+ required)
- Historical baseline restoration lane: **PR #58** (`feature/pester-fixture-maintenance`)

## Historical summary counts

| Branch / tip | Passed | Failed | Skipped | Source |
|---|---:|---:|---:|---|
| `main` (`51155e7`) | 373 | **46** | 1 | Local run 2026-06-24, before PR #46 merge |
| `feature/cybernet-xlsx-target-ingester-2026-06` (PR #61) | 372 | **46** | 2 | CI run `28134037338`, before PR #46 merge |
| `feature/targets-folder-guard-2026-06` (PR #62) | 372 | **46** | 2 | CI run `28134034486`, before PR #46 merge |
| `feature/pester-fixture-maintenance` (PR #58) | — | — | — | Open baseline-fix lane |

**Historical conclusion:** The same **46 failures** appeared on old `main`, PR #61, and PR #62 at the time of this triage. They were **not introduced** by the Cybernet xlsx ingester (G) or targets-folder guard (X) when compared against that old baseline.

**Current conclusion:** Rebase or refresh PR #61, PR #62, and PR #58 against current `main`, then rerun Pester before using this document as merge evidence.

## Classification key

| Tag | Meaning |
|---|---|
| `historical-baseline` | Missing fixture, reference file, or script artifact expected by the old test harness |
| `environment` | Requires corporate network, AD, or machine state not present in local/CI smoke |
| `feature` | Regression caused by an open feature branch — **none observed in this historical triage** |

## Historical failing tests (46)

The following failures were observed before PR #46 merged. Treat this list as historical evidence only until it is remeasured on current `main`.

### Deployment / mapping fixtures

| Test | Classification | Notes |
|---|---|---|
| `Compare-DeploymentToAd.ps1 (CSV, -SkipAd).Runs against fixtures and writes CSV` | historical-baseline | AD/deployment fixture path |
| `Mapping/Config CSV files.host-mappings.csv loads without error and exposes the expected columns` | historical-baseline | Missing `host-mappings.csv` fixture |
| `Mapping/Config CSV files.wcc_printers.csv loads with at least one row` | historical-baseline | Missing `wcc_printers.csv` fixture |

### Neuron maintenance / software reference

| Test | Classification | Notes |
|---|---|---|
| `Get-NeuronMaintenanceSnapshot.ps1 -- script contract.Captures the main maintenance-console inspired sections` | historical-baseline | Snapshot script fixture contract |
| `QR task dispatcher registration -- NeuronMaintenance.Registers the NeuronMaintenance task name` | historical-baseline | Task registration fixture |
| `Neuron maintenance baseline and documentation.Baseline config exists` | historical-baseline | Missing baseline JSON |
| `Neuron maintenance baseline and documentation.Baseline config is valid JSON` | historical-baseline | Missing baseline JSON |
| `Neuron maintenance baseline and documentation.Documentation exists` | historical-baseline | Missing doc artifact |
| `Neuron maintenance baseline and documentation.Documentation includes survey and remote emulation intent` | historical-baseline | Missing doc content |
| `NeuronTargets.example.csv -- template contract.Template file exists` | historical-baseline | Missing template CSV |
| `NeuronTargets.example.csv -- template contract.Provides the expected columns` | historical-baseline | Missing template CSV |
| `Neuron software reference baseline -- 11.8.0.328.Reference JSON exists` | historical-baseline | Missing reference JSON |
| `Neuron software reference baseline -- 11.8.0.328.Reference JSON is valid and has firmware plus DDI sections` | historical-baseline | Missing reference JSON |
| `Neuron software reference baseline -- 11.8.0.328.Includes key DDI packages visible in the console reference` | historical-baseline | Missing reference JSON |
| `Observed package example and docs.Observed package example exists with expected header` | historical-baseline | Missing observed package fixture |
| `Observed package example and docs.Documentation exists and explains survey usage` | historical-baseline | Missing doc artifact |

### Registry install-diff pipeline

| Test | Classification | Notes |
|---|---|---|
| `Compare-RegistrySnapshots script.exists` | historical-baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.contains comment-based help sections` | historical-baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.does not include forbidden registry mutation or remote registry commands` | historical-baseline | Script/fixture path |
| `Compare-RegistrySnapshots script.classifies created/deleted/modified and applies rules and writes outputs` | historical-baseline | Fixture-driven diff test |
| `Registry Install Diff Orchestrator.exists` | historical-baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.has comment based help synopsis` | historical-baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.blocks approved remediation as unsupported` | historical-baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.does not contain forbidden registry write or remoting patterns` | historical-baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.recononly runs or records missing dependency gracefully` | historical-baseline | Orchestrator script missing |
| `Registry Install Diff Orchestrator.analyzeinstall dry-run emits manifest and summary` | historical-baseline | Orchestrator script missing |
| `Get-RegistrySnapshot Script.script exists` | historical-baseline | Script missing |
| `Get-RegistrySnapshot Script.has comment-based help synopsis` | historical-baseline | Script missing |
| `Get-RegistrySnapshot Script.accepts localhost invocation with narrow key and parses output` | historical-baseline | Script/fixture |
| `Get-RegistrySnapshot Script.creates output JSON when OutputPath is supplied` | historical-baseline | Script/fixture |
| `Get-RegistrySnapshot Script.handles missing paths without fatal crash` | historical-baseline | Script/fixture |
| `Get-RegistrySnapshot Script.accepts exclude patterns array` | historical-baseline | Script/fixture |
| `Get-RegistrySnapshot Script.does not include forbidden write or remoting commands` | historical-baseline | Script/fixture |

### Repo-wide standards

| Test | Classification | Notes |
|---|---|---|
| `Repo-wide BOM compliance.All .ps1 files in the repo have UTF-8 BOM` | historical-baseline | Repo-wide encoding debt |
| `Dollar-sign escaping standards.No repo scripts use unescaped dollar signs in Write-Host string literals that would fail` | historical-baseline | Repo-wide escaping debt |

### Target readiness / tracked install

| Test | Classification | Notes |
|---|---|---|
| `Test-TargetReadiness script.exists` | historical-baseline | Script/fixture |
| `Test-TargetReadiness script.contains comment-based help sections` | historical-baseline | Script/fixture |
| `Test-TargetReadiness script.can run localhost mode without remote dependency` | historical-baseline | Script/fixture |
| `Test-TargetReadiness script.parses CSV targets with common column names` | historical-baseline | Script/fixture |
| `Test-TargetReadiness script.returns structured statuses for unreachable targets without crashing batch` | historical-baseline | Script/fixture |
| `Test-TargetReadiness script.does not contain forbidden registry or remoting mutation commands` | historical-baseline | Script/fixture |
| `Invoke-TrackedInstall.dry-run works with direct InstallerPath and does not execute installer` | historical-baseline | Script/fixture |
| `Invoke-TrackedInstall.creates output JSON when OutputPath is supplied and JSON parses` | historical-baseline | Script/fixture |
| `Invoke-TrackedInstall.non-localhost target returns Unsupported with RemoteInstallNotImplemented` | historical-baseline | Script/fixture |
| `Invoke-TrackedInstall.missing installer path in execution mode fails safely` | historical-baseline | Script/fixture |
| `Invoke-TrackedInstall.attempts source config lookup or reports parser/config issue gracefully` | historical-baseline | Script/fixture |

## Known gaps

- This document has not yet been remeasured on current `main` after PR #46 merged.
- PR #61 and PR #62 results cited here are pre-PR #46 measurements.
- PR #58 may overlap with fixes already merged through PR #46 and must be reassessed before merge.
- Bot review coverage on this PR was limited by external review rate limits.

## Risks

- Treating the historical **46 failures** count as current truth can create false blockers or hide newly introduced regressions.
- Merging this document without the historical qualifier could mislead future PR review.
- PR #58, PR #61, and PR #62 may need rebase/refresh work before their old validation claims remain valid.

## Recommended next steps

1. Pull current `main` and rerun `tools/Test-Pester5Suite.ps1`.
2. Record the current `main` pass/fail/skip count in a new dated row or follow-up note.
3. Rebase or update PR #58, PR #61, and PR #62 on current `main`.
4. Rerun their validation after rebase.
5. Use this document only as historical context unless those reruns confirm the same failures still exist.

## Local reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-Pester5Suite.ps1
```

Raw historical log (old local `main`): `_out/pester-main-baseline.log` (worktree artifact, not committed).
