<#
.SYNOPSIS
    Canonical Northwell field entrypoint for system-wide shared-printer mapping.

.DESCRIPTION
    Maps one or more Windows shared printer queues to one or more Northwell PCs.
    The remote action runs as SYSTEM and uses PrintUIEntry /ga, which creates a
    per-computer printer connection for all users of the PC. Printer IP addresses
    are deliberately rejected.

    Printer input may be either:
      - \\server\queue (or //server/queue), or
      - queue name only. Queue-only input is resolved through Active Directory,
        or combined with -PrintServer when supplied explicitly.

    Target input is a workstation hostname/FQDN, never an IP address.

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001 -Printer '\\PRINTSERVER\QUEUE01'

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001,WPJ001OPR002 -Printer 'QUEUE01'

.EXAMPLE
    .\mapping\Invoke-NorthwellPrinterMapping.ps1 -ComputerName WPJ001OPR001 -Printer 'QUEUE01' -PrintServer PRINTSERVER

.NOTES
    Run from an elevated Windows PowerShell or PowerShell session on the
    authorized Northwell network. The operator account must have administrative
    access to the target PCs' C$ shares and remote Task Scheduler.
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

# Fail before touching endpoints if a referenced print-server hostname cannot resolve.
$printServers = @($resolvedPrinters | ForEach-Object {
    if ($_ -match '^\\\\([^\\]+)\\') { $Matches[1] }
} | Where-Object { $_ } | Sort-Object -Unique)
foreach ($server in $printServers) {
    try {
        $null = [System.Net.Dns]::GetHostAddresses($server)
    }
    catch {
        throw "Print server '$server' did not resolve in DNS. No endpoint changes were made. $($_.Exception.Message)"
    }
}

$runToken = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($SessionRoot)) {
    $SessionRoot = Join-Path (Join-Path $PSScriptRoot 'Logs') "NorthwellPrinterMap-$runToken"
}
New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
$controllerLog = Join-Path $SessionRoot 'Controller.log'
$planPath = Join-Path $SessionRoot 'ResolvedPlan.json'
$summaryPath = Join-Path $SessionRoot 'Summary.json'

function Write-ControllerLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format s), $Message
    Write-Host $line
    $line | Out-File -LiteralPath $controllerLog -Encoding utf8 -Append
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

if ($WhatIfPreference) {
    foreach ($computer in $resolvedComputers) {
        foreach ($queue in $resolvedPrinters) {
            $null = $PSCmdlet.ShouldProcess($computer, "Map system-wide printer $queue")
        }
    }
    Write-ControllerLog 'WhatIf complete. No remote files, tasks, or printer connections were changed.'
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
                    ('\\{0}\{1}' -f ([string]$item.Server).TrimStart('\'), [string]$item.Printer).ToLowerInvariant()
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

    Write-AgentLog "Running as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) on $env:COMPUTERNAME"
    Write-AgentLog "Requested machine-wide queues: $($queues -join ', ')"

    foreach ($queue in $queues) {
        if ($queue -notmatch '^\\\\[^\\]+\\[^\\]+$') {
            throw "Unsafe/non-UNC queue reached agent: $queue"
        }
        Write-AgentLog "ADD /ga $queue"
        $process = Start-Process -FilePath 'rundll32.exe' -ArgumentList @(
            'printui.dll,PrintUIEntry',
            '/ga',
            "/n$queue"
        ) -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "PrintUIEntry /ga failed for $queue with exit code $($process.ExitCode)."
        }
    }

    try {
        $gp = Start-Process -FilePath 'gpupdate.exe' -ArgumentList @('/target:computer','/force') -WindowStyle Hidden -Wait -PassThru
        Write-AgentLog "gpupdate exit code: $($gp.ExitCode)"
    }
    catch {
        Write-AgentLog "WARN gpupdate: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 2
    $machineWide = @(Get-MachineWidePrinterConnections)
    $missing = @($queues | Where-Object { $machineWide -notcontains $_ })
    $success = ($missing.Count -eq 0)

    if ($success) {
        Write-AgentLog 'Verified every requested queue under HKLM machine-wide printer connections.'
    }
    else {
        Write-AgentLog "VERIFY FAIL missing from HKLM: $($missing -join ', ')"
    }

    @{
        ComputerName = $env:COMPUTERNAME
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Mode = 'MachineWidePerComputer'
        Success = $success
        Requested = $queues
        MachineWideUNC = $machineWide
        Missing = $missing
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
catch {
    Write-AgentLog "FATAL: $($_.Exception.Message)"
    @{
        ComputerName = $env:COMPUTERNAME
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Mode = 'MachineWidePerComputer'
        Success = $false
        Error = $_.Exception.Message
        Finished = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
'@

$results = New-Object System.Collections.Generic.List[object]

foreach ($computer in $resolvedComputers) {
    $safeComputer = ($computer -replace '[^A-Za-z0-9.-]', '_')
    $localHostDir = Join-Path $SessionRoot $safeComputer
    New-Item -ItemType Directory -Path $localHostDir -Force | Out-Null

    $remoteRel = "ProgramData\SysAdminSuite\Mapping\NorthwellPrinterMap\$runToken"
    $remoteAdminDir = "\\$computer\C$\$remoteRel"
    $remoteAgentAdmin = Join-Path $remoteAdminDir 'Agent.ps1'
    $remoteConfigAdmin = Join-Path $remoteAdminDir 'Config.json'
    $remoteStatusAdmin = Join-Path $remoteAdminDir 'Status.json'
    $remoteLogAdmin = Join-Path $remoteAdminDir 'Agent.log'
    $remoteAgentLocal = "C:\$remoteRel\Agent.ps1"
    $remoteConfigLocal = "C:\$remoteRel\Config.json"
    $remoteWorkLocal = "C:\$remoteRel"
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

        $query = Start-Process -FilePath 'schtasks.exe' -ArgumentList @('/Query','/S',$computer,'/FO','LIST') -NoNewWindow -Wait -PassThru
        if ($query.ExitCode -ne 0) {
            throw "Remote Task Scheduler query failed with exit code $($query.ExitCode)."
        }

        if (-not $PSCmdlet.ShouldProcess($computer, "Map $($resolvedPrinters.Count) shared printer queue(s) machine-wide as SYSTEM")) {
            $hostResult.Stage = 'Skipped'
            $hostResult.Message = 'ShouldProcess declined.'
            $results.Add([pscustomobject]$hostResult)
            continue
        }

        New-Item -ItemType Directory -Path $remoteAdminDir -Force | Out-Null
        Set-Content -LiteralPath $remoteAgentAdmin -Value $agentCode -Encoding UTF8
        @{
            Printers = $resolvedPrinters
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $remoteConfigAdmin -Encoding UTF8

        $when = (Get-Date).AddMinutes(2)
        $taskArgs = @(
            '/Create','/F',
            '/S',$computer,
            '/RU','SYSTEM',
            '/RL','HIGHEST',
            '/SC','ONCE',
            '/SD',$when.ToShortDateString(),
            '/ST',$when.ToString('HH:mm'),
            '/TN',$taskName,
            '/TR',("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -ConfigPath `"{1}`" -WorkDir `"{2}`"" -f $remoteAgentLocal,$remoteConfigLocal,$remoteWorkLocal)
        )
        $create = Start-Process -FilePath 'schtasks.exe' -ArgumentList $taskArgs -NoNewWindow -Wait -PassThru
        if ($create.ExitCode -ne 0) { throw "SCHTASKS /Create failed with exit code $($create.ExitCode)." }
        $taskCreated = $true

        $run = Start-Process -FilePath 'schtasks.exe' -ArgumentList @('/Run','/S',$computer,'/TN',$taskName) -NoNewWindow -Wait -PassThru
        if ($run.ExitCode -ne 0) { throw "SCHTASKS /Run failed with exit code $($run.ExitCode)." }

        $hostResult.Stage = 'WaitingForProof'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $remoteStatusAdmin)) {
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path -LiteralPath $remoteStatusAdmin)) {
            throw "Timed out after $TimeoutSeconds seconds waiting for Status.json. Remote evidence was not observed."
        }

        Copy-Item -LiteralPath $remoteStatusAdmin -Destination (Join-Path $localHostDir 'Status.json') -Force
        if (Test-Path -LiteralPath $remoteLogAdmin) {
            Copy-Item -LiteralPath $remoteLogAdmin -Destination (Join-Path $localHostDir 'Agent.log') -Force
        }

        $status = Get-Content -LiteralPath $remoteStatusAdmin -Raw | ConvertFrom-Json
        if (-not [bool]$status.Success) {
            $detail = if ($status.Error) { [string]$status.Error } elseif ($status.Missing) { 'Missing machine-wide queue(s): ' + (@($status.Missing) -join ', ') } else { 'Agent returned Success=false.' }
            throw $detail
        }
        if ([string]$status.Identity -notmatch 'SYSTEM$') {
            throw "Remote worker did not run as SYSTEM (identity: $($status.Identity))."
        }

        $verified = @($status.MachineWideUNC | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $missingControllerProof = @($resolvedPrinters | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $verified -notcontains $_ })
        if ($missingControllerProof.Count -gt 0) {
            throw "Status.json did not prove requested machine-wide connection(s): $($missingControllerProof -join ', ')"
        }

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
        if ($taskCreated) {
            try {
                $null = Start-Process -FilePath 'schtasks.exe' -ArgumentList @('/Delete','/S',$computer,'/TN',$taskName,'/F') -NoNewWindow -Wait -PassThru
            }
            catch { Write-ControllerLog "[$computer] WARN task cleanup: $($_.Exception.Message)" }
        }
        if (-not $KeepRemoteArtifacts) {
            try {
                if (Test-Path -LiteralPath $remoteAdminDir) {
                    Remove-Item -LiteralPath $remoteAdminDir -Recurse -Force -ErrorAction Stop
                }
            }
            catch { Write-ControllerLog "[$computer] WARN remote artifact cleanup: $($_.Exception.Message)" }
        }
    }

    $results.Add([pscustomobject]$hostResult)
}

$summary = [ordered]@{
    RunToken = $runToken
    Success = (@($results | Where-Object { -not $_.Success }).Count -eq 0)
    Mode = 'MachineWidePerComputer'
    Computers = $resolvedComputers
    Printers = $resolvedPrinters
    Results = @($results)
    PlanPath = $planPath
    ControllerLog = $controllerLog
    Finished = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$results | Format-Table Computer,Success,Stage,Message -AutoSize
Write-ControllerLog "Summary: $summaryPath"

$failures = @($results | Where-Object { -not $_.Success })
if ($failures.Count -gt 0) {
    throw "Printer mapping failed on $($failures.Count) target(s). Review $summaryPath and per-host evidence."
}

Write-ControllerLog 'PASS: every target returned SYSTEM-context, HKLM machine-wide queue proof.'
