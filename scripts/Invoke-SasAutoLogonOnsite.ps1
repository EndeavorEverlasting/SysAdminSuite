#Requires -Version 5.1
<##
.SYNOPSIS
Operator-friendly AutoLogon qualification launcher for field use.

.DESCRIPTION
Keeps request preparation and validation available on guest/off-network connections, but gates
all live target activity on approved Northwell network posture. If no local qualification request
exists, copies the tracked example into the ignored survey/input workspace and opens it for editing
instead of failing with a raw missing-file exception.
##>
[CmdletBinding()]
param(
    [ValidateSet('Menu','Prepare','Validate','Pilot','Evidence')]
    [string]$Action = 'Menu'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$requestDirectory = Join-Path $repoRoot 'survey\input\autologon-system-qualification'
$templatePath = Join-Path $repoRoot 'configs\software-packages\autologon-system-qualification-request.example.json'
$qualificationScript = Join-Path $repoRoot 'scripts\Invoke-SasAutoLogonSystemQualification.ps1'
$networkGate = Join-Path $repoRoot 'scripts\Confirm-SasNorthwellNetwork.ps1'

foreach ($required in @($templatePath,$qualificationScript,$networkGate)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing on-site qualification dependency: $required"
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
    $requests = Get-SasQualificationRequests
    if ($requests.Count -gt 0) { return $true }
    [void](New-SasLocalQualificationRequest)
    Write-Host ''
    Write-Host 'No live or validation action was started.' -ForegroundColor Yellow
    Write-Host 'Complete the request, save it, then rerun this launcher.'
    return $false
}

if ($Action -eq 'Menu') {
    Clear-Host
    Write-Host 'SysAdminSuite AutoLogon On-Site Qualification' -ForegroundColor Cyan
    Write-Host 'Paths are repo-relative. Guest network is safe for request preparation/validation only.' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '[1] Prepare/edit qualification request (guest-safe)'
    Write-Host '[2] Validate qualification request (guest-safe; no target contact)'
    Write-Host '[3] Run controlled LocalSystem pilot (Northwell network required)'
    Write-Host '[4] Open latest qualification evidence'
    Write-Host '[Q] Quit'
    $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
    switch ($choice) {
        '1' { $Action = 'Prepare' }
        '2' { $Action = 'Validate' }
        '3' { $Action = 'Pilot' }
        '4' { $Action = 'Evidence' }
        'Q' { return }
        default { throw 'No valid on-site qualification action was selected.' }
    }
}

switch ($Action) {
    'Prepare' {
        $requests = Get-SasQualificationRequests
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
        exit $LASTEXITCODE
    }
    'Pilot' {
        if (-not (Confirm-SasRequestExists)) { exit 4 }
        Write-Host ''
        Write-Host 'Checking local network posture before any target contact...' -ForegroundColor Cyan
        & $networkGate -Purpose 'AutoLogon LocalSystem qualification pilot'
        $networkExit = $LASTEXITCODE
        if ($networkExit -ne 0) {
            Write-Host "AutoLogon pilot stopped by the network gate with exit code $networkExit." -ForegroundColor Yellow
            exit $networkExit
        }
        & $qualificationScript -Action Live
        exit $LASTEXITCODE
    }
    'Evidence' {
        & $qualificationScript -Action OpenLatest
        exit $LASTEXITCODE
    }
}
