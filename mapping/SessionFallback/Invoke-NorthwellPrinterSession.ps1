#Requires -Version 5.1
<#
.SYNOPSIS
  Endpoint-only Northwell user-session printer materializer and privileged one-shot cleanup.
.DESCRIPTION
  The administrator-owned config binds this agent to the already-proven SYSTEM /ga
  queues. This never registers /ga, installs drivers, changes policy or maps by IP.
  Run is invoked in the actual logged-on user's token (Task Scheduler or Startup).
  CleanupOnce is invoked by a SYSTEM logon task and removes ONLY its owned one-shot
  Startup launcher after observing matching HKU queue proof and a user receipt.
#>
[CmdletBinding()]
param([ValidateSet('Run','CleanupOnce','Status')][string]$Mode='Run')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramData 'SysAdminSuite\PrinterSessionFallback'
$configPath = Join-Path $root 'assignment.v1.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Approved printer session-fallback assignment is absent.' }
$config = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ($config.SchemaVersion -cne 'sas-northwell-printer-session-fallback/v1') { throw 'Unknown fallback config contract.' }
if (([string]$config.ComputerName).Split('.')[0] -ine $env:COMPUTERNAME) { throw 'Fallback hostname does not match this workstation.' }
$queues = @($config.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object -Unique)
if ($queues.Count -eq 0) { throw 'Fallback has no queues.' }
foreach ($queue in $queues) {
    if ($queue -notmatch '^\\\\[A-Za-z0-9][A-Za-z0-9._-]*\\[A-Za-z0-9][A-Za-z0-9._$-]*$') { throw 'Invalid approved shared UNC printer identity.' }
}
$token = [string]$config.ReceiptToken
if ($token -notmatch '^[a-f0-9]{32}$') { throw 'Invalid fallback binding token.' }

function Get-SasPrinterConnections {
    param([Parameter(Mandatory)][string]$RegistryPath)
    if (-not (Test-Path -LiteralPath $RegistryPath)) { return @() }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(Get-ChildItem -LiteralPath $RegistryPath -ErrorAction Stop)) {
        $key = ([string]$entry.PSChildName).ToLowerInvariant()
        if ($key -match '^,,([^,]+),(.+)$') { $found.Add(('\\{0}\{1}' -f $Matches[1],$Matches[2]).ToLowerInvariant()) }
        elseif ($key -match '^\\\\[^\\]+\\[^\\]+$') { $found.Add($key) }
    }
    return @($found.ToArray() | Sort-Object -Unique)
}

function Assert-SasMachineProof {
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
    $registered = @(Get-SasPrinterConnections -RegistryPath $key)
    foreach ($queue in $queues) {
        if ($registered -notcontains $queue) { throw "Approved machine /ga registration not currently proven for $queue." }
    }
}

function Test-SasSessionProof {
    param([Parameter(Mandatory)][string]$RegistryPath)
    $actual = @(Get-SasPrinterConnections -RegistryPath $RegistryPath)
    return (@($queues | Where-Object { $actual -notcontains $_ }).Count -eq 0)
}

Assert-SasMachineProof

if ($Mode -eq 'Status') {
    [pscustomobject]@{ Result='MACHINE_WIDE_REGISTERED'; Computer=$env:COMPUTERNAME; Queues=$queues; Stage=$config.StageMode; ReceiptToken=$token }
    return
}

if ($Mode -eq 'Run') {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.IsSystem) { throw 'Per-user materialization cannot run under SYSTEM.' }
    $userKey = 'Registry::HKEY_CURRENT_USER\Printers\Connections'
    $verified = Test-SasSessionProof -RegistryPath $userKey
    if (-not $verified) {
        $rundll = Join-Path $env:SystemRoot 'System32\rundll32.exe'
        if (-not (Test-Path -LiteralPath $rundll -PathType Leaf)) { throw 'Windows PrintUI is unavailable.' }
        foreach ($queue in $queues) {
            & $rundll 'printui.dll,PrintUIEntry' '/in' '/q' ("/n{0}" -f $queue)
        }
        $deadline = (Get-Date).AddSeconds(90)
        do {
            Start-Sleep -Seconds 2
            $verified = Test-SasSessionProof -RegistryPath $userKey
        } while (-not $verified -and (Get-Date) -lt $deadline)
    }
    if (-not $verified) { throw 'Printer session remains unproven for this user; Startup helper is retained.' }

    # The HKCU marker is a diagnostic handoff to privileged cleanup, NOT proof on its own.
    $receiptKey = 'HKCU:\Software\SysAdminSuite\PrinterSessionFallback'
    $null = New-Item -Path $receiptKey -Force -ErrorAction Stop
    $null = New-ItemProperty -Path $receiptKey -Name ReceiptToken -Value $token -PropertyType String -Force -ErrorAction Stop
    $null = New-ItemProperty -Path $receiptKey -Name VerifiedUtc -Value ([datetime]::UtcNow.ToString('o')) -PropertyType String -Force -ErrorAction Stop

    $receiptDirectory = Join-Path $env:LOCALAPPDATA 'SysAdminSuite\Printer'
    New-Item -Path $receiptDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $receipt = [ordered]@{
        SchemaVersion='sas-northwell-printer-user-proof/v1'
        Result='USER_SESSION_VERIFIED'
        Computer=$env:COMPUTERNAME
        UserSid=$identity.User.Value
        UserName=$identity.Name
        Printers=$queues
        OriginMachineProof=[string]$config.OriginEvidence
        StageMode=[string]$config.StageMode
        VerifiedUtc=[datetime]::UtcNow.ToString('o')
        TestPagePrinted=$false
    }
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $receiptDirectory 'latest-printer-session.json') -Encoding UTF8 -ErrorAction Stop
    Write-Host 'USER_SESSION_VERIFIED: Approved printer connections are present in HKCU.'
    return
}

# Only the privileged SYSTEM cleanup task may remove Common Startup artifacts.
if (-not ([Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem) { throw 'CleanupOnce requires SYSTEM.' }
if ([string]$config.StageMode -ne 'OneShot') { throw 'CleanupOnce is not applicable to a durable logon task.' }
$successSid = $null
$hku = 'Registry::HKEY_USERS'
foreach ($hive in @(Get-ChildItem -LiteralPath $hku -ErrorAction Stop)) {
    $sid = [string]$hive.PSChildName
    if ($sid -notmatch '^S-1-5-21-(\d+-){3}\d+$') { continue }
    $receiptPath = "Registry::HKEY_USERS\$sid\Software\SysAdminSuite\PrinterSessionFallback"
    if (-not (Test-Path -LiteralPath $receiptPath)) { continue }
    $saved = Get-ItemProperty -LiteralPath $receiptPath -Name ReceiptToken -ErrorAction SilentlyContinue
    if ($null -eq $saved -or [string]$saved.ReceiptToken -cne $token) { continue }
    if (Test-SasSessionProof -RegistryPath "Registry::HKEY_USERS\$sid\Printers\Connections") {
        $successSid = $sid
        break
    }
}
if ($null -eq $successSid) { throw 'No logged-on user has both an exact receipt and HKU printer proof; keeping Startup helper.' }

$startupPath = [string]$config.StartupPath
if ($startupPath -notmatch '^[A-Z]:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\SAS-NorthwellPrinter-OneShot\.cmd$') {
    throw 'Unsafe or unexpected Startup cleanup target.'
}
if (Test-Path -LiteralPath $startupPath -PathType Leaf) {
    $actualHash = (Get-FileHash -LiteralPath $startupPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($actualHash -ine [string]$config.StartupSha256) { throw 'Startup helper changed after staging; manual review required.' }
    Remove-Item -LiteralPath $startupPath -Force -ErrorAction Stop
}
if (Test-Path -LiteralPath $startupPath) { throw 'Startup launcher cleanup failed.' }
$proofPath = Join-Path $root 'one-shot-cleanup.v1.json'
[ordered]@{ Result='ONESHOT_CLEANED'; Computer=$env:COMPUTERNAME; VerifiedSid=$successSid; DeletedStartup=$startupPath; Proof=[datetime]::UtcNow.ToString('o') } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $proofPath -Encoding UTF8 -ErrorAction Stop
$svc = New-Object -ComObject 'Schedule.Service'
$svc.Connect()
$svc.GetFolder('\').DeleteTask('SysAdminSuite_NorthwellPrinterOneShotCleanup',0)
Write-Host 'ONESHOT_CLEANED: Per-user queue proof observed; owned Startup launcher and cleanup task retired.'
