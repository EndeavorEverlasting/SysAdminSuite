#Requires -Version 5.1
<#
.SYNOPSIS
Technician-facing launcher for one WinRM-blocked AutoLogon run.
.DESCRIPTION
Finds preserved one-target AutoLogon runs that stopped before deployment evidence was emitted,
lets the technician select one, requires an explicit RECOVER acknowledgement, and delegates all
preflight, harmless live-cert, state collection, deployment, cleanup, and reporting to the
repository-owned recovery orchestrator. No PowerShell command reconstruction is required.
#>

[CmdletBinding()]
param(
    [ValidateSet('Menu','Recover','OpenLatest')]
    [string]$Action = 'Menu',
    [string]$RunRoot,
    [string]$ConfirmText,
    [switch]$NonInteractive,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-SasRecoverableRuns {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $Root -Directory -Filter 'autologon-deploy-*' -ErrorAction SilentlyContinue |
            Where-Object {
                $requests = @(Get-ChildItem -LiteralPath $_.FullName -Filter 'validated_deployment_request_*.json' -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '[\\/]recovery[\\/]' })
                $installEvidence = @()
                foreach ($pattern in @('software_install_summary.json','smb_task_transport_result_*.json','validated_deployment_result.json','software_install_finalization.json')) {
                    $installEvidence += @(Get-ChildItem -LiteralPath $_.FullName -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)
                }
                $requests.Count -eq 1 -and $installEvidence.Count -eq 0
            } |
            Sort-Object LastWriteTimeUtc -Descending
    )
}

function Resolve-SasRecoveryRun {
    param(
        [string]$RequestedRoot,
        [Parameter(Mandatory = $true)][string]$SearchRoot,
        [switch]$Unattended
    )
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $candidate = [IO.Path]::GetFullPath($RequestedRoot)
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "RunRoot not found: $candidate" }
        return $candidate
    }
    $runs = @(Get-SasRecoverableRuns -Root $SearchRoot)
    if ($runs.Count -eq 0) { throw 'No one-target AutoLogon run is eligible for automatic WinRM-blocker recovery.' }
    if ($runs.Count -eq 1) { return $runs[0].FullName }
    if ($Unattended) {
        throw "Multiple recoverable runs exist. Supply -RunRoot explicitly: $(@($runs.Name) -join ', ')"
    }
    Write-Host ''
    Write-Host 'Recoverable AutoLogon runs:' -ForegroundColor Yellow
    for ($index = 0; $index -lt $runs.Count; $index++) {
        Write-Host ('  [{0}] {1}' -f ($index + 1), $runs[$index].Name)
    }
    $selection = Read-Host 'Choose the run number'
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $runs.Count) {
        throw 'No valid recovery run was selected.'
    }
    return $runs[$number - 1].FullName
}

function Get-SasRecoveryTarget {
    param([Parameter(Mandatory = $true)][string]$Root)
    $requestFile = @(Get-ChildItem -LiteralPath $Root -Filter 'validated_deployment_request_*.json' -File -Recurse -ErrorAction Stop |
        Where-Object { $_.FullName -notmatch '[\\/]recovery[\\/]' })
    if ($requestFile.Count -ne 1) { throw 'Selected run no longer has exactly one preserved validated request.' }
    $request = Get-Content -LiteralPath $requestFile[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $targets = @($request.targets | ForEach-Object { [string]$_ })
    if ($targets.Count -ne 1) { throw 'Selected recovery run is not a one-target pilot.' }
    return $targets[0]
}

function Open-SasRecoveryFolder {
    param([string]$Path, [switch]$Suppress)
    if ($Suppress -or [string]::IsNullOrWhiteSpace($Path)) { return }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($Path) | Out-Null
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$recoveryScript = Join-Path $PSScriptRoot 'Invoke-SasAutoLogonWinRmRecovery.ps1'
if (-not (Test-Path -LiteralPath $recoveryScript -PathType Leaf)) { throw "Recovery orchestrator not found: $recoveryScript" }
$searchRoot = Join-Path $repoRoot 'survey\output\runs\autologon-proof'

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon WinRM Blocker Recovery' -ForegroundColor Cyan
    Write-Host 'Use this only when the preserved run stopped before any install or SMB adapter result was emitted.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '[1] Recover interrupted one-target run'
    Write-Host '[2] Open latest recovery evidence'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Recover' }
        '2' { $Action = 'OpenLatest' }
        'Q' { return }
        default { throw 'No valid recovery action was selected.' }
    }
}

switch ($Action) {
    'Recover' {
        $effectiveRunRoot = Resolve-SasRecoveryRun -RequestedRoot $RunRoot -SearchRoot $searchRoot -Unattended:$NonInteractive
        $target = Get-SasRecoveryTarget -Root $effectiveRunRoot
        Write-Host ''
        Write-Host "Preserved run: $(Split-Path -Leaf $effectiveRunRoot)" -ForegroundColor Cyan
        Write-Host "Authorized target from request: $target" -ForegroundColor Cyan
        Write-Host 'The recovery will run a fresh SMB preflight, harmless live cert, transient state task, and—only when safe—the preserved validated deployment request.' -ForegroundColor Yellow
        Write-Host 'It will not enable WinRM or reboot the workstation.' -ForegroundColor Green
        $ack = $ConfirmText
        if ([string]::IsNullOrWhiteSpace($ack) -and -not $NonInteractive) {
            $ack = Read-Host 'Type RECOVER to continue'
        }
        if ([string]$ack -cne 'RECOVER') { throw 'Recovery acknowledgement was not supplied exactly as RECOVER.' }

        $result = & $recoveryScript -RunRoot $effectiveRunRoot -ComputerName $target `
            -AllowNetworkActivity -AllowTargetMutation -ConfirmRecovery -PassThru
        Write-Host ''
        Write-Host "Recovery classification: $($result.classification)" -ForegroundColor Green
        Write-Host "Evidence: $($result.recovery_root)" -ForegroundColor Green
        Open-SasRecoveryFolder -Path $result.recovery_root -Suppress:$NoOpen
        $result
    }

    'OpenLatest' {
        $latest = Get-ChildItem -LiteralPath $searchRoot -Directory -Filter 'autologon-deploy-*' -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $_.FullName 'recovery') -Directory -Filter 'autologon-recovery-*' -ErrorAction SilentlyContinue } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if (-not $latest) { throw 'No AutoLogon recovery evidence exists yet.' }
        Write-Host "Opening: $($latest.FullName)" -ForegroundColor Cyan
        Open-SasRecoveryFolder -Path $latest.FullName -Suppress:$NoOpen
        [pscustomobject]@{ action='OpenLatest'; recovery_root=$latest.FullName }
    }
}
