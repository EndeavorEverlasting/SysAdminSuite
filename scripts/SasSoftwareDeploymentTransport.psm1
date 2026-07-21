#Requires -Version 5.1
<#
.SYNOPSIS
Read-only observation and fail-closed selection for software deployment transports.
.DESCRIPTION
The module observes WinRM and Kerberos/SMB/Task Scheduler prerequisites. It never
installs software, changes target configuration, or creates scheduled tasks.
#>

Set-StrictMode -Version 2.0

function New-SasTransportTicketObservation {
    param([bool]$Requested = $false, [bool]$Issued = $false)
    [pscustomobject]@{
        requested = $Requested
        issued = $Issued
        ticket_bytes_emitted = $false
    }
}

function New-SasTransportTcpObservation {
    param([bool]$Tested = $false, [bool]$Reachable = $false, [bool]$TimedOut = $false)
    [pscustomobject]@{
        tested = $Tested
        reachable = $Reachable
        timed_out = $TimedOut
    }
}

function New-SasTransportAuthorizationObservation {
    param([bool]$Attempted = $false, [bool]$Authorized = $false, [bool]$AuthorizationDenied = $false)
    [pscustomobject]@{
        attempted = $Attempted
        authorized = $Authorized
        authorization_denied = $AuthorizationDenied
    }
}

function Test-SasTransportObservationContradiction {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Observations)

    if (-not $Observations.dns.attempted -and ($Observations.dns.resolved -or $Observations.dns.timed_out)) { return $true }
    if ($Observations.dns.resolved -and ([int]$Observations.dns.address_count -lt 1 -or $Observations.dns.timed_out)) { return $true }
    if (-not $Observations.dns.resolved -and [int]$Observations.dns.address_count -gt 0) { return $true }

    foreach ($ticketName in @('http', 'host', 'cifs')) {
        $ticket = $Observations.service_tickets.$ticketName
        if ($ticket.issued -and -not $ticket.requested) { return $true }
        if ($ticket.ticket_bytes_emitted) { return $true }
    }
    if ($Observations.identity.ticket_bytes_emitted) { return $true }

    foreach ($portName in @('port_5985', 'port_5986', 'port_445', 'port_135')) {
        $port = $Observations.tcp.$portName
        if ($port.reachable -and (-not $port.tested -or $port.timed_out)) { return $true }
        if ($port.timed_out -and -not $port.tested) { return $true }
    }

    foreach ($name in @('winrm_session', 'admin_share')) {
        $item = $Observations.$name
        if (($item.authorized -or $item.authorization_denied) -and -not $item.attempted) { return $true }
        if ($item.authorized -and $item.authorization_denied) { return $true }
    }
    if (($Observations.schedule_service.running -or $Observations.schedule_service.authorization_denied) -and -not $Observations.schedule_service.queried) { return $true }
    if ($Observations.schedule_service.running -and $Observations.schedule_service.authorization_denied) { return $true }
    if (($Observations.scheduled_task_query.succeeded -or $Observations.scheduled_task_query.authorization_denied) -and -not $Observations.scheduled_task_query.queried) { return $true }
    if ($Observations.scheduled_task_query.succeeded -and $Observations.scheduled_task_query.authorization_denied) { return $true }
    return $false
}

function New-SasSoftwareDeploymentTransportResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Observations,
        [Parameter(Mandatory = $true)][ValidateSet('sanitized_fixture', 'operator_local_live')][string]$EvidenceClass,
        [Parameter(Mandatory = $true)][bool]$NetworkActivityPerformed
    )

    if ($EvidenceClass -eq 'sanitized_fixture' -and $NetworkActivityPerformed) {
        throw 'A sanitized fixture cannot claim network activity.'
    }

    $classification = 'inconclusive'
    $transport = 'none'
    $reasonCodes = @('required_observation_missing')
    $authorizationProven = $false
    $preflightComplete = $false

    $contradictory = Test-SasTransportObservationContradiction -Observations $Observations
    $timedOut = [bool]$Observations.dns.timed_out
    foreach ($portName in @('port_5985', 'port_5986', 'port_445', 'port_135')) {
        if ($Observations.tcp.$portName.timed_out) { $timedOut = $true }
    }

    $winrmPortReady = (
        ($Observations.tcp.port_5985.tested -and $Observations.tcp.port_5985.reachable -and -not $Observations.tcp.port_5985.timed_out) -or
        ($Observations.tcp.port_5986.tested -and $Observations.tcp.port_5986.reachable -and -not $Observations.tcp.port_5986.timed_out)
    )
    $winrmReady = $winrmPortReady -and
        $Observations.winrm_session.attempted -and
        $Observations.winrm_session.authorized -and
        -not $Observations.winrm_session.authorization_denied

    $smbReady = $Observations.dns.attempted -and
        $Observations.dns.resolved -and
        -not $Observations.dns.timed_out -and
        $Observations.identity.domain_joined -and
        $Observations.identity.tgt_present -and
        $Observations.service_tickets.cifs.requested -and
        $Observations.service_tickets.cifs.issued -and
        $Observations.tcp.port_445.tested -and
        $Observations.tcp.port_445.reachable -and
        -not $Observations.tcp.port_445.timed_out -and
        $Observations.tcp.port_135.tested -and
        $Observations.tcp.port_135.reachable -and
        -not $Observations.tcp.port_135.timed_out -and
        $Observations.admin_share.attempted -and
        $Observations.admin_share.authorized -and
        -not $Observations.admin_share.authorization_denied -and
        $Observations.schedule_service.queried -and
        $Observations.schedule_service.running -and
        -not $Observations.schedule_service.authorization_denied -and
        $Observations.scheduled_task_query.queried -and
        $Observations.scheduled_task_query.succeeded -and
        -not $Observations.scheduled_task_query.authorization_denied

    $authorizationDenied = $Observations.winrm_session.authorization_denied -or
        $Observations.admin_share.authorization_denied -or
        $Observations.schedule_service.authorization_denied -or
        $Observations.scheduled_task_query.authorization_denied

    $allPortsTested = $true
    $anyPortReachable = $false
    foreach ($portName in @('port_5985', 'port_5986', 'port_445', 'port_135')) {
        if (-not $Observations.tcp.$portName.tested) { $allPortsTested = $false }
        if ($Observations.tcp.$portName.reachable) { $anyPortReachable = $true }
    }

    if ($contradictory) {
        $reasonCodes = @('contradictory_observations')
    }
    elseif ($timedOut) {
        $reasonCodes = @('observation_timeout', 'required_observation_missing')
    }
    elseif ($winrmReady) {
        $classification = 'winrm_ready'
        $transport = 'winrm'
        $reasonCodes = @('winrm_session_authorized')
        $authorizationProven = $true
        $preflightComplete = $true
    }
    elseif ($smbReady) {
        $classification = 'kerberos_smb_task_ready'
        $transport = 'kerberos_smb_task'
        $reasonCodes = @('all_kerberos_smb_task_prerequisites_satisfied')
        $authorizationProven = $true
        $preflightComplete = $true
    }
    elseif ($authorizationDenied) {
        $classification = 'transport_reachable_authorization_denied'
        $reasonCodes = @('reachable_transport_authorization_denied')
        $preflightComplete = $true
    }
    elseif ($allPortsTested -and -not $anyPortReachable) {
        $classification = 'no_supported_transport'
        $reasonCodes = @('required_transport_ports_unreachable')
        $preflightComplete = $true
    }

    $proofCeiling = if ($EvidenceClass -eq 'sanitized_fixture') {
        'Sanitized fixture proof of read-only transport classification only; no target was contacted, changed, or authorized for deployment.'
    }
    else {
        'Operator-local read-only preflight observations and transport classification only; no task creation, software execution, or target mutation is proven.'
    }

    [pscustomobject]@{
        schema_version = 'sas-software-deployment-transport-result/v1'
        workflow_id = 'software-deployment-transport'
        evidence_class = $EvidenceClass
        target_scope = [pscustomobject]@{
            target_count = 1
            identifier_emitted = $false
        }
        observations = $Observations
        decision = [pscustomobject]@{
            classification = $classification
            selected_transport = $transport
            reason_codes = @($reasonCodes)
            silent_fallback_permitted = $false
            fallback_after_mutation_permitted = $false
        }
        proof = [pscustomobject]@{
            preflight_complete = $preflightComplete
            transport_authorization_proven = $authorizationProven
            task_creation_proven = $false
            system_execution_proven = $false
            result_retrieval_proven = $false
            cleanup_proven = $false
            live_runtime = ($EvidenceClass -eq 'operator_local_live')
        }
        network_activity_performed = $NetworkActivityPerformed
        target_mutation_performed = $false
        proof_ceiling = $proofCeiling
    }
}

function Invoke-SasBoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arguments,
        [Parameter(Mandatory = $true)][ValidateRange(1, 30)][int]$TimeoutSeconds
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
            return [pscustomobject]@{ exit_code = -1; timed_out = $true; output = ''; error = '' }
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            exit_code = $process.ExitCode
            timed_out = $false
            output = [string]$stdoutTask.Result
            error = [string]$stderrTask.Result
        }
    }
    catch {
        return [pscustomobject]@{ exit_code = -1; timed_out = $false; output = ''; error = $_.Exception.Message }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-SasBoundedPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [Parameter(Mandatory = $true)][ValidateRange(1, 30)][int]$TimeoutSeconds
    )

    $powershell = [PowerShell]::Create()
    try {
        [void]$powershell.AddScript($ScriptBlock.ToString())
        foreach ($name in $Parameters.Keys) { [void]$powershell.AddParameter($name, $Parameters[$name]) }
        $async = $powershell.BeginInvoke()
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            try { $powershell.Stop() } catch { }
            return [pscustomobject]@{ succeeded = $false; timed_out = $true; output = @(); error_text = '' }
        }
        $output = @($powershell.EndInvoke($async))
        $errors = @($powershell.Streams.Error | ForEach-Object { $_.Exception.Message })
        return [pscustomobject]@{
            succeeded = ($errors.Count -eq 0)
            timed_out = $false
            output = $output
            error_text = ($errors -join ' ')
        }
    }
    catch {
        return [pscustomobject]@{ succeeded = $false; timed_out = $false; output = @(); error_text = $_.Exception.Message }
    }
    finally {
        $powershell.Dispose()
    }
}

function Test-SasAuthorizationDeniedText {
    param([string]$Text)
    return ([string]$Text -match '(?i)access\s+is\s+denied|unauthori[sz]ed|logon\s+failure|authentication\s+failed|0x80070005')
}

function Resolve-SasBoundedDns {
    param([string]$ComputerName, [int]$TimeoutSeconds)
    $async = $null
    try {
        $async = [System.Net.Dns]::BeginGetHostAddresses($ComputerName, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            return [pscustomobject]@{ attempted = $true; resolved = $false; address_count = 0; timed_out = $true }
        }
        $addresses = @([System.Net.Dns]::EndGetHostAddresses($async))
        return [pscustomobject]@{ attempted = $true; resolved = ($addresses.Count -gt 0); address_count = [Math]::Min($addresses.Count, 32); timed_out = $false }
    }
    catch {
        return [pscustomobject]@{ attempted = $true; resolved = $false; address_count = 0; timed_out = $false }
    }
    finally {
        if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
    }
}

function Test-SasBoundedTcpPort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutSeconds)
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $null
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            return New-SasTransportTcpObservation -Tested $true -TimedOut $true
        }
        $client.EndConnect($async)
        return New-SasTransportTcpObservation -Tested $true -Reachable $true
    }
    catch {
        return New-SasTransportTcpObservation -Tested $true
    }
    finally {
        if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
        $client.Close()
    }
}

function Test-SasFqdn {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ComputerName)
    return ($ComputerName.Length -le 253 -and
        $ComputerName.Contains('.') -and
        $ComputerName -match '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
}

function Invoke-SasSoftwareDeploymentTransportObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $false)][System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 5
    )

    if (-not (Test-SasFqdn -ComputerName $ComputerName)) {
        throw 'ComputerName must be a fully qualified DNS name.'
    }

    $domainJoined = $false
    try {
        $domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
    }
    catch {
        try { $domainJoined = [bool](Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
    }

    $tgtCheck = Invoke-SasBoundedProcess -FilePath 'klist.exe' -Arguments '' -TimeoutSeconds $TimeoutSeconds
    $tgtPresent = (-not $tgtCheck.timed_out -and $tgtCheck.exit_code -eq 0 -and $tgtCheck.output -match '(?i)krbtgt/')

    $dns = Resolve-SasBoundedDns -ComputerName $ComputerName -TimeoutSeconds $TimeoutSeconds
    $tickets = [ordered]@{}
    foreach ($service in @('HTTP', 'HOST', 'CIFS')) {
        if ($dns.resolved -and $domainJoined -and $tgtPresent) {
            $ticketResult = Invoke-SasBoundedProcess -FilePath 'klist.exe' -Arguments ("get {0}/{1}" -f $service, $ComputerName) -TimeoutSeconds $TimeoutSeconds
            $tickets[$service.ToLowerInvariant()] = New-SasTransportTicketObservation -Requested $true -Issued (-not $ticketResult.timed_out -and $ticketResult.exit_code -eq 0)
        }
        else {
            $tickets[$service.ToLowerInvariant()] = New-SasTransportTicketObservation
        }
    }

    $tcp = [ordered]@{}
    foreach ($port in @(5985, 5986, 445, 135)) {
        $tcp["port_$port"] = Test-SasBoundedTcpPort -ComputerName $ComputerName -Port $port -TimeoutSeconds $TimeoutSeconds
    }

    $winrm = New-SasTransportAuthorizationObservation
    if ($tcp.port_5985.reachable -or $tcp.port_5986.reachable) {
        $winrmParameters = @{
            ComputerName = $ComputerName
            UseSsl = (-not $tcp.port_5985.reachable -and $tcp.port_5986.reachable)
            TimeoutMilliseconds = ($TimeoutSeconds * 1000)
            SuppliedCredential = $Credential
        }
        $winrmProbe = Invoke-SasBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters $winrmParameters -ScriptBlock {
            param($ComputerName, $UseSsl, $TimeoutMilliseconds, $SuppliedCredential)
            $option = New-PSSessionOption -OpenTimeout $TimeoutMilliseconds -OperationTimeout $TimeoutMilliseconds
            $parameters = @{ ComputerName = $ComputerName; SessionOption = $option; ErrorAction = 'Stop' }
            if ($UseSsl) { $parameters.UseSSL = $true }
            if ($null -ne $SuppliedCredential) { $parameters.Credential = $SuppliedCredential }
            $session = $null
            try {
                $session = New-PSSession @parameters
                $true
            }
            finally {
                if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            }
        }
        $winrm = New-SasTransportAuthorizationObservation -Attempted $true -Authorized $winrmProbe.succeeded -AuthorizationDenied (Test-SasAuthorizationDeniedText -Text $winrmProbe.error_text)
    }

    $adminShare = New-SasTransportAuthorizationObservation
    $scheduleService = [pscustomobject]@{ queried = $false; running = $false; authorization_denied = $false }
    $scheduledTaskQuery = [pscustomobject]@{ queried = $false; succeeded = $false; authorization_denied = $false }

    if ($tcp.port_445.reachable -and $tcp.port_135.reachable) {
        $shareProbe = Invoke-SasBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential } -ScriptBlock {
            param($ComputerName, $SuppliedCredential)
            $root = "\\$ComputerName\ADMIN$"
            $driveName = $null
            try {
                if ($null -ne $SuppliedCredential) {
                    $driveName = 'SAS' + [guid]::NewGuid().ToString('N').Substring(0, 8)
                    New-PSDrive -Name $driveName -PSProvider FileSystem -Root $root -Credential $SuppliedCredential -ErrorAction Stop | Out-Null
                    Get-ChildItem -LiteralPath ($driveName + ':\') -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
                }
                else {
                    Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null
                }
                $true
            }
            finally {
                if ($driveName) { Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue }
            }
        }
        $adminShare = New-SasTransportAuthorizationObservation -Attempted $true -Authorized $shareProbe.succeeded -AuthorizationDenied (Test-SasAuthorizationDeniedText -Text $shareProbe.error_text)

        $serviceProbe = Invoke-SasBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential; OperationTimeout = $TimeoutSeconds } -ScriptBlock {
            param($ComputerName, $SuppliedCredential, $OperationTimeout)
            $session = $null
            try {
                $option = New-CimSessionOption -Protocol Dcom
                $parameters = @{ ComputerName = $ComputerName; SessionOption = $option; ErrorAction = 'Stop' }
                if ($null -ne $SuppliedCredential) { $parameters.Credential = $SuppliedCredential }
                $session = New-CimSession @parameters
                $service = Get-CimInstance -CimSession $session -ClassName Win32_Service -Filter "Name='Schedule'" -OperationTimeoutSec $OperationTimeout -ErrorAction Stop
                [pscustomobject]@{ found = ($null -ne $service); running = ($null -ne $service -and $service.State -eq 'Running') }
            }
            finally {
                if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
            }
        }
        $serviceDenied = Test-SasAuthorizationDeniedText -Text $serviceProbe.error_text
        $serviceOutput = @($serviceProbe.output | Select-Object -First 1)
        $scheduleService = [pscustomobject]@{
            queried = (-not $serviceProbe.timed_out)
            running = ($serviceProbe.succeeded -and $serviceOutput.Count -eq 1 -and [bool]$serviceOutput[0].running)
            authorization_denied = $serviceDenied
        }

        if ($null -eq $Credential) {
            $taskProcess = Invoke-SasBoundedProcess -FilePath 'schtasks.exe' -Arguments ("/Query /S {0} /FO CSV /NH" -f $ComputerName) -TimeoutSeconds $TimeoutSeconds
            $taskErrorText = $taskProcess.error + ' ' + $taskProcess.output
            $scheduledTaskQuery = [pscustomobject]@{
                queried = (-not $taskProcess.timed_out)
                succeeded = (-not $taskProcess.timed_out -and $taskProcess.exit_code -eq 0)
                authorization_denied = (Test-SasAuthorizationDeniedText -Text $taskErrorText)
            }
        }
        else {
            # The CIM read avoids exposing a SecureString as a native-process command-line argument.
            $taskProbe = Invoke-SasBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential; OperationTimeout = $TimeoutSeconds } -ScriptBlock {
                param($ComputerName, $SuppliedCredential, $OperationTimeout)
                $session = $null
                try {
                    $option = New-CimSessionOption -Protocol Dcom
                    $parameters = @{ ComputerName = $ComputerName; SessionOption = $option; Credential = $SuppliedCredential; ErrorAction = 'Stop' }
                    $session = New-CimSession @parameters
                    Get-CimInstance -CimSession $session -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName MSFT_ScheduledTask -OperationTimeoutSec $OperationTimeout -ErrorAction Stop | Select-Object -First 1 | Out-Null
                    $true
                }
                finally {
                    if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
                }
            }
            $taskDenied = Test-SasAuthorizationDeniedText -Text $taskProbe.error_text
            $scheduledTaskQuery = [pscustomobject]@{
                queried = (-not $taskProbe.timed_out)
                succeeded = $taskProbe.succeeded
                authorization_denied = $taskDenied
            }
        }
    }

    [pscustomobject]@{
        dns = $dns
        identity = [pscustomobject]@{ domain_joined = $domainJoined; tgt_present = $tgtPresent; ticket_bytes_emitted = $false }
        service_tickets = [pscustomobject]$tickets
        tcp = [pscustomobject]$tcp
        winrm_session = $winrm
        admin_share = $adminShare
        schedule_service = $scheduleService
        scheduled_task_query = $scheduledTaskQuery
    }
}

Export-ModuleMember -Function Test-SasFqdn, Test-SasTransportObservationContradiction, New-SasSoftwareDeploymentTransportResult, Invoke-SasSoftwareDeploymentTransportObservation
