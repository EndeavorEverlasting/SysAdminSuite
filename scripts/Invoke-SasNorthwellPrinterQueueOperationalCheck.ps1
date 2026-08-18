#Requires -Version 5.1
<#
.SYNOPSIS
    Non-printing operational check for a mapped Northwell shared printer queue.

.DESCRIPTION
    Runs the bounded queue diagnostic engine without requesting a test page, then
    reconciles its transport/status telemetry with durable prior physical-print
    evidence for the same queue. Raw diagnostic evidence is preserved unchanged.

    The operator-facing result is written to stable latest.json/latest.txt aliases
    under LOCALAPPDATA so terminal closure never destroys the useful evidence.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Printer,

    [string]$PrinterIp,

    [ValidateRange(2, 30)]
    [int]$TimeoutSeconds = 10,

    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Northwell printer operational check must run from Windows.'
}

function ConvertTo-SasPowerShellLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-SasPriorPhysicalProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Printer,
        [string]$ExcludePath
    )

    $candidates = @(
        Get-ChildItem -LiteralPath $Base -Filter 'printer-queue-proof-result.json' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { [string]::IsNullOrWhiteSpace($ExcludePath) -or $_.FullName -ne $ExcludePath } |
            Sort-Object LastWriteTimeUtc -Descending
    )

    foreach ($candidate in $candidates) {
        try {
            $value = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $printerProperty = $value.PSObject.Properties['printer']
            $physicalProperty = $value.PSObject.Properties['physical_output_observed']
            if ($null -eq $printerProperty -or $null -eq $physicalProperty) { continue }
            if ([string]$printerProperty.Value -ne $Printer) { continue }
            if ($physicalProperty.Value -ne $true) { continue }

            $completed = $null
            $completedProperty = $value.PSObject.Properties['completed_utc']
            if ($null -ne $completedProperty) { $completed = [string]$completedProperty.Value }

            return [pscustomobject]([ordered]@{
                found = $true
                evidence_path = $candidate.FullName
                completed_utc = $completed
                source_status = if ($value.PSObject.Properties['status']) { [string]$value.status } else { $null }
                source_classification = if ($value.PSObject.Properties['classification']) { [string]$value.classification } else { $null }
                physical_output_observed = $true
            })
        }
        catch {
            continue
        }
    }

    return [pscustomobject]([ordered]@{
        found = $false
        evidence_path = $null
        completed_utc = $null
        source_status = $null
        source_classification = $null
        physical_output_observed = $false
    })
}

function Get-SasOperationalOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Raw,
        [Parameter(Mandatory)]$PriorPhysicalProof
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    $tcp445Open = @($Raw.tcp | Where-Object { $_.port -eq 445 -and $_.status -eq 'OPEN' }).Count -gt 0
    $tcp135Open = @($Raw.tcp | Where-Object { $_.port -eq 135 -and $_.status -eq 'OPEN' }).Count -gt 0
    $spoolerRunning = ($Raw.spooler -and $Raw.spooler.running -eq $true)
    $queueFound = ($Raw.local_queue -and $Raw.local_queue.found -eq $true)
    $queueNormal = ($queueFound -and [string]$Raw.local_queue.printer_status -eq 'Normal')
    $cimOnline = ($Raw.cim_queue -and $Raw.cim_queue.found -eq $true -and $Raw.cim_queue.work_offline -eq $false)
    $deviceReachable = ($null -eq $Raw.printer_ip_probe_9100 -or [string]$Raw.printer_ip_probe_9100.status -eq 'OPEN')

    $remoteStatus = if ($Raw.remote_query) { [string]$Raw.remote_query.status } else { 'NOT_AVAILABLE' }
    $rpcDynamicEstablished = @($Raw.observed_rpc_connections | Where-Object {
        $_.remote_port -ne 135 -and [string]$_.state -eq 'Established'
    }).Count -gt 0
    $rpcDynamicSynSent = @($Raw.observed_rpc_connections | Where-Object {
        $_.remote_port -ne 135 -and [string]$_.state -eq 'SynSent'
    }).Count -gt 0

    if ($remoteStatus -eq 'TIMEOUT') {
        [void]$warnings.Add('REMOTE_STATUS_QUERY_TIMEOUT')
    }
    elseif ($remoteStatus -eq 'FAILED') {
        [void]$warnings.Add('REMOTE_STATUS_QUERY_FAILED')
    }
    if ($rpcDynamicSynSent -and $rpcDynamicEstablished) {
        [void]$warnings.Add('TRANSIENT_RPC_SYN_SENT_WITH_ESTABLISHED_DYNAMIC_RPC')
    }
    elseif ($rpcDynamicSynSent) {
        [void]$warnings.Add('REMOTE_STATUS_RPC_PENDING_WITHOUT_ESTABLISHED_SAMPLE')
    }
    if ($queueNormal -and $cimOnline -and $remoteStatus -ne 'PASS') {
        [void]$warnings.Add('REMOTE_STATUS_TELEMETRY_DISAGREES_WITH_LOCAL_QUEUE')
    }

    if (-not $spoolerRunning) {
        return [pscustomobject]@{ status='FAIL'; classification='LOCAL_SPOOLER_NOT_RUNNING'; proof_level='CURRENT_LOCAL_FAILURE'; warnings=@($warnings) }
    }
    if (-not $queueFound) {
        return [pscustomobject]@{ status='FAIL'; classification='SHARED_QUEUE_NOT_MAPPED_LOCALLY'; proof_level='CURRENT_LOCAL_FAILURE'; warnings=@($warnings) }
    }
    if (-not $tcp445Open) {
        return [pscustomobject]@{ status='FAIL'; classification='PRINT_SERVER_SMB_UNREACHABLE'; proof_level='CURRENT_TRANSPORT_FAILURE'; warnings=@($warnings) }
    }
    if (-not $deviceReachable) {
        return [pscustomobject]@{ status='FAIL'; classification='PRINTER_DEVICE_9100_UNREACHABLE'; proof_level='CURRENT_DEVICE_TRANSPORT_FAILURE'; warnings=@($warnings) }
    }

    $coreHealthy = $spoolerRunning -and $queueFound -and $queueNormal -and $cimOnline -and $tcp445Open

    if ($coreHealthy -and $PriorPhysicalProof.found -eq $true) {
        if (-not $tcp135Open) { [void]$warnings.Add('RPC_ENDPOINT_MAPPER_UNREACHABLE_BUT_PRIOR_PHYSICAL_PRINT_PROVED') }
        return [pscustomobject]@{
            status = 'PASS'
            classification = 'QUEUE_OPERATIONAL_PHYSICAL_PROOF_PRESERVED'
            proof_level = 'CURRENT_QUEUE_HEALTH_PLUS_PRIOR_PHYSICAL_OUTPUT'
            warnings = @($warnings)
        }
    }

    if ($coreHealthy -and ($remoteStatus -eq 'PASS' -or $rpcDynamicEstablished)) {
        if (-not $tcp135Open) { [void]$warnings.Add('RPC_ENDPOINT_MAPPER_UNREACHABLE') }
        return [pscustomobject]@{
            status = 'PASS'
            classification = if ($remoteStatus -eq 'PASS') { 'QUEUE_OPERATIONAL_REMOTE_STATUS_PASS' } else { 'QUEUE_OPERATIONAL_STATUS_TELEMETRY_DEGRADED' }
            proof_level = 'CURRENT_LOCAL_QUEUE_AND_TRANSPORT_HEALTH'
            warnings = @($warnings)
        }
    }

    if ($coreHealthy) {
        if (-not $tcp135Open) { [void]$warnings.Add('RPC_ENDPOINT_MAPPER_UNREACHABLE') }
        return [pscustomobject]@{
            status = 'PARTIAL'
            classification = 'QUEUE_CORE_HEALTHY_REMOTE_STATUS_UNPROVEN'
            proof_level = 'CURRENT_LOCAL_QUEUE_HEALTH_ONLY'
            warnings = @($warnings)
        }
    }

    return [pscustomobject]@{
        status = 'PARTIAL'
        classification = 'QUEUE_OPERATIONAL_CHECK_INCONCLUSIVE'
        proof_level = 'DIAGNOSTIC_ONLY'
        warnings = @($warnings)
    }
}

$unc = $Printer.Trim()
if ($unc -notmatch '^\\\\(?<server>[^\\\s]+)\\(?<queue>[^\\]+)$') {
    throw 'Printer must be one shared queue in UNC form: \\server\queue.'
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

New-Item -ItemType Directory -Path $base -Force | Out-Null
$runRoot = Join-Path $base ('operational-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$diagnosticEngine = Join-Path $PSScriptRoot 'Invoke-SasNorthwellPrinterQueueProof.ps1'
if (-not (Test-Path -LiteralPath $diagnosticEngine)) {
    throw "Missing bounded diagnostic engine: $diagnosticEngine"
}

$stdoutPath = Join-Path $runRoot 'diagnostic.stdout.txt'
$stderrPath = Join-Path $runRoot 'diagnostic.stderr.txt'
$startedUtc = [DateTime]::UtcNow
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = "& " + (ConvertTo-SasPowerShellLiteral $diagnosticEngine) +
    " -Printer " + (ConvertTo-SasPowerShellLiteral $unc) +
    " -TimeoutSeconds $TimeoutSeconds -NonInteractive -OutputRoot " + (ConvertTo-SasPowerShellLiteral $base)
if (-not [string]::IsNullOrWhiteSpace($PrinterIp)) {
    $command += " -PrinterIp " + (ConvertTo-SasPowerShellLiteral $PrinterIp.Trim())
}
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

$process = Start-Process -FilePath $psExe `
    -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -PassThru

$processTimeoutSeconds = ($TimeoutSeconds * 5) + 20
$completed = $process.WaitForExit($processTimeoutSeconds * 1000)
if (-not $completed) {
    try { $process.Kill() } catch {}
    try { [void]$process.WaitForExit(2000) } catch {}
}

$rawArtifact = Get-ChildItem -LiteralPath $base -Filter 'printer-queue-proof-result.json' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTimeUtc -ge $startedUtc.AddSeconds(-2) } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

$resultPath = Join-Path $runRoot 'printer-queue-operational-result.json'
$summaryPath = Join-Path $runRoot 'printer-queue-operational-summary.txt'
$latestJson = Join-Path $base 'latest.json'
$latestText = Join-Path $base 'latest.txt'
$latestPointer = Join-Path $base 'LATEST-PATH.txt'
$latestStdout = Join-Path $base 'latest-diagnostic.stdout.txt'
$latestStderr = Join-Path $base 'latest-diagnostic.stderr.txt'

if (-not $rawArtifact) {
    $result = [ordered]@{
        schema_version = 'sas-northwell-printer-queue-operational/v1'
        status = 'FAIL'
        classification = if ($completed) { 'DIAGNOSTIC_ENGINE_NO_RESULT' } else { 'DIAGNOSTIC_ENGINE_PROCESS_TIMEOUT' }
        proof_level = 'NO_RESULT_ARTIFACT'
        printer = $unc
        printer_ip_diagnostic_only = $PrinterIp
        no_test_page_requested = $true
        direct_ip_mapping_performed = $false
        source_result_path = $null
        prior_physical_proof = $null
        diagnostic_warnings = @()
        diagnostic_stdout = $stdoutPath
        diagnostic_stderr = $stderrPath
        evidence_path = $resultPath
        completed_utc = [DateTime]::UtcNow.ToString('o')
    }
}
else {
    $raw = Get-Content -LiteralPath $rawArtifact.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    $priorPhysical = Get-SasPriorPhysicalProof -Base $base -Printer $unc -ExcludePath $rawArtifact.FullName
    $outcome = Get-SasOperationalOutcome -Raw $raw -PriorPhysicalProof $priorPhysical

    $result = [ordered]@{
        schema_version = 'sas-northwell-printer-queue-operational/v1'
        status = [string]$outcome.status
        classification = [string]$outcome.classification
        proof_level = [string]$outcome.proof_level
        printer = $unc
        printer_ip_diagnostic_only = $PrinterIp
        no_test_page_requested = $true
        direct_ip_mapping_performed = $false
        source_status = [string]$raw.status
        source_classification = [string]$raw.classification
        source_result_path = $rawArtifact.FullName
        prior_physical_proof = $priorPhysical
        diagnostic_warnings = @($outcome.warnings)
        current = [ordered]@{
            spooler = $raw.spooler
            dns = $raw.dns
            tcp = $raw.tcp
            local_queue = $raw.local_queue
            cim_queue = $raw.cim_queue
            remote_query = $raw.remote_query
            observed_rpc_connections = $raw.observed_rpc_connections
            printer_ip_probe_9100 = $raw.printer_ip_probe_9100
        }
        diagnostic_stdout = $stdoutPath
        diagnostic_stderr = $stderrPath
        evidence_path = $resultPath
        completed_utc = [DateTime]::UtcNow.ToString('o')
    }
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Copy-Item -LiteralPath $resultPath -Destination $latestJson -Force
if (Test-Path -LiteralPath $stdoutPath) { Copy-Item -LiteralPath $stdoutPath -Destination $latestStdout -Force }
if (Test-Path -LiteralPath $stderrPath) { Copy-Item -LiteralPath $stderrPath -Destination $latestStderr -Force }

$summary = @(
    'SysAdminSuite Northwell Printer Queue Operational Check'
    ('Status: ' + $result.status)
    ('Classification: ' + $result.classification)
    ('Proof level: ' + $result.proof_level)
    ('Printer: ' + $unc)
    'Test page requested by this run: NO'
    ('Warnings: ' + ((@($result.diagnostic_warnings) -join ', ')))
    ('Result JSON: ' + $resultPath)
    ('Raw diagnostic stdout: ' + $stdoutPath)
    ('Raw diagnostic stderr: ' + $stderrPath)
    ('Stable latest JSON: ' + $latestJson)
    ('Stable latest summary: ' + $latestText)
)
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | Set-Content -LiteralPath $latestText -Encoding UTF8
@(
    ('Run directory: ' + $runRoot)
    ('Summary: ' + $summaryPath)
    ('Result: ' + $resultPath)
    ('Raw diagnostic result: ' + $(if ($rawArtifact) { $rawArtifact.FullName } else { '<none>' }))
) | Set-Content -LiteralPath $latestPointer -Encoding UTF8

Write-Host ''
Write-Host '=== NORTHWELL PRINTER OPERATIONAL CHECK ===' -ForegroundColor Cyan
$summary | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host 'Evidence is durable. Closing this terminal does not lose the result.' -ForegroundColor Green
Write-Host ''

[pscustomobject]$result

if ($result.status -eq 'FAIL') { exit 1 }
exit 0
