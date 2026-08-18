#Requires -Version 5.1
<#
.SYNOPSIS
    Bounded proof lane for a mapped Northwell shared printer queue.

.DESCRIPTION
    Diagnoses one explicit \\server\queue connection without remapping by printer IP.
    The script validates the shared-queue contract, records local queue state, proves
    bounded TCP 445 and 135 reachability, performs one bounded remote print-queue
    query while observing RPC TCP connections, and can optionally issue one bounded
    Windows test page. Runtime evidence is written beneath LOCALAPPDATA.

    This is a proof/diagnostic lane. It never installs a Standard TCP/IP printer and
    never uses PrinterIp as a mapping target. PrinterIp, when supplied, is diagnostics
    only and is probed only on TCP 9100.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Printer,

    [string]$PrinterIp,

    [ValidateRange(2, 30)]
    [int]$TimeoutSeconds = 10,

    [switch]$PrintTestPage,

    [switch]$NonInteractive,

    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Northwell printer queue proof must run from Windows.'
}

function Test-SasIpLiteral {
    param([Parameter(Mandatory)][string]$Value)
    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Value, [ref]$parsed)
}

function Test-SasTcpBounded {
    param(
        [Parameter(Mandatory)][string]$Computer,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$TimeoutMs
    )

    $client = New-Object System.Net.Sockets.TcpClient
    $result = [ordered]@{
        computer = $Computer
        port = $Port
        status = 'ERROR'
        error = $null
    }

    try {
        $async = $client.BeginConnect($Computer, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $result.status = 'TIMEOUT'
            return [pscustomobject]$result
        }
        $client.EndConnect($async)
        $result.status = if ($client.Connected) { 'OPEN' } else { 'FAILED' }
    }
    catch {
        $result.status = 'FAILED'
        $result.error = $_.Exception.Message
    }
    finally {
        $client.Close()
    }

    return [pscustomobject]$result
}

function ConvertTo-SasDnsARecordRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$Record
    )

    process {
        if ($null -eq $Record) { return }

        # Resolve-DnsName can emit heterogeneous records even for an A query
        # (for example a CNAME followed by an A record). Under StrictMode,
        # touching a missing .IPAddress property throws and aborts the whole
        # proof lane. Inspect the property bag before reading optional fields.
        $ipProperty = $Record.PSObject.Properties['IPAddress']
        if ($null -eq $ipProperty) { return }

        $ipText = [string]$ipProperty.Value
        if ([string]::IsNullOrWhiteSpace($ipText)) { return }

        $parsedIp = $null
        if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$parsedIp)) { return }
        if ($parsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return }

        $nameProperty = $Record.PSObject.Properties['Name']
        $recordName = if ($null -ne $nameProperty) { [string]$nameProperty.Value } else { '' }

        [pscustomobject]([ordered]@{
            name = $recordName
            ip_address = $parsedIp.ToString()
        })
    }
}

function ConvertTo-SasPowerShellLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Start-SasChildPowerShell {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][string]$WorkRoot,
        [Parameter(Mandatory)][string]$Label
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $safeLabel = $Label -replace '[^A-Za-z0-9_.-]', '_'
    $stdoutPath = Join-Path $WorkRoot ($safeLabel + '.stdout.txt')
    $stderrPath = Join-Path $WorkRoot ($safeLabel + '.stderr.txt')
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) {
        throw "Windows PowerShell child engine not found: $psExe"
    }

    $process = Start-Process -FilePath $psExe `
        -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru

    return [pscustomobject]@{
        process = $process
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
    }
}

function Complete-SasBoundedChildPowerShell {
    param(
        [Parameter(Mandatory)]$Child,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $process = $Child.process
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        try { $process.Kill() } catch {}
        try { [void]$process.WaitForExit(2000) } catch {}
    }

    $stdout = if (Test-Path -LiteralPath $Child.stdout_path) {
        Get-Content -LiteralPath $Child.stdout_path -Raw -ErrorAction SilentlyContinue
    } else { '' }
    $stderr = if (Test-Path -LiteralPath $Child.stderr_path) {
        Get-Content -LiteralPath $Child.stderr_path -Raw -ErrorAction SilentlyContinue
    } else { '' }

    return [pscustomobject]@{
        timed_out = (-not $completed)
        exit_code = if ($completed) { [int]$process.ExitCode } else { $null }
        stdout = [string]$stdout
        stderr = [string]$stderr
    }
}

$unc = $Printer.Trim()
if ($unc -notmatch '^\\\\(?<server>[^\\\s]+)\\(?<queue>[^\\]+)$') {
    throw 'Printer must be one shared queue in UNC form: \\server\queue. Direct IP, IPP, HTTP, and local-port inputs are not accepted.'
}

$server = [string]$Matches.server
$queue = ([string]$Matches.queue).Trim()
if ([string]::IsNullOrWhiteSpace($queue)) {
    throw 'Printer queue name cannot be blank.'
}
if (Test-SasIpLiteral -Value $server) {
    throw 'Printer server must be a queue server hostname, not an IP address.'
}
if ($unc -match '^(?i)(https?|ipp)://') {
    throw 'Printer must be a Windows shared queue, not an HTTP/IPP URL.'
}

if (-not [string]::IsNullOrWhiteSpace($PrinterIp)) {
    if (-not (Test-SasIpLiteral -Value $PrinterIp.Trim())) {
        throw 'PrinterIp is optional diagnostic evidence only and, when supplied, must be an IP literal.'
    }
    $PrinterIp = $PrinterIp.Trim()
}

$base = if (-not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot
}
elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Join-Path $env:LOCALAPPDATA 'SysAdminSuite\field-runs\printer-queue-proof'
}
else {
    Join-Path ([System.IO.Path]::GetTempPath()) 'SysAdminSuite\field-runs\printer-queue-proof'
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path $base $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultPath = Join-Path $runRoot 'printer-queue-proof-result.json'

$result = [ordered]@{
    schema_version = 'sas-northwell-printer-queue-proof/v1'
    status = 'IN_PROGRESS'
    classification = 'UNCLASSIFIED'
    printer = $unc
    print_server = $server
    queue = $queue
    printer_ip_diagnostic_only = $PrinterIp
    mapping_policy = 'SHARED_QUEUE_ONLY'
    direct_ip_mapping_performed = $false
    timeout_seconds = $TimeoutSeconds
    spooler = $null
    dns = @()
    tcp = @()
    local_queue = $null
    cim_queue = $null
    smb_session = @()
    remote_query = $null
    observed_rpc_connections = @()
    printer_ip_probe_9100 = $null
    test_page = $null
    physical_output_observed = $null
    proof_level = 'DIAGNOSTIC_ONLY'
    diagnostic_warnings = @()
    evidence_path = $resultPath
    error = $null
    completed_utc = $null
}

try {
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    $result.spooler = [ordered]@{
        status = [string]$spooler.Status
        running = ($spooler.Status -eq 'Running')
    }

    $dnsRecords = @(Resolve-DnsName -Name $server -Type A -QuickTimeout -ErrorAction Stop)
    $dnsRows = @($dnsRecords | ConvertTo-SasDnsARecordRows)
    $result.dns = $dnsRows
    if ($dnsRows.Count -eq 0) {
        throw "Print server '$server' did not resolve to an IPv4 address."
    }
    $serverIp = [string]$dnsRows[0].ip_address

    $timeoutMs = $TimeoutSeconds * 1000
    $tcp445 = Test-SasTcpBounded -Computer $server -Port 445 -TimeoutMs $timeoutMs
    $tcp135 = Test-SasTcpBounded -Computer $server -Port 135 -TimeoutMs $timeoutMs
    $result.tcp = @($tcp445, $tcp135)

    if (-not [string]::IsNullOrWhiteSpace($PrinterIp)) {
        $result.printer_ip_probe_9100 = Test-SasTcpBounded -Computer $PrinterIp -Port 9100 -TimeoutMs $timeoutMs
    }

    try {
        $local = Get-Printer -Name $unc -Full -ErrorAction Stop
        $result.local_queue = [ordered]@{
            found = $true
            name = [string]$local.Name
            computer_name = [string]$local.ComputerName
            type = [string]$local.Type
            driver_name = [string]$local.DriverName
            port_name = [string]$local.PortName
            printer_status = [string]$local.PrinterStatus
        }
    }
    catch {
        $result.local_queue = [ordered]@{
            found = $false
            error = $_.Exception.Message
        }
    }

    try {
        $cim = Get-CimInstance Win32_Printer -ErrorAction Stop |
            Where-Object { $_.Name -eq $unc } |
            Select-Object -First 1
        if ($cim) {
            $result.cim_queue = [ordered]@{
                found = $true
                network = [bool]$cim.Network
                server_name = [string]$cim.ServerName
                share_name = [string]$cim.ShareName
                driver_name = [string]$cim.DriverName
                port_name = [string]$cim.PortName
                printer_status = [int]$cim.PrinterStatus
                work_offline = [bool]$cim.WorkOffline
            }
        }
        else {
            $result.cim_queue = [ordered]@{ found = $false }
        }
    }
    catch {
        $result.cim_queue = [ordered]@{ found = $false; error = $_.Exception.Message }
    }

    try {
        $result.smb_session = @(
            Get-SmbConnection -ErrorAction Stop |
                Where-Object { $_.ServerName -ieq $server } |
                ForEach-Object {
                    [ordered]@{
                        server_name = [string]$_.ServerName
                        share_name = [string]$_.ShareName
                        dialect = [string]$_.Dialect
                        num_opens = [int]$_.NumOpens
                    }
                }
        )
    }
    catch {
        $result.smb_session = @()
    }

    $observed = New-Object System.Collections.Generic.List[object]
    $serverLiteral = ConvertTo-SasPowerShellLiteral -Value $server
    $queueLiteral = ConvertTo-SasPowerShellLiteral -Value $queue
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module PrintManagement -ErrorAction Stop
`$p = Get-Printer -ComputerName $serverLiteral -Name $queueLiteral -Full -ErrorAction Stop
[pscustomobject]@{
    name = [string]`$p.Name
    computer_name = [string]`$p.ComputerName
    driver_name = [string]`$p.DriverName
    port_name = [string]`$p.PortName
    printer_status = [string]`$p.PrinterStatus
    shared = [bool]`$p.Shared
    published = [bool]`$p.Published
} | ConvertTo-Json -Compress
"@

    $remoteChild = Start-SasChildPowerShell -ScriptText $remoteScript -WorkRoot $runRoot -Label 'remote-print-query'
    $remoteDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $remoteDeadline -and -not $remoteChild.process.HasExited) {
        try {
            Get-NetTCPConnection -RemoteAddress $serverIp -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $observed.Add([pscustomobject]@{
                        local_address = [string]$_.LocalAddress
                        local_port = [int]$_.LocalPort
                        remote_address = [string]$_.RemoteAddress
                        remote_port = [int]$_.RemotePort
                        state = [string]$_.State
                        owning_process = [int]$_.OwningProcess
                    })
                }
        }
        catch {}
        Start-Sleep -Milliseconds 250
    }

    $remainingMs = [Math]::Max(0, [int](($remoteDeadline - (Get-Date)).TotalMilliseconds))
    $remoteCompleted = if ($remoteChild.process.HasExited) { $true } else { $remoteChild.process.WaitForExit($remainingMs) }
    if (-not $remoteCompleted) {
        try { $remoteChild.process.Kill() } catch {}
        try { [void]$remoteChild.process.WaitForExit(2000) } catch {}
    }
    $remoteStdout = if (Test-Path -LiteralPath $remoteChild.stdout_path) { Get-Content -LiteralPath $remoteChild.stdout_path -Raw -ErrorAction SilentlyContinue } else { '' }
    $remoteStderr = if (Test-Path -LiteralPath $remoteChild.stderr_path) { Get-Content -LiteralPath $remoteChild.stderr_path -Raw -ErrorAction SilentlyContinue } else { '' }

    if (-not $remoteCompleted) {
        $result.remote_query = [ordered]@{
            status = 'TIMEOUT'
            error = "Remote Get-Printer exceeded the bounded $TimeoutSeconds-second process lifetime."
        }
    }
    elseif ($remoteChild.process.ExitCode -eq 0) {
        $remoteValue = $null
        try { $remoteValue = $remoteStdout | ConvertFrom-Json -ErrorAction Stop } catch {}
        $result.remote_query = [ordered]@{
            status = 'PASS'
            queue = $remoteValue
            error = $null
        }
    }
    else {
        $result.remote_query = [ordered]@{
            status = 'FAILED'
            error = ([string]$remoteStderr).Trim()
        }
    }

    $result.observed_rpc_connections = @(
        $observed |
            Sort-Object remote_port,state,local_address,local_port -Unique
    )

    if ($PrintTestPage) {
        $uncLiteral = ConvertTo-SasPowerShellLiteral -Value $unc
        $testScript = @"
`$ErrorActionPreference = 'Stop'
`$p = Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { `$_.Name -eq $uncLiteral } | Select-Object -First 1
if (-not `$p) { throw 'Mapped printer object not found.' }
`$r = Invoke-CimMethod -InputObject `$p -MethodName PrintTestPage -ErrorAction Stop
[pscustomobject]@{ return_value = [int]`$r.ReturnValue } | ConvertTo-Json -Compress
"@
        $testChild = Start-SasChildPowerShell -ScriptText $testScript -WorkRoot $runRoot -Label 'print-test-page'
        $testResult = Complete-SasBoundedChildPowerShell -Child $testChild -TimeoutSeconds $TimeoutSeconds

        if ($testResult.timed_out) {
            $result.test_page = [ordered]@{
                status = 'TIMEOUT'
                return_value = $null
                error = "PrintTestPage exceeded the bounded $TimeoutSeconds-second process lifetime."
            }
        }
        elseif ($testResult.exit_code -eq 0) {
            $testValue = $null
            try { $testValue = $testResult.stdout | ConvertFrom-Json -ErrorAction Stop } catch {}
            $returnValue = if ($testValue) { [int]$testValue.return_value } else { $null }
            $result.test_page = [ordered]@{
                status = if ($returnValue -eq 0) { 'ACCEPTED' } else { 'FAILED' }
                return_value = $returnValue
                error = $null
            }
        }
        else {
            $result.test_page = [ordered]@{
                status = 'FAILED'
                return_value = $null
                error = ([string]$testResult.stderr).Trim()
            }
        }

        if (-not $NonInteractive) {
            $answer = Read-Host 'Did a physical test page emerge from the requested printer? [Y/N]'
            $result.physical_output_observed = ($answer -match '^(?i)y(es)?$')
        }
    }

    $tcp445Open = ($tcp445.status -eq 'OPEN')
    $tcp135Open = ($tcp135.status -eq 'OPEN')
    $queueFound = ($result.local_queue -and $result.local_queue.found)
    $rpcSynSent = @($result.observed_rpc_connections | Where-Object {
        $_.remote_port -ne 135 -and $_.state -eq 'SynSent'
    }).Count -gt 0
    $rpcDynamicEstablished = @($result.observed_rpc_connections | Where-Object {
        $_.remote_port -ne 135 -and $_.state -eq 'Established'
    }).Count -gt 0
    $rpcDynamicStalled = $rpcSynSent -and -not $rpcDynamicEstablished

    # Physical output from the explicitly requested test page is the strongest
    # end-to-end proof available to this lane. Diagnostic calls may time out even
    # after the spooler successfully submits and the device prints. Preserve those
    # anomalies as warnings, but never let them downgrade observed physical output.
    if ($PrintTestPage -and $result.physical_output_observed -eq $true) {
        $warnings = New-Object System.Collections.Generic.List[string]
        if ($result.remote_query.status -eq 'TIMEOUT') {
            [void]$warnings.Add('REMOTE_QUERY_TIMEOUT_DESPITE_PHYSICAL_PRINT')
        }
        if ($result.test_page -and $result.test_page.status -eq 'TIMEOUT') {
            [void]$warnings.Add('TEST_PAGE_CALL_TIMEOUT_DESPITE_PHYSICAL_PRINT')
        }
        if ($rpcSynSent -and $rpcDynamicEstablished) {
            [void]$warnings.Add('TRANSIENT_RPC_SYN_SENT_WITH_ESTABLISHED_DYNAMIC_RPC')
        }
        elseif ($rpcDynamicStalled) {
            [void]$warnings.Add('RPC_DYNAMIC_PORT_STALL_OBSERVED_DESPITE_PHYSICAL_PRINT')
        }
        if ($result.test_page -and $result.test_page.return_value -eq 1722) {
            [void]$warnings.Add('PRINT_TEST_RPC_1722_DESPITE_PHYSICAL_PRINT')
        }

        $result.diagnostic_warnings = @($warnings)
        $result.classification = 'LIVE_PHYSICAL_PRINT_PROOF_PASS'
        $result.status = 'PASS'
        $result.proof_level = 'LIVE_PHYSICAL_OUTPUT_OPERATOR_OBSERVED'
    }
    elseif (-not $result.spooler.running) {
        $result.classification = 'LOCAL_SPOOLER_NOT_RUNNING'
        $result.status = 'FAIL'
    }
    elseif (-not $queueFound) {
        $result.classification = 'SHARED_QUEUE_NOT_MAPPED_LOCALLY'
        $result.status = 'FAIL'
    }
    elseif (-not $tcp445Open) {
        $result.classification = 'PRINT_SERVER_SMB_UNREACHABLE'
        $result.status = 'FAIL'
    }
    elseif (-not $tcp135Open) {
        $result.classification = 'RPC_ENDPOINT_MAPPER_UNREACHABLE'
        $result.status = 'FAIL'
    }
    elseif ($result.remote_query.status -eq 'TIMEOUT' -and $rpcDynamicStalled) {
        $result.classification = 'PRINT_RPC_DYNAMIC_PORT_STALLED'
        $result.status = 'FAIL'
    }
    elseif ($result.remote_query.status -eq 'TIMEOUT') {
        $result.classification = 'REMOTE_PRINT_QUERY_TIMEOUT'
        $result.status = 'FAIL'
    }
    elseif ($PrintTestPage -and $result.test_page -and $result.test_page.return_value -eq 1722) {
        $result.classification = 'PRINT_TEST_RPC_SERVER_UNAVAILABLE_1722'
        $result.status = 'FAIL'
    }
    elseif ($PrintTestPage -and $result.test_page -and $result.test_page.status -eq 'ACCEPTED') {
        $result.classification = 'TEST_PAGE_ACCEPTED_PHYSICAL_OUTPUT_UNPROVEN'
        $result.status = 'PARTIAL'
        $result.proof_level = 'PRINT_REQUEST_ACCEPTED_ONLY'
    }
    elseif ($result.remote_query.status -eq 'PASS') {
        $result.classification = 'QUEUE_TRANSPORT_AND_REMOTE_QUERY_PASS'
        $result.status = 'PASS'
        $result.proof_level = 'REMOTE_QUEUE_QUERY_PASS_PHYSICAL_OUTPUT_UNPROVEN'
    }
    else {
        $result.classification = 'QUEUE_DIAGNOSTIC_INCONCLUSIVE'
        $result.status = 'PARTIAL'
    }
}
catch {
    $result.status = 'FAIL'
    if ($result.classification -eq 'UNCLASSIFIED') {
        $result.classification = 'PROOF_LANE_ERROR'
    }
    $result.error = $_.Exception.Message
}
finally {
    $result.completed_utc = [DateTime]::UtcNow.ToString('o')
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}

Write-Host ''
Write-Host '=== NORTHWELL PRINTER QUEUE PROOF ===' -ForegroundColor Cyan
Write-Host ("Status:         {0}" -f $result.status)
Write-Host ("Classification: {0}" -f $result.classification)
Write-Host ("Proof level:    {0}" -f $result.proof_level)
if ($result.diagnostic_warnings.Count -gt 0) {
    Write-Host ("Warnings:       {0}" -f ($result.diagnostic_warnings -join ', '))
}
Write-Host ("Evidence:       {0}" -f $resultPath)
Write-Host 'Direct-IP mapping performed: NO'
Write-Host ''

[pscustomobject]$result

if ($result.status -eq 'FAIL') { exit 1 }
exit 0
