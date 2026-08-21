<#
.SYNOPSIS
    Shareless fallback for Northwell machine-wide printer state.

.DESCRIPTION
    Used only after the canonical printer engine proves that administrative SMB
    staging failed before any Status.json was returned. This fallback does not use
    C$ or ADMIN$ for payload staging. It first proves read access to the target's
    Remote Registry, captures the owning HKLM printer state, and confirms Remote
    Task Scheduler access. When a state transition is required it creates a bounded
    SYSTEM task whose action is the native PrintUIEntry /ga or /gd command itself.
    Success is accepted only after fresh Remote Registry HKLM proof shows every
    requested queue in the desired state.

    No test page is printed. No direct printer IP is accepted. No trust, DNS,
    firewall, GPO, WinRM, or credential setting is modified.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [Alias('Computer','Computers','HostName','HostNames')]
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,

    [Parameter(Mandatory)]
    [Alias('Queue','Queues','PrinterQueue','PrinterQueues')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Printer,

    [ValidateSet('Present','Absent')]
    [string]$DesiredState = 'Present',

    [string]$PrintServer,
    [string]$DnsSuffix = 'nslijhs.net',

    [ValidateRange(15,600)]
    [int]$TimeoutSeconds = 120,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SessionRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'Northwell printer management must run from Windows.' }

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Required resolver module not found: $modulePath" }
Import-Module $modulePath -Force -ErrorAction Stop

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) { throw 'Run PowerShell as Administrator. Machine-wide printer management requires an elevated controller session.' }

$operation = if ($DesiredState -eq 'Present') { 'Map' } else { 'Unmap' }
$nativeSwitch = if ($DesiredState -eq 'Present') { '/ga' } else { '/gd' }
$proofLevel = if ($DesiredState -eq 'Present') { 'MACHINE_WIDE_REGISTRATION_PRESENT' } else { 'MACHINE_WIDE_REGISTRATION_ABSENT' }
$inverseState = if ($DesiredState -eq 'Present') { 'Absent' } else { 'Present' }
$inverseAction = if ($DesiredState -eq 'Present') { 'Unmap' } else { 'Map' }

$resolvedComputers = @(
    $ComputerName |
        ForEach-Object { Resolve-SasNorthwellTargetComputer -ComputerName $_ -DnsSuffix $DnsSuffix } |
        Sort-Object -Unique
)
$resolvedPrinters = @(
    $Printer |
        ForEach-Object { ConvertTo-SasNorthwellPrinterUnc -Printer $_ -PrintServer $PrintServer } |
        Sort-Object -Unique
)
if ($resolvedComputers.Count -eq 0) { throw 'No valid target computers were supplied.' }
if ($resolvedPrinters.Count -eq 0) { throw 'No valid shared printer queues were supplied.' }

foreach ($queue in $resolvedPrinters) {
    if ($queue -match '["\r\n]') { throw "Printer queue contains characters unsafe for the shareless scheduled-task transport: $queue" }
}

if ($DesiredState -eq 'Present') {
    foreach ($server in @(
        $resolvedPrinters |
            ForEach-Object { if ($_ -match '^\\\\([^\\]+)\\') { $Matches[1] } } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )) {
        try {
            $addresses = @([System.Net.Dns]::GetHostAddresses($server))
            if ($addresses.Count -eq 0) { throw 'No addresses returned.' }
        }
        catch {
            throw "Print server '$server' did not resolve in DNS. No endpoint changes were made. $($_.Exception.Message)"
        }
    }
}

$SessionRoot = [IO.Path]::GetFullPath($SessionRoot)
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
$controllerLog = Join-Path $SessionRoot 'Controller.log'
$summaryPath = Join-Path $SessionRoot 'Summary.json'
$undoPath = Join-Path $SessionRoot 'UndoPlan.json'
$planPath = Join-Path $SessionRoot 'ResolvedPlan.json'
$results = New-Object System.Collections.Generic.List[object]
$runToken = New-SasNorthwellPrinterRunToken

function Write-ControllerLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format s),$Message
    Write-Host $line
    $line | Out-File -LiteralPath $controllerLog -Encoding utf8 -Append
}

function Invoke-SasRemoteReg {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Stage
    )
    $lines = @(& reg.exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    foreach ($line in $lines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-ControllerLog "[$Computer][$Stage] $line" }
    }
    return [pscustomobject]@{ ExitCode=$exitCode; Lines=$lines }
}

function Invoke-SasRemoteTaskScheduler {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Stage
    )
    $lines = @(& schtasks.exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    foreach ($line in $lines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-ControllerLog "[$Computer][$Stage] $line" }
    }
    if ($exitCode -ne 0) { throw "Remote Task Scheduler $Stage failed with exit code $exitCode." }
}

function ConvertFrom-SasRemotePrinterConnectionKey {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $trimmed = $Name.Trim()
    if ($trimmed -match '^,,([^,]+),(.+)$') {
        return ('\\{0}\{1}' -f $Matches[1],$Matches[2]).ToLowerInvariant()
    }
    if ($trimmed -match '^\\\\[^\\]+\\[^\\]+$') { return $trimmed.ToLowerInvariant() }
    return $null
}

function Get-SasRemoteSystemRoot {
    param([Parameter(Mandatory)][string]$Computer)
    $key = "\\$Computer\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $query = Invoke-SasRemoteReg -Computer $Computer -Stage 'RemoteRegistryAuthority' -Arguments @('QUERY',$key,'/v','SystemRoot')
    if ($query.ExitCode -ne 0) { throw "Remote Registry authority query failed with exit code $($query.ExitCode)." }
    foreach ($line in @($query.Lines)) {
        if ($line -match '^\s*SystemRoot\s+REG_[A-Z0-9_]+\s+(.+?)\s*$') {
            $value = $Matches[1].Trim().TrimEnd('\')
            if ($value -notmatch '^[A-Za-z]:\\[^"\r\n]+$') { throw "Remote SystemRoot is unsafe or unexpected: $value" }
            return $value
        }
    }
    throw 'Remote Registry query succeeded but SystemRoot was not returned.'
}

function Get-SasRemoteMachineWidePrinterConnections {
    param([Parameter(Mandatory)][string]$Computer)
    $key = "\\$Computer\HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections"
    $query = Invoke-SasRemoteReg -Computer $Computer -Stage 'RemoteRegistryPrinterProof' -Arguments @('QUERY',$key)
    if ($query.ExitCode -ne 0) {
        $text = @($query.Lines) -join "`n"
        if ($text -match '(?i)unable to find the specified registry key or value|cannot find the specified registry key') {
            return [pscustomobject]@{ Connections=@(); RawKeys=@() }
        }
        throw "Remote printer HKLM query failed with exit code $($query.ExitCode)."
    }

    $raw = New-Object System.Collections.Generic.List[string]
    $connections = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($query.Lines)) {
        if ($line -notmatch '(?i)\\Print\\Connections\\(.+?)\s*$') { continue }
        $leaf = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
        $raw.Add($leaf)
        $candidate = ConvertFrom-SasRemotePrinterConnectionKey -Name $leaf
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $connections.Add($candidate) }
    }
    return [pscustomobject]@{
        Connections = @($connections.ToArray() | Sort-Object -Unique)
        RawKeys = @($raw.ToArray() | Sort-Object -Unique)
    }
}

function New-SasSharelessPrinterTaskAction {
    param(
        [Parameter(Mandatory)][string]$SystemRoot,
        [Parameter(Mandatory)][ValidateSet('/ga','/gd')][string]$NativeSwitch,
        [Parameter(Mandatory)][string]$Queue
    )
    if ($Queue -match '["\r\n]') { throw "Unsafe queue reached task action builder: $Queue" }
    $rundll32 = Join-Path $SystemRoot 'System32\rundll32.exe'
    return ('"{0}" printui.dll,PrintUIEntry {1} /n"{2}"' -f $rundll32,$NativeSwitch,$Queue)
}

function Get-SasChangedRequestedPrinters {
    param([string[]]$Before,[string[]]$After,[string[]]$Requested,[string]$State)
    if ($State -eq 'Present') { return @($Requested | Where-Object { $Before -notcontains $_ -and $After -contains $_ }) }
    return @($Requested | Where-Object { $Before -contains $_ -and $After -notcontains $_ })
}

function Write-SasFallbackUndoPlan {
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($result in $results) {
        $changed = @($result.ChangedPrinters)
        if ($changed.Count -eq 0) { continue }
        $entries.Add([pscustomobject][ordered]@{
            Computer = [string]$result.Computer
            Printers = $changed
            DesiredState = $inverseState
            Action = $inverseAction
            SourceSuccess = [bool]$result.Success
        })
    }
    [ordered]@{
        SchemaVersion = 'sas-northwell-printer-undo/v1'
        SourceRunToken = $runToken
        SourceSessionRoot = $SessionRoot
        SourceAction = $operation
        SourceDesiredState = $DesiredState
        UndoAction = $inverseAction
        UndoDesiredState = $inverseState
        EntryCount = $entries.Count
        Entries = $entries.ToArray()
        Created = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $undoPath -Encoding UTF8
}

function Write-SasFallbackSummary {
    $failed = @($results | Where-Object { -not $_.Success })
    Write-SasFallbackUndoPlan
    [ordered]@{
        RunToken = $runToken
        Success = ($results.Count -eq $resolvedComputers.Count -and $failed.Count -eq 0)
        Operation = $operation
        DesiredState = $DesiredState
        Mode = 'MachineWidePerComputer'
        ProofLevel = $proofLevel
        Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
        RemoteIdentity = 'SYSTEM'
        PrinterCommand = "rundll32 printui.dll,PrintUIEntry $nativeSwitch"
        RuntimePrintObservedByEngine = $false
        TestPagesPrinted = $false
        Computers = $resolvedComputers
        Printers = $resolvedPrinters
        CompletedTargets = $results.Count
        TotalTargets = $resolvedComputers.Count
        Results = $results.ToArray()
        PlanPath = $planPath
        UndoPlan = $undoPath
        ControllerLog = $controllerLog
        SessionRoot = $SessionRoot
        Updated = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
}

[ordered]@{
    RunToken = $runToken
    Operation = $operation
    DesiredState = $DesiredState
    Mode = 'MachineWidePerComputer'
    ProofLevel = $proofLevel
    Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
    RemoteIdentity = 'SYSTEM'
    PrinterCommand = "rundll32 printui.dll,PrintUIEntry $nativeSwitch"
    RuntimePrintObservedByEngine = $false
    TestPagesPrinted = $false
    Computers = $resolvedComputers
    Printers = $resolvedPrinters
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-ControllerLog '=== Shareless Northwell printer fallback ==='
Write-ControllerLog 'Transport: Remote Task Scheduler SYSTEM action + Remote Registry HKLM proof. No administrative share payload is used.'
Write-ControllerLog "Targets: $($resolvedComputers -join ', ')"
Write-ControllerLog "Queues : $($resolvedPrinters -join ', ')"
Write-ControllerLog "Desired state: $DesiredState"
Write-SasFallbackSummary

foreach ($computer in $resolvedComputers) {
    $safeComputer = ($computer -replace '[^A-Za-z0-9.-]','_')
    $localHostDir = Join-Path $SessionRoot $safeComputer
    New-Item -ItemType Directory -Path $localHostDir -Force | Out-Null
    $attempted = New-Object System.Collections.Generic.List[string]
    $hostResult = [ordered]@{
        Computer = $computer
        Success = $false
        Stage = 'Preflight'
        Message = ''
        DesiredState = $DesiredState
        ChangedPrinters = @()
        AlreadyDesiredPrinters = @()
        MutationAttemptedPrinters = @()
        StagingShare = 'NONE'
        Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
        Evidence = $localHostDir
    }

    try {
        Write-ControllerLog "[$computer] Proving Remote Registry baseline before any mutation."
        $systemRoot = Get-SasRemoteSystemRoot -Computer $computer
        $beforeProof = Get-SasRemoteMachineWidePrinterConnections -Computer $computer
        $before = @($beforeProof.Connections)

        Write-ControllerLog "[$computer] Proving Remote Task Scheduler authority."
        Invoke-SasRemoteTaskScheduler -Computer $computer -Stage 'Query' -Arguments @('/Query','/S',$computer,'/FO','LIST')

        $alreadyDesired = @()
        $toChange = @()
        foreach ($queue in $resolvedPrinters) {
            $present = ($before -contains $queue.ToLowerInvariant())
            if (($DesiredState -eq 'Present' -and $present) -or ($DesiredState -eq 'Absent' -and -not $present)) {
                $alreadyDesired += $queue.ToLowerInvariant()
            }
            else { $toChange += $queue.ToLowerInvariant() }
        }
        $hostResult.AlreadyDesiredPrinters = @($alreadyDesired | Sort-Object -Unique)

        if (-not $PSCmdlet.ShouldProcess($computer,"$operation $($toChange.Count) shared printer queue(s) machine-wide as SYSTEM using shareless transport")) {
            $hostResult.Stage = 'Skipped'
            $hostResult.Message = 'ShouldProcess declined.'
            continue
        }

        $index = 0
        foreach ($queue in $toChange) {
            $index++
            $taskName = "SysAdminSuite_NorthwellPrinterDirect_${runToken}_$index"
            $taskAction = New-SasSharelessPrinterTaskAction -SystemRoot $systemRoot -NativeSwitch $nativeSwitch -Queue $queue
            $taskCreated = $false
            try {
                $createArguments = New-SasNorthwellPrinterTaskCreateArguments -Computer $computer -TaskName $taskName -RemoteLauncherLocal $taskAction
                Invoke-SasRemoteTaskScheduler -Computer $computer -Stage 'Create' -Arguments $createArguments
                $taskCreated = $true
                $attempted.Add($queue)
                Invoke-SasRemoteTaskScheduler -Computer $computer -Stage 'Run' -Arguments @('/Run','/S',$computer,'/TN',$taskName)

                $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                $queueProven = $false
                while ((Get-Date) -lt $deadline) {
                    $currentProof = Get-SasRemoteMachineWidePrinterConnections -Computer $computer
                    $current = @($currentProof.Connections)
                    $isPresent = ($current -contains $queue)
                    if (($DesiredState -eq 'Present' -and $isPresent) -or ($DesiredState -eq 'Absent' -and -not $isPresent)) {
                        $queueProven = $true
                        break
                    }
                    Start-Sleep -Seconds 2
                }
                if (-not $queueProven) { throw "Timed out after $TimeoutSeconds seconds waiting for remote HKLM desired-state proof for $queue." }
            }
            finally {
                if ($taskCreated) {
                    try { Invoke-SasRemoteTaskScheduler -Computer $computer -Stage 'Delete' -Arguments @('/Delete','/S',$computer,'/TN',$taskName,'/F') }
                    catch { Write-ControllerLog "[$computer] WARN task cleanup '$taskName': $($_.Exception.Message)" }
                }
            }
        }

        $afterProof = Get-SasRemoteMachineWidePrinterConnections -Computer $computer
        $after = @($afterProof.Connections)
        $missing = if ($DesiredState -eq 'Present') { @($resolvedPrinters | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $after -notcontains $_ }) } else { @() }
        $stillPresent = if ($DesiredState -eq 'Absent') { @($resolvedPrinters | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $after -contains $_ }) } else { @() }
        $changed = @(Get-SasChangedRequestedPrinters -Before $before -After $after -Requested @($resolvedPrinters | ForEach-Object { $_.ToLowerInvariant() }) -State $DesiredState)
        $success = if ($DesiredState -eq 'Present') { $missing.Count -eq 0 } else { $stillPresent.Count -eq 0 }

        $status = [ordered]@{
            ComputerName = $computer
            Identity = 'NT AUTHORITY\SYSTEM'
            IdentityProof = if ($attempted.Count -gt 0) { 'REMOTE_TASK_SCHEDULER_/RU_SYSTEM' } else { 'NOOP_REMOTE_REGISTRY_DESIRED_STATE' }
            Mode = 'MachineWidePerComputer'
            DesiredState = $DesiredState
            ProofLevel = $proofLevel
            Success = $success
            Requested = @($resolvedPrinters | ForEach-Object { $_.ToLowerInvariant() })
            BeforeMachineWideUNC = $before
            MachineWideUNC = $after
            ChangedPrinters = $changed
            AlreadyDesiredPrinters = @($alreadyDesired | Sort-Object -Unique)
            Missing = $missing
            StillPresent = $stillPresent
            RawConnectionKeys = @($afterProof.RawKeys)
            MutationAttemptedPrinters = $attempted.ToArray()
            StagingShare = 'NONE'
            Transport = 'REMOTE_TASK_SCHEDULER+REMOTE_REGISTRY_NO_ADMIN_SHARE'
            StatusAuthority = 'CONTROLLER_REMOTE_REGISTRY'
            RuntimePrintObservedByEngine = $false
            TestPagesPrinted = $false
            Finished = (Get-Date).ToString('o')
        }
        $statusPath = Join-Path $localHostDir 'Status.json'
        $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8

        $hostResult.ChangedPrinters = $changed
        $hostResult.MutationAttemptedPrinters = $attempted.ToArray()
        $hostResult.Success = $success
        if ($success) {
            $hostResult.Stage = if ($DesiredState -eq 'Present') { 'VerifiedPresent' } else { 'VerifiedAbsent' }
            $hostResult.Message = "Shareless SYSTEM $nativeSwitch completed and requested queues were verified $DesiredState under remote HKLM."
            Write-ControllerLog "[$computer] PASS: shareless remote HKLM desired-state proof obtained."
        }
        else {
            throw 'Shareless transport completed but authoritative remote HKLM desired-state proof was incomplete.'
        }
    }
    catch {
        $hostResult.Success = $false
        $hostResult.Stage = 'Failed'
        $hostResult.Message = $_.Exception.Message
        $hostResult.MutationAttemptedPrinters = $attempted.ToArray()
        Write-ControllerLog "[$computer] FAIL: $($_.Exception.Message)"
    }
    finally {
        $results.Add([pscustomobject]$hostResult)
        Write-SasFallbackSummary
    }
}

$results | Format-Table Computer,Success,Stage,DesiredState,Transport,Message -AutoSize
Write-ControllerLog "Summary: $summaryPath"
Write-ControllerLog "Undo plan: $undoPath"
Write-SasFallbackSummary

$failures = @($results | Where-Object { -not $_.Success })
if ($failures.Count -gt 0) {
    throw "Shareless printer $($operation.ToLowerInvariant()) failed on $($failures.Count) target(s). Review $summaryPath."
}
Write-ControllerLog "PASS: every target returned authoritative remote HKLM '$DesiredState' proof without administrative-share staging."
Write-SasFallbackSummary
