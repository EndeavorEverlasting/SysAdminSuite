#Requires -Version 5.1
<#
.SYNOPSIS
    Materializes already-proven machine-wide Northwell printer connections for
    users who are currently logged on without using C$ or ADMIN$.

.DESCRIPTION
    This helper is used only after the shareless machine-wide transport has proven
    the requested /ga registration through Remote Registry HKLM. It discovers
    loaded interactive user hives through Remote Registry HKU, registers a bounded
    Task Scheduler InteractiveToken task directly through the remote Schedule.Service
    COM API, runs PrintUIEntry /in quietly in each existing user session, and
    accepts success only after Remote Registry HKU proves the per-user connection.

    Native Windows printer-install dialogs are advisory only and are suppressed for
    this unattended action. Remote Registry HKU state remains the authoritative proof.

    No password, SMB payload, WinRM, direct-IP printer mapping, or test page is used.
    If no interactive user hive is loaded, the durable /ga registration remains the
    authority and the result is reported as pending the next logon.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$EvidenceRoot,
    [ValidateRange(30,180)][int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Printer core module not found: $modulePath" }
Import-Module $modulePath -Force -ErrorAction Stop

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) { throw 'Run the shareless active-user finalizer from an elevated controller session.' }

$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
$summaryPath = Join-Path $EvidenceRoot 'Summary.json'
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Summary.json not found: $summaryPath" }
$summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if (-not [bool]$summary.Success) { throw 'Shareless active-user materialization requires an already successful machine-wide mapping run.' }
if ([string]$summary.Mode -ne 'MachineWidePerComputer') { throw "Unsupported printer evidence mode: $($summary.Mode)" }
if ([string]$summary.DesiredState -ne 'Present') { throw "Shareless active-user materialization supports only proven Present state; got '$($summary.DesiredState)'." }
if ([string]$summary.Transport -ne 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE') {
    throw "Shareless active-user materialization requires shareless machine-wide transport; got '$($summary.Transport)'."
}

$computers = @($summary.Computers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
$printers = @($summary.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
if ($computers.Count -lt 1 -or $printers.Count -lt 1) { throw 'Shareless machine-wide evidence has no target computers or printers.' }

function Invoke-SasRemoteRegRead {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $lines = @(& reg.exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{ ExitCode=[int]$LASTEXITCODE; Lines=$lines }
}

function ConvertFrom-SasPrinterConnectionKeyName {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $trimmed = $Name.Trim()
    if ($trimmed -match '^,,([^,]+),(.+)$') { return ('\\{0}\{1}' -f $Matches[1],$Matches[2]).ToLowerInvariant() }
    if ($trimmed -match '^\\\\[^\\]+\\[^\\]+$') { return $trimmed.ToLowerInvariant() }
    return $null
}

function Get-SasMachineWideStatusForComputer {
    param([Parameter(Mandatory)][string]$Computer)
    $key = $Computer.Split('.')[0].ToLowerInvariant()
    foreach ($file in @(Get-ChildItem -LiteralPath $EvidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction Stop)) {
        try {
            $status = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (([string]$status.ComputerName).Split('.')[0].ToLowerInvariant() -eq $key) { return $status }
        }
        catch {}
    }
    throw "Machine-wide Status.json was not found for $Computer under $EvidenceRoot"
}

function Get-SasRemoteInteractiveUsers {
    param([Parameter(Mandatory)][string]$Computer)
    $root = Invoke-SasRemoteRegRead -Computer $Computer -Arguments @('QUERY',"\\$Computer\HKU")
    if ($root.ExitCode -ne 0) { throw "Remote Registry HKU query failed for $Computer with exit code $($root.ExitCode)." }

    $sids = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($root.Lines)) {
        if ($line -match '(?i)^HKEY_USERS\\(S-1-5-21-(?:\d+-){3}\d+)\s*$') { $sids.Add($Matches[1]) }
    }

    $users = New-Object System.Collections.Generic.List[object]
    foreach ($sid in @($sids.ToArray() | Sort-Object -Unique)) {
        $volatile = Invoke-SasRemoteRegRead -Computer $Computer -Arguments @('QUERY',"\\$Computer\HKU\$sid\Volatile Environment",'/s')
        if ($volatile.ExitCode -ne 0) { continue }
        $username = ''
        $domain = ''
        foreach ($line in @($volatile.Lines)) {
            if ([string]::IsNullOrWhiteSpace($username) -and $line -match '^\s*USERNAME\s+REG_[A-Z0-9_]+\s+(.+?)\s*$') { $username = $Matches[1].Trim() }
            elseif ([string]::IsNullOrWhiteSpace($domain) -and $line -match '^\s*USERDOMAIN\s+REG_[A-Z0-9_]+\s+(.+?)\s*$') { $domain = $Matches[1].Trim() }
        }
        if ([string]::IsNullOrWhiteSpace($username)) { continue }
        if ($username -match '^(?i:SYSTEM|LOCAL SERVICE|NETWORK SERVICE|DWM-\d+|UMFD-\d+)$') { continue }
        $account = if ([string]::IsNullOrWhiteSpace($domain)) { $username } else { "$domain\$username" }
        $users.Add([pscustomobject]@{ Sid=$sid; Account=$account })
    }
    return @($users.ToArray() | Sort-Object Sid -Unique)
}

function Get-SasRemoteUserPrinterConnections {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Sid
    )
    $key = "\\$Computer\HKU\$Sid\Printers\Connections"
    $query = Invoke-SasRemoteRegRead -Computer $Computer -Arguments @('QUERY',$key)
    if ($query.ExitCode -ne 0) {
        $text = @($query.Lines) -join "`n"
        if ($text -match '(?i)unable to find the specified registry key or value|cannot find the specified registry key') { return @() }
        throw "Remote user-printer HKU query failed for $Computer / $Sid with exit code $($query.ExitCode)."
    }
    $connections = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($query.Lines)) {
        if ($line -notmatch '(?i)\\Printers\\Connections\\(.+?)\s*$') { continue }
        $candidate = ConvertFrom-SasPrinterConnectionKeyName -Name $Matches[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $connections.Add($candidate) }
    }
    return @($connections.ToArray() | Sort-Object -Unique)
}

function Invoke-SasRemoteInteractivePrinterTask {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string[]]$Queues,
        [Parameter(Mandatory)][string]$SystemRoot,
        [Parameter(Mandatory)][int]$WaitSeconds
    )

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect($Computer)
    $folder = $service.GetFolder('\')
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'SysAdminSuite immediate Northwell printer materialization without administrative-share staging.'
    $definition.Principal.UserId = $Sid
    $definition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 0
    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.ExecutionTimeLimit = 'PT2M'

    $rundll32 = Join-Path $SystemRoot 'System32\rundll32.exe'
    foreach ($queue in $Queues) {
        if ($queue -match '["\r\n]') { throw "Unsafe queue reached interactive task action: $queue" }
        $action = $definition.Actions.Create(0)
        $action.Path = $rundll32
        $action.Arguments = 'printui.dll,PrintUIEntry /in /q /n"{0}"' -f $queue
    }

    $taskName = 'SysAdminSuite_NorthwellPrinterUserDirect_' + [guid]::NewGuid().ToString('N')
    try {
        $task = $folder.RegisterTaskDefinition($taskName,$definition,6,$Sid,$null,3,$null)
        $null = $task.Run($null)
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            $observed = @(Get-SasRemoteUserPrinterConnections -Computer $Computer -Sid $Sid)
            $missing = @($Queues | Where-Object { $observed -notcontains $_ })
            if ($missing.Count -eq 0) { return [pscustomobject]@{ Success=$true; Connections=$observed; Missing=@() } }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)
        return [pscustomobject]@{ Success=$false; Connections=$observed; Missing=$missing }
    }
    finally {
        try { $folder.DeleteTask($taskName,0) } catch {}
    }
}

function Get-SasRemoteSystemRoot {
    param([Parameter(Mandatory)][string]$Computer)
    $key = "\\$Computer\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $query = Invoke-SasRemoteRegRead -Computer $Computer -Arguments @('QUERY',$key,'/v','SystemRoot')
    if ($query.ExitCode -ne 0) { throw "Remote Registry SystemRoot query failed for $Computer with exit code $($query.ExitCode)." }
    foreach ($line in @($query.Lines)) {
        if ($line -match '^\s*SystemRoot\s+REG_[A-Z0-9_]+\s+(.+?)\s*$') {
            $value = $Matches[1].Trim().TrimEnd('\')
            if ($value -notmatch '^[A-Za-z]:\\[^"\r\n]+$') { throw "Remote SystemRoot is unsafe or unexpected: $value" }
            return $value
        }
    }
    throw "Remote Registry query for $Computer did not return SystemRoot."
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($computer in $computers) {
    $status = Get-SasMachineWideStatusForComputer -Computer $computer
    $null = Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters $printers -DesiredState Present

    try {
        $users = @(Get-SasRemoteInteractiveUsers -Computer $computer)
        if ($users.Count -eq 0) {
            $results.Add([pscustomobject][ordered]@{
                Computer=$computer; Printers=$printers; Success=$true; ActiveUser=$null; ActiveUsers=@();
                Materialized=$false; PendingNextLogon=$true; Disposition='MACHINE_WIDE_REGISTERED_PENDING_NEXT_LOGON';
                Transport='REMOTE_TASK_SCHEDULER_COM+REMOTE_REGISTRY_HKU_NO_ADMIN_SHARE'; TestPagesPrinted=$false
            })
            continue
        }

        $systemRoot = Get-SasRemoteSystemRoot -Computer $computer
        $userResults = New-Object System.Collections.Generic.List[object]
        foreach ($user in $users) {
            $proof = Invoke-SasRemoteInteractivePrinterTask -Computer $computer -Sid $user.Sid -Queues $printers -SystemRoot $systemRoot -WaitSeconds $TimeoutSeconds
            $userResults.Add([pscustomobject][ordered]@{
                Account=$user.Account; Sid=$user.Sid; Success=[bool]$proof.Success;
                Connections=@($proof.Connections); Missing=@($proof.Missing)
            })
        }
        $failedUsers = @($userResults | Where-Object { -not $_.Success })
        $success = ($failedUsers.Count -eq 0)
        $results.Add([pscustomobject][ordered]@{
            Computer=$computer; Printers=$printers; Success=$success;
            ActiveUser=if ($users.Count -eq 1) { $users[0].Account } else { $null };
            ActiveUsers=@($users | ForEach-Object { $_.Account }); UserProof=$userResults.ToArray();
            Materialized=$success; PendingNextLogon=$false;
            Disposition=if ($success) { 'ACTIVE_USER_CONNECTION_VERIFIED' } else { 'ACTIVE_USER_CONNECTION_NOT_VERIFIED' };
            Transport='REMOTE_TASK_SCHEDULER_COM+REMOTE_REGISTRY_HKU_NO_ADMIN_SHARE'; TestPagesPrinted=$false
        })
    }
    catch {
        $results.Add([pscustomobject][ordered]@{
            Computer=$computer; Printers=$printers; Success=$false; ActiveUser=$null; ActiveUsers=@();
            Materialized=$false; PendingNextLogon=$false; Disposition='ACTIVE_USER_MATERIALIZATION_ERROR';
            Error=$_.Exception.Message; Transport='REMOTE_TASK_SCHEDULER_COM+REMOTE_REGISTRY_HKU_NO_ADMIN_SHARE'; TestPagesPrinted=$false
        })
    }
}

$failed = @($results | Where-Object { -not $_.Success })
$pending = @($results | Where-Object { $_.Success -and $_.PendingNextLogon })
$materialized = @($results | Where-Object { $_.Success -and $_.Materialized })
$outPath = Join-Path $EvidenceRoot 'ActiveUserMaterialization.json'
[ordered]@{
    SchemaVersion='sas-northwell-printer-active-user/v1'
    Success=($failed.Count -eq 0)
    MachineWideRegistrationRequired=$true
    ImmediateActiveUserConnectionRequiredWhenLoggedOn=$true
    TestPagesPrinted=$false
    DirectIpMapping=$false
    Transport='REMOTE_TASK_SCHEDULER_COM+REMOTE_REGISTRY_HKU_NO_ADMIN_SHARE'
    MaterializedTargets=$materialized.Count
    PendingNextLogonTargets=$pending.Count
    FailedTargets=$failed.Count
    Results=$results.ToArray()
    Updated=(Get-Date).ToString('o')
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8

foreach ($result in $results) {
    if (-not $result.Success) { Write-Host ("FAIL: {0} - {1}" -f $result.Computer,$result.Error) -ForegroundColor Red }
    elseif ($result.PendingNextLogon) { Write-Host ("REGISTERED: {0} - no interactive user hive is loaded; /ga will apply at the next logon." -f $result.Computer) -ForegroundColor Yellow }
    else { Write-Host ("READY: {0} - requested printer connection is proven in every loaded interactive user hive." -f $result.Computer) -ForegroundColor Green }
}
Write-Host ("Active-user evidence: {0}" -f $outPath) -ForegroundColor DarkGray
if ($failed.Count -gt 0) { throw "Printer registration exists, but shareless immediate active-user connection failed on $($failed.Count) target(s)." }
