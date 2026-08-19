#Requires -Version 5.1
<#
.SYNOPSIS
Hard-process-bounded Kerberos SMB + Task Scheduler preflight observations.
.DESCRIPTION
Provides the default no-credential kerberos_smb_task observation path used by
Test-SasSoftwareDeploymentTransport.ps1. Potentially blocking remote Windows
operations run in killable child processes so a VPN/route black hole cannot
strand the operator terminal inside an in-process PowerShell Stop/Dispose path.

The module is read-only. It requests Kerberos tickets, tests TCP reachability,
reads ADMIN$, reads the Schedule service state, and queries one reserved
nonexistent task name. It never creates/runs/deletes a task, writes to the
remote target, prompts for credentials, or serializes target identifiers.
#>

Set-StrictMode -Version 2.0

function New-SasHardBoundedTicketObservation {
    param([bool]$Requested = $false, [bool]$Issued = $false)
    [pscustomobject]@{
        requested = $Requested
        issued = $Issued
        ticket_bytes_emitted = $false
    }
}

function New-SasHardBoundedTcpObservation {
    param([bool]$Tested = $false, [bool]$Reachable = $false, [bool]$TimedOut = $false)
    [pscustomobject]@{
        tested = $Tested
        reachable = $Reachable
        timed_out = $TimedOut
    }
}

function New-SasHardBoundedAuthorizationObservation {
    param([bool]$Attempted = $false, [bool]$Authorized = $false, [bool]$AuthorizationDenied = $false)
    [pscustomobject]@{
        attempted = $Attempted
        authorized = $Authorized
        authorization_denied = $AuthorizationDenied
    }
}

function Invoke-SasTransportHardBoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arguments,
        [Parameter(Mandatory = $true)][ValidateRange(1,30)][int]$TimeoutSeconds
    )

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        if (-not $process.Start()) { throw "Unable to start required read-only utility: $FilePath" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            try { [void]$process.WaitForExit(1000) } catch { }
            return [pscustomobject]@{
                exit_code = -1
                timed_out = $true
                output = ''
                error = ''
            }
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            exit_code = [int]$process.ExitCode
            timed_out = $false
            output = [string]$stdoutTask.Result
            error = [string]$stderrTask.Result
        }
    }
    catch {
        return [pscustomobject]@{
            exit_code = -1
            timed_out = $false
            output = ''
            error = $_.Exception.Message
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-SasTransportHardBoundedPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [Parameter(Mandatory = $true)][ValidateRange(1,30)][int]$TimeoutSeconds
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Invoke-SasTransportHardBoundedProcess -FilePath $exe -Arguments (
        '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {0}' -f $encoded
    ) -TimeoutSeconds $TimeoutSeconds
}

function Resolve-SasHardBoundedDns {
    param([string]$ComputerName, [int]$TimeoutSeconds)
    $async = $null
    try {
        $async = [System.Net.Dns]::BeginGetHostAddresses($ComputerName, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            return [pscustomobject]@{ attempted=$true; resolved=$false; address_count=0; timed_out=$true }
        }
        $addresses = @([System.Net.Dns]::EndGetHostAddresses($async))
        return [pscustomobject]@{
            attempted = $true
            resolved = ($addresses.Count -gt 0)
            address_count = [Math]::Min($addresses.Count, 32)
            timed_out = $false
        }
    }
    catch {
        return [pscustomobject]@{ attempted=$true; resolved=$false; address_count=0; timed_out=$false }
    }
    finally {
        if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
    }
}

function Test-SasHardBoundedTcpPort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutSeconds)
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $null
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            return New-SasHardBoundedTcpObservation -Tested $true -TimedOut $true
        }
        $client.EndConnect($async)
        return New-SasHardBoundedTcpObservation -Tested $true -Reachable $true
    }
    catch {
        return New-SasHardBoundedTcpObservation -Tested $true
    }
    finally {
        if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
        $client.Close()
    }
}

function Test-SasHardBoundedAuthorizationDeniedText {
    param([string]$Text)
    return ([string]$Text -match '(?i)access\s+is\s+denied|unauthori[sz]ed|logon\s+failure|authentication\s+failed|0x80070005')
}

function Test-SasHardBoundedTaskNotFoundText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot\s+find|does\s+not\s+exist|not\s+exist|system\s+cannot\s+find\s+the\s+file')
}

function Get-SasHardBoundedDomainJoined {
    param([int]$TimeoutSeconds)
    $script = @'
$ErrorActionPreference = 'Stop'
try {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ([bool]$computer.PartOfDomain) { [Console]::Out.Write('TRUE'); exit 0 }
    [Console]::Out.Write('FALSE'); exit 3
}
catch {
    try {
        $computer = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ([bool]$computer.PartOfDomain) { [Console]::Out.Write('TRUE'); exit 0 }
        [Console]::Out.Write('FALSE'); exit 3
    }
    catch { exit 4 }
}
'@
    $probe = Invoke-SasTransportHardBoundedPowerShell -ScriptText $script -TimeoutSeconds $TimeoutSeconds
    return (-not [bool]$probe.timed_out -and [int]$probe.exit_code -eq 0 -and ([string]$probe.output).Trim() -eq 'TRUE')
}

function Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ComputerName,
        [ValidateRange(1,30)][int]$TimeoutSeconds = 5
    )

    $timeoutStage = ''
    $domainJoined = Get-SasHardBoundedDomainJoined -TimeoutSeconds $TimeoutSeconds
    $tgtCheck = Invoke-SasTransportHardBoundedProcess -FilePath 'klist.exe' -Arguments '' -TimeoutSeconds $TimeoutSeconds
    $tgtPresent = (-not [bool]$tgtCheck.timed_out -and [int]$tgtCheck.exit_code -eq 0 -and [string]$tgtCheck.output -match '(?i)krbtgt/')
    if ([bool]$tgtCheck.timed_out) { $timeoutStage = 'tgt_query' }

    $dns = Resolve-SasHardBoundedDns -ComputerName $ComputerName -TimeoutSeconds $TimeoutSeconds
    if ([bool]$dns.timed_out -and -not $timeoutStage) { $timeoutStage = 'dns' }

    $tickets = [ordered]@{
        http = New-SasHardBoundedTicketObservation
        host = New-SasHardBoundedTicketObservation
        cifs = New-SasHardBoundedTicketObservation
    }
    $tcp = [ordered]@{
        port_5985 = New-SasHardBoundedTcpObservation
        port_5986 = New-SasHardBoundedTcpObservation
        port_445 = New-SasHardBoundedTcpObservation
        port_135 = New-SasHardBoundedTcpObservation
    }
    $winrm = New-SasHardBoundedAuthorizationObservation
    $adminShare = New-SasHardBoundedAuthorizationObservation
    $scheduleService = [pscustomobject]@{ queried=$false; running=$false; authorization_denied=$false }
    $scheduledTaskQuery = [pscustomobject]@{ queried=$false; succeeded=$false; authorization_denied=$false }

    $identityReady = ([bool]$dns.resolved -and -not [bool]$dns.timed_out -and $domainJoined -and $tgtPresent)
    if ($identityReady) {
        $ticket = Invoke-SasTransportHardBoundedProcess -FilePath 'klist.exe' -Arguments ("get CIFS/{0}" -f $ComputerName) -TimeoutSeconds $TimeoutSeconds
        $tickets.cifs = New-SasHardBoundedTicketObservation -Requested $true -Issued (-not [bool]$ticket.timed_out -and [int]$ticket.exit_code -eq 0)
        if ([bool]$ticket.timed_out -and -not $timeoutStage) { $timeoutStage = 'cifs_ticket' }

        $hostTicket = Invoke-SasTransportHardBoundedProcess -FilePath 'klist.exe' -Arguments ("get HOST/{0}" -f $ComputerName) -TimeoutSeconds $TimeoutSeconds
        $tickets.host = New-SasHardBoundedTicketObservation -Requested $true -Issued (-not [bool]$hostTicket.timed_out -and [int]$hostTicket.exit_code -eq 0)
        if ([bool]$hostTicket.timed_out -and -not $timeoutStage) { $timeoutStage = 'host_ticket' }
    }

    if ([bool]$tickets.cifs.issued -and [bool]$tickets.host.issued) {
        $tcp.port_445 = Test-SasHardBoundedTcpPort -ComputerName $ComputerName -Port 445 -TimeoutSeconds $TimeoutSeconds
        if ([bool]$tcp.port_445.timed_out -and -not $timeoutStage) { $timeoutStage = 'tcp_445' }
    }

    if ([bool]$tcp.port_445.reachable) {
        $target64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ComputerName))
        $shareScript = @"
`$ErrorActionPreference = 'Stop'
`$target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$target64'))
try {
    Get-ChildItem -LiteralPath ("\\{0}\ADMIN$" -f `$target) -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
    [Console]::Out.Write('AUTHORIZED')
    exit 0
}
catch {
    [Console]::Error.Write(`$_.Exception.Message)
    exit 5
}
"@
        $shareProbe = Invoke-SasTransportHardBoundedPowerShell -ScriptText $shareScript -TimeoutSeconds $TimeoutSeconds
        $shareText = ([string]$shareProbe.error) + ' ' + ([string]$shareProbe.output)
        $adminShare = New-SasHardBoundedAuthorizationObservation -Attempted $true `
            -Authorized (-not [bool]$shareProbe.timed_out -and [int]$shareProbe.exit_code -eq 0 -and ([string]$shareProbe.output).Trim() -eq 'AUTHORIZED') `
            -AuthorizationDenied (Test-SasHardBoundedAuthorizationDeniedText -Text $shareText)
        if ([bool]$shareProbe.timed_out -and -not $timeoutStage) { $timeoutStage = 'admin_share' }
    }

    if ([bool]$adminShare.authorized) {
        $tcp.port_135 = Test-SasHardBoundedTcpPort -ComputerName $ComputerName -Port 135 -TimeoutSeconds $TimeoutSeconds
        if ([bool]$tcp.port_135.timed_out -and -not $timeoutStage) { $timeoutStage = 'tcp_135' }
    }

    if ([bool]$tcp.port_135.reachable) {
        $target64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ComputerName))
        $serviceScript = @"
`$ErrorActionPreference = 'Stop'
`$target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$target64'))
`$session = `$null
try {
    `$option = New-CimSessionOption -Protocol Dcom
    `$session = New-CimSession -ComputerName `$target -SessionOption `$option -ErrorAction Stop
    `$service = Get-CimInstance -CimSession `$session -ClassName Win32_Service -Filter "Name='Schedule'" -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop
    if (`$null -ne `$service -and [string]`$service.State -eq 'Running') { [Console]::Out.Write('RUNNING'); exit 0 }
    [Console]::Out.Write('NOT_RUNNING'); exit 3
}
catch {
    [Console]::Error.Write(`$_.Exception.Message)
    exit 5
}
finally {
    if (`$null -ne `$session) { Remove-CimSession -CimSession `$session -ErrorAction SilentlyContinue }
}
"@
        $serviceProbe = Invoke-SasTransportHardBoundedPowerShell -ScriptText $serviceScript -TimeoutSeconds $TimeoutSeconds
        $serviceText = ([string]$serviceProbe.error) + ' ' + ([string]$serviceProbe.output)
        $scheduleService = [pscustomobject]@{
            queried = (-not [bool]$serviceProbe.timed_out)
            running = (-not [bool]$serviceProbe.timed_out -and [int]$serviceProbe.exit_code -eq 0 -and ([string]$serviceProbe.output).Trim() -eq 'RUNNING')
            authorization_denied = (Test-SasHardBoundedAuthorizationDeniedText -Text $serviceText)
        }
        if ([bool]$serviceProbe.timed_out -and -not $timeoutStage) { $timeoutStage = 'schedule_service' }

        $taskName = '\SysAdminSuite_TransportPreflight_Probe'
        $taskProbe = Invoke-SasTransportHardBoundedProcess -FilePath 'schtasks.exe' -Arguments ("/Query /S {0} /TN {1} /FO LIST" -f $ComputerName,$taskName) -TimeoutSeconds $TimeoutSeconds
        $taskText = ([string]$taskProbe.error) + ' ' + ([string]$taskProbe.output)
        $taskDenied = Test-SasHardBoundedAuthorizationDeniedText -Text $taskText
        $scheduledTaskQuery = [pscustomobject]@{
            queried = (-not [bool]$taskProbe.timed_out)
            succeeded = (-not [bool]$taskProbe.timed_out -and -not $taskDenied -and ([int]$taskProbe.exit_code -eq 0 -or (Test-SasHardBoundedTaskNotFoundText -Text $taskText)))
            authorization_denied = $taskDenied
        }
        if ([bool]$taskProbe.timed_out -and -not $timeoutStage) { $timeoutStage = 'scheduled_task_query' }
    }

    [pscustomobject]@{
        schema_version = 'sas-software-deployment-hard-bounded-observation-envelope/v1'
        observations = [pscustomobject]@{
            dns = $dns
            identity = [pscustomobject]@{
                domain_joined = $domainJoined
                tgt_present = $tgtPresent
                ticket_bytes_emitted = $false
            }
            service_tickets = [pscustomobject]$tickets
            tcp = [pscustomobject]$tcp
            winrm_session = $winrm
            admin_share = $adminShare
            schedule_service = $scheduleService
            scheduled_task_query = $scheduledTaskQuery
        }
        diagnostic = [pscustomobject]@{
            engine = 'hard_process_bounded'
            timeout_stage = $timeoutStage
            per_operation_timeout_seconds = $TimeoutSeconds
            child_process_isolation = $true
            target_identifier_emitted = $false
            username_emitted = $false
            credential_emitted = $false
            target_mutation_performed = $false
        }
    }
}

Export-ModuleMember -Function Invoke-SasSoftwareDeploymentKerberosSmbHardBoundedObservation
