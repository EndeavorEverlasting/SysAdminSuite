#Requires -Version 5.1
<#
.SYNOPSIS
Intent-scoped, read-only software deployment transport observation.
.DESCRIPTION
Collects only the network observations required by the requested deployment
transport. Kerberos SMB plus Task Scheduler is the default deployment intent.
Broad transport discovery remains an explicit caller choice in the front door.
No function in this module creates a task, writes to the target, enables a
service, changes firewall policy, or prompts for credentials.
#>

Set-StrictMode -Version 2.0

function New-SasLowNoiseTicketObservation {
    param([bool]$Requested = $false, [bool]$Issued = $false)
    [pscustomobject]@{
        requested = $Requested
        issued = $Issued
        ticket_bytes_emitted = $false
    }
}

function New-SasLowNoiseTcpObservation {
    param([bool]$Tested = $false, [bool]$Reachable = $false, [bool]$TimedOut = $false)
    [pscustomobject]@{
        tested = $Tested
        reachable = $Reachable
        timed_out = $TimedOut
    }
}

function New-SasLowNoiseAuthorizationObservation {
    param([bool]$Attempted = $false, [bool]$Authorized = $false, [bool]$AuthorizationDenied = $false)
    [pscustomobject]@{
        attempted = $Attempted
        authorized = $Authorized
        authorization_denied = $AuthorizationDenied
    }
}

function Invoke-SasLowNoiseBoundedProcess {
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

function Invoke-SasLowNoiseBoundedPowerShell {
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

function Resolve-SasLowNoiseDns {
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

function Test-SasLowNoiseTcpPort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutSeconds)
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $null
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            return New-SasLowNoiseTcpObservation -Tested $true -TimedOut $true
        }
        $client.EndConnect($async)
        return New-SasLowNoiseTcpObservation -Tested $true -Reachable $true
    }
    catch {
        return New-SasLowNoiseTcpObservation -Tested $true
    }
    finally {
        if ($null -ne $async -and $null -ne $async.AsyncWaitHandle) { $async.AsyncWaitHandle.Close() }
        $client.Close()
    }
}

function Test-SasLowNoiseAuthorizationDeniedText {
    param([string]$Text)
    return ([string]$Text -match '(?i)access\s+is\s+denied|unauthori[sz]ed|logon\s+failure|authentication\s+failed|0x80070005')
}

function Test-SasLowNoiseTaskNotFoundText {
    param([string]$Text)
    return ([string]$Text -match '(?i)cannot\s+find|does\s+not\s+exist|not\s+exist|system\s+cannot\s+find\s+the\s+file')
}

function Get-SasLowNoiseSourceIdentity {
    $domainJoined = $false
    try {
        $domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
    }
    catch {
        try { $domainJoined = [bool](Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
    }
    return $domainJoined
}

function Invoke-SasSoftwareDeploymentLowNoiseObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][ValidateSet('kerberos_smb_task', 'winrm')][string]$TransportIntent,
        [Parameter(Mandatory = $false)][System.Management.Automation.PSCredential]$Credential,
        [ValidateRange(1, 30)][int]$TimeoutSeconds = 5
    )

    $domainJoined = Get-SasLowNoiseSourceIdentity
    $tgtCheck = Invoke-SasLowNoiseBoundedProcess -FilePath 'klist.exe' -Arguments '' -TimeoutSeconds $TimeoutSeconds
    $tgtPresent = (-not $tgtCheck.timed_out -and $tgtCheck.exit_code -eq 0 -and $tgtCheck.output -match '(?i)krbtgt/')
    $dns = Resolve-SasLowNoiseDns -ComputerName $ComputerName -TimeoutSeconds $TimeoutSeconds

    $tickets = [ordered]@{
        http = New-SasLowNoiseTicketObservation
        host = New-SasLowNoiseTicketObservation
        cifs = New-SasLowNoiseTicketObservation
    }
    $tcp = [ordered]@{
        port_5985 = New-SasLowNoiseTcpObservation
        port_5986 = New-SasLowNoiseTcpObservation
        port_445 = New-SasLowNoiseTcpObservation
        port_135 = New-SasLowNoiseTcpObservation
    }
    $winrm = New-SasLowNoiseAuthorizationObservation
    $adminShare = New-SasLowNoiseAuthorizationObservation
    $scheduleService = [pscustomobject]@{ queried = $false; running = $false; authorization_denied = $false }
    $scheduledTaskQuery = [pscustomobject]@{ queried = $false; succeeded = $false; authorization_denied = $false }

    $identityReady = ($dns.resolved -and -not $dns.timed_out -and $domainJoined -and $tgtPresent)

    if ($TransportIntent -eq 'winrm') {
        if ($identityReady) {
            $ticketResult = Invoke-SasLowNoiseBoundedProcess -FilePath 'klist.exe' -Arguments ("get HTTP/{0}" -f $ComputerName) -TimeoutSeconds $TimeoutSeconds
            $tickets.http = New-SasLowNoiseTicketObservation -Requested $true -Issued (-not $ticketResult.timed_out -and $ticketResult.exit_code -eq 0)
        }
        if ($tickets.http.issued) {
            $tcp.port_5985 = Test-SasLowNoiseTcpPort -ComputerName $ComputerName -Port 5985 -TimeoutSeconds $TimeoutSeconds
            if (-not $tcp.port_5985.reachable -and -not $tcp.port_5985.timed_out) {
                $tcp.port_5986 = Test-SasLowNoiseTcpPort -ComputerName $ComputerName -Port 5986 -TimeoutSeconds $TimeoutSeconds
            }
        }
        if ($tcp.port_5985.reachable -or $tcp.port_5986.reachable) {
            $winrmParameters = @{
                ComputerName = $ComputerName
                UseSsl = (-not $tcp.port_5985.reachable -and $tcp.port_5986.reachable)
                TimeoutMilliseconds = ($TimeoutSeconds * 1000)
                SuppliedCredential = $Credential
            }
            $winrmProbe = Invoke-SasLowNoiseBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters $winrmParameters -ScriptBlock {
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
            $winrm = New-SasLowNoiseAuthorizationObservation -Attempted $true -Authorized $winrmProbe.succeeded -AuthorizationDenied (Test-SasLowNoiseAuthorizationDeniedText -Text $winrmProbe.error_text)
        }
    }
    else {
        if ($identityReady) {
            $ticketResult = Invoke-SasLowNoiseBoundedProcess -FilePath 'klist.exe' -Arguments ("get CIFS/{0}" -f $ComputerName) -TimeoutSeconds $TimeoutSeconds
            $tickets.cifs = New-SasLowNoiseTicketObservation -Requested $true -Issued (-not $ticketResult.timed_out -and $ticketResult.exit_code -eq 0)
        }
        if ($tickets.cifs.issued) {
            $tcp.port_445 = Test-SasLowNoiseTcpPort -ComputerName $ComputerName -Port 445 -TimeoutSeconds $TimeoutSeconds
        }
        if ($tcp.port_445.reachable) {
            $shareProbe = Invoke-SasLowNoiseBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential } -ScriptBlock {
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
            $adminShare = New-SasLowNoiseAuthorizationObservation -Attempted $true -Authorized $shareProbe.succeeded -AuthorizationDenied (Test-SasLowNoiseAuthorizationDeniedText -Text $shareProbe.error_text)
        }
        if ($adminShare.authorized) {
            $tcp.port_135 = Test-SasLowNoiseTcpPort -ComputerName $ComputerName -Port 135 -TimeoutSeconds $TimeoutSeconds
        }
        if ($tcp.port_135.reachable) {
            $serviceProbe = Invoke-SasLowNoiseBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential; OperationTimeout = $TimeoutSeconds } -ScriptBlock {
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
            $serviceDenied = Test-SasLowNoiseAuthorizationDeniedText -Text $serviceProbe.error_text
            $serviceOutput = @($serviceProbe.output | Select-Object -First 1)
            $scheduleService = [pscustomobject]@{
                queried = (-not $serviceProbe.timed_out)
                running = ($serviceProbe.succeeded -and $serviceOutput.Count -eq 1 -and [bool]$serviceOutput[0].running)
                authorization_denied = $serviceDenied
            }

            $probeTaskName = '\SysAdminSuite_TransportPreflight_Probe'
            if ($null -eq $Credential) {
                $taskProcess = Invoke-SasLowNoiseBoundedProcess -FilePath 'schtasks.exe' -Arguments ("/Query /S {0} /TN {1} /FO LIST" -f $ComputerName, $probeTaskName) -TimeoutSeconds $TimeoutSeconds
                $taskText = $taskProcess.error + ' ' + $taskProcess.output
                $taskDenied = Test-SasLowNoiseAuthorizationDeniedText -Text $taskText
                $scheduledTaskQuery = [pscustomobject]@{
                    queried = (-not $taskProcess.timed_out)
                    succeeded = (-not $taskProcess.timed_out -and -not $taskDenied -and ($taskProcess.exit_code -eq 0 -or (Test-SasLowNoiseTaskNotFoundText -Text $taskText)))
                    authorization_denied = $taskDenied
                }
            }
            else {
                $taskProbe = Invoke-SasLowNoiseBoundedPowerShell -TimeoutSeconds $TimeoutSeconds -Parameters @{ ComputerName = $ComputerName; SuppliedCredential = $Credential; OperationTimeout = $TimeoutSeconds; ProbeTaskName = 'SysAdminSuite_TransportPreflight_Probe' } -ScriptBlock {
                    param($ComputerName, $SuppliedCredential, $OperationTimeout, $ProbeTaskName)
                    $session = $null
                    try {
                        $option = New-CimSessionOption -Protocol Dcom
                        $parameters = @{ ComputerName = $ComputerName; SessionOption = $option; Credential = $SuppliedCredential; ErrorAction = 'Stop' }
                        $session = New-CimSession @parameters
                        Get-CimInstance -CimSession $session -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName MSFT_ScheduledTask -Filter ("TaskName='{0}'" -f $ProbeTaskName) -OperationTimeoutSec $OperationTimeout -ErrorAction Stop | Out-Null
                        $true
                    }
                    finally {
                        if ($null -ne $session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
                    }
                }
                $taskDenied = Test-SasLowNoiseAuthorizationDeniedText -Text $taskProbe.error_text
                $scheduledTaskQuery = [pscustomobject]@{
                    queried = (-not $taskProbe.timed_out)
                    succeeded = ($taskProbe.succeeded -and -not $taskDenied)
                    authorization_denied = $taskDenied
                }
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

Export-ModuleMember -Function Invoke-SasSoftwareDeploymentLowNoiseObservation
