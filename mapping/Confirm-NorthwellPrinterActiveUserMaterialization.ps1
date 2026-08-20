#Requires -Version 5.1
<#
.SYNOPSIS
    Finishes a successful SYSTEM-wide Northwell printer registration by making the
    queue available immediately to an already logged-on user and proving that state.

.DESCRIPTION
    PrintUIEntry /ga is durable per-computer registration, but Windows applies that
    connection when a user logs on. This finalizer preserves /ga as the all-users
    authority, then uses a short SYSTEM coordinator task on each target. If a user is
    already logged on, the coordinator starts a passwordless Task Scheduler
    InteractiveToken task in that existing user session, runs PrintUIEntry /in, and
    verifies the user's printer-connection registry state. If nobody is logged on,
    the existing /ga registration remains valid and is explicitly reported as
    pending the next logon instead of being called immediately available.

    No test page is printed and no direct-IP or credential fallback is used.
#>

[CmdletBinding()]
param(
    [string]$EvidenceRoot,

    [ValidateRange(30, 180)]
    [int]$TimeoutSeconds = 90,

    [switch]$KeepRemoteArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
$agentPath = Join-Path $PSScriptRoot 'Agents\Invoke-NorthwellPrinterActiveUserAgent.ps1'
$latestPointer = Join-Path $PSScriptRoot 'Logs\LATEST-PATH.txt'

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Printer core module not found: $modulePath" }
if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) { throw "Active-user printer agent not found: $agentPath" }
Import-Module $modulePath -Force -ErrorAction Stop

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) { throw 'Run the active-user printer finalizer from an elevated controller session.' }

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    if (-not (Test-Path -LiteralPath $latestPointer -PathType Leaf)) { throw "Latest printer evidence pointer not found: $latestPointer" }
    $EvidenceRoot = ([string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction Stop)).Trim()
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    throw "Printer evidence root does not exist: $EvidenceRoot"
}
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)

function Get-SasMappingGroupsFromEvidence {
    param([Parameter(Mandatory)][string]$Root)

    $summaryPath = Join-Path $Root 'Summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Summary.json not found: $summaryPath" }
    $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not [bool]$summary.Success) { throw 'Active-user materialization requires an already successful machine-wide mapping run.' }

    if ([string]$summary.Mode -eq 'NorthwellPrinterBatch') {
        $groups = New-Object System.Collections.Generic.List[object]
        foreach ($result in @($summary.Results)) {
            if (-not [bool]$result.Success) { throw "Batch group $($result.Group) did not have successful machine-wide proof." }
            $groupRoot = [string]$result.Evidence
            $childSummaryPath = Join-Path $groupRoot 'Summary.json'
            if (-not (Test-Path -LiteralPath $childSummaryPath -PathType Leaf)) { throw "Batch child Summary.json not found: $childSummaryPath" }
            $child = Get-Content -LiteralPath $childSummaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not [bool]$child.Success) { throw "Batch child mapping proof is not successful: $childSummaryPath" }
            $groups.Add([pscustomobject]@{
                Root = $groupRoot
                Computers = @($child.Computers)
                Printers = @($child.Printers)
            })
        }
        return $groups.ToArray()
    }

    if ([string]$summary.Mode -ne 'MachineWidePerComputer') {
        throw "Unsupported printer evidence mode for active-user materialization: $($summary.Mode)"
    }
    return ,([pscustomobject]@{
        Root = $Root
        Computers = @($summary.Computers)
        Printers = @($summary.Printers)
    })
}

function Get-SasMappingStatusForComputer {
    param(
        [Parameter(Mandatory)][string]$GroupRoot,
        [Parameter(Mandatory)][string]$Computer
    )

    $computerKey = ([string]$Computer).Split('.')[0].ToLowerInvariant()
    foreach ($file in @(Get-ChildItem -LiteralPath $GroupRoot -Filter 'Status.json' -File -Recurse -ErrorAction Stop)) {
        try {
            $status = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $statusKey = ([string]$status.ComputerName).Split('.')[0].ToLowerInvariant()
            if ($statusKey -eq $computerKey) { return $status }
        }
        catch {}
    }
    throw "Machine-wide Status.json was not found for $Computer under $GroupRoot"
}

function Invoke-SasRemoteTaskScheduler {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Stage
    )

    $output = @(& schtasks.exe @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Remote Task Scheduler $Stage failed for $Computer with exit code $exitCode. $($output -join ' ')"
    }
}

$groups = @(Get-SasMappingGroupsFromEvidence -Root $EvidenceRoot)
$results = New-Object System.Collections.Generic.List[object]

foreach ($group in $groups) {
    $printers = @($group.Printers | ForEach-Object { ([string]$_).Trim() } | Sort-Object -Unique)
    if ($printers.Count -eq 0) { throw "No printers were found in mapping evidence: $($group.Root)" }

    foreach ($computer in @($group.Computers | Sort-Object -Unique)) {
        $status = Get-SasMappingStatusForComputer -GroupRoot $group.Root -Computer $computer
        $null = Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters $printers

        $runToken = New-SasNorthwellPrinterRunToken
        $remoteRel = "ProgramData\SysAdminSuite\Mapping\NorthwellPrinterUser\$runToken"
        $remoteAdminDir = "\\$computer\C$\$remoteRel"
        $remoteAgentAdmin = Join-Path $remoteAdminDir 'Agent.ps1'
        $remoteConfigAdmin = Join-Path $remoteAdminDir 'Config.json'
        $remoteLauncherAdmin = Join-Path $remoteAdminDir 'Start-Agent.cmd'
        $remoteStatusAdmin = Join-Path $remoteAdminDir 'MaterializationStatus.json'
        $remoteAgentLocal = "C:\$remoteRel\Agent.ps1"
        $remoteConfigLocal = "C:\$remoteRel\Config.json"
        $remoteWorkLocal = "C:\$remoteRel"
        $remoteLauncherLocal = "C:\$remoteRel\Start-Agent.cmd"
        $taskName = "SysAdminSuite_NorthwellPrinterUser_$runToken"
        $taskCreated = $false

        $safeComputer = ([string]$computer -replace '[^A-Za-z0-9.-]', '_')
        $localEvidenceDir = Join-Path $group.Root $safeComputer
        New-Item -ItemType Directory -Path $localEvidenceDir -Force | Out-Null
        $localStatusPath = Join-Path $localEvidenceDir 'ActiveUserMaterialization.json'

        try {
            New-Item -ItemType Directory -Path $remoteAdminDir -Force -ErrorAction Stop | Out-Null
            Copy-Item -LiteralPath $agentPath -Destination $remoteAgentAdmin -Force -ErrorAction Stop
            [ordered]@{ Printers = $printers } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $remoteConfigAdmin -Encoding UTF8

            $launcher = '@echo off' + "`r`n" +
                ('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}" -WorkDir "{2}"' -f $remoteAgentLocal, $remoteConfigLocal, $remoteWorkLocal) + "`r`n"
            Set-Content -LiteralPath $remoteLauncherAdmin -Value $launcher -Encoding ASCII

            $createArgs = @(New-SasNorthwellPrinterTaskCreateArguments -Computer $computer -TaskName $taskName -RemoteLauncherLocal $remoteLauncherLocal)
            Invoke-SasRemoteTaskScheduler -Arguments $createArgs -Computer $computer -Stage 'Create'
            $taskCreated = $true
            Invoke-SasRemoteTaskScheduler -Arguments @('/Run','/S',$computer,'/TN',$taskName) -Computer $computer -Stage 'Run'

            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            while (-not (Test-Path -LiteralPath $remoteStatusAdmin -PathType Leaf) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 1
            }
            if (-not (Test-Path -LiteralPath $remoteStatusAdmin -PathType Leaf)) {
                throw "Active-user materialization evidence was not returned within $TimeoutSeconds seconds."
            }

            Copy-Item -LiteralPath $remoteStatusAdmin -Destination $localStatusPath -Force -ErrorAction Stop
            $materialization = Get-Content -LiteralPath $localStatusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not [bool]$materialization.Success) {
                $detail = if ($materialization.PSObject.Properties['Error']) { [string]$materialization.Error } else { [string]$materialization.Disposition }
                throw "Active-user printer connection was not verified on $computer. $detail"
            }

            $pending = $false
            if ($materialization.PSObject.Properties['PendingNextLogon']) { $pending = [bool]$materialization.PendingNextLogon }
            $activeUser = ''
            if ($materialization.PSObject.Properties['ActiveUser']) { $activeUser = [string]$materialization.ActiveUser }
            $materialized = $false
            if ($materialization.PSObject.Properties['Materialized']) { $materialized = [bool]$materialization.Materialized }

            $results.Add([pscustomobject][ordered]@{
                Computer = $computer
                Printers = $printers
                Success = $true
                ActiveUser = $activeUser
                Materialized = $materialized
                PendingNextLogon = $pending
                Disposition = [string]$materialization.Disposition
                Evidence = $localStatusPath
            })
        }
        catch {
            $results.Add([pscustomobject][ordered]@{
                Computer = $computer
                Printers = $printers
                Success = $false
                ActiveUser = $null
                Materialized = $false
                PendingNextLogon = $false
                Disposition = 'FINALIZATION_FAILED'
                Error = $_.Exception.Message
                Evidence = $localStatusPath
            })
        }
        finally {
            if ($taskCreated) {
                try { & schtasks.exe /Delete /F /S $computer /TN $taskName 2>&1 | Out-Null } catch {}
            }
            if (-not $KeepRemoteArtifacts) {
                try { Remove-Item -LiteralPath $remoteAdminDir -Recurse -Force -ErrorAction Stop } catch {}
            }
        }
    }
}

$failed = @($results | Where-Object { -not $_.Success })
$pending = @($results | Where-Object { $_.Success -and $_.PendingNextLogon })
$materialized = @($results | Where-Object { $_.Success -and $_.Materialized })
$summaryPath = Join-Path $EvidenceRoot 'ActiveUserMaterialization.json'
[ordered]@{
    SchemaVersion = 'sas-northwell-printer-active-user/v1'
    Success = ($failed.Count -eq 0)
    MachineWideRegistrationRequired = $true
    ImmediateActiveUserConnectionRequiredWhenLoggedOn = $true
    TestPagesPrinted = $false
    DirectIpMapping = $false
    MaterializedTargets = $materialized.Count
    PendingNextLogonTargets = $pending.Count
    FailedTargets = $failed.Count
    Results = $results.ToArray()
    Updated = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ''
foreach ($result in $results) {
    if (-not $result.Success) {
        Write-Host ("FAIL: {0} - {1}" -f $result.Computer, $result.Error) -ForegroundColor Red
    }
    elseif ($result.PendingNextLogon) {
        Write-Host ("REGISTERED: {0} - no interactive user is logged on; /ga will apply at the next logon." -f $result.Computer) -ForegroundColor Yellow
    }
    else {
        Write-Host ("READY: {0} - active user {1} has the requested printer connection now." -f $result.Computer, $result.ActiveUser) -ForegroundColor Green
    }
}
Write-Host ("Active-user evidence: {0}" -f $summaryPath) -ForegroundColor DarkGray

if ($failed.Count -gt 0) {
    throw "Printer registration exists, but immediate active-user connection failed on $($failed.Count) target(s)."
}
