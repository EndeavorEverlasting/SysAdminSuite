<#
.SYNOPSIS
    Canonical Northwell field engine for reversible system-wide shared-printer state.

.DESCRIPTION
    Drives one or more shared printer queues to Present (map) or Absent (unmap)
    on one or more Northwell PCs. Endpoint work runs as SYSTEM and uses the
    paired PrintUIEntry per-computer operations /ga and /gd.

    The engine records the requested queue state before and after mutation.
    UndoPlan.json contains only queues whose state actually changed, so an
    idempotent no-op never creates a destructive inverse action.
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

    [ValidateRange(15, 600)]
    [int]$TimeoutSeconds = 120,

    [switch]$KeepRemoteArtifacts,
    [string]$SessionRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'Northwell printer management must run from Windows.' }

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) { throw "Required resolver module not found: $modulePath" }
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

# Mapping requires a currently resolvable print server. Unmapping deliberately does
# not: removing a stale machine-wide connection must remain possible even when the
# retired/unreachable print server no longer resolves.
if ($DesiredState -eq 'Present') {
    $printServers = @(
        $resolvedPrinters | ForEach-Object {
            if ($_ -match '^\\\\([^\\]+)\\') { $Matches[1] }
        } | Where-Object { $_ } | Sort-Object -Unique
    )
    foreach ($server in $printServers) {
        try {
            $addresses = @([System.Net.Dns]::GetHostAddresses($server))
            if ($addresses.Count -eq 0) { throw 'No addresses returned.' }
        }
        catch {
            throw "Print server '$server' did not resolve in DNS. No endpoint changes were made. $($_.Exception.Message)"
        }
    }
}

$runToken = New-SasNorthwellPrinterRunToken
if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $prefix = if ($DesiredState -eq 'Present') { 'NorthwellPrinterMap' } else { 'NorthwellPrinterUnmap' }
    $SessionRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "$prefix-$runToken"
}
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
$controllerLog = Join-Path $SessionRoot 'Controller.log'
$planPath = Join-Path $SessionRoot 'ResolvedPlan.json'
$summaryPath = Join-Path $SessionRoot 'Summary.json'
$undoPath = Join-Path $SessionRoot 'UndoPlan.json'
$latestPath = Join-Path (Join-Path $PSScriptRoot 'Logs') 'LATEST-PATH.txt'
$results = New-Object System.Collections.Generic.List[object]

function Write-ControllerLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format s), $Message
    Write-Host $line
    $line | Out-File -LiteralPath $controllerLog -Encoding utf8 -Append
}

function Write-UndoPlan {
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

function Write-RunSummary {
    $failedCount = @($results | Where-Object { -not $_.Success }).Count
    Write-UndoPlan
    [ordered]@{
        RunToken = $runToken
        Success = ($results.Count -eq $resolvedComputers.Count -and $failedCount -eq 0)
        Operation = $operation
        DesiredState = $DesiredState
        Mode = 'MachineWidePerComputer'
        ProofLevel = $proofLevel
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
    $SessionRoot | Set-Content -LiteralPath $latestPath -Encoding UTF8
}

function Invoke-RemoteTaskScheduler {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][string]$Stage
    )
    $output = @(& schtasks.exe @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Write-ControllerLog "[$Computer][$Stage] $line" }
    }
    if ($exitCode -ne 0) { throw "Remote Task Scheduler $Stage failed with exit code $exitCode." }
}

[ordered]@{
    RunToken = $runToken
    Operation = $operation
    DesiredState = $DesiredState
    Mode = 'MachineWidePerComputer'
    ProofLevel = $proofLevel
    Transport = 'SMB+AdministrativeShareFallback+RemoteTaskScheduler'
    RemoteIdentity = 'SYSTEM'
    PrinterCommand = "rundll32 printui.dll,PrintUIEntry $nativeSwitch"
    RuntimePrintObservedByEngine = $false
    TestPagesPrinted = $false
    Computers = $resolvedComputers
    Printers = $resolvedPrinters
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-ControllerLog "=== Northwell system-wide printer $($operation.ToLowerInvariant()) ==="
Write-ControllerLog "Targets: $($resolvedComputers -join ', ')"
Write-ControllerLog "Queues : $($resolvedPrinters -join ', ')"
Write-ControllerLog "Desired state: $DesiredState"
Write-ControllerLog "Evidence: $SessionRoot"
Write-ControllerLog 'Policy: shared queue names only; direct printer IP management is rejected.'
Write-ControllerLog "Scope: per-computer ($nativeSwitch), executed as SYSTEM for multi-user PCs. No test page is emitted."
Write-ControllerLog 'Reversibility: UndoPlan.json records only queues whose machine-wide state actually changed.'
Write-RunSummary

if ($WhatIfPreference) {
    foreach ($computer in $resolvedComputers) {
        foreach ($queue in $resolvedPrinters) {
            $null = $PSCmdlet.ShouldProcess($computer, "$operation system-wide printer $queue")
        }
    }
    Write-ControllerLog 'WhatIf complete. No remote files, tasks, or printer connections were changed.'
    Write-RunSummary
    return
}

$agentCode = @'
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$WorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logPath = Join-Path $WorkDir 'Agent.log'
$statusPath = Join-Path $WorkDir 'Status.json'
$desiredState = 'Unknown'
$queues = @()
$before = @()
$after = @()
$changed = @()
$alreadyDesired = @()
$missing = @()
$stillPresent = @()
$rawConnectionKeys = @()

function Write-AgentLog {
    param([string]$Message)
    ('[{0}] {1}' -f (Get-Date -Format s), $Message) | Add-Content -LiteralPath $logPath -Encoding UTF8
}

function ConvertFrom-MachineWideConnectionKeyName {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $trimmed = $Name.Trim()
    if ($trimmed -match '^,,([^,]+),(.+)$') {
        return ('\\{0}\{1}' -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    if ($trimmed -match '^\\\\[^\\]+\\[^\\]+$') {
        return $trimmed.ToLowerInvariant()
    }
    return $null
}

function Get-RawMachineWidePrinterConnectionKeys {
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
    if (-not (Test-Path -LiteralPath $key)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.PSChildName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Get-MachineWidePrinterConnections {
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
    if (-not (Test-Path -LiteralPath $key)) { return @() }

    $connections = New-Object System.Collections.Generic.List[string]
    foreach ($subKey in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
        try {
            $candidate = $null
            $item = Get-ItemProperty -LiteralPath $subKey.PSPath -ErrorAction Stop
            $serverProperty = $item.PSObject.Properties['Server']
            $printerProperty = $item.PSObject.Properties['Printer']
            $serverValue = if ($null -ne $serverProperty) { ([string]$serverProperty.Value).Trim() } else { '' }
            $printerValue = if ($null -ne $printerProperty) { ([string]$printerProperty.Value).Trim() } else { '' }

            if ($printerValue -match '^\\\\[^\\]+\\[^\\]+$') {
                $candidate = $printerValue.ToLowerInvariant()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($serverValue) -and -not [string]::IsNullOrWhiteSpace($printerValue)) {
                $candidate = ('\\{0}\{1}' -f $serverValue.TrimStart([char[]]'\'), $printerValue.TrimStart([char[]]'\')).ToLowerInvariant()
            }
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                $candidate = ConvertFrom-MachineWideConnectionKeyName -Name ([string]$subKey.PSChildName)
            }
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $connections.Add($candidate) }
        }
        catch {}
    }
    return @($connections.ToArray() | Sort-Object -Unique)
}

function Get-ChangedRequestedPrinters {
    param([string[]]$Before, [string[]]$After, [string[]]$Requested, [string]$State)
    if ($State -eq 'Present') {
        return @($Requested | Where-Object { $Before -notcontains $_ -and $After -contains $_ })
    }
    return @($Requested | Where-Object { $Before -contains $_ -and $After -notcontains $_ })
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $desiredState = [string]$config.DesiredState
    if ($desiredState -notin @('Present','Absent')) { throw "Unsafe desired state reached agent: $desiredState" }
    $queues = @($config.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($queues.Count -eq 0) { throw 'No queues in staged configuration.' }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-AgentLog "Running as $identity on $env:COMPUTERNAME"
    if ($identity -notmatch 'SYSTEM$') { throw "Worker identity is not SYSTEM: $identity" }
    Write-AgentLog "Requested machine-wide queues: $($queues -join ', ')"
    Write-AgentLog "Desired state: $desiredState"

    $before = @(Get-MachineWidePrinterConnections)
    Write-AgentLog "Before machine-wide count: $($before.Count)"

    foreach ($queue in $queues) {
        if ($queue -notmatch '^\\\\[^\\]+\\[^\\]+$') { throw "Unsafe/non-UNC queue reached agent: $queue" }
        $isPresent = ($before -contains $queue)
        if ($desiredState -eq 'Present') {
            if ($isPresent) {
                $alreadyDesired += $queue
                Write-AgentLog "NOOP already present: $queue"
                continue
            }
            Write-AgentLog "ADD /ga $queue"
            & "$env:SystemRoot\System32\rundll32.exe" 'printui.dll,PrintUIEntry' '/ga' "/n$queue"
            Write-AgentLog "PrintUIEntry /ga invocation returned for $queue; registry proof will determine success."
        }
        else {
            if (-not $isPresent) {
                $alreadyDesired += $queue
                Write-AgentLog "NOOP already absent: $queue"
                continue
            }
            Write-AgentLog "DELETE /gd $queue"
            & "$env:SystemRoot\System32\rundll32.exe" 'printui.dll,PrintUIEntry' '/gd' "/n$queue"
            Write-AgentLog "PrintUIEntry /gd invocation returned for $queue; registry proof will determine success."
        }
    }

    Write-AgentLog 'PrintUIEntry returned. Verifying the owning HKLM machine-wide desired state directly; no synchronous gpupdate and no native LASTEXITCODE assumption is required for this proof level.'
    $verifyDeadline = (Get-Date).AddSeconds(30)
    do {
        $after = @(Get-MachineWidePrinterConnections)
        if ($desiredState -eq 'Present') {
            $missing = @($queues | Where-Object { $after -notcontains $_ })
            $stillPresent = @()
            if ($missing.Count -eq 0) { break }
        }
        else {
            $missing = @()
            $stillPresent = @($queues | Where-Object { $after -contains $_ })
            if ($stillPresent.Count -eq 0) { break }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $verifyDeadline)

    $rawConnectionKeys = @(Get-RawMachineWidePrinterConnectionKeys)
    $changed = @(Get-ChangedRequestedPrinters -Before $before -After $after -Requested $queues -State $desiredState)
    $success = if ($desiredState -eq 'Present') { $missing.Count -eq 0 } else { $stillPresent.Count -eq 0 }
    $agentProofLevel = if ($desiredState -eq 'Present') { 'MACHINE_WIDE_REGISTRATION_PRESENT' } else { 'MACHINE_WIDE_REGISTRATION_ABSENT' }
    if ($success) {
        Write-AgentLog "Verified desired machine-wide state '$desiredState' for every requested queue."
    }
    elseif ($desiredState -eq 'Present') {
        Write-AgentLog "VERIFY FAIL missing after 30 seconds: $($missing -join ', ')"
        if ($rawConnectionKeys.Count -gt 0) { Write-AgentLog "HKLM connection subkeys observed: $($rawConnectionKeys -join ', ')" }
    }
    else {
        Write-AgentLog "VERIFY FAIL still present after 30 seconds: $($stillPresent -join ', ')"
        if ($rawConnectionKeys.Count -gt 0) { Write-AgentLog "HKLM connection subkeys observed: $($rawConnectionKeys -join ', ')" }
    }

    [ordered]@{
        ComputerName = $env:COMPUTERNAME
        Identity = $identity
        Mode = 'MachineWidePerComputer'
        DesiredState = $desiredState
        ProofLevel = $agentProofLevel
        Success = $success
        Requested = $queues
        BeforeMachineWideUNC = $before
        MachineWideUNC = $after
        ChangedPrinters = $changed
        AlreadyDesiredPrinters = @($alreadyDesired | Sort-Object -Unique)
        Missing = $missing
        StillPresent = $stillPresent
        RawConnectionKeys = $rawConnectionKeys
        RuntimePrintObservedByEngine = $false
        TestPagesPrinted = $false
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
catch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    try {
        $after = @(Get-MachineWidePrinterConnections)
        $rawConnectionKeys = @(Get-RawMachineWidePrinterConnectionKeys)
    }
    catch {
        $after = @()
        $rawConnectionKeys = @()
    }
    if ($desiredState -in @('Present','Absent') -and $queues.Count -gt 0) {
        $changed = @(Get-ChangedRequestedPrinters -Before $before -After $after -Requested $queues -State $desiredState)
    }
    Write-AgentLog "FATAL: $($_.Exception.Message)"
    [ordered]@{
        ComputerName = $env:COMPUTERNAME
        Identity = $identity
        Mode = 'MachineWidePerComputer'
        DesiredState = $desiredState
        Success = $false
        Requested = $queues
        BeforeMachineWideUNC = $before
        MachineWideUNC = $after
        ChangedPrinters = $changed
        AlreadyDesiredPrinters = @($alreadyDesired | Sort-Object -Unique)
        Missing = $missing
        StillPresent = $stillPresent
        RawConnectionKeys = $rawConnectionKeys
        RuntimePrintObservedByEngine = $false
        TestPagesPrinted = $false
        Error = $_.Exception.Message
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
'@

foreach ($computer in $resolvedComputers) {
    $safeComputer = ($computer -replace '[^A-Za-z0-9.-]', '_')
    $localHostDir = Join-Path $SessionRoot $safeComputer
    New-Item -ItemType Directory -Path $localHostDir -Force | Out-Null

    $remoteSubPath = "SysAdminSuite\Mapping\NorthwellPrinterState\$runToken"
    $stagingCandidates = @(
        [pscustomobject][ordered]@{
            Name = 'C$'
            AdminRoot = "\\$computer\C$"
            AdminRelative = "ProgramData\$remoteSubPath"
            LocalRoot = 'C:\ProgramData'
        },
        [pscustomobject][ordered]@{
            Name = 'ADMIN$'
            AdminRoot = "\\$computer\ADMIN$"
            AdminRelative = "Temp\$remoteSubPath"
            LocalRoot = '%SystemRoot%\Temp'
        }
    )
    $staging = $null
    foreach ($candidate in $stagingCandidates) {
        if (Test-Path -LiteralPath $candidate.AdminRoot) {
            $staging = $candidate
            break
        }
    }

    $remoteAdminDir = $null
    $remoteAgentAdmin = $null
    $remoteConfigAdmin = $null
    $remoteLauncherAdmin = $null
    $remoteStatusAdmin = $null
    $remoteLogAdmin = $null
    $remoteAgentLocal = $null
    $remoteConfigLocal = $null
    $remoteWorkLocal = $null
    $remoteLauncherLocal = $null
    $remoteTaskAction = $null
    if ($null -ne $staging) {
        $remoteAdminDir = Join-Path $staging.AdminRoot $staging.AdminRelative
        $remoteAgentAdmin = Join-Path $remoteAdminDir 'Agent.ps1'
        $remoteConfigAdmin = Join-Path $remoteAdminDir 'Config.json'
        $remoteLauncherAdmin = Join-Path $remoteAdminDir 'Start-Agent.cmd'
        $remoteStatusAdmin = Join-Path $remoteAdminDir 'Status.json'
        $remoteLogAdmin = Join-Path $remoteAdminDir 'Agent.log'
        $remoteWorkLocal = Join-Path $staging.LocalRoot $remoteSubPath
        $remoteAgentLocal = Join-Path $remoteWorkLocal 'Agent.ps1'
        $remoteConfigLocal = Join-Path $remoteWorkLocal 'Config.json'
        $remoteLauncherLocal = Join-Path $remoteWorkLocal 'Start-Agent.cmd'
        $remoteTaskAction = if ($staging.Name -eq 'ADMIN$') {
            'cmd.exe /d /s /c ""{0}""' -f $remoteLauncherLocal
        }
        else {
            $remoteLauncherLocal
        }
    }
    $taskName = "SysAdminSuite_NorthwellPrinterState_$runToken"
    $taskCreated = $false

    $hostResult = [ordered]@{
        Computer = $computer
        Success = $false
        Stage = 'Preflight'
        Message = ''
        DesiredState = $DesiredState
        ChangedPrinters = @()
        AlreadyDesiredPrinters = @()
        StagingShare = if ($null -ne $staging) { [string]$staging.Name } else { $null }
        Evidence = $localHostDir
    }

    try {
        Write-ControllerLog "[$computer] Preflight administrative staging share and Task Scheduler."
        if ($null -eq $staging) {
            throw "Admin share unavailable: neither \\$computer\C$ nor \\$computer\ADMIN$ is accessible. Confirm an approved Northwell WAB, hardwire, or authenticated VPN route, DNS, credentials, firewall, and admin rights."
        }
        Write-ControllerLog "[$computer] Staging share selected: $($staging.Name)."
        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Query' -Arguments @('/Query','/S',$computer,'/FO','LIST')

        if (-not $PSCmdlet.ShouldProcess($computer, "$operation $($resolvedPrinters.Count) shared printer queue(s) machine-wide as SYSTEM")) {
            $hostResult.Stage = 'Skipped'
            $hostResult.Message = 'ShouldProcess declined.'
            continue
        }

        New-Item -ItemType Directory -Path $remoteAdminDir -Force | Out-Null
        Set-Content -LiteralPath $remoteAgentAdmin -Value $agentCode -Encoding UTF8
        [ordered]@{ Printers = $resolvedPrinters; DesiredState = $DesiredState } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $remoteConfigAdmin -Encoding UTF8

        $launcher = @(
            '@echo off',
            ('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}" -WorkDir "{2}"' -f $remoteAgentLocal,$remoteConfigLocal,$remoteWorkLocal),
            'exit /b %ERRORLEVEL%'
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $remoteLauncherAdmin -Value $launcher -Encoding ASCII

        $createArguments = New-SasNorthwellPrinterTaskCreateArguments -Computer $computer -TaskName $taskName -RemoteLauncherLocal $remoteTaskAction
        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Create' -Arguments $createArguments
        $taskCreated = $true
        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Run' -Arguments @('/Run','/S',$computer,'/TN',$taskName)

        $hostResult.Stage = 'WaitingForProof'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $remoteStatusAdmin)) { Start-Sleep -Seconds 2 }
        if (-not (Test-Path -LiteralPath $remoteStatusAdmin)) {
            if (Test-Path -LiteralPath $remoteLogAdmin) {
                try {
                    foreach ($line in @(Get-Content -LiteralPath $remoteLogAdmin -Tail 20 -ErrorAction Stop)) { Write-ControllerLog "[$computer][Agent] $line" }
                }
                catch { Write-ControllerLog "[$computer] WARN timeout Agent.log read: $($_.Exception.Message)" }
            }
            try { Invoke-RemoteTaskScheduler -Computer $computer -Stage 'TimeoutQuery' -Arguments @('/Query','/S',$computer,'/TN',$taskName,'/V','/FO','LIST') }
            catch { Write-ControllerLog "[$computer] WARN timeout task query: $($_.Exception.Message)" }
            throw "Timed out after $TimeoutSeconds seconds waiting for Status.json. Remote evidence was not observed."
        }

        $status = Get-Content -LiteralPath $remoteStatusAdmin -Raw | ConvertFrom-Json
        $hostResult.ChangedPrinters = @($status.ChangedPrinters)
        $hostResult.AlreadyDesiredPrinters = @($status.AlreadyDesiredPrinters)
        $null = Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters $resolvedPrinters -DesiredState $DesiredState

        $hostResult.Success = $true
        $hostResult.Stage = if ($DesiredState -eq 'Present') { 'VerifiedPresent' } else { 'VerifiedAbsent' }
        $hostResult.Message = "SYSTEM $nativeSwitch completed and requested queues were verified $DesiredState under HKLM."
        Write-ControllerLog "[$computer] PASS: machine-wide desired state '$DesiredState' verified."
    }
    catch {
        $hostResult.Success = $false
        $hostResult.Stage = 'Failed'
        $hostResult.Message = $_.Exception.Message
        Write-ControllerLog "[$computer] FAIL: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $remoteStatusAdmin -and (Test-Path -LiteralPath $remoteStatusAdmin)) {
            try {
                $finalStatus = Get-Content -LiteralPath $remoteStatusAdmin -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $hostResult.ChangedPrinters = @($finalStatus.ChangedPrinters)
                $hostResult.AlreadyDesiredPrinters = @($finalStatus.AlreadyDesiredPrinters)
            }
            catch { Write-ControllerLog "[$computer] WARN final Status.json parse: $($_.Exception.Message)" }
        }

        foreach ($remoteEvidence in @(
            @{ Source = $remoteStatusAdmin; Name = 'Status.json' },
            @{ Source = $remoteLogAdmin; Name = 'Agent.log' }
        )) {
            try {
                if ($null -ne $remoteEvidence.Source -and (Test-Path -LiteralPath $remoteEvidence.Source)) {
                    Copy-Item -LiteralPath $remoteEvidence.Source -Destination (Join-Path $localHostDir $remoteEvidence.Name) -Force -ErrorAction Stop
                }
            }
            catch { Write-ControllerLog "[$computer] WARN evidence copy '$($remoteEvidence.Name)': $($_.Exception.Message)" }
        }

        if ($taskCreated) {
            try { Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Delete' -Arguments @('/Delete','/S',$computer,'/TN',$taskName,'/F') }
            catch { Write-ControllerLog "[$computer] WARN task cleanup: $($_.Exception.Message)" }
        }
        if (-not $KeepRemoteArtifacts -and $null -ne $remoteAdminDir) {
            try {
                if (Test-Path -LiteralPath $remoteAdminDir) { Remove-Item -LiteralPath $remoteAdminDir -Recurse -Force -ErrorAction Stop }
            }
            catch { Write-ControllerLog "[$computer] WARN remote artifact cleanup: $($_.Exception.Message)" }
        }

        $results.Add([pscustomobject]$hostResult)
        Write-RunSummary
    }
}

$results | Format-Table Computer,Success,Stage,DesiredState,Message -AutoSize
Write-ControllerLog "Summary: $summaryPath"
Write-ControllerLog "Undo plan: $undoPath"
Write-RunSummary

$failures = @($results | Where-Object { -not $_.Success })
if ($failures.Count -gt 0) {
    throw "Printer $($operation.ToLowerInvariant()) failed on $($failures.Count) target(s). Review $summaryPath. Any observed state transitions are captured in $undoPath."
}

Write-ControllerLog "PASS: every target returned SYSTEM-context machine-wide '$DesiredState' proof."
Write-RunSummary
