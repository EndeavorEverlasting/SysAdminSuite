# AutoLogon VPN field test lane — 2026-07-30

## Purpose

Provide the shortest supported continuation after PR #298 merged to `main` for an operator who has left the physical site but retains approved Northwell VPN access to the powered-on Cybernet target.

This document is an operator sequence, not a replacement transport or deployment implementation.

## Current canonical state

- PR #298 merged the hardened Cybernet clinical-core and AutoLogon S4U field path to `main`.
- PR #298 merge commit: `ede5170f55b38b8e6593c6501372eab3629ee509`.
- The supported AutoLogon deployment command is `sas autologon Remote HOST`.
- The Remote lane performs the protected-network gate, safe interrupted probe-only recovery, AutoLogon S4U deployment, and restart-completion observation.
- Do not rerun `sas cybernet Core HOST` merely to reach AutoLogon.
- Do not reconstruct Task Scheduler or cleanup operations manually.
- Do not bypass the network gate for VPN testing.

## Lane A — ordinary Internet

Use ordinary Internet only to acquire canonical `main`. Earlier field runs intentionally persisted the feature-branch ref, so do not rely on an unqualified `sas refresh` for this one convergence step.

```powershell
$ErrorActionPreference = 'Stop'
$Sas = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin\sas.cmd'
if (-not (Test-Path -LiteralPath $Sas -PathType Leaf)) {
    throw "sas is not installed at $Sas"
}

$Repo = (& $Sas repo | Select-Object -Last 1).Trim()
if ([string]::IsNullOrWhiteSpace($Repo)) { throw 'sas repo returned no repository path.' }
$Refresh = Join-Path $Repo 'scripts\Refresh-SasOperatorCommand.ps1'
if (-not (Test-Path -LiteralPath $Refresh -PathType Leaf)) { throw "Missing refresh script: $Refresh" }

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Refresh -RepositoryRoot $Repo -Ref main
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The refresh installer may move the cached repo root to the isolated field-ready main checkout.
$Repo = (& $Sas repo | Select-Object -Last 1).Trim()
$Head = (git -C $Repo rev-parse HEAD).Trim()
git -C $Repo merge-base --is-ancestor ede5170f55b38b8e6593c6501372eab3629ee509 $Head
if ($LASTEXITCODE -ne 0) {
    throw "Refreshed HEAD does not contain merged PR #298. HEAD=$Head"
}

Write-Host "CANONICAL MAIN READY: $Head" -ForegroundColor Green
& $Sas context
exit $LASTEXITCODE
```

Expected proof:

- `SAS_OPERATOR_REFRESH_READY`
- `REF: main`
- `CANONICAL MAIN READY: <sha>`
- PR #298 merge commit is an ancestor of the refreshed HEAD
- no target contact or target mutation

Then manually enable the approved Northwell VPN.

## Lane B — approved Northwell VPN / protected network

First prove that the existing network guard recognizes the VPN posture. The guard may accept direct approved Wi-Fi or configured non-Wi-Fi Northwell evidence. VPN does not create an emergency bypass.

```powershell
$ErrorActionPreference = 'Stop'
$Sas = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin\sas.cmd'
& $Sas network
$NetworkExit = $LASTEXITCODE
if ($NetworkExit -ne 0) {
    Write-Host "NETWORK GATE EXIT: $NetworkExit" -ForegroundColor Yellow
    exit $NetworkExit
}
Write-Host 'VPN / NORTHWELL NETWORK GATE: PASS' -ForegroundColor Green
```

Only after that returns success, deploy AutoLogon:

```powershell
$ErrorActionPreference = 'Stop'
$Target = 'REPLACE_WITH_EXACT_AUTHORIZED_HOST'
$Sas = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\bin\sas.cmd'
& $Sas autologon Remote $Target
$ExitCode = $LASTEXITCODE
if ($ExitCode -ne 0) {
    Write-Host "AUTOLOGON EXIT: $ExitCode" -ForegroundColor Yellow
}
exit $ExitCode
```

Expected successful terminal marker:

- `AUTOLOGON_DEPLOYMENT_RESTART_COMPLETED`

The restart-completion wrapper owns the target restart and offline/online observation. Do not manually reboot the target while the supported command is running.

## If the VPN network gate blocks

Stop before deployment. Do not set an ad-hoc bypass variable and do not contact the target manually. Return the complete `sas network` output, especially:

- network classification
- observed Windows network label
- evidence path
- configured/non-Wi-Fi evidence result

That failure is a network-posture classification problem, not evidence that the S4U implementation should be rewritten.

## If AutoLogon fails after the VPN gate passes

Return the complete streamed command output. Classify from the durable transaction evidence before running unrelated diagnostics:

- phase / stage
- classification
- target mutation state
- probe lifecycle state
- install lifecycle state
- exact task cleanup state
- exact run-root cleanup state
- restart observation state
- evidence path

A subsequent `sas autologon Remote HOST` is allowed to auto-recover only safely recorded probe-only interruptions. Install/after-state evidence fails closed and requires evidence-led handling instead of blind redeployment.
