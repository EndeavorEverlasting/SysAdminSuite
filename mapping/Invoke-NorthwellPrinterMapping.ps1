<#
.SYNOPSIS
    Canonical Northwell field engine for system-wide shared-printer mapping.

.DESCRIPTION
    Maps one or more Windows shared printer queues to one or more Northwell PCs.
    The endpoint action runs as SYSTEM and uses PrintUIEntry /ga so the printer
    registration is per-computer, not tied to the technician's signed-in profile.

    Printer input may be:
      - \\server\queue
      - //server/queue
      - queue name only (resolved from Active Directory, or paired with -PrintServer)

    Direct printer IPs, IP print servers, target-PC IPs, URLs, and ambiguous queue
    names are rejected before endpoint mutation.

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001 -Printer '\\PRINTSERVER\QUEUE01'

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001,WPJ001OPR002 -Printer 'QUEUE01'

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001 -Printer 'QUEUE01' -PrintServer PRINTSERVER

.NOTES
    Technicians should normally launch Map-NorthwellPrinter-SystemWide.cmd at the
    repository root. Run this engine elevated from an authorized Windows controller
    on the Northwell network. The operator must have administrative C$ and remote
    Task Scheduler access to the target PCs. Runtime evidence is preserved locally
    even when a target fails.
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

    [string]$PrintServer,

    [string]$DnsSuffix = 'nslijhs.net',

    [ValidateRange(15, 600)]
    [int]$TimeoutSeconds = 120,

    [switch]$KeepRemoteArtifacts,

    [string]$SessionRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Northwell printer mapping must run from Windows.'
}

$modulePath = Join-Path $PSScriptRoot 'Modules\NorthwellPrinterMapping.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Required resolver module not found: $modulePath"
}
Import-Module $modulePath -Force -ErrorAction Stop

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    throw 'Run PowerShell as Administrator. Machine-wide mapping requires an elevated controller session.'
}

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

$runToken = New-SasNorthwellPrinterRunToken
if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $SessionRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "NorthwellPrinterMap-$runToken"
}
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
$controllerLog = Join-Path $SessionRoot 'Controller.log'
$planPath = Join-Path $SessionRoot 'ResolvedPlan.json'
$summaryPath = Join-Path $SessionRoot 'Summary.json'
$results = New-Object System.Collections.Generic.List[object]

function Write-ControllerLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format s), $Message
    Write-Host $line
    $line | Out-File -LiteralPath $controllerLog -Encoding utf8 -Append
}

function Write-RunSummary {
    $failedCount = @($results | Where-Object { -not $_.Success }).Count
    [ordered]@{
        RunToken = $runToken
        Success = ($results.Count -eq $resolvedComputers.Count -and $failedCount -eq 0)
        Mode = 'MachineWidePerComputer'
        RemoteIdentity = 'SYSTEM'
        PrinterCommand = 'rundll32 printui.dll,PrintUIEntry /ga'
        Computers = $resolvedComputers
        Printers = $resolvedPrinters
        CompletedTargets = $results.Count
        TotalTargets = $resolvedComputers.Count
        Results = @($results)
        PlanPath = $planPath
        ControllerLog = $controllerLog
        Updated = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
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
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-ControllerLog "[$Computer][$Stage] $line"
        }
    }
    if ($exitCode -ne 0) {
        throw "Remote Task Scheduler $Stage failed with exit code $exitCode."
    }
}

@{
    RunToken = $runToken
    Mode = 'MachineWidePerComputer'
    Transport = 'SMB+C$+RemoteTaskScheduler'
    RemoteIdentity = 'SYSTEM'
    PrinterCommand = 'rundll32 printui.dll,PrintUIEntry /ga'
    Computers = $resolvedComputers
    Printers = $resolvedPrinters
    Created = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-ControllerLog '=== Northwell system-wide printer mapping ==='
Write-ControllerLog "Targets: $($resolvedComputers -join ', ')"
Write-ControllerLog "Queues : $($resolvedPrinters -join ', ')"
Write-ControllerLog "Evidence: $SessionRoot"
Write-ControllerLog 'Policy: shared queue names only; direct printer IP mapping is rejected.'
Write-ControllerLog 'Scope: per-computer (/ga), executed as SYSTEM for multi-user PCs.'
Write-RunSummary

if ($WhatIfPreference) {
    foreach ($computer in $resolvedComputers) {
        foreach ($queue in $resolvedPrinters) {
            $null = $PSCmdlet.ShouldProcess($computer, "Map system-wide printer $queue")
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

function Write-AgentLog {
    param([string]$Message)
    ('[{0}] {1}' -f (Get-Date -Format s), $Message) | Add-Content -LiteralPath $logPath -Encoding UTF8
}

function Get-MachineWidePrinterConnections {
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections'
    if (-not (Test-Path -LiteralPath $key)) { return @() }

    return @(
        Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
                if ($item.Server -and $item.Printer) {
                    ('\\{0}\{1}' -f ([string]$item.Server).TrimStart([char[]]'\'), [string]$item.Printer).ToLowerInvariant()
                }
            }
            catch {}
        } | Where-Object { $_ } | Sort-Object -Unique
    )
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $queues = @($config.Printers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($queues.Count -eq 0) { throw 'No queues in staged configuration.' }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-AgentLog "Running as $identity on $env:COMPUTERNAME"
    if ($identity -notmatch 'SYSTEM$') { throw "Worker identity is not SYSTEM: $identity" }
    Write-AgentLog "Requested machine-wide queues: $($queues -join ', ')"

    foreach ($queue in $queues) {
        if ($queue -notmatch '^\\\\[^\\]+\\[^\\]+$') {
            throw "Unsafe/non-UNC queue reached agent: $queue"
        }
        Write-AgentLog "ADD /ga $queue"
        & "$env:SystemRoot\System32\rundll32.exe" 'printui.dll,PrintUIEntry' '/ga' "/n$queue"
        $printUiExitCode = $LASTEXITCODE
        if ($printUiExitCode -ne 0) {
            throw "PrintUIEntry /ga failed for $queue with exit code $printUiExitCode."
        }
    }

    try {
        $gp = Start-Process -FilePath 'gpupdate.exe' -ArgumentList @('/target:computer','/force') -WindowStyle Hidden -Wait -PassThru
        Write-AgentLog "gpupdate exit code: $($gp.ExitCode)"
    }
    catch {
        Write-AgentLog "WARN gpupdate: $($_.Exception.Message)"
    }

    $verifyDeadline = (Get-Date).AddSeconds(30)
    do {
        $machineWide = @(Get-MachineWidePrinterConnections)
        $missing = @($queues | Where-Object { $machineWide -notcontains $_ })
        if ($missing.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $verifyDeadline)

    $success = ($missing.Count -eq 0)
    if ($success) {
        Write-AgentLog 'Verified every requested queue under HKLM machine-wide printer connections.'
    }
    else {
        Write-AgentLog "VERIFY FAIL missing from HKLM after 30 seconds: $($missing -join ', ')"
    }

    @{
        ComputerName = $env:COMPUTERNAME
        Identity = $identity
        Mode = 'MachineWidePerComputer'
        Success = $success
        Requested = $queues
        MachineWideUNC = $machineWide
        Missing = $missing
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
catch {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-AgentLog "FATAL: $($_.Exception.Message)"
    @{
        ComputerName = $env:COMPUTERNAME
        Identity = $identity
        Mode = 'MachineWidePerComputer'
        Success = $false
        Error = $_.Exception.Message
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
'@

foreach ($computer in $resolvedComputers) {
    $safeComputer = ($computer -replace '[^A-Za-z0-9.-]', '_')
    $localHostDir = Join-Path $SessionRoot $safeComputer
    New-Item -ItemType Directory -Path $localHostDir -Force | Out-Null

    $remoteRel = "ProgramData\SysAdminSuite\Mapping\NorthwellPrinterMap\$runToken"
    $remoteAdminDir = "\\$computer\C$\$remoteRel"
    $remoteAgentAdmin = Join-Path $remoteAdminDir 'Agent.ps1'
    $remoteConfigAdmin = Join-Path $remoteAdminDir 'Config.json'
    $remoteLauncherAdmin = Join-Path $remoteAdminDir 'Start-Agent.cmd'
    $remoteStatusAdmin = Join-Path $remoteAdminDir 'Status.json'
    $remoteLogAdmin = Join-Path $remoteAdminDir 'Agent.log'
    $remoteAgentLocal = "C:\$remoteRel\Agent.ps1"
    $remoteConfigLocal = "C:\$remoteRel\Config.json"
    $remoteWorkLocal = "C:\$remoteRel"
    $remoteLauncherLocal = "C:\$remoteRel\Start-Agent.cmd"
    $taskName = "SysAdminSuite_NorthwellPrinterMap_$runToken"
    $taskCreated = $false

    $hostResult = [ordered]@{
        Computer = $computer
        Success = $false
        Stage = 'Preflight'
        Message = ''
        Evidence = $localHostDir
    }

    try {
        Write-ControllerLog "[$computer] Preflight C$ and Task Scheduler."
        if (-not (Test-Path -LiteralPath "\\$computer\C$")) {
            throw "Admin share unavailable: \\$computer\C$. Confirm Northwell network, DNS, credentials, firewall, and admin rights."
        }

        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Query' -Arguments @('/Query','/S',$computer,'/FO','LIST')

        if (-not $PSCmdlet.ShouldProcess($computer, "Map $($resolvedPrinters.Count) shared printer queue(s) machine-wide as SYSTEM")) {
            $hostResult.Stage = 'Skipped'
            $hostResult.Message = 'ShouldProcess declined.'
            continue
        }

        New-Item -ItemType Directory -Path $remoteAdminDir -Force | Out-Null
        Set-Content -LiteralPath $remoteAgentAdmin -Value $agentCode -Encoding UTF8
        @{ Printers = $resolvedPrinters } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $remoteConfigAdmin -Encoding UTF8

        $launcher = @(
            '@echo off',
            ('"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File {0} -ConfigPath {1} -WorkDir {2}' -f $remoteAgentLocal,$remoteConfigLocal,$remoteWorkLocal),
            'exit /b %ERRORLEVEL%'
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $remoteLauncherAdmin -Value $launcher -Encoding ASCII

        $createArguments = New-SasNorthwellPrinterTaskCreateArguments -Computer $computer -TaskName $taskName -RemoteLauncherLocal $remoteLauncherLocal
        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Create' -Arguments $createArguments
        $taskCreated = $true
        Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Run' -Arguments @('/Run','/S',$computer,'/TN',$taskName)

        $hostResult.Stage = 'WaitingForProof'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $remoteStatusAdmin)) {
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path -LiteralPath $remoteStatusAdmin)) {
            throw "Timed out after $TimeoutSeconds seconds waiting for Status.json. Remote evidence was not observed."
        }

        $status = Get-Content -LiteralPath $remoteStatusAdmin -Raw | ConvertFrom-Json
        $null = Assert-SasNorthwellPrinterStatusProof -Status $status -RequestedPrinters $resolvedPrinters

        $hostResult.Success = $true
        $hostResult.Stage = 'VerifiedMachineWide'
        $hostResult.Message = 'SYSTEM /ga completed and all requested queues were verified under HKLM.'
        Write-ControllerLog "[$computer] PASS: machine-wide registration verified."
    }
    catch {
        $hostResult.Success = $false
        $hostResult.Stage = 'Failed'
        $hostResult.Message = $_.Exception.Message
        Write-ControllerLog "[$computer] FAIL: $($_.Exception.Message)"
    }
    finally {
        foreach ($remoteEvidence in @(
            @{ Source = $remoteStatusAdmin; Name = 'Status.json' },
            @{ Source = $remoteLogAdmin; Name = 'Agent.log' }
        )) {
            try {
                if (Test-Path -LiteralPath $remoteEvidence.Source) {
                    Copy-Item -LiteralPath $remoteEvidence.Source -Destination (Join-Path $localHostDir $remoteEvidence.Name) -Force -ErrorAction Stop
                }
            }
            catch {
                Write-ControllerLog "[$computer] WARN evidence copy '$($remoteEvidence.Name)': $($_.Exception.Message)"
            }
        }

        if ($taskCreated) {
            try {
                Invoke-RemoteTaskScheduler -Computer $computer -Stage 'Delete' -Arguments @('/Delete','/S',$computer,'/TN',$taskName,'/F')
            }
            catch {
                Write-ControllerLog "[$computer] WARN task cleanup: $($_.Exception.Message)"
            }
        }

        if (-not $KeepRemoteArtifacts) {
            try {
                if (Test-Path -LiteralPath $remoteAdminDir) {
                    Remove-Item -LiteralPath $remoteAdminDir -Recurse -Force -ErrorAction Stop
                }
            }
            catch {
                Write-ControllerLog "[$computer] WARN remote artifact cleanup: $($_.Exception.Message)"
            }
        }

        $results.Add([pscustomobject]$hostResult)
        Write-RunSummary
    }
}

$results | Format-Table Computer,Success,Stage,Message -AutoSize
Write-ControllerLog "Summary: $summaryPath"
Write-RunSummary

$failures = @($results | Where-Object { -not $_.Success })
if ($failures.Count -gt 0) {
    throw "Printer mapping failed on $($failures.Count) target(s). Review $summaryPath and per-host evidence."
}

Write-ControllerLog 'PASS: every target returned SYSTEM-context, HKLM machine-wide queue proof.'
Write-RunSummary
