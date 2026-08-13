#Requires -Version 5.1
<#
.SYNOPSIS
Operator-friendly AutoLogon launcher for field use.

.DESCRIPTION
Keeps canonical LocalSystem qualification available for a future materially different candidate,
and routes the supported field deployment through one AutoLogon-only transaction that owns
protected-network proof, canonical target resolution, interrupted probe-only recovery, S4U apply,
bounded restart observation, cleanup proof, persistent operator state, and terminal evidence.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Prepare','Validate','Pilot','Remote','S4U','Recover','Evidence')]
    [string]$Action = 'Menu',
    [string]$ComputerName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$qualificationScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
$fieldDeploymentScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonFieldDeployment.ps1'
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'

foreach ($required in @($templatePath,$qualificationScript,$fieldDeploymentScript,$networkGate)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing on-site AutoLogon dependency: $required"
    }
}

function Get-SasQualificationRequests {
    if (-not (Test-Path -LiteralPath $requestDirectory -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $requestDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

function New-SasLocalQualificationRequest {
    New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
    $destination = Join-Path $requestDirectory 'qualification-request.local.json'
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Copy-Item -LiteralPath $templatePath -Destination $destination
        Write-Host 'Created an operator-local qualification request from the tracked template.' -ForegroundColor Green
    }
    else {
        Write-Host 'Using the existing operator-local qualification request.' -ForegroundColor Cyan
    }
    Write-Host "Request: $destination"
    Write-Host 'This path is ignored by git. Replace every REPLACE/placeholder field with approved real values.' -ForegroundColor Yellow
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList @($destination) | Out-Null }
    catch { Write-Warning "Could not open Notepad automatically: $($_.Exception.Message)" }
    return $destination
}

function Confirm-SasRequestExists {
    $requests = @(Get-SasQualificationRequests)
    if ($requests.Count -gt 0) { return $true }
    [void](New-SasLocalQualificationRequest)
    Write-Host ''
    Write-Host 'No live or validation action was started.' -ForegroundColor Yellow
    Write-Host 'Complete the request, save it, then rerun this launcher.'
    return $false
}

function Resolve-SasRemoteTarget {
    param([string]$RequestedTarget)
    if (-not [string]::IsNullOrWhiteSpace($RequestedTarget)) {
        return $RequestedTarget.Trim()
    }
    $typed = (Read-Host 'Enter the exact authorized Cybernet hostname or FQDN').Trim()
    if ([string]::IsNullOrWhiteSpace($typed)) {
        throw 'An explicit target is required for the remote AutoLogon deployment.'
    }
    return $typed
}

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon On-Site' -ForegroundColor Cyan
    Write-Host 'Remote Kerberos/S4U is the supported field deployment lane; LocalSystem qualification remains a separate future-candidate lane.' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '[1] Deploy AutoLogon: canonicalize target, converge safe probe recovery, apply once, restart, verify cleanup'
    Write-Host '[2] Recover safely recorded interrupted probe-only runs without installing AutoLogon'
    Write-Host '[3] Prepare/edit LocalSystem qualification request for a different candidate'
    Write-Host '[4] Validate LocalSystem qualification request (no target contact)'
    Write-Host '[5] Run controlled LocalSystem qualification pilot (requires different candidate)'
    Write-Host '[6] Open latest LocalSystem qualification evidence'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Remote' }
        '2' { $Action = 'Recover' }
        '3' { $Action = 'Prepare' }
        '4' { $Action = 'Validate' }
        '5' { $Action = 'Pilot' }
        '6' { $Action = 'Evidence' }
        'Q' { return }
        default { throw 'No valid on-site AutoLogon action was selected.' }
    }
}

switch ($Action) {
    'Prepare' {
        $requests = @(Get-SasQualificationRequests)
        if ($requests.Count -eq 0) {
            [void](New-SasLocalQualificationRequest)
        }
        elseif ($requests.Count -eq 1) {
            Write-Host "Opening request: $($requests[0].FullName)"
            Start-Process -FilePath 'notepad.exe' -ArgumentList @($requests[0].FullName) | Out-Null
        }
        else {
            Write-Host "Multiple requests exist under: $requestDirectory"
            Start-Process -FilePath 'explorer.exe' -ArgumentList @($requestDirectory) | Out-Null
        }
        return
    }
    'Validate' {
        if (-not (Confirm-SasRequestExists)) { exit 4 }
        & $qualificationScript -Action Plan
        return
    }
    'Pilot' {
        if (-not (Confirm-SasRequestExists)) { exit 4 }
        & $qualificationScript -Action Live
        exit $LASTEXITCODE
    }
    'Recover' {
        $target = Resolve-SasRemoteTarget -RequestedTarget $ComputerName
        & $fieldDeploymentScript -Action Recover -ComputerName $target
        exit $LASTEXITCODE
    }
    { $_ -in @('Remote','S4U') } {
        $target = Resolve-SasRemoteTarget -RequestedTarget $ComputerName
        & $fieldDeploymentScript -Action Remote -ComputerName $target
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $qualificationScript -Action OpenLatest
        return
    }
}
