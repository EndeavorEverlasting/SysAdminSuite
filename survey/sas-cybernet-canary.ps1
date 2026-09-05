#Requires -Version 5.1
<#
.SYNOPSIS
Run a bounded, read-only Cybernet identity canary against explicit approved candidates.

.DESCRIPTION
The canary reduces unnecessary network traffic; it is not a monitoring-evasion feature.
It accepts at most five explicit hostname/FQDN/IP candidates, rejects ranges/CIDRs/wildcards,
reuses completed canary evidence from the previous 24 hours, performs one canonical network
preflight narrowed to TCP 135 and 445 for remaining candidates, and attempts one DCOM/CIM
session only when both ports are open. That session first proves Windows client-workstation
class from Win32_OperatingSystem ProductType. Manufacturer/model/BIOS serial are queried only
for a confirmed client workstation. It never mutates a target and never accepts credentials
on the command line.

The two-port posture is a Windows-PC candidate signature, not Cybernet identity. Model + serial
remain evidence for comparison with the approved Cybernet hardware reference.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Target,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 168)]
    [int]$ReuseWithinHours = 24
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$preflight = Join-Path $repoRoot 'survey\sas-network-preflight.ps1'
$targetRoot = Join-Path $repoRoot 'targets\local'
$outputRoot = Join-Path $repoRoot 'survey\output\cybernet_canary'
$MaxTargets = 5

if (-not (Test-Path -LiteralPath $preflight -PathType Leaf)) {
    throw "Canonical network preflight is missing: $preflight"
}

function Test-SasExplicitCanaryTarget {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $candidate = $Value.Trim()
    if ($candidate -match '[/*?\[\]]') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d') { return $false }
    if ($candidate -match '^\d{1,3}(?:\.\d{1,3}){3}\s*-\s*\d{1,3}(?:\.\d{1,3}){3}$') { return $false }
    if ($candidate -match '\.\.') { return $false }

    $ip = $null
    if ([System.Net.IPAddress]::TryParse($candidate, [ref]$ip)) { return $true }
    if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$') { return $true }
    if ($candidate -match '^[A-Za-z0-9]+[-_][A-Za-z0-9_-]+$') { return $true }
    if ($candidate -match '^[A-Za-z]{2,6}[0-9]{2,}[A-Za-z0-9_-]*$') { return $true }
    return $false
}

function Get-SasFreshCanaryEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$TargetName,
        [Parameter(Mandatory = $true)][datetime]$Cutoff
    )

    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) { return $null }
    $markers = @(Get-ChildItem -LiteralPath $outputRoot -Filter 'cybernet_canary_complete.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending)
    foreach ($marker in $markers) {
        try { $completion = Get-Content -LiteralPath $marker.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($completion.completed -ne $true -or [string]::IsNullOrWhiteSpace([string]$completion.result_sha256)) { continue }
        $resultPath = Join-Path $marker.DirectoryName 'cybernet_canary_identity.csv'
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { continue }
        try { $actualHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash } catch { continue }
        if (-not $actualHash.Equals([string]$completion.result_sha256, [StringComparison]::OrdinalIgnoreCase)) { continue }

        foreach ($row in @(Import-Csv -LiteralPath $resultPath -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace([string]$row.Target) -or -not ([string]$row.Target).Equals($TargetName, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not $row.PSObject.Properties['Port445'] -or -not $row.PSObject.Properties['PcSignatureStatus']) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$row.ObservationTimestamp)) { continue }
            try { $observedAt = [datetime]$row.ObservationTimestamp } catch { continue }
            if ($observedAt.ToUniversalTime() -lt $Cutoff.ToUniversalTime()) { continue }
            return $row
        }
    }
    return $null
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$targets = New-Object 'System.Collections.Generic.List[string]'
foreach ($rawTarget in @($Target)) {
    $candidate = ([string]$rawTarget).Trim()
    if (-not (Test-SasExplicitCanaryTarget -Value $candidate)) {
        throw "Invalid canary target '$rawTarget'. Use one explicit hostname/FQDN/IP only; CIDRs, ranges, wildcards, and subnet discovery are refused."
    }
    if ($seen.Add($candidate)) { [void]$targets.Add($candidate) }
}

if ($targets.Count -eq 0) { throw 'No explicit Cybernet canary targets were supplied.' }
if ($targets.Count -gt $MaxTargets) {
    throw "CYBERNET_CANARY_SCOPE_EXCEEDED: maximum $MaxTargets explicit candidates per run; received $($targets.Count). Split the approved candidate list into smaller canaries."
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$runId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$nonce = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = Join-Path $outputRoot ("${runId}_${nonce}")
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$resultCsv = Join-Path $runRoot 'cybernet_canary_identity.csv'
$summaryJson = Join-Path $runRoot 'cybernet_canary_summary.json'
$completionPath = Join-Path $runRoot 'cybernet_canary_complete.json'
$targetFile = Join-Path $targetRoot ("cybernet_canary_${runId}_${nonce}.txt")

$cutoff = (Get-Date).AddHours(-1 * $ReuseWithinHours)
$results = New-Object 'System.Collections.Generic.List[object]'
$liveTargets = New-Object 'System.Collections.Generic.List[string]'

foreach ($candidate in $targets) {
    $fresh = Get-SasFreshCanaryEvidence -TargetName $candidate -Cutoff $cutoff
    if ($null -ne $fresh) {
        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            ObservationTimestamp = [string]$fresh.ObservationTimestamp
            Target = $candidate
            ResolvedAddress = [string]$fresh.ResolvedAddress
            PingStatus = [string]$fresh.PingStatus
            Port135 = [string]$fresh.Port135
            Port445 = [string]$fresh.Port445
            PcSignatureStatus = [string]$fresh.PcSignatureStatus
            WorkstationStatus = [string]$fresh.WorkstationStatus
            ObservedOperatingSystem = [string]$fresh.ObservedOperatingSystem
            ObservedHostName = [string]$fresh.ObservedHostName
            ObservedManufacturer = [string]$fresh.ObservedManufacturer
            ObservedModel = [string]$fresh.ObservedModel
            ObservedSerial = [string]$fresh.ObservedSerial
            IdentityStatus = [string]$fresh.IdentityStatus
            EvidenceSource = 'FreshLocalReuse'
            NetworkActivityPerformed = $false
            Notes = "Reused completed canary evidence observed within $ReuseWithinHours hours (source status: $([string]$fresh.IdentityStatus)); no live probe performed."
        })
    } else {
        [void]$liveTargets.Add($candidate)
    }
}

$preflightRows = @()
try {
    if ($liveTargets.Count -gt 0) {
        $liveTargets | Set-Content -LiteralPath $targetFile -Encoding UTF8
        $preflightRoot = Join-Path $runRoot 'preflight'
        & $preflight -TargetFile $targetFile -Ports @(135,445) -PolicyProfile 'network_preflight' -OutputDirectory $preflightRoot
        $preflightCsv = @(Get-ChildItem -LiteralPath $preflightRoot -Filter 'network_preflight_*.csv' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
        if ($preflightCsv.Count -ne 1) { throw 'Canary preflight did not produce exactly one network_preflight CSV.' }
        $preflightRows = @(Import-Csv -LiteralPath $preflightCsv[0].FullName)
    }

    foreach ($candidate in $liveTargets) {
        $rows = @($preflightRows | Where-Object { ([string]$_.Target).Equals($candidate, [StringComparison]::OrdinalIgnoreCase) })
        $firstRow = $rows | Select-Object -First 1
        $resolved = if ($null -ne $firstRow) { [string]$firstRow.ResolvedAddress } else { '' }
        $pingStatus = if ($null -ne $firstRow) { [string]$firstRow.PingStatus } else { '' }
        $port135Row = $rows | Where-Object { [int]$_.Port -eq 135 } | Select-Object -First 1
        $port445Row = $rows | Where-Object { [int]$_.Port -eq 445 } | Select-Object -First 1
        $port135 = if ($null -ne $port135Row) { [string]$port135Row.PortStatus } else { 'NotChecked' }
        $port445 = if ($null -ne $port445Row) { [string]$port445Row.PortStatus } else { 'NotChecked' }
        $pcSignatureStatus = if ($port135 -eq 'Open' -and $port445 -eq 'Open') { 'WINDOWS_PC_SIGNATURE_MATCH' } else { 'WINDOWS_PC_SIGNATURE_NOT_MATCHED' }
        $identityEndpoint = if (-not [string]::IsNullOrWhiteSpace($resolved)) { $resolved } else { $candidate }

        $observationTimestamp = (Get-Date).ToString('o')
        $observedOs = ''
        $observedHost = ''
        $manufacturer = ''
        $model = ''
        $serial = ''
        $workstationStatus = 'NOT_EVALUATED'
        $identityStatus = 'PC_SIGNATURE_NOT_MATCHED_METADATA_SKIPPED'
        $noteParts = New-Object 'System.Collections.Generic.List[string]'
        [void]$noteParts.Add('Both TCP 135 and 445 are required before any DCOM/CIM metadata query.')

        if ($pcSignatureStatus -eq 'WINDOWS_PC_SIGNATURE_MATCH') {
            $noteParts.Clear()
            $session = $null
            try {
                $sessionOption = New-CimSessionOption -Protocol Dcom
                $session = New-CimSession -ComputerName $identityEndpoint -SessionOption $sessionOption -ErrorAction Stop
            } catch {
                $identityStatus = 'IDENTITY_SESSION_FAILED'
                [void]$noteParts.Add('Dual-port PC signature matched, but the single read-only DCOM/CIM session failed or was denied; no retry performed.')
            }

            if ($null -ne $session) {
                try {
                    $os = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem -Property Caption,ProductType -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                    if ($null -ne $os) {
                        $observedOs = [string]$os.Caption
                        if ([int]$os.ProductType -eq 1) {
                            $workstationStatus = 'WINDOWS_CLIENT_WORKSTATION_CONFIRMED'
                        } else {
                            $workstationStatus = 'NON_CLIENT_WINDOWS_OS'
                            $identityStatus = 'NON_WORKSTATION_OS_METADATA_SKIPPED'
                            [void]$noteParts.Add("Windows ProductType $([int]$os.ProductType) is not a client workstation; manufacturer/model/serial queries were skipped.")
                        }
                    }
                } catch {
                    $workstationStatus = 'WORKSTATION_CLASS_UNRESOLVED'
                    $identityStatus = 'WORKSTATION_CLASS_UNRESOLVED_METADATA_SKIPPED'
                    [void]$noteParts.Add('Windows workstation class could not be proven; manufacturer/model/serial queries were skipped.')
                }

                if ($workstationStatus -eq 'WINDOWS_CLIENT_WORKSTATION_CONFIRMED') {
                    try {
                        $computer = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem -Property Name,Manufacturer,Model -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                        if ($null -ne $computer) {
                            $observedHost = [string]$computer.Name
                            $manufacturer = [string]$computer.Manufacturer
                            $model = [string]$computer.Model
                        }
                    } catch {
                        [void]$noteParts.Add('Win32_ComputerSystem hardware query failed or was denied.')
                    }

                    try {
                        $bios = Get-CimInstance -CimSession $session -ClassName Win32_BIOS -Property SerialNumber -OperationTimeoutSec 8 -ErrorAction Stop | Select-Object -First 1
                        if ($null -ne $bios) { $serial = [string]$bios.SerialNumber }
                    } catch {
                        [void]$noteParts.Add('Win32_BIOS serial query failed or was denied.')
                    }

                    if (-not [string]::IsNullOrWhiteSpace($model) -and -not [string]::IsNullOrWhiteSpace($serial)) {
                        $identityStatus = 'IDENTITY_COLLECTED'
                        [void]$noteParts.Add('Confirmed client workstation returned model and BIOS serial in the single DCOM/CIM session.')
                    } elseif (-not [string]::IsNullOrWhiteSpace($observedHost) -or -not [string]::IsNullOrWhiteSpace($manufacturer) -or -not [string]::IsNullOrWhiteSpace($model) -or -not [string]::IsNullOrWhiteSpace($serial)) {
                        $identityStatus = 'IDENTITY_PARTIAL'
                        [void]$noteParts.Add('Partial hardware identity was retained; no retry performed.')
                    } else {
                        $identityStatus = 'IDENTITY_QUERY_FAILED'
                    }
                }

                Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
            }
        }

        $results.Add([pscustomobject]@{
            Timestamp = (Get-Date).ToString('o')
            ObservationTimestamp = $observationTimestamp
            Target = $candidate
            ResolvedAddress = $resolved
            PingStatus = $pingStatus
            Port135 = $port135
            Port445 = $port445
            PcSignatureStatus = $pcSignatureStatus
            WorkstationStatus = $workstationStatus
            ObservedOperatingSystem = $observedOs
            ObservedHostName = $observedHost
            ObservedManufacturer = $manufacturer
            ObservedModel = $model
            ObservedSerial = $serial
            IdentityStatus = $identityStatus
            EvidenceSource = 'LiveBoundedCanary'
            NetworkActivityPerformed = $true
            Notes = ($noteParts -join ' ')
        })
    }
} finally {
    if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
        Remove-Item -LiteralPath $targetFile -Force -ErrorAction SilentlyContinue
    }
}

$ordered = @($targets | ForEach-Object {
    $name = $_
    $results | Where-Object { ([string]$_.Target).Equals($name, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
})
$ordered | Export-Csv -LiteralPath $resultCsv -NoTypeInformation -Encoding UTF8

$summary = [pscustomobject]@{
    schema_version = 'sas-cybernet-canary-summary/v2'
    generated_at = (Get-Date).ToString('o')
    target_count = $targets.Count
    fresh_reuse_count = @($ordered | Where-Object { $_.EvidenceSource -eq 'FreshLocalReuse' }).Count
    live_canary_count = @($ordered | Where-Object { $_.EvidenceSource -eq 'LiveBoundedCanary' }).Count
    pc_signature_match_count = @($ordered | Where-Object { $_.PcSignatureStatus -eq 'WINDOWS_PC_SIGNATURE_MATCH' }).Count
    workstation_confirmed_count = @($ordered | Where-Object { $_.WorkstationStatus -eq 'WINDOWS_CLIENT_WORKSTATION_CONFIRMED' }).Count
    identity_collected_count = @($ordered | Where-Object { $_.IdentityStatus -eq 'IDENTITY_COLLECTED' }).Count
    metadata_skipped_count = @($ordered | Where-Object { $_.IdentityStatus -like '*METADATA_SKIPPED' }).Count
    target_mutation_performed = $false
    stealth_or_evasion_claim = $false
    result_csv = $resultCsv
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

$resultHash = (Get-FileHash -LiteralPath $resultCsv -Algorithm SHA256).Hash
$completion = [pscustomobject]@{
    schema_version = 'sas-cybernet-canary-completion/v2'
    completed = $true
    completed_at = (Get-Date).ToString('o')
    result_sha256 = $resultHash
}
$completionTemp = $completionPath + '.tmp'
$completion | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $completionTemp -Encoding UTF8
Move-Item -LiteralPath $completionTemp -Destination $completionPath -Force

Write-Host ''
Write-Host 'Cybernet low-noise identity canary' -ForegroundColor Cyan
Write-Host 'Terminal contract: invoke through the installed sas command from Windows PowerShell; current directory is irrelevant.'
Write-Host "Targets: $($targets.Count) (hard cap: $MaxTargets)"
Write-Host "Fresh completed evidence reused without packets: $($summary.fresh_reuse_count)"
Write-Host "Live bounded canaries: $($summary.live_canary_count)"
Write-Host "Dual-port Windows-PC signature matches: $($summary.pc_signature_match_count)"
Write-Host "Confirmed Windows client workstations: $($summary.workstation_confirmed_count)"
Write-Host 'Traffic contract: explicit candidates only; DNS + one ICMP attempt + TCP 135 and 445; no canary retry; one DCOM/CIM session only after both ports open; hardware metadata only after ProductType=1.'
Write-Host 'Monitoring contract: this reduces unnecessary traffic but does not hide activity or guarantee that normal monitoring will not alert.' -ForegroundColor Yellow
Write-Host "Result: $resultCsv" -ForegroundColor Green
Write-Host "Summary: $summaryJson"
Write-Host "Completion marker: $completionPath"
$ordered | Select-Object Target,PcSignatureStatus,WorkstationStatus,ObservedManufacturer,ObservedModel,ObservedSerial,IdentityStatus,EvidenceSource | Format-Table -AutoSize
