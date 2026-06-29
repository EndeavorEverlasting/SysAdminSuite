#Requires -Version 5.1
<#
.SYNOPSIS
Stages probe-ready network preflight targets from Alejandro's approved Cybernet serial list.

.DESCRIPTION
This planner does not ping, scan, query AD, or mutate targets. It turns a serial list into a reduced
network-preflight handoff only when approved local evidence bridges a serial to a probe-ready hostname
or IP address.

The common field path is:
- Alejandro serial list under targets/local/ or logs/targets/
- approved evidence exports under targets/local/, logs/targets/, survey/output/, logs/nmap/, or survey/artifacts/
- generated to_probe_targets.txt under survey/input/serial_preflight/<run_id>/
- sas-network-preflight.ps1 consumes that generated target file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SerialFile,

    [Parameter(Mandatory = $false)]
    [string[]]$EvidenceFile = @(),

    [Parameter(Mandatory = $false)]
    [int[]]$Ports = @(135, 445, 3389, 9100),

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$AllowNonstandardInput,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFixtures
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule)) {
    throw "Missing shared target intake module: $targetIntakeModule"
}
Import-Module $targetIntakeModule -Force

function Get-RowValue {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return ([string]$prop.Value).Trim()
        }
    }
    return ''
}

function ConvertTo-NormalizedSerial {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.Trim()).ToUpperInvariant() -replace '[^A-Z0-9]', '')
}

function Test-IsIpAddress {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $ip = $null
    return [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$ip)
}

function Test-ProbeReadyTargetValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $v = $Value.Trim()
    if (Test-IsIpAddress -Value $v) { return $true }
    if ($v -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
    if ($v -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
    if ($v -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }
    return $false
}

function Get-ExplicitTargetType {
    param($Row)
    return Get-RowValue -Row $Row -Names @('IdentifierType', 'TargetType', 'Type', 'ValueType')
}

function Test-ExplicitHostType {
    param($Row)
    $typeValue = Get-ExplicitTargetType -Row $Row
    if ([string]::IsNullOrWhiteSpace($typeValue)) { return $false }
    return $typeValue -match '^(HostName|Hostname|Host|ComputerName|DnsName|DNSName|FQDN|IPv4|IPv6|IPAddress|IP)$'
}

function Test-ExplicitNonHostType {
    param($Row)
    $typeValue = Get-ExplicitTargetType -Row $Row
    if ([string]::IsNullOrWhiteSpace($typeValue)) { return $false }
    return -not (Test-ExplicitHostType -Row $Row)
}

function Get-SerialFromRow {
    param($Row)
    return Get-RowValue -Row $Row -Names @(
        'Serial',
        'SerialNumber',
        'AlejandroSerial',
        'Alejandro Serial',
        'DeviceSerial',
        'Device Serial',
        'TargetSerial',
        'Target Serial',
        'ComputerSerial',
        'Computer Serial',
        'AssetSerial',
        'Asset Serial',
        'SN'
    )
}

function Get-ProbeTargetFromRow {
    param($Row)

    $host = Get-RowValue -Row $Row -Names @('HostName', 'Hostname', 'ComputerName', 'DeviceName', 'Name', 'DnsName', 'DNSName', 'FQDN', 'IPAddress', 'IP', 'IPv4')
    if (-not [string]::IsNullOrWhiteSpace($host) -and (Test-ProbeReadyTargetValue -Value $host)) {
        return $host
    }

    $target = Get-RowValue -Row $Row -Names @('Target')
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        if (Test-ExplicitNonHostType -Row $Row) { return '' }
        if (Test-ProbeReadyTargetValue -Value $target) { return $target }
    }

    $identifier = Get-RowValue -Row $Row -Names @('Identifier')
    if (-not [string]::IsNullOrWhiteSpace($identifier) -and (Test-ExplicitHostType -Row $Row)) {
        if (Test-ProbeReadyTargetValue -Value $identifier) { return $identifier }
    }

    return ''
}

function Get-EvidencePathFromRow {
    param($Row)
    $value = Get-RowValue -Row $Row -Names @('EvidencePath', 'EvidenceClass', 'EvidenceSource', 'Source', 'StrongestEvidencePath')
    if ([string]::IsNullOrWhiteSpace($value)) { return 'approved_local_evidence' }
    return $value
}

function Read-SerialFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $records = New-Object System.Collections.Generic.List[object]
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $rowNumber = 0

    if ($extension -eq '.txt') {
        foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
            $trimmed = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed.StartsWith('#')) { continue }
            $rowNumber++
            $records.Add([pscustomobject]@{
                InputRowId = $rowNumber
                Serial = $trimmed
                NormalizedSerial = ConvertTo-NormalizedSerial -Value $trimmed
                SourceFile = $Path
            })
        }
        return $records
    }

    if ($extension -ne '.csv') {
        throw "Unsupported serial file extension '$extension'. Use .csv or .txt."
    }

    foreach ($row in @(Import-Csv -LiteralPath $Path)) {
        $rowNumber++
        $serial = Get-SerialFromRow -Row $row
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $values = @($row.PSObject.Properties | ForEach-Object { [string]$_.Value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($values.Count -eq 1) { $serial = $values[0] }
        }
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }
        $records.Add([pscustomobject]@{
            InputRowId = $rowNumber
            Serial = $serial.Trim()
            NormalizedSerial = ConvertTo-NormalizedSerial -Value $serial
            SourceFile = $Path
        })
    }

    return $records
}

function Read-EvidenceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -ne '.csv') {
        throw "Unsupported evidence file extension '$extension'. Use .csv evidence exports."
    }

    $records = New-Object System.Collections.Generic.List[object]
    $rowNumber = 0
    foreach ($row in @(Import-Csv -LiteralPath $Path)) {
        $rowNumber++
        $serial = Get-SerialFromRow -Row $row
        $target = Get-ProbeTargetFromRow -Row $row
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }
        $records.Add([pscustomobject]@{
            EvidenceRowId = $rowNumber
            Serial = $serial.Trim()
            NormalizedSerial = ConvertTo-NormalizedSerial -Value $serial
            ProbeTarget = $target
            EvidencePath = Get-EvidencePathFromRow -Row $row
            EvidenceSourceFile = $Path
        })
    }
    return $records
}

function New-SafeRunId {
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        $safe = ($RunId.ToLowerInvariant() -replace '[^a-z0-9_-]', '-')
        if (-not [string]::IsNullOrWhiteSpace($safe)) { return $safe }
    }
    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$repoRoot = Get-SasRepoRoot -StartPath $PSScriptRoot
$roots = Get-SasTargetIntakeRoots -RepoRoot $repoRoot

Assert-SasApprovedInputPath -Path $SerialFile -RepoRoot $repoRoot -Role 'Alejandro serial list' -AllowStaging -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
foreach ($evidence in $EvidenceFile) {
    Assert-SasApprovedInputPath -Path $evidence -RepoRoot $repoRoot -Role 'serial-to-target evidence file' -AllowStaging -AllowGenerated -AllowFixtures:$AllowFixtures -AllowNonstandard:$AllowNonstandardInput
}

$serialFilePath = (Resolve-Path -LiteralPath $SerialFile).Path
$evidenceFilePaths = @($EvidenceFile | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })

$resolvedRunId = New-SafeRunId
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Join-Path $roots.OutputRoots[0] 'serial_preflight') $resolvedRunId
}
if ([string]::IsNullOrWhiteSpace($StagingDirectory)) {
    $StagingDirectory = Join-Path (Join-Path $roots.StagingRoot 'serial_preflight') $resolvedRunId
}

Assert-SasApprovedOutputPath -Path $OutputDirectory -RepoRoot $repoRoot -Role 'serial preflight output directory' -AllowNonstandard:$AllowNonstandardInput
if (-not (Test-SasPathUnderRoot -Path $StagingDirectory -Root $roots.StagingRoot)) {
    if (-not $AllowNonstandardInput) {
        throw "serial preflight staging directory must be under survey/input. Refusing: $StagingDirectory"
    }
    Write-Warning "NONSTANDARD OUTPUT OVERRIDE: serial preflight staging directory is outside survey/input: $StagingDirectory"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $StagingDirectory | Out-Null

$serialRows = @(Read-SerialFile -Path $serialFilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_.NormalizedSerial) })
if ($serialRows.Count -eq 0) {
    throw 'No serials were found in the provided Alejandro serial list.'
}

$evidenceRows = New-Object System.Collections.Generic.List[object]
if ([System.IO.Path]::GetExtension($serialFilePath).ToLowerInvariant() -eq '.csv') {
    foreach ($row in @(Read-EvidenceFile -Path $serialFilePath)) { $evidenceRows.Add($row) }
}
foreach ($path in $evidenceFilePaths) {
    foreach ($row in @(Read-EvidenceFile -Path $path)) { $evidenceRows.Add($row) }
}

$plan = New-Object System.Collections.Generic.List[object]
$review = New-Object System.Collections.Generic.List[object]
$targets = New-Object System.Collections.Generic.List[string]
$seenTargets = @{}

foreach ($serial in $serialRows) {
    $matches = @($evidenceRows | Where-Object { $_.NormalizedSerial -eq $serial.NormalizedSerial })
    $probeMatches = @($matches | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ProbeTarget) -and (Test-ProbeReadyTargetValue -Value $_.ProbeTarget) })
    $selected = $probeMatches | Select-Object -First 1
    $candidateTargets = @($probeMatches | ForEach-Object { $_.ProbeTarget } | Sort-Object -Unique)

    if ($null -ne $selected) {
        $decision = 'STAGE_FOR_NETWORK_PREFLIGHT'
        $reason = 'serial has approved local evidence that bridges to a probe-ready hostname/IP'
        $probeTarget = [string]$selected.ProbeTarget
        $evidencePath = [string]$selected.EvidencePath
        $evidenceSource = [string]$selected.EvidenceSourceFile
        $key = $probeTarget.ToLowerInvariant()
        if (-not $seenTargets.ContainsKey($key)) {
            $seenTargets[$key] = $true
            $targets.Add($probeTarget)
        }
    } else {
        $decision = 'REVIEW_REQUIRED_NO_PROBE_READY_EVIDENCE'
        $reason = 'serial was present but no approved hostname/IP bridge was found; do not ping the serial string'
        $probeTarget = ''
        $evidencePath = if ($matches.Count -gt 0) { 'evidence_without_probe_ready_target' } else { 'serial_only_population' }
        $evidenceSource = if ($matches.Count -gt 0) { (($matches | ForEach-Object { $_.EvidenceSourceFile } | Sort-Object -Unique) -join ';') } else { '' }
    }

    $planRow = [pscustomobject]@{
        InputRowId = $serial.InputRowId
        Serial = $serial.Serial
        NormalizedSerial = $serial.NormalizedSerial
        ProbeTarget = $probeTarget
        CandidateTargets = ($candidateTargets -join ';')
        EvidencePath = $evidencePath
        EvidenceSourceFile = $evidenceSource
        Decision = $decision
        DecisionReason = $reason
        NetworkActivityPerformed = $false
    }
    $plan.Add($planRow)
    if ($decision -like 'REVIEW_REQUIRED*') { $review.Add($planRow) }
}

$planPath = Join-Path $OutputDirectory 'serial_preflight_plan.csv'
$reviewPath = Join-Path $OutputDirectory 'review_required.csv'
$summaryPath = Join-Path $OutputDirectory 'serial_preflight_summary.json'
$handoffPath = Join-Path $OutputDirectory 'operator_handoff.txt'
$targetPath = Join-Path $StagingDirectory 'to_probe_targets.txt'

$plan | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
$review | Export-Csv -LiteralPath $reviewPath -NoTypeInformation -Encoding UTF8
$targets | Set-Content -LiteralPath $targetPath -Encoding UTF8

$nextCommand = ".\survey\sas-network-preflight.ps1 -TargetFile `"$targetPath`" -Ports $($Ports -join ',')"
$summary = [pscustomobject]@{
    run_id = $resolvedRunId
    generated_at = (Get-Date).ToString('o')
    serial_file = $serialFilePath
    evidence_files = $evidenceFilePaths
    input_serial_count = $serialRows.Count
    staged_probe_target_count = $targets.Count
    review_required_count = $review.Count
    plan_path = $planPath
    review_required_path = $reviewPath
    to_probe_targets_path = $targetPath
    operator_handoff_path = $handoffPath
    next_network_preflight_command = $nextCommand
    network_activity_performed = $false
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

@(
    'SysAdminSuite serial preflight plan',
    "RunId: $resolvedRunId",
    "Alejandro serial list: $serialFilePath",
    "Evidence files: $($evidenceFilePaths -join '; ')",
    "Serials read: $($serialRows.Count)",
    "Probe-ready targets staged: $($targets.Count)",
    "Review-required serials: $($review.Count)",
    "Plan: $planPath",
    "Review: $reviewPath",
    "Staged target file: $targetPath",
    '',
    'Run in Windows PowerShell:',
    $nextCommand,
    '',
    'Planner network activity performed: false',
    'Do not ping serial strings. Ping only the generated hostname/IP target file.'
) | Set-Content -LiteralPath $handoffPath -Encoding UTF8

Write-Host "Serial preflight plan complete: $resolvedRunId"
Write-Host "Serials read: $($serialRows.Count)"
Write-Host "Probe-ready targets staged: $($targets.Count)"
Write-Host "Review-required serials: $($review.Count)"
Write-Host "Staged target file: $targetPath"
Write-Host ''
Write-Host 'Run in Windows PowerShell:'
Write-Host $nextCommand
