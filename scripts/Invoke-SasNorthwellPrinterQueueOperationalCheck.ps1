#Requires -Version 5.1
<#
.SYNOPSIS
    Non-printing operational check for a mapped Northwell shared printer queue.

.DESCRIPTION
    Runs the bounded queue diagnostic engine without requesting a test page when
    the requested target is the local workstation. For a different target PC, it
    does not misclassify the controller workstation's local queue state as target
    state. Instead it reconciles the requested target and queue against preserved
    canonical SYSTEM + HKLM mapping evidence from the latest complete mapping run.

    When ComputerName is omitted, the engine tries to recover one unambiguous
    target for the requested queue from the canonical mapping LATEST-PATH evidence.
    If target context cannot be recovered safely, the check fails closed instead of
    silently substituting the controller workstation.

    Durable prior physical-print evidence remains available for local operational
    checks. Raw diagnostic evidence is preserved unchanged when diagnostics run.

    The operator-facing result is written to stable latest.json/latest.txt aliases
    under LOCALAPPDATA so terminal closure never destroys the useful evidence.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Printer,

    [string]$ComputerName,

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

$repoRoot = Split-Path -Parent $PSScriptRoot

function ConvertTo-SasPowerShellLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-SasComputerKey {
    param([Parameter(Mandatory)][string]$Value)
    $trimmed = $Value.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return '' }
    return ($trimmed -split '\.')[0].ToLowerInvariant()
}

function Get-SasLatestMappingEvidenceRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [ValidateRange(1, 40)][int]$RetryCount = 8,
        [ValidateRange(0, 2000)][int]$RetryDelayMilliseconds = 250
    )

    $mappingLogs = Join-Path $RepoRoot 'mapping\Logs'
    $latestPointer = Join-Path $mappingLogs 'LATEST-PATH.txt'
    $mappingLogsFull = [System.IO.Path]::GetFullPath($mappingLogs).TrimEnd([char[]]'\') + '\'

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            if (Test-Path -LiteralPath $latestPointer -PathType Leaf) {
                $rawRoot = [string](Get-Content -LiteralPath $latestPointer -Raw -ErrorAction Stop)
                if (-not [string]::IsNullOrWhiteSpace($rawRoot)) {
                    $candidateRoot = [System.IO.Path]::GetFullPath($rawRoot.Trim())
                    if ($candidateRoot.StartsWith($mappingLogsFull, [System.StringComparison]::OrdinalIgnoreCase) -and
                        (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
                        $summaryPath = Join-Path $candidateRoot 'Summary.json'
                        if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
                            $summary = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                            $completedProperty = $summary.PSObject.Properties['CompletedTargets']
                            $totalProperty = $summary.PSObject.Properties['TotalTargets']
                            if ($null -ne $completedProperty -and $null -ne $totalProperty) {
                                $completedTargets = [int]$completedProperty.Value
                                $totalTargets = [int]$totalProperty.Value
                                if ($totalTargets -gt 0 -and $completedTargets -eq $totalTargets) {
                                    return $candidateRoot
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            # A producer may still be publishing pointer/summary bytes. Retry boundedly.
        }

        if ($attempt -lt $RetryCount -and $RetryDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $RetryDelayMilliseconds
        }
    }

    return $null
}

function Get-SasLatestMappedTargetForPrinter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Printer
    )

    $evidenceRoot = Get-SasLatestMappingEvidenceRoot -RepoRoot $RepoRoot
    if ([string]::IsNullOrWhiteSpace($evidenceRoot)) { return $null }

    $printerKey = $Printer.Trim().ToLowerInvariant()
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(Get-ChildItem -LiteralPath $evidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction SilentlyContinue)) {
        try {
            $status = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $computerProperty = $status.PSObject.Properties['ComputerName']
            $requestedProperty = $status.PSObject.Properties['Requested']
            if ($null -eq $computerProperty -or $null -eq $requestedProperty) { continue }

            $requested = @($requestedProperty.Value | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            if ($requested -notcontains $printerKey) { continue }

            $candidateComputer = [string]$computerProperty.Value
            if ([string]::IsNullOrWhiteSpace($candidateComputer)) { continue }
            $targets.Add($candidateComputer.Trim())
        }
        catch {
            continue
        }
    }

    $uniqueTargets = @($targets.ToArray() | Sort-Object -Unique)
    if ($uniqueTargets.Count -ne 1) { return $null }
    return [string]$uniqueTargets[0]
}

function Get-SasRemoteMachineWideProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$Printer
    )

    $targetKey = ConvertTo-SasComputerKey -Value $ComputerName
    $printerKey = $Printer.Trim().ToLowerInvariant()
    $evidenceRoot = Get-SasLatestMappingEvidenceRoot -RepoRoot $RepoRoot

    if ([string]::IsNullOrWhiteSpace($targetKey) -or [string]::IsNullOrWhiteSpace($evidenceRoot)) {
        return [pscustomobject]([ordered]@{
            found = $false
            proven = $false
            evidence_root = $evidenceRoot
            evidence_path = $null
            completed_utc = $null
            identity = $null
            requested = @()
            machine_wide_unc = @()
            missing = @()
        })
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $evidenceRoot -Filter 'Status.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )

    foreach ($candidate in $candidates) {
        try {
            $status = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

            $computerProperty = $status.PSObject.Properties['ComputerName']
            if ($null -eq $computerProperty) { continue }
            if ((ConvertTo-SasComputerKey -Value ([string]$computerProperty.Value)) -ne $targetKey) { continue }

            $requestedProperty = $status.PSObject.Properties['Requested']
            $requested = @()
            if ($null -ne $requestedProperty) {
                $requested = @($requestedProperty.Value | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            }
            if ($requested -notcontains $printerKey) { continue }

            $verifiedProperty = $status.PSObject.Properties['MachineWideUNC']
            $verified = @()
            if ($null -ne $verifiedProperty) {
                $verified = @($verifiedProperty.Value | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            }

            $missingProperty = $status.PSObject.Properties['Missing']
            $missing = @()
            if ($null -ne $missingProperty) {
                $missing = @($missingProperty.Value)
            }

            $successProperty = $status.PSObject.Properties['Success']
            $success = ($null -ne $successProperty -and [bool]$successProperty.Value)

            $identityProperty = $status.PSObject.Properties['Identity']
            $identity = if ($null -ne $identityProperty) { [string]$identityProperty.Value } else { '' }

            $finishedProperty = $status.PSObject.Properties['Finished']
            $finished = if ($null -ne $finishedProperty) { [string]$finishedProperty.Value } else { $null }

            $proven = $success -and $identity -match 'SYSTEM$' -and @($missing).Count -eq 0 -and $verified -contains $printerKey

            return [pscustomobject]([ordered]@{
                found = $true
                proven = $proven
                evidence_root = $evidenceRoot
                evidence_path = $candidate.FullName
                completed_utc = $finished
                identity = $identity
                requested = $requested
                machine_wide_unc = $verified
                missing = $missing
            })
        }
        catch {
            continue
        }
    }

    return [pscustomobject]([ordered]@{
        found = $false
        proven = $false
        evidence_root = $evidenceRoot
        evidence_path = $null
        completed_utc = $null
        identity = $null
        requested = @()
        machine_wide_unc = @()
        missing = @()
    })
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

$targetResolution = 'EXPLICIT'
$targetComputer = if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName.Trim()
}
else {
    $recoveredTarget = Get-SasLatestMappedTargetForPrinter -RepoRoot $repoRoot -Printer $unc
    if (-not [string]::IsNullOrWhiteSpace($recoveredTarget)) {
        $targetResolution = 'LATEST_MAPPING_EVIDENCE'
        $recoveredTarget
    }
    else {
        $targetResolution = 'UNRESOLVED'
        $null
    }
}

$targetContextResolved = -not [string]::IsNullOrWhiteSpace([string]$targetComputer)
$targetKey = if ($targetContextResolved) { ConvertTo-SasComputerKey -Value ([string]$targetComputer) } else { '' }
$localKey = ConvertTo-SasComputerKey -Value $env:COMPUTERNAME
$remoteTarget = ($targetContextResolved -and $targetKey -ne $localKey)

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

$resultPath = Join-Path $runRoot 'printer-queue-operational-result.json'
$summaryPath = Join-Path $runRoot 'printer-queue-operational-summary.txt'
$latestJson = Join-Path $base 'latest.json'
$latestText = Join-Path $base 'latest.txt'
$latestPointer = Join-Path $base 'LATEST-PATH.txt'
$latestStdout = Join-Path $base 'latest-diagnostic.stdout.txt'
$latestStderr = Join-Path $base 'latest-diagnostic.stderr.txt'
$stdoutPath = Join-Path $runRoot 'diagnostic.stdout.txt'
$stderrPath = Join-Path $runRoot 'diagnostic.stderr.txt'
$diagnosticOutputRoot = Join-Path $runRoot 'diagnostic'
$rawArtifact = $null
$completed = $true
$localDiagnosticRan = $false

if (-not $targetContextResolved) {
    $result = [ordered]@{
        schema_version = 'sas-northwell-printer-queue-operational/v1'
        status = 'FAIL'
        classification = 'TARGET_CONTEXT_UNRESOLVED'
        proof_level = 'NO_TARGET_CONTEXT'
        printer = $unc
        target_computer = $null
        target_resolution = $targetResolution
        evaluation_mode = 'TARGET_CONTEXT_REQUIRED'
        printer_ip_diagnostic_only = $PrinterIp
        no_test_page_requested = $true
        direct_ip_mapping_performed = $false
        source_status = $null
        source_classification = $null
        source_result_path = $null
        source_mapping_evidence = $null
        prior_physical_proof = $null
        diagnostic_warnings = @('TARGET_CONTEXT_NOT_PROVEN')
        current = $null
        diagnostic_stdout = $null
        diagnostic_stderr = $null
        evidence_path = $resultPath
        completed_utc = [DateTime]::UtcNow.ToString('o')
    }
}
elseif ($remoteTarget) {
    $remoteProof = Get-SasRemoteMachineWideProof -RepoRoot $repoRoot -ComputerName ([string]$targetComputer) -Printer $unc
    if ($remoteProof.proven -eq $true) {
        $result = [ordered]@{
            schema_version = 'sas-northwell-printer-queue-operational/v1'
            status = 'PASS'
            classification = 'REMOTE_TARGET_MACHINE_WIDE_REGISTRATION_PROVEN'
            proof_level = 'MACHINE_WIDE_REGISTRATION'
            printer = $unc
            target_computer = $targetComputer
            target_resolution = $targetResolution
            evaluation_mode = 'REMOTE_MAPPING_EVIDENCE'
            printer_ip_diagnostic_only = $PrinterIp
            no_test_page_requested = $true
            direct_ip_mapping_performed = $false
            source_status = 'PASS'
            source_classification = 'HKLM_MACHINE_WIDE_QUEUE_PROOF'
            source_result_path = $remoteProof.evidence_path
            source_mapping_evidence = $remoteProof
            prior_physical_proof = $null
            diagnostic_warnings = @('REMOTE_TARGET_RUNTIME_QUEUE_STATE_NOT_OBSERVED')
            current = $null
            diagnostic_stdout = $null
            diagnostic_stderr = $null
            evidence_path = $resultPath
            completed_utc = [DateTime]::UtcNow.ToString('o')
        }
    }
    elseif ($remoteProof.found -eq $true) {
        $result = [ordered]@{
            schema_version = 'sas-northwell-printer-queue-operational/v1'
            status = 'FAIL'
            classification = 'REMOTE_TARGET_MACHINE_WIDE_REGISTRATION_NOT_PROVEN'
            proof_level = 'MACHINE_WIDE_REGISTRATION_FAILED'
            printer = $unc
            target_computer = $targetComputer
            target_resolution = $targetResolution
            evaluation_mode = 'REMOTE_MAPPING_EVIDENCE'
            printer_ip_diagnostic_only = $PrinterIp
            no_test_page_requested = $true
            direct_ip_mapping_performed = $false
            source_status = 'FAIL'
            source_classification = 'HKLM_MACHINE_WIDE_QUEUE_PROOF_MISMATCH'
            source_result_path = $remoteProof.evidence_path
            source_mapping_evidence = $remoteProof
            prior_physical_proof = $null
            diagnostic_warnings = @('REMOTE_TARGET_MAPPING_EVIDENCE_DID_NOT_PROVE_REQUESTED_QUEUE')
            current = $null
            diagnostic_stdout = $null
            diagnostic_stderr = $null
            evidence_path = $resultPath
            completed_utc = [DateTime]::UtcNow.ToString('o')
        }
    }
    else {
        $result = [ordered]@{
            schema_version = 'sas-northwell-printer-queue-operational/v1'
            status = 'FAIL'
            classification = 'REMOTE_TARGET_MACHINE_WIDE_EVIDENCE_NOT_FOUND'
            proof_level = 'NO_MATCHING_MAPPING_EVIDENCE'
            printer = $unc
            target_computer = $targetComputer
            target_resolution = $targetResolution
            evaluation_mode = 'REMOTE_MAPPING_EVIDENCE'
            printer_ip_diagnostic_only = $PrinterIp
            no_test_page_requested = $true
            direct_ip_mapping_performed = $false
            source_status = $null
            source_classification = $null
            source_result_path = $null
            source_mapping_evidence = $remoteProof
            prior_physical_proof = $null
            diagnostic_warnings = @('NO_MATCHING_REMOTE_MAPPING_EVIDENCE')
            current = $null
            diagnostic_stdout = $null
            diagnostic_stderr = $null
            evidence_path = $resultPath
            completed_utc = [DateTime]::UtcNow.ToString('o')
        }
    }
}
else {
    $localDiagnosticRan = $true
    $diagnosticEngine = Join-Path $PSScriptRoot 'Invoke-SasNorthwellPrinterQueueProof.ps1'
    if (-not (Test-Path -LiteralPath $diagnosticEngine)) {
        throw "Missing bounded diagnostic engine: $diagnosticEngine"
    }

    New-Item -ItemType Directory -Path $diagnosticOutputRoot -Force | Out-Null
    $startedUtc = [DateTime]::UtcNow
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $command = "& " + (ConvertTo-SasPowerShellLiteral $diagnosticEngine) +
        " -Printer " + (ConvertTo-SasPowerShellLiteral $unc) +
        " -TimeoutSeconds $TimeoutSeconds -NonInteractive -OutputRoot " + (ConvertTo-SasPowerShellLiteral $diagnosticOutputRoot)
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

    $rawArtifact = Get-ChildItem -LiteralPath $diagnosticOutputRoot -Filter 'printer-queue-proof-result.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -ge $startedUtc.AddSeconds(-2) } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $rawArtifact) {
        $result = [ordered]@{
            schema_version = 'sas-northwell-printer-queue-operational/v1'
            status = 'FAIL'
            classification = if ($completed) { 'DIAGNOSTIC_ENGINE_NO_RESULT' } else { 'DIAGNOSTIC_ENGINE_PROCESS_TIMEOUT' }
            proof_level = 'NO_RESULT_ARTIFACT'
            printer = $unc
            target_computer = $targetComputer
            target_resolution = $targetResolution
            evaluation_mode = 'LOCAL_OPERATIONAL_DIAGNOSTIC'
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
        if ([string]$raw.printer -ne $unc) {
            throw "Isolated diagnostic artifact printer mismatch. Expected '$unc'; observed '$([string]$raw.printer)'."
        }
        $priorPhysical = Get-SasPriorPhysicalProof -Base $base -Printer $unc -ExcludePath $rawArtifact.FullName
        $outcome = Get-SasOperationalOutcome -Raw $raw -PriorPhysicalProof $priorPhysical

        $result = [ordered]@{
            schema_version = 'sas-northwell-printer-queue-operational/v1'
            status = [string]$outcome.status
            classification = [string]$outcome.classification
            proof_level = [string]$outcome.proof_level
            printer = $unc
            target_computer = $targetComputer
            target_resolution = $targetResolution
            evaluation_mode = 'LOCAL_OPERATIONAL_DIAGNOSTIC'
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
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Copy-Item -LiteralPath $resultPath -Destination $latestJson -Force
if ($localDiagnosticRan -and (Test-Path -LiteralPath $stdoutPath)) { Copy-Item -LiteralPath $stdoutPath -Destination $latestStdout -Force }
if ($localDiagnosticRan -and (Test-Path -LiteralPath $stderrPath)) { Copy-Item -LiteralPath $stderrPath -Destination $latestStderr -Force }

$summary = @(
    'SysAdminSuite Northwell Printer Queue Operational Check'
    ('Status: ' + $result.status)
    ('Classification: ' + $result.classification)
    ('Proof level: ' + $result.proof_level)
    ('Target computer: ' + $(if ($targetContextResolved) { [string]$targetComputer } else { '<unresolved>' }))
    ('Target resolution: ' + $targetResolution)
    ('Evaluation mode: ' + $result.evaluation_mode)
    ('Printer: ' + $unc)
    'Test page requested by this run: NO'
    ('Warnings: ' + ((@($result.diagnostic_warnings) -join ', ')))
    ('Result JSON: ' + $resultPath)
    ('Raw diagnostic stdout: ' + $(if ($localDiagnosticRan) { $stdoutPath } else { '<not run for remote/unresolved target>' }))
    ('Raw diagnostic stderr: ' + $(if ($localDiagnosticRan) { $stderrPath } else { '<not run for remote/unresolved target>' }))
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
    ('Mapping proof source: ' + $(if ($remoteTarget -and $result.source_result_path) { [string]$result.source_result_path } else { '<none>' }))
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
