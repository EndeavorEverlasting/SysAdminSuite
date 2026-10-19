#Requires -Version 5.1
<#
.SYNOPSIS
  Approved-controller delivery for a Northwell printer user-session recovery.
.DESCRIPTION
  Requires successful canonical SYSTEM/HKLM Status.json evidence for exactly one
  approved workstation, an elevated Northwell controller and authorized C$/remote
  Task Scheduler access. Does not rerun mapping, change driver or security policy.
  -Plan does not mutate any remote target. Stage modes require explicit APPLY.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Task','OneShot','Status','Remove')][string]$Mode,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,62}(\.[A-Za-z0-9-]+)*$')][string]$ComputerName,
    [string]$EvidenceRoot,
    [switch]$Plan,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$core = Join-Path $repoRoot 'mapping\Modules\NorthwellPrinterMapping.Core.psm1'
$authorityModule = Join-Path $repoRoot 'scripts\SasNorthwellNetworkAuthority.psm1'
$endpointAgent = Join-Path $PSScriptRoot 'Invoke-NorthwellPrinterSession.ps1'
foreach ($required in @($core,$authorityModule,$endpointAgent)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required SysAdminSuite dependency missing: $required" }
}
Import-Module $core -Force -ErrorAction Stop
Import-Module $authorityModule -Force -ErrorAction Stop
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'A protected-network elevated controller session is required.' }
$networkProof = Assert-SasNorthwellNetwork
if ($null -eq $networkProof) { throw 'Northwell network authority was not proved.' }
$shortHost = $ComputerName.Split('.')[0].ToUpperInvariant()
$remoteRoot = "\\$ComputerName\C$\ProgramData\SysAdminSuite\PrinterSessionFallback"
$targetRoot = 'C:\ProgramData\SysAdminSuite\PrinterSessionFallback'
$remoteConfig = Join-Path $remoteRoot 'assignment.v1.json'
$remoteAgent = Join-Path $remoteRoot 'Invoke-NorthwellPrinterSession.ps1'
$normalTask = 'SysAdminSuite_NorthwellPrinterSession'
$cleanupTask = 'SysAdminSuite_NorthwellPrinterOneShotCleanup'
$startupName = 'SAS-NorthwellPrinter-OneShot.cmd'

function Get-SasRemoteSchedule {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect($ComputerName)
    return $svc
}
function Get-SasTaskOrNull {
    param([Parameter(Mandatory)]$Folder,[Parameter(Mandatory)][string]$Name)
    try { return $Folder.GetTask($Name) } catch { return $null }
}
function Get-SasKnownCommonStartup {
    $key = "\\$ComputerName\HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
    $output = @(& reg.exe QUERY $key /v 'Common Startup' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve target Windows Common Startup via protected Remote Registry.' }
    $location = $null
    foreach ($line in $output) {
        if ([string]$line -match '^\s*Common Startup\s+REG_(?:EXPAND_)?SZ\s+([A-Za-z]:\\.+?)\s*$') {
            $location = $Matches[1].Trim()
        }
    }
    if ([string]::IsNullOrWhiteSpace($location)) { throw 'Windows Common Startup registry location unavailable.' }
    if ($location -notmatch '^[A-Z]:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup$') {
        throw "Unexpected Common Startup location; manual review required: $location"
    }
    $drive = $location.Substring(0,1)
    return [pscustomobject]@{
        TargetPath=$location
        AdminPath=("\\$ComputerName\{0}$\{1}" -f $drive,$location.Substring(3))
    }
}
function New-SasLogonTask {
    param([Parameter(Mandatory)]$Service,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$InvocationMode,[switch]$SystemPrincipal)
    $folder = $Service.GetFolder('\')
    $definition = $Service.NewTask(0)
    $definition.RegistrationInfo.Description = 'SysAdminSuite Northwell approved-queue session materialization / cleanup.'
    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $false
    $definition.Settings.ExecutionTimeLimit = 'PT4M'
    $definition.Settings.MultipleInstances = 2
    $trigger = $definition.Triggers.Create(9) # TASK_TRIGGER_LOGON
    $trigger.Enabled = $true
    if ($SystemPrincipal) {
        $definition.Principal.UserId = 'SYSTEM'
        $definition.Principal.LogonType = 5 # TASK_LOGON_SERVICE_ACCOUNT
        $definition.Principal.RunLevel = 1
        $trigger.Delay = 'PT2M'
        $logon = 5
    }
    else {
        $definition.Principal.GroupId = 'S-1-5-32-545' # BUILTIN\Users
        $definition.Principal.LogonType = 4 # TASK_LOGON_GROUP
        $definition.Principal.RunLevel = 0
        $logon = 4
    }
    $action = $definition.Actions.Create(0)
    $action.Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $action.Arguments = '-NoLogo -NoProfile -File "{0}\Invoke-NorthwellPrinterSession.ps1" -Mode {1}' -f $targetRoot,$InvocationMode
    $null = $folder.RegisterTaskDefinition($Name,$definition,6,$null,$null,$logon,$null)
    if ($null -eq (Get-SasTaskOrNull -Folder $folder -Name $Name)) { throw "Task creation not proven: $Name" }
}
function Assert-SasM0Evidence {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw 'EvidenceRoot is required before staging.' }
    $root = [IO.Path]::GetFullPath($EvidenceRoot)
    $summaryPath = Join-Path $root 'Summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw 'Canonical Summary.json not found.' }
    $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not [bool]$summary.Success -or [string]$summary.Mode -ne 'MachineWidePerComputer' -or [string]$summary.DesiredState -ne 'Present') {
        throw 'Expected successful single-target canonical Northwell SYSTEM /ga Present evidence.'
    }
    if (@($summary.Computers).Count -ne 1 -or ([string]@($summary.Computers)[0]).Split('.')[0] -ine $shortHost) {
        throw 'Target host mismatch with canonical mapping Summary.json.'
    }
    $printers = @($summary.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object -Unique)
    if ($printers.Count -lt 1) { throw 'Canonical evidence lists no requested printers.' }
    foreach ($printer in $printers) {
        if ($printer -notmatch '^\\\\[A-Za-z0-9][A-Za-z0-9._-]*\\[A-Za-z0-9][A-Za-z0-9._$-]*$') { throw 'Approved printer must be a safe Northwell shared UNC queue.' }
    }
    $statusItems = @(Get-ChildItem -LiteralPath $root -Filter 'Status.json' -Recurse -File -ErrorAction Stop)
    $matched = @($statusItems | Where-Object {
        try { (([string](Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).ComputerName).Split('.')[0] -ieq $shortHost) } catch { $false }
    })
    if ($matched.Count -ne 1) { throw 'Exactly one canonical target Status.json is required.' }
    $status = Get-Content -LiteralPath $matched[0].FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $null = Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters $printers -DesiredState Present
    return [pscustomobject]@{ Root=$root; Printers=$printers }
}

$svc = Get-SasRemoteSchedule
$folder = $svc.GetFolder('\')
if ($Mode -in @('Status','Remove')) {
    $existing = if (Test-Path -LiteralPath $remoteConfig -PathType Leaf) {
        Get-Content -LiteralPath $remoteConfig -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } else { $null }
    if ($Mode -eq 'Status') {
        [pscustomobject]@{
            Result=if ($null -eq $existing) {'NOT_STAGED'} else {'STAGED_NOT_LIVE_CERTIFIED'}
            Computer=$ComputerName
            Mode=if ($null -eq $existing) {$null} else {$existing.StageMode}
            DurableTask=($null -ne (Get-SasTaskOrNull -Folder $folder -Name $normalTask))
            CleanupTask=($null -ne (Get-SasTaskOrNull -Folder $folder -Name $cleanupTask))
            CleanupReceipt=(Test-Path -LiteralPath (Join-Path $remoteRoot 'one-shot-cleanup.v1.json'))
        }
        return
    }
    if (-not $Apply) { throw 'Remove requires explicit -Apply.' }
    if ($null -ne $existing -and [string]$existing.StageMode -eq 'OneShot') {
        $startup = Get-SasKnownCommonStartup
        $startupFile = Join-Path $startup.AdminPath $startupName
        if (Test-Path -LiteralPath $startupFile -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $startupFile -Algorithm SHA256).Hash -ine [string]$existing.StartupSha256) {
                throw 'One-shot Startup payload differs from approved copy; do not delete unrelated file.'
            }
            Remove-Item -LiteralPath $startupFile -Force -ErrorAction Stop
        }
    }
    foreach ($taskName in @($normalTask,$cleanupTask)) {
        if ($null -ne (Get-SasTaskOrNull -Folder $folder -Name $taskName)) { $folder.DeleteTask($taskName,0) }
    }
    if (Test-Path -LiteralPath $remoteConfig) { Remove-Item -LiteralPath $remoteConfig -Force -ErrorAction Stop }
    if (Test-Path -LiteralPath $remoteAgent) { Remove-Item -LiteralPath $remoteAgent -Force -ErrorAction Stop }
    Write-Host 'RETIRED: owned printer fallback tasks, config, agent and any matching one-shot Startup launcher.'
    return
}

$proof = Assert-SasM0Evidence
Write-Host ('PLAN: {0} -> {1} approved queue(s), mode {2}.' -f $ComputerName,$proof.Printers.Count,$Mode)
Write-Host ('M0 evidence: {0}' -f $proof.Root)
if ($Plan) { Write-Host 'PLAN_ONLY: no files/tasks were staged.'; return }
if (-not $Apply) { throw 'Staging requires explicit -Apply after reviewing the above plan.' }
if (Test-Path -LiteralPath $remoteConfig -PathType Leaf) { throw 'Existing fallback staged; inspect or Remove explicitly instead of overwriting.' }
if (-not (Test-Path -LiteralPath $remoteRoot -PathType Container)) {
    New-Item -Path $remoteRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
$startup = if ($Mode -eq 'OneShot') { Get-SasKnownCommonStartup } else { $null }
$startupTarget = if ($null -eq $startup) { $null } else { Join-Path $startup.TargetPath $startupName }
$line = '@echo off' + [Environment]::NewLine +
    '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "' +
    $targetRoot + '\Invoke-NorthwellPrinterSession.ps1" -Mode Run' + [Environment]::NewLine
$startupBytes = [Text.Encoding]::ASCII.GetBytes($line)
$hasher = [Security.Cryptography.SHA256]::Create()
try { $expectedHash = ([BitConverter]::ToString($hasher.ComputeHash($startupBytes))).Replace('-','') } finally { $hasher.Dispose() }
$config = [ordered]@{
    SchemaVersion='sas-northwell-printer-session-fallback/v1'
    Organization='northwell-health'
    ComputerName=$shortHost
    Printers=$proof.Printers
    StageMode=$Mode
    ReceiptToken=([guid]::NewGuid().ToString('N'))
    OriginEvidence=$proof.Root
    StartupPath=$startupTarget
    StartupSha256=if ($Mode -eq 'OneShot') {$expectedHash} else {$null}
    StageUtc=[datetime]::UtcNow.ToString('o')
}
# Administrator-owned target payload, verified by SHA256 after SMB staging.
Copy-Item -LiteralPath $endpointAgent -Destination $remoteAgent -ErrorAction Stop
if ((Get-FileHash -LiteralPath $endpointAgent -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $remoteAgent -Algorithm SHA256).Hash) {
    throw 'Remote printer fallback agent integrity check failed.'
}
$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $remoteConfig -Encoding UTF8 -ErrorAction Stop
if ($Mode -eq 'Task') {
    New-SasLogonTask -Service $svc -Name $normalTask -InvocationMode 'Run'
}
else {
    # Register SYSTEM cleanup before placing the executable in Common Startup.
    New-SasLogonTask -Service $svc -Name $cleanupTask -InvocationMode 'CleanupOnce' -SystemPrincipal
    $startupRemote = Join-Path $startup.AdminPath $startupName
    if (Test-Path -LiteralPath $startupRemote) { throw 'Owned-name Startup entry already exists; manual review before overwriting.' }
    [IO.File]::WriteAllBytes($startupRemote,$startupBytes)
    if ((Get-FileHash -LiteralPath $startupRemote -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'Common Startup one-shot SHA256 verification failed.'
    }
}
Write-Host ('STAGED_NOT_LIVE_CERTIFIED: {0}. Validate a real standard-user logon and session connection.' -f $Mode)
