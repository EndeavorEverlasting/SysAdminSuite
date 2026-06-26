<#
.SYNOPSIS
PowerShell-first SysAdminSuite field network preflight.

.DESCRIPTION
Runs read-only DNS, ping, and selected TCP port checks against an explicit approved target file.
Live target intake is read from centralized SysAdminSuite target roots:
- targets/local
- logs/targets

survey/input is accepted only as normalized runtime staging. Generated output is written under
survey/output/network_preflight by default.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetFile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [int[]]$Ports = @(135, 445, 3389, 9100),

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$AllowNonstandardInput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoGuess = Split-Path -Parent $PSScriptRoot
$targetIntakeModule = Join-Path $repoGuess 'scripts/SasTargetIntake.psm1'
if (-not (Test-Path -LiteralPath $targetIntakeModule)) {
    throw "Missing shared target intake module: $targetIntakeModule"
}
Import-Module $targetIntakeModule -Force

function Resolve-SasRepoRoot {
    return Get-SasRepoRoot -StartPath $PSScriptRoot
}

function Get-FullPathSafe {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ConvertTo-SasFullPath -Path $Path
}

function Test-IsUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    return Test-SasPathUnderRoot -Path $Path -Root $Root
}

function Write-SasStageProgress {
    param(
        [Parameter(Mandatory = $true)][int]$Step,
        [Parameter(Mandatory = $true)][int]$Total,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][int]$Percent
    )

    $boundedPercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $line = "[$Step/$Total] $Message - $boundedPercent%"
    Write-Host $line
    Write-Progress -Activity 'SysAdminSuite network preflight' -Status $line -PercentComplete $boundedPercent
}

function Get-CandidateTargetFiles {
    param([Parameter(Mandatory = $true)][string[]]$Roots)
    $repo = Resolve-SasRepoRoot
    $all = @(Get-SasCandidateTargetFile -RepoRoot $repo)
    foreach ($candidate in $all) {
        foreach ($root in $Roots) {
            if (Test-SasPathUnderRoot -Path $candidate.FullName -Root $root) {
                $candidate
                break
            }
        }
    }
}

function Show-TargetFileSelectionHelp {
    param(
        [Parameter(Mandatory = $true)][string[]]$CandidateRoots,
        [Parameter(Mandatory = $true)][string]$StagingRoot
    )

    Write-Host 'No -TargetFile was provided. Stopping without probing.'
    Write-Host ''
    Write-Host 'Select an approved .txt or .csv target file from one of these live intake roots:'
    foreach ($root in $CandidateRoots) { Write-Host "- $root" }
    Write-Host ''
    Write-Host "survey/input is normalized runtime staging only: $StagingRoot"
    Write-Host ''
    Write-Host 'Candidate files found:'
    $candidates = @(Get-CandidateTargetFiles -Roots $CandidateRoots)
    if ($candidates.Count -eq 0) {
        Write-Host '- none found'
    } else {
        foreach ($candidate in $candidates) {
            Write-Host "- $($candidate.FullName)"
        }
    }
    Write-Host ''
    Write-Host 'Run in Windows PowerShell:'
    Write-Host '.\survey\sas-network-preflight.ps1 -TargetFile .\targets\local\approved_targets.csv -Ports 135,445,3389,9100'
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

function Test-ExplicitHostType {
    param($Row)
    $typeValue = Get-RowValue -Row $Row -Names @('IdentifierType', 'TargetType', 'Type', 'ValueType')
    if ([string]::IsNullOrWhiteSpace($typeValue)) { return $false }
    return $typeValue -match '^(HostName|Hostname|Host|ComputerName|DnsName|FQDN|IPv4|IPv6|IPAddress|IP)$'
}

function Read-TextTargets {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        if (Test-ProbeReadyTargetValue -Value $trimmed) {
            $items.Add($trimmed)
        } else {
            Write-Host "Skipping non-probe-ready TXT value: $trimmed"
        }
    }
    return $items
}

function Read-CsvTargets {
    param([Parameter(Mandatory = $true)][string]$Path)

    $rows = @(Import-Csv -LiteralPath $Path)
    $items = New-Object System.Collections.Generic.List[string]
    $hostColumns = @('HostName', 'Hostname', 'ComputerName', 'DeviceName', 'Name')
    $targetColumns = @('Target', 'Identifier')

    foreach ($row in $rows) {
        $host = Get-RowValue -Row $row -Names $hostColumns
        if (-not [string]::IsNullOrWhiteSpace($host)) {
            $items.Add($host)
            continue
        }

        $target = Get-RowValue -Row $row -Names $targetColumns
        if ([string]::IsNullOrWhiteSpace($target)) { continue }

        if ((Test-ExplicitHostType -Row $row) -or (Test-ProbeReadyTargetValue -Value $target)) {
            $items.Add($target)
        }
    }

    return $items
}

function Read-ApprovedTargets {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.txt' { return Read-TextTargets -Path $Path }
        '.csv' { return Read-CsvTargets -Path $Path }
        default { throw "Unsupported target file extension '$extension'. Use .txt or .csv." }
    }
}

function Resolve-TargetAddress {
    param([Parameter(Mandatory = $true)][string]$Target)

    if (Test-IsIpAddress -Value $Target) { return $Target.Trim() }

    $cmd = Get-Command Resolve-DnsName -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        $record = Resolve-DnsName -Name $Target -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -and $_.IPAddress -match '^\d+\.' } |
            Select-Object -First 1
        if ($null -ne $record) { return [string]$record.IPAddress }
    }

    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($Target)
        $ipv4 = $addresses | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
        if ($null -ne $ipv4) { return [string]$ipv4.IPAddressToString }
    } catch {
        return ''
    }

    return ''
}

function Test-PingStatus {
    param([Parameter(Mandatory = $true)][string]$Target)

    try {
        $ok = Test-Connection -ComputerName $Target -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ok) { return 'Reachable' }
        return 'NoPing'
    } catch {
        return 'NoPing'
    }
}

function Test-PortStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$Port
    )

    $cmd = Get-Command Test-NetConnection -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return 'NotChecked' }

    try {
        $ok = Test-NetConnection -ComputerName $Target -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($ok) { return 'Open' }
        return 'Closed'
    } catch {
        return 'Closed'
    }
}

$repoRoot = Resolve-SasRepoRoot
$rootSet = Get-SasTargetIntakeRoots -RepoRoot $repoRoot
$targetsLocalRoot = $rootSet.SourceRoots[0]
$logsTargetsRoot = $rootSet.SourceRoots[1]
$surveyInputRoot = $rootSet.StagingRoot
$surveyOutputRoot = $rootSet.OutputRoots[0]
$logsNmapRoot = $rootSet.OutputRoots[1]
$surveyArtifactsRoot = $rootSet.OutputRoots[2]

$candidateRoots = @($targetsLocalRoot, $logsTargetsRoot)
$allowedInputRoots = @($targetsLocalRoot, $logsTargetsRoot, $surveyInputRoot)
$allowedOutputRoots = @($surveyOutputRoot, $logsNmapRoot, $surveyArtifactsRoot)

if ([string]::IsNullOrWhiteSpace($TargetFile)) {
    Show-TargetFileSelectionHelp -CandidateRoots $candidateRoots -StagingRoot $surveyInputRoot
    exit 1
}

if (-not (Test-Path -LiteralPath $TargetFile -PathType Leaf)) {
    throw "Target file not found: $TargetFile"
}

$selectedTargetFile = Get-FullPathSafe -Path (Resolve-Path -LiteralPath $TargetFile).Path
$inputIsCodified = Test-SasPathUnderAnyRoot -Path $selectedTargetFile -Roots $allowedInputRoots
if (-not $inputIsCodified) {
    if (-not $AllowNonstandardInput) {
        throw "Selected target file is outside codified intake roots. Use targets/local, logs/targets, or normalized survey/input. Refusing: $selectedTargetFile"
    }
    Write-Warning "NONSTANDARD INPUT OVERRIDE: selected file is outside codified intake roots: $selectedTargetFile"
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $surveyOutputRoot 'network_preflight'
}

$outputDirectoryFull = Get-FullPathSafe -Path $OutputDirectory
$outputIsCodified = Test-SasPathUnderAnyRoot -Path $outputDirectoryFull -Roots $allowedOutputRoots
if (-not $outputIsCodified) {
    if (-not $AllowNonstandardInput) {
        throw "Output directory is outside codified output roots. Use survey/output, logs/nmap, or survey/artifacts. Refusing: $outputDirectoryFull"
    }
    Write-Warning "NONSTANDARD OUTPUT OVERRIDE: output directory is outside codified output roots: $outputDirectoryFull"
}

foreach ($port in $Ports) {
    if ($port -lt 1 -or $port -gt 65535) { throw "Invalid TCP port: $port" }
}

Write-SasStageProgress -Step 1 -Total 4 -Message 'Loading approved target file' -Percent 25
$targetsRaw = @(Read-ApprovedTargets -Path $selectedTargetFile)
$seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$targets = New-Object System.Collections.Generic.List[string]
foreach ($target in $targetsRaw) {
    $clean = ([string]$target).Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { continue }
    if ($seen.Add($clean)) { $targets.Add($clean) }
}

if ($targets.Count -eq 0) {
    throw 'The selected file did not yield probe-ready hostnames or IP addresses. Provide a .txt with one hostname/IP per line, or a .csv with HostName, Hostname, Target, Identifier, ComputerName, Name, or DeviceName. Serial-only rows must be normalized or enriched to hostnames before network preflight.'
}

New-Item -ItemType Directory -Force -Path $outputDirectoryFull | Out-Null
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputCsv = Join-Path $outputDirectoryFull "network_preflight_$runId.csv"

Write-Host "Selected target file: $selectedTargetFile"
Write-Host "Target count: $($targets.Count)"
Write-Host "Selected ports: $($Ports -join ',')"
Write-Host "Output path: $outputCsv"

Write-SasStageProgress -Step 2 -Total 4 -Message 'Resolving DNS for selected targets' -Percent 50
$resolved = @{}
$ping = @{}
for ($i = 0; $i -lt $targets.Count; $i++) {
    $target = $targets[$i]
    $itemNumber = $i + 1
    $percent = [int][Math]::Floor(($itemNumber / [double]$targets.Count) * 100)
    $line = "[$itemNumber/$($targets.Count)] Resolving DNS for $target - $percent%"
    Write-Host $line
    Write-Progress -Activity 'Resolving DNS for selected targets' -Status $line -PercentComplete $percent
    $resolved[$target] = Resolve-TargetAddress -Target $target
    $pingTarget = if ($resolved[$target]) { $resolved[$target] } else { $target }
    $ping[$target] = Test-PingStatus -Target $pingTarget
}

Write-SasStageProgress -Step 3 -Total 4 -Message 'Checking TCP ports' -Percent 75
$rows = New-Object System.Collections.Generic.List[object]
$totalChecks = $targets.Count * $Ports.Count
$checkNumber = 0
foreach ($target in $targets) {
    $probeTarget = if ($resolved[$target]) { $resolved[$target] } else { $target }
    foreach ($port in $Ports) {
        $checkNumber++
        $status = Test-PortStatus -Target $probeTarget -Port $port
        $percent = [int][Math]::Floor(($checkNumber / [double]$totalChecks) * 100)
        $line = "[$checkNumber/$totalChecks] $target port $port - $status - $percent%"
        Write-Host $line
        Write-Progress -Activity 'Checking TCP ports' -Status $line -PercentComplete $percent

        $notes = @()
        if (-not $resolved[$target]) { $notes += 'DNS unresolved or IP literal not resolved through DNS' }
        if ($status -eq 'NotChecked') { $notes += 'Test-NetConnection unavailable in this PowerShell runtime' }

        $rows.Add([pscustomobject]@{
            Timestamp       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Target          = $target
            ResolvedAddress = $resolved[$target]
            PingStatus      = $ping[$target]
            Port            = $port
            PortStatus      = $status
            SourceFile      = $selectedTargetFile
            Notes           = ($notes -join '; ')
        })
    }
}

Write-SasStageProgress -Step 4 -Total 4 -Message 'Writing network_preflight.csv' -Percent 100
$rows | Export-Csv -LiteralPath $outputCsv -NoTypeInformation -Encoding UTF8
Write-Progress -Activity 'SysAdminSuite network preflight' -Completed
Write-Host "Final CSV path: $outputCsv"
